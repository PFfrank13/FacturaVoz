// Conciliación bancaria básica (Fase 8 · módulo 15): subes el estado de cuenta (Excel .xlsx o CSV del banco),
// la app sugiere qué ingreso corresponde a qué factura por cobrar (monto, nombre, número, fecha) y tú confirmas.
// Al confirmar se registra el cobro. Las líneas repetidas no se vuelven a importar (huella única).
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../errors.dart';
import '../import_logic.dart' show decodeImportBytes, detectDelimiter, parseCsv;
import '../logic/bank_match.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/live.dart';
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../xlsx_reader.dart';

List<List<String>> _tableOf(Uint8List b) {
  if (looksLikeZip(b)) return readXlsxTable(b) ?? const [];
  final text = decodeImportBytes(b);
  final first = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  return parseCsv(text, detectDelimiter(first));
}

class BankReconScreen extends StatefulWidget {
  const BankReconScreen({super.key});

  @override
  State<BankReconScreen> createState() => _BankReconScreenState();
}

class _BankReconScreenState extends State<BankReconScreen> {
  List<BankLineRow>? _lines;
  List<InvoiceRecord> _open = const [];
  String? _error;
  bool _busy = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _lines = LiveCache.get<List<BankLineRow>>('bank.lines');
    _open = LiveCache.get<List<InvoiceRecord>>('bank.open') ?? const [];
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await V2Repo.bankLines();
      final o = await ProRepo.listReceivables().catchError((_) => <InvoiceRecord>[]);
      LiveCache.put('bank.lines', l);
      LiveCache.put('bank.open', o);
      if (mounted) {
        setState(() {
          _lines = l;
          _open = o;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv', 'txt'], withData: true);
    final f = r?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      if (looksLikeOldXls(f.bytes!)) throw AppException('Es un Excel antiguo (.xls). Ábrelo y guárdalo como .xlsx o .csv.');
      final lines = parseBankTable(_tableOf(f.bytes!));
      if (lines.isEmpty) throw AppException('No encontramos columnas de fecha y monto en ese archivo.');
      final n = await V2Repo.importBankLines([
        for (final l in lines)
          if (l.amount != 0)
            {
              'line_date': l.date,
              'description': l.description.length > 300 ? l.description.substring(0, 300) : l.description,
              'amount': l.amount,
              'reference': l.reference.isEmpty ? null : (l.reference.length > 80 ? l.reference.substring(0, 80) : l.reference),
              'fingerprint': l.fingerprint,
            },
      ], f.name);
      _msg = n == 0 ? 'Esas líneas ya estaban importadas.' : 'Se importaron $n líneas nuevas.';
      await _load();
    } catch (e) {
      _msg = friendly(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirm(BankLineRow l, InvoiceRecord inv) async {
    setState(() => _busy = true);
    try {
      final amount = l.amount > inv.balance ? inv.balance : l.amount;
      final note = 'Banco: ${l.description}';
      await Repo.addPayment(invoiceId: inv.id, amount: amount, method: 'transferencia', note: note.length > 140 ? note.substring(0, 140) : note, paidOn: l.date);
      await V2Repo.setBankLine(l.id, status: 'conciliado', invoiceId: inv.id);
      AppState.instance.bump();
      if (mounted) showSuccess(context, 'Cobro registrado en ${inv.fiscalNumber ?? inv.number}');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickManual(BankLineRow l) async {
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final inv = await showModalBottomSheet<InvoiceRecord>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: ListView(children: [
          ListTile(title: Text('¿A qué factura corresponde ${money(l.amount, cur)}?')),
          for (final i in _open)
            ListTile(
              title: Text('${i.fiscalNumber ?? i.number} · ${i.clientName}'),
              subtitle: Text('Saldo ${money(i.balance, i.currency)} · ${displayDate(i.issueDate)}'),
              onTap: () => Navigator.pop(ctx, i),
            ),
        ]),
      ),
    );
    if (inv != null) _confirm(l, inv);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final lines = _lines ?? const <BankLineRow>[];
    final receivables = [
      for (final i in _open) Receivable(invoiceId: i.id, number: i.fiscalNumber ?? i.number, client: i.clientName, balance: i.balance, issueDate: i.issueDate),
    ];
    final asBank = {for (final l in lines) l.id: BankLine(date: l.date, description: l.description, amount: l.amount, reference: l.reference)};
    final sugg = suggestMatches(asBank.values.toList(), receivables);
    MatchSuggestion? suggestionFor(BankLineRow l) {
      final b = asBank[l.id];
      for (final s in sugg) {
        if (identical(s.line, b)) return s;
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Conciliación bancaria')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _lines == null
              ? const SkeletonList()
              : AbsorbPointer(
                  absorbing: _busy,
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                      SoftCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('1. Descarga tu estado de cuenta en Excel o CSV desde la web de tu banco.\n2. Súbelo aquí.\n3. Confirma las coincidencias que te proponemos.',
                              style: t.textTheme.bodyMedium),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _busy ? null : _import,
                            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file_rounded),
                            label: const Text('Subir estado de cuenta'),
                          ),
                          if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg, style: t.textTheme.bodySmall)),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      if (lines.isEmpty)
                        const EmptyState(title: 'Nada pendiente', body: 'Cuando subas tu estado de cuenta, aquí verás los ingresos por conciliar.')
                      else ...[
                        SectionTitle('Por conciliar (${lines.length})'),
                        for (final l in lines)
                          Builder(builder: (context) {
                            final s = suggestionFor(l);
                            final inv = s == null ? null : _open.where((i) => i.id == s.invoice.invoiceId).firstOrNull;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SoftCard(
                                padding: const EdgeInsets.all(14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(l.description.isEmpty ? '(sin descripción)' : l.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall)),
                                    Money(money(l.amount, cur), weight: FontWeight.w800, color: l.amount > 0 ? Brand.ok : Brand.bad),
                                  ]),
                                  Text('${displayDate(l.date)}${l.reference.isNotEmpty ? ' · op. ${l.reference}' : ''}', style: t.textTheme.bodySmall),
                                  if (inv != null) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(color: Brand.ok.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(Radii.md)),
                                      child: Row(children: [
                                        const Icon(Icons.auto_awesome_rounded, color: Brand.ok, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text('Parece ${inv.fiscalNumber ?? inv.number} de ${inv.clientName} (${s!.why})', style: t.textTheme.bodySmall)),
                                        FilledButton(onPressed: () => _confirm(l, inv), child: const Text('Confirmar')),
                                      ]),
                                    ),
                                  ],
                                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                    if (l.amount > 0 && _open.isNotEmpty) TextButton(onPressed: () => _pickManual(l), child: const Text('Elegir factura')),
                                    TextButton(
                                      onPressed: () async {
                                        await V2Repo.setBankLine(l.id, status: 'ignorado').catchError((_) {});
                                        _load();
                                      },
                                      child: const Text('Ignorar'),
                                    ),
                                  ]),
                                ]),
                              ),
                            );
                          }),
                      ],
                    ]),
                  ),
                ),
    );
  }
}
