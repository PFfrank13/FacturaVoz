// Importar facturas históricas: elegir archivo → revisar → subir por bloques → procesar en segundo plano con barra en vivo.
import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../errors.dart';
import '../import_logic.dart';
import '../models.dart';
import '../services/importer.dart';
import '../services/repo.dart';
import '../services/workbook_import.dart';
import 'workbook_import.dart';
import '../xlsx_reader.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Se ejecuta en otro hilo para no congelar la pantalla con archivos grandes.
ParsedImport _parseBytes(Uint8List b) {
  if (looksLikeOldXls(b)) {
    return const ParsedImport(rows: [], rejected: 0, columns: {}, error: 'Es un Excel antiguo (.xls). Ábrelo en Excel y guárdalo como .xlsx o .csv.');
  }
  if (looksLikeZip(b)) {
    final table = readXlsxTable(b);
    if (table == null) return const ParsedImport(rows: [], rejected: 0, columns: {}, error: 'No pudimos abrir este Excel. Guárdalo de nuevo como .xlsx o .csv.');
    return parseImportTable(table);
  }
  return parseImportText(decodeImportBytes(b));
}

class _FileResult {
  const _FileResult(this.name, this.parsed);
  final String name;
  final ParsedImport parsed;
  bool get ok => parsed.error == null && parsed.rows.isNotEmpty;
}

enum _Phase { pick, preview, uploading, processing, done, failed }

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  _Phase _phase = _Phase.pick;
  ParsedImport? _parsed;
  String _fileName = '';
  List<_FileResult> _files = const [];
  bool _includesTax = true;
  String _error = '';
  bool _reading = false;

  String? _jobId;
  ImportJob? _job;
  int _sent = 0;
  bool _cancelled = false;
  StreamSubscription<ImportJob>? _sub;
  Timer? _poll;
  bool _driving = false;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void dispose() {
    _cancelled = true; // detiene la subida/avance desde esta pantalla; el worker de la base sigue solo
    _sub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _resume() async {
    final org = Repo.activeOrgId;
    if (org == null) return;
    try {
      final j = await ImportService.activeJob(org);
      if (j != null && mounted) {
        _jobId = j.id;
        setState(() {
          _job = j;
          _phase = _Phase.processing;
        });
        _watch(j.id);
      }
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = '';
      _reading = true;
    });
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['csv', 'txt', 'xlsx', 'xls'], allowMultiple: true, withData: true);
      final picked = r?.files ?? const [];
      if (picked.isEmpty) {
        if (mounted) setState(() => _reading = false);
        return;
      }
      String? problem;
      var bytesTotal = 0;
      for (final f in picked) {
        bytesTotal += f.bytes?.length ?? 0;
      }
      if (picked.length > 24) problem = 'Elige hasta 24 archivos por vez.';
      if (bytesTotal > 120 * 1024 * 1024) problem = 'Los archivos pesan demasiado juntos (máximo 120 MB). Impórtalos en dos tandas.';
      if (problem != null) {
        if (mounted) {
          setState(() {
            _reading = false;
            _error = problem!;
          });
        }
        return;
      }
      // Libro con varias hojas (clientes + comprobantes + detalle + catálogo): importador relacional.
      if (picked.length == 1 && picked.first.bytes != null && looksLikeWorkbook(picked.first.bytes!)) {
        if (mounted) setState(() => _reading = false);
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => WorkbookImportScreen(bytes: picked.first.bytes!, fileName: picked.first.name)));
        return;
      }
      final results = <_FileResult>[];
      for (final f in picked) {
        if (f.bytes == null) {
          results.add(_FileResult(f.name, const ParsedImport(rows: [], rejected: 0, columns: {}, error: 'No se pudo leer este archivo.')));
          continue;
        }
        results.add(_FileResult(f.name, await compute(_parseBytes, f.bytes!)));
      }
      if (!mounted) return;
      final good = results.where((x) => x.ok).toList();
      final rows = [for (final g in good) ...g.parsed.rows];
      setState(() {
        _reading = false;
        _files = results;
        if (good.isEmpty) {
          _error = results.length == 1 ? (results.first.parsed.error ?? 'No encontramos filas con importe válido.') : 'Ninguno de los archivos tiene filas con importe válido.';
        } else if (rows.length > maxImportRows) {
          _error = 'Son más de $maxImportRows filas en total. Impórtalos en dos tandas.';
        } else {
          _fileName = good.length == 1 ? good.first.name : '${good.length} archivos';
          _parsed = ParsedImport(rows: rows, rejected: good.fold(0, (a, g) => a + g.parsed.rejected), columns: good.first.parsed.columns);
          _phase = _Phase.preview;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _reading = false;
          _error = 'No se pudo leer los archivos. Guárdalos como Excel (.xlsx) o CSV e inténtalo de nuevo.';
        });
      }
    }
  }

  Future<void> _begin() async {
    final org = Repo.activeOrgId;
    final parsed = _parsed;
    if (org == null || parsed == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.uploading;
      _sent = 0;
      _error = '';
    });
    try {
      final id = await ImportService.createJob(org, _fileName);
      _jobId = id;
      await ImportService.upload(id, parsed.rows, onProgress: (n) {
        if (mounted) setState(() => _sent = n);
      }, cancelled: () => _cancelled);
      if (_cancelled) return;
      await ImportService.start(id, _includesTax ? 18 : 0);
      if (!mounted) return;
      final j = await ImportService.fetch(id);
      setState(() {
        _job = j;
        _phase = (j?.status == 'failed') ? _Phase.failed : _Phase.processing;
        if (j?.status == 'failed') _error = j?.error ?? 'No se pudo procesar.';
      });
      if (j != null && !j.finished) _watch(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = friendly(e);
        });
      }
    }
  }

  void _apply(ImportJob j) {
    if (!mounted) return;
    setState(() {
      _job = j;
      if (j.status == 'done') _phase = _Phase.done;
      if (j.status == 'failed') {
        _phase = _Phase.failed;
        _error = j.error ?? 'No se pudo procesar.';
      }
      if (j.status == 'cancelled') _phase = _Phase.pick;
    });
    if (j.status == 'done') HapticFeedback.mediumImpact();
  }

  /// Realtime + consulta de respaldo cada 4 s + empuje de lotes mientras la pantalla esté abierta.
  void _watch(String id) {
    _sub?.cancel();
    _sub = ImportService.watch(id).listen(_apply, onError: (_) {});
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final j = await ImportService.fetch(id);
        if (j != null) _apply(j);
        if (j == null || j.finished) _poll?.cancel();
      } catch (_) {}
    });
    _drive(id);
  }

  Future<void> _drive(String id) async {
    if (_driving) return;
    _driving = true;
    var errors = 0;
    while (mounted && !_cancelled && _phase == _Phase.processing) {
      try {
        await ImportService.step(id);
        errors = 0;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } catch (_) {
        if (++errors >= 5) break; // el worker de la base continúa por su cuenta
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    _driving = false;
  }

  Future<void> _cancelJob() async {
    final id = _jobId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cancelar la importación?'),
        content: const Text('Las facturas que ya se importaron se quedan. Las pendientes no se procesarán.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancelar importación')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ImportService.cancel(id);
      if (mounted) setState(() => _phase = _Phase.pick);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _Phase.uploading,
      child: Scaffold(
        appBar: AppBar(title: const Text('Importar facturas'), actions: [
          IconButton(
            tooltip: 'Importaciones anteriores',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WorkbookHistoryScreen())),
          ),
        ]),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(a), child: c)),
            child: KeyedSubtree(key: ValueKey(_phase), child: _body(context)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) => switch (_phase) {
        _Phase.pick => _pickView(context),
        _Phase.preview => _previewView(context),
        _Phase.uploading => _progressView(context, uploading: true),
        _Phase.processing => _progressView(context, uploading: false),
        _Phase.done => _doneView(context),
        _Phase.failed => _failedView(context),
      };

  Widget _pickView(BuildContext context) {
    final t = Theme.of(context);
    Widget step(IconData i, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(i, size: 20, color: t.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.textTheme.titleSmall), Text(body, style: t.textTheme.bodySmall)])),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Reveal(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(Radii.xl), boxShadow: Brand.softShadow(false, a: 0.3)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 34),
            SizedBox(height: 12),
            Text('Trae tus facturas antiguas', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Sube uno o varios archivos a la vez (por meses, por años…) y leemos Cliente, Servicio e Importe de miles de comprobantes. Tú sigues usando la app mientras se procesan.',
                style: TextStyle(color: Colors.white70, height: 1.35)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Reveal(
        index: 1,
        child: SoftCard(
          child: Column(children: [
            step(Icons.download_rounded, '1. Descarga tu registro', 'En el portal de SUNAT (SOL → Registro de Ventas) o en tu sistema anterior, exporta a Excel (.xlsx), CSV o TXT.'),
            step(Icons.table_view_rounded, '2. Súbelo aquí', 'Detectamos las columnas solas, también en Excel (.xlsx). Los .xls antiguos guárdalos como .xlsx.'),
            step(Icons.verified_user_rounded, '3. Sin tu clave SOL', 'No pedimos usuario ni contraseña de SUNAT: solo el archivo que tú descargas.'),
          ]),
        ),
      ),
      if (_error.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error, style: t.textTheme.bodyMedium?.copyWith(color: Brand.bad))),
      const SizedBox(height: 18),
      GradientButton(label: _reading ? 'Leyendo archivos…' : 'Elegir archivos', icon: Icons.folder_open_rounded, busy: _reading, onPressed: _reading ? null : _pickFile),
    ]);
  }

  Widget _previewView(BuildContext context) {
    final t = Theme.of(context);
    final p = _parsed!;
    final sample = p.rows.take(5).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Reveal(
        child: SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in _files)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(f.ok ? Icons.description_rounded : Icons.error_outline_rounded, size: 20, color: f.ok ? t.colorScheme.primary : Brand.bad),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f.name, style: t.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text(f.ok ? '${f.parsed.rows.length} filas' : 'se omite', style: t.textTheme.bodySmall?.copyWith(color: f.ok ? null : Brand.bad)),
                ]),
              ),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StatusPill('${p.rows.length} listas para importar', tone: PillTone.ok),
              if (p.rejected > 0) StatusPill('${p.rejected} sin importe válido (se omiten)', tone: PillTone.warn),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Reveal(
        index: 1,
        child: SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Columnas detectadas', style: t.textTheme.titleSmall),
            const SizedBox(height: 10),
            for (final e in p.columns.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 80, child: Text(e.key, style: t.textTheme.bodySmall)),
                  const Icon(Icons.arrow_right_alt_rounded, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(e.value.isEmpty ? 'no encontrada' : e.value,
                        overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium?.copyWith(color: e.value.isEmpty ? t.colorScheme.onSurfaceVariant : null)),
                  ),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Reveal(
        index: 2,
        child: SoftCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            value: _includesTax,
            onChanged: (v) => setState(() => _includesTax = v),
            title: const Text('Los importes incluyen IGV (18%)', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Actívalo si el archivo trae el total con impuesto, como el registro de SUNAT.'),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Reveal(
        index: 3,
        child: SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vista previa', style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final r in sample)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.client.isEmpty ? 'Cliente sin nombre' : r.client, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium),
                      Text(r.description.isEmpty ? 'Servicio importado' : r.description, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Text(money(r.amount, r.currency), style: t.textTheme.titleSmall),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      GradientButton(label: 'Importar ${p.rows.length} facturas', icon: Icons.play_arrow_rounded, onPressed: _begin),
      TextButton(onPressed: () => setState(() => _phase = _Phase.pick), child: const Text('Elegir otros archivos')),
    ]);
  }

  Widget _progressView(BuildContext context, {required bool uploading}) {
    final t = Theme.of(context);
    final total = _parsed?.rows.length ?? 0;
    final value = uploading ? (total == 0 ? 0.0 : _sent / total) : (_job?.progress ?? 0.0);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _SpinnerBadge(),
          const SizedBox(height: 22),
          Text(uploading ? 'Subiendo tu archivo…' : 'Procesando tus facturas…', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            uploading
                ? 'Mantén esta pantalla abierta unos segundos mientras se sube. ($_sent de $total)'
                : 'Procesando tus facturas... puedes cerrar esta ventana y te avisaremos por correo al terminar.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 26),
          _ProgressBar(value: value),
          const SizedBox(height: 14),
          if (!uploading && _job != null)
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              StatusPill('${_job!.imported} importadas', tone: PillTone.ok),
              if (_job!.skipped > 0) StatusPill('${_job!.skipped} omitidas', tone: PillTone.warn),
              StatusPill('${_job!.processed} de ${_job!.total}', tone: PillTone.neutral),
            ]),
          const SizedBox(height: 22),
          if (!uploading) ...[
            OutlinedButton.icon(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded), label: const Text('Cerrar y seguir en segundo plano')),
            TextButton(onPressed: _cancelJob, child: const Text('Cancelar importación')),
          ],
        ]),
      ),
    );
  }

  Widget _doneView(BuildContext context) {
    final t = Theme.of(context);
    final j = _job;
    return Stack(children: [
      const Positioned.fill(child: ConfettiBurst(count: 90)),
      Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(scale: v.clamp(0.0, 1.4), child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: Brand.heroGradient, boxShadow: Brand.softShadow(false, a: 0.35)),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
            ),
          ),
          const SizedBox(height: 22),
          Text('¡Listo!', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            '${j?.imported ?? 0} facturas importadas${(j?.skipped ?? 0) > 0 ? ' · ${j!.skipped} omitidas (repetidas o sin datos válidos)' : ''}.\nYa aparecen en tu lista y en tus reportes.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 24),
          GradientButton(label: 'Ver mis facturas', icon: Icons.receipt_long_rounded, onPressed: () => Navigator.of(context).pop()),
        ]),
      ),
    ),
    ]);
  }

  Widget _failedView(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: Brand.bad, size: 56),
          const SizedBox(height: 14),
          Text('No se pudo terminar', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_error.isEmpty ? 'Inténtalo de nuevo.' : _error, textAlign: TextAlign.center),
          const SizedBox(height: 22),
          GradientButton(label: 'Intentar de nuevo', icon: Icons.refresh_rounded, onPressed: () => setState(() => _phase = _Phase.pick)),
        ]),
      ),
    );
  }
}

/// Barra con degradado que se llena con suavidad, con porcentaje animado.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 14,
            color: t.colorScheme.primary.withValues(alpha: 0.12),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(widthFactor: v < 0.02 && v > 0 ? 0.02 : v, child: const DecoratedBox(decoration: BoxDecoration(gradient: Brand.heroGradient), child: SizedBox.expand())),
          ),
        ),
        const SizedBox(height: 8),
        Text('${(v * 100).floor()}%', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _SpinnerBadge extends StatefulWidget {
  const _SpinnerBadge();

  @override
  State<_SpinnerBadge> createState() => _SpinnerBadgeState();
}

class _SpinnerBadgeState extends State<_SpinnerBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _c,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: Brand.heroGradient, boxShadow: Brand.softShadow(false, a: 0.35)),
          child: const Icon(Icons.autorenew_rounded, color: Colors.white, size: 42),
        ),
      );
}
