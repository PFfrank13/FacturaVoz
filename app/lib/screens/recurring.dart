import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../errors.dart';
import '../growth.dart';
import '../models.dart';
import '../models_growth.dart';
import '../services/growth_repo.dart';
import '../services/live.dart';
import '../services/pro_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Facturación recurrente: alquileres, mensualidades y mantenimientos se facturan solos cada mes.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> with LiveReload<RecurringScreen> {
  List<RecurringTemplate>? _items;
  String? _error;
  bool _running = false;

  @override
  List<String> get liveTables => const ['recurring_invoices', 'invoices'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _items = LiveCache.get<List<RecurringTemplate>>('recurring.list');
    _load(generate: true);
    startLive(); // tiempo real
  }

  @override
  void dispose() {
    stopLive();
    super.dispose();
  }

  /// Al abrir, genera lo que toque hoy (por si pg_cron no está activo) y luego lista.
  Future<void> _load({bool generate = false}) async {
    try {
      if (generate) {
        try {
          final n = await GrowthRepo.runRecurringNow();
          if (n > 0) {
            AppState.instance.bump();
            if (mounted) showSuccess(context, n == 1 ? '1 factura recurrente creada' : '$n facturas recurrentes creadas');
          }
        } catch (_) {}
      }
      final r = await GrowthRepo.listRecurring();
      LiveCache.put('recurring.list', r);
      if (mounted) {
        setState(() {
          _items = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261102_revolucion.sql en Supabase.' : friendly(e));
    }
  }

  Future<void> _runNow() async {
    setState(() => _running = true);
    try {
      final n = await GrowthRepo.runRecurringNow();
      AppState.instance.bump();
      if (!mounted) return;
      if (n > 0) {
        showSuccess(context, n == 1 ? '1 factura creada' : '$n facturas creadas');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hoy no toca ninguna. Se crean solas en su fecha.')));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _edit([RecurringTemplate? t]) async {
    final saved = await showRecurringEditor(context, template: t);
    if (saved && mounted) {
      showSuccess(context, 'Programada');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = _items;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final monthly = round2((items ?? const <RecurringTemplate>[]).where((r) => r.active && r.currency == cur).fold<double>(0, (s, r) => s + r.totals.total));
    return Scaffold(
      appBar: AppBar(title: const Text('Facturación recurrente')),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'new-recurring', onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Programar')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 110), children: [
          if (_error != null)
            SoftCard(child: Text(_error!, textAlign: TextAlign.center))
          else if (items == null)
            const SkeletonList(count: 3)
          else ...[
            Reveal(
              child: Aurora(
                borderRadius: BorderRadius.circular(Radii.xl),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Ingreso fijo programado al mes', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5)),
                    const SizedBox(height: 4),
                    CountUp(
                      value: monthly,
                      builder: (c, v) => Text(money(v, cur), style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -1)),
                    ),
                    const SizedBox(height: 6),
                    Text('Cada factura se crea sola en su fecha como borrador; tú solo revisas y emites.',
                        style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                      onPressed: _running ? null : _runNow,
                      icon: _running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.bolt_rounded),
                      label: const Text('Generar las de hoy'),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              const EmptyState(title: 'Factura una vez, cobra siempre', body: 'Programa alquileres, mensualidades o mantenimientos. FacturaVoz crea la factura cada mes en la fecha que elijas.')
            else
              for (final (i, r) in items.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Reveal(
                    key: ValueKey(r.id),
                    index: i < 8 ? i : 8,
                    child: Pressable(
                      onTap: () => _edit(r),
                      child: Opacity(
                        opacity: r.active ? 1 : 0.55,
                        child: SoftCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(15)),
                              child: Text('${r.dayOfMonth}', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(r.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                                Text(
                                  '${r.items.first.description}${r.items.length > 1 ? ' y ${r.items.length - 1} más' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 6),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  TagChip(r.active ? 'Próxima: ${displayDate(r.nextRun)}' : 'En pausa', color: r.active ? Brand.indigo : Brand.warn, icon: Icons.event_repeat_rounded),
                                  if (r.dueDays > 0) TagChip('Crédito ${r.dueDays} días', color: Brand.lilac),
                                  if (r.runs > 0) TagChip('${r.runs} emitidas', color: Brand.ok),
                                  if (r.lastError.isNotEmpty) const TagChip('Revisar datos', color: Brand.bad, icon: Icons.error_outline_rounded),
                                ]),
                              ]),
                            ),
                            const SizedBox(width: 8),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Money(money(r.totals.total, r.currency), size: 15, weight: FontWeight.w700),
                              Switch(
                                value: r.active,
                                onChanged: (v) async {
                                  Haptics.select();
                                  try {
                                    await GrowthRepo.setRecurringActive(r.id!, v);
                                    _load();
                                  } catch (e) {
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
                                  }
                                },
                              ),
                            ]),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ]),
      ),
    );
  }
}

class _LineCtrl {
  _LineCtrl(LineItem i)
      : desc = TextEditingController(text: i.description),
        qty = TextEditingController(text: qtyText(i.quantity <= 0 ? 1 : i.quantity)),
        price = TextEditingController(text: i.unitPrice <= 0 ? '' : qtyText(i.unitPrice));
  final TextEditingController desc;
  final TextEditingController qty;
  final TextEditingController price;
  List<ChangeNotifier> get all => [desc, qty, price];
}

/// Crea o edita una plantilla. [template] = editar; [from] = crear a partir de una factura existente.
Future<bool> showRecurringEditor(BuildContext context, {RecurringTemplate? template, InvoiceRecord? from}) async {
  final profile = AppState.instance.profile;
  final cur = template?.currency ?? from?.currency ?? profile?.currency ?? 'PEN';
  final client = TextEditingController(text: template?.clientName ?? (from == null || from.clientName == '—' ? '' : from.clientName));
  final taxId = TextEditingController(text: template?.clientTaxId ?? from?.clientTaxId ?? '');
  final notes = TextEditingController(text: template?.notes ?? '');
  final lines = [
    for (final i in (template?.items ?? from?.items ?? <LineItem>[LineItem()])) _LineCtrl(i),
  ];
  double rate = template?.taxRate ?? from?.taxRate ?? profile?.taxRate ?? 18.0;
  var day = template?.dayOfMonth ?? (DateTime.now().day > 28 ? 1 : DateTime.now().day);
  var dueDays = template?.dueDays ?? 0;
  var active = template?.active ?? true;
  var err = '';
  var saving = false;
  final numFmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final t = Theme.of(ctx);
      List<LineItem> items() => [
            for (final l in lines)
              LineItem(description: l.desc.text.trim(), quantity: parseDecimal(l.qty.text) ?? 0, unitPrice: parseDecimal(l.price.text) ?? -1),
          ];
      final total = computeTotals(items().where((i) => i.unitPrice >= 0 && i.quantity > 0), rate).total;

      Future<void> save() async {
        final it = items();
        String? problem;
        if (client.text.trim().isEmpty) {
          problem = 'Escribe el cliente';
        } else if (it.any((i) => i.description.isEmpty)) {
          problem = 'Cada línea necesita una descripción';
        } else if (it.any((i) => i.quantity <= 0 || i.quantity > 100000)) {
          problem = 'Revisa las cantidades';
        } else if (it.any((i) => i.unitPrice < 0 || i.unitPrice > 10000000)) {
          problem = 'Revisa los precios';
        }
        if (problem != null) {
          Haptics.error();
          setS(() => err = problem!);
          return;
        }
        setS(() {
          saving = true;
          err = '';
        });
        try {
          // Se conserva la próxima fecha si no cambió el día (promoción de nulos válida en cualquier versión de Dart).
          final keptRun = template != null && template.dayOfMonth == day && template.nextRun.isNotEmpty ? template.nextRun : null;
          await GrowthRepo.saveRecurring(RecurringTemplate(
            id: template?.id,
            clientName: client.text,
            clientTaxId: taxId.text,
            items: it,
            taxRate: rate,
            currency: cur,
            notes: notes.text,
            dayOfMonth: day,
            dueDays: dueDays,
            nextRun: keptRun ?? firstRunDate(todayIso(), day),
            active: active,
          ));
          if (ctx.mounted) Navigator.pop(ctx, true);
        } catch (e) {
          setS(() {
            saving = false;
            err = ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261102_revolucion.sql.' : friendly(e);
          });
        }
      }

      Future<void> remove() async {
        try {
          await GrowthRepo.deleteRecurring(template!.id!);
          if (ctx.mounted) Navigator.pop(ctx, true);
        } catch (e) {
          setS(() => err = friendly(e));
        }
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(template == null ? 'Programar factura mensual' : 'Editar programación', style: t.textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(controller: client, maxLength: 120, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Cliente', counterText: '')),
            const SizedBox(height: 10),
            TextField(controller: taxId, maxLength: 30, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'DNI o RUC (opcional)', counterText: '')),
            const SizedBox(height: 14),
            Text('Detalle', style: t.textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final (k, l) in lines.indexed)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(Radii.lg)),
                child: Column(children: [
                  TextField(controller: l.desc, maxLength: 200, onChanged: (_) => setS(() {}), decoration: const InputDecoration(labelText: 'Servicio o producto', counterText: '')),
                  const SizedBox(height: 8),
                  Row(children: [
                    SizedBox(
                      width: 90,
                      child: TextField(controller: l.qty, inputFormatters: numFmt, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setS(() {}), decoration: const InputDecoration(labelText: 'Cant.')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: l.price,
                        inputFormatters: numFmt,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setS(() {}),
                        decoration: InputDecoration(labelText: 'Precio sin IGV', prefixText: '${currencySymbols[cur] ?? cur} '),
                      ),
                    ),
                    if (lines.length > 1)
                      IconButton(
                        onPressed: () => setS(() {
                          final removed = lines.removeAt(k);
                          disposeAfterClose(removed.all);
                        }),
                        icon: const Icon(Icons.delete_outline_rounded, color: Brand.bad),
                      ),
                  ]),
                ]),
              ),
            if (lines.length < 20)
              TextButton.icon(onPressed: () => setS(() => lines.add(_LineCtrl(LineItem()))), icon: const Icon(Icons.add_circle_outline_rounded), label: const Text('Agregar línea')),
            const SizedBox(height: 6),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 18, label: Text('IGV 18 %')),
                ButtonSegment(value: 0, label: Text('Exonerado 0 %')),
              ],
              selected: {rate == 0 ? 0.0 : 18.0},
              onSelectionChanged: (s) => setS(() => rate = s.first),
            ),
            const SizedBox(height: 16),
            Text('Se crea cada mes el día', style: t.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in const [1, 5, 10, 15, 20, 25, 28])
                ChoiceChip(label: Text('$d'), selected: day == d, onSelected: (_) => setS(() => day = d)),
              if (!const [1, 5, 10, 15, 20, 25, 28].contains(day)) ChoiceChip(label: Text('$day'), selected: true, onSelected: (_) {}),
            ]),
            const SizedBox(height: 14),
            Text('Condición de pago', style: t.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (d, label) in const [(0, 'Al contado'), (7, '7 días'), (15, '15 días'), (30, '30 días')])
                ChoiceChip(label: Text(label), selected: dueDays == d, onSelected: (_) => setS(() => dueDays = d)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: notes, maxLength: 400, decoration: const InputDecoration(labelText: 'Nota en cada factura (opcional)', counterText: '')),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setS(() => active = v), title: const Text('Activa')),
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(err, style: const TextStyle(color: Brand.bad))),
            Row(children: [
              Expanded(child: Text('Cada mes: ${money(total, cur)}', style: t.textTheme.titleMedium)),
            ]),
            const SizedBox(height: 12),
            GradientButton(label: saving ? 'Guardando…' : 'Guardar', icon: Icons.event_repeat_rounded, busy: saving, onPressed: saving ? null : save),
            if (template?.id != null) TextButton(onPressed: remove, child: const Text('Eliminar programación', style: TextStyle(color: Brand.bad))),
          ]),
        ),
      );
    }),
  );
  disposeAfterClose([client, taxId, notes, for (final l in lines) ...l.all]);
  return ok == true;
}
