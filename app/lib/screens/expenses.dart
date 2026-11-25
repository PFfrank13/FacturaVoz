import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../models_pro.dart';
import '../logic/scan_checks.dart';
import '../reports.dart' show monthNames, monthRange;
import '../services/pro_repo.dart';
import '../services/live.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../ui/retail_layout.dart';
import '../ui/design_tokens.dart';
import 'scan.dart';

IconData expenseIcon(String c) => switch (c) {
      'mercaderia' => Icons.inventory_2_rounded,
      'insumos' => Icons.handyman_rounded,
      'servicios' => Icons.bolt_rounded,
      'alquiler' => Icons.storefront_rounded,
      'planilla' => Icons.groups_rounded,
      'transporte' => Icons.local_shipping_rounded,
      'marketing' => Icons.campaign_rounded,
      'impuestos' => Icons.account_balance_rounded,
      'equipos' => Icons.devices_rounded,
      _ => Icons.receipt_rounded,
    };

/// Registrar o confirmar un gasto. [prefill] viene del Copiloto (voz) o del escáner. Devuelve true si se guardó.
Future<bool> showExpenseSheet(BuildContext context, {Expense? prefill}) async {
  final cur = AppState.instance.profile?.currency ?? 'PEN';
  final desc = TextEditingController(text: prefill?.description ?? '');
  final total = TextEditingController(text: prefill == null || prefill.total <= 0 ? '' : qtyText(prefill.total));
  final tax = TextEditingController(text: prefill == null || prefill.tax <= 0 ? '' : qtyText(prefill.tax));
  final supplier = TextEditingController(text: prefill?.supplierName ?? '');
  var category = prefill?.category ?? 'otros';
  var date = prefill?.spentOn.isNotEmpty == true ? prefill!.spentOn : todayIso();
  var hasIgv = (prefill?.tax ?? 0) > 0;
  var err = '';
  var saving = false;
  // v2.0: avisos sobre lo leído por el escáner (sin tocar el escáner): fecha antigua, comprador distinto, a mano.
  final scan = prefill?.source == 'scan' ? DocScan.last : null;
  final handwritten = scan != null && looksHandwritten(supplierTaxId: scan.supplierTaxId, docNumber: scan.docNumber, docType: scan.docType);
  final warnings = scan == null
      ? const <ScanWarning>[]
      : scanWarnings(
          issueDate: scan.issueDate,
          supplierTaxId: scan.supplierTaxId,
          clientTaxId: scan.clientTaxId,
          docType: scan.docType,
          confidence: shownConfidence(scan.confidence, handwritten: handwritten),
          looksHandwritten: handwritten,
          myRuc: AppState.instance.profile?.taxId ?? '',
          today: todayIso(),
        );

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final t = Theme.of(ctx);
      Future<void> save() async {
        final v = parseDecimal(total.text);
        final g = hasIgv ? (parseDecimal(tax.text) ?? round2((v ?? 0) - (v ?? 0) / 1.18)) : 0.0;
        String? problem;
        if (desc.text.trim().isEmpty) {
          problem = 'Describe el gasto';
        } else if (v == null || v <= 0) {
          problem = 'Escribe el monto total pagado';
        } else if (g < 0 || g > v) {
          problem = 'El IGV no puede ser mayor que el total';
        }
        if (problem != null || v == null) {
          setS(() => err = problem ?? 'Revisa el monto');
          return;
        }
        setS(() {
          saving = true;
          err = '';
        });
        try {
          await ProRepo.addExpense(Expense(
            spentOn: date,
            category: category,
            description: desc.text,
            total: v,
            tax: round2(g),
            currency: prefill?.currency ?? cur,
            supplierName: supplier.text,
            supplierTaxId: prefill?.supplierTaxId ?? '',
            docNumber: prefill?.docNumber ?? '',
            source: prefill?.source ?? 'manual',
          ));
          if (ctx.mounted) Navigator.pop(ctx, true);
        } catch (e) {
          setS(() {
            saving = false;
            err = ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261101_negocio_pro.sql.' : friendly(e);
          });
        }
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(prefill == null ? 'Nuevo gasto' : 'Confirma el gasto', style: t.textTheme.titleLarge),
            if (prefill?.source == 'scan') Text('Leído de la foto: revisa los montos antes de guardar.', style: t.textTheme.bodySmall),
            if (scan != null)
              Text('Seguridad de la lectura: ${(shownConfidence(scan.confidence, handwritten: handwritten) * 100).round()} %${handwritten ? ' (escrito a mano)' : ''}', style: t.textTheme.bodySmall),
            for (final w in warnings)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: (w.serious ? Brand.bad : Brand.warn).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(w.serious ? Icons.error_outline_rounded : Icons.info_outline_rounded, size: 18, color: w.serious ? Brand.bad : Brand.warn),
                  const SizedBox(width: 8),
                  Expanded(child: Text(w.text, style: t.textTheme.bodySmall)),
                ]),
              ),
            if (prefill?.source == 'voice') Text('Entendí esto de lo que dijiste.', style: t.textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: total,
              autofocus: prefill == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700),
              decoration: InputDecoration(labelText: 'Total pagado', prefixText: '${currencySymbols[prefill?.currency ?? cur] ?? cur} '),
            ),
            const SizedBox(height: 12),
            TextField(controller: desc, maxLength: 200, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: '¿En qué?', counterText: '')),
            const SizedBox(height: 12),
            Text('Categoría', style: t.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in expenseCategories.entries)
                ChoiceChip(
                  avatar: Icon(expenseIcon(e.key), size: 17),
                  label: Text(e.value.split(' (').first),
                  selected: category == e.key,
                  onSelected: (_) {
                    Haptics.select();
                    setS(() => category = e.key);
                  },
                ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: supplier, maxLength: 120, decoration: const InputDecoration(labelText: 'Proveedor (opcional)', counterText: '')),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: hasIgv,
              onChanged: (v) => setS(() => hasIgv = v),
              title: const Text('Tiene factura con IGV'),
              subtitle: const Text('El IGV de tus compras se descuenta del que pagas (crédito fiscal).'),
            ),
            if (hasIgv)
              TextField(
                controller: tax,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: 'IGV (vacío = 18 % incluido)'),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text('Fecha: ${displayDate(date)}'),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.parse(date),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (d != null) setS(() => date = todayIso(d));
              },
            ),
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err, style: const TextStyle(color: Brand.bad))),
            const SizedBox(height: 14),
            GradientButton(label: saving ? 'Guardando…' : 'Guardar gasto', icon: Icons.check_rounded, busy: saving, onPressed: saving ? null : save),
          ]),
        ),
      );
    }),
  );
  disposeAfterClose([desc, total, tax, supplier]);
  return ok == true;
}

/// Lista de gastos por mes.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> with LiveReload<ExpensesScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  List<Expense>? _items;
  String? _error;

  @override
  List<String> get liveTables => const ['expenses'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _load();
    startLive(); // tiempo real
  }

  @override
  void dispose() {
    stopLive();
    super.dispose();
  }

  Future<void> _load() async {
    final key = 'expenses.$_year-$_month';
    setState(() {
      _items = LiveCache.get<List<Expense>>(key); // lo último que se vio de ese mes, al instante
      _error = null;
    });
    try {
      final r = monthRange(_year, _month);
      final list = await ProRepo.listExpenses(r.from, r.toExclusive);
      LiveCache.put(key, list);
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) setState(() => _error = ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261101_negocio_pro.sql en Supabase.' : friendly(e));
    }
  }

  void _shift(int d) {
    final x = DateTime(_year, _month + d, 1);
    if (x.isAfter(DateTime.now())) return;
    Haptics.select();
    _year = x.year;
    _month = x.month;
    _load();
  }

  Future<void> _add() async {
    if (await showExpenseSheet(context)) {
      AppState.instance.bump();
      if (mounted) showSuccess(context, 'Gasto registrado');
      _load();
    }
  }

  Future<void> _scan() async {
    final ok = await pushPremium<bool>(context, const ScanScreen());
    if (ok == true) {
      AppState.instance.bump();
      _load();
    }
  }

  Future<void> _delete(Expense e) async {
    try {
      await ProRepo.deleteExpense(e.id!);
      AppState.instance.bump();
      _load();
    } catch (x) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(x))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final items = _items;
    final total = round2((items ?? const <Expense>[]).where((e) => e.currency == cur).fold<double>(0, (s, e) => s + e.total));
    final now = DateTime.now();
    final isCurrent = _year == now.year && _month == now.month;
    return RetailResponsiveFrame(maxWidth: 1100, child: Scaffold(
      appBar: AppBar(title: const Text('Gastos'), actions: [if (Access.instance.has('cuaderno_ia')) IconButton(onPressed: _scan, icon: const Icon(Icons.document_scanner_rounded), tooltip: 'Escanear comprobante')]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('Gasto')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 110), children: [
          Row(children: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(child: Text('${monthNames[_month - 1]} $_year', textAlign: TextAlign.center, style: t.textTheme.titleMedium)),
            IconButton(onPressed: isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          const SizedBox(height: 8),
          Reveal(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: t.colorScheme.surface,
                borderRadius: BorderRadius.circular(FvTokens.cardRadius),
                border: Border.all(
                  color: t.colorScheme.outlineVariant.withValues(alpha: .2)),
                boxShadow: FvTokens.shadow(t.brightness),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total de gastos del mes',
                  style: t.textTheme.labelMedium?.copyWith(
                    color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 7),
                CountUp(
                  value: total,
                  builder: (c, v) => Money(
                    money(v, cur), size: 30, weight: FontWeight.w800)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            SoftCard(child: Text(_error!, textAlign: TextAlign.center))
          else if (items == null)
            const SkeletonList(count: 4)
          else if (items.isEmpty)
            const EmptyState(title: 'Sin gastos este mes', body: 'Registra tus compras y pagos (o escanea la boleta) para saber cuánto ganas de verdad.')
          else
            LayoutBuilder(builder: (context, available) {
              final columns = retailCardColumnCount(
                available.maxWidth, twoColumnMinWidth: 820);
              final width = (available.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 0,
                children: [
                  for (final (i, e) in items.indexed)
                    SizedBox(width: width, child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Reveal(
                  key: ValueKey(e.id),
                  index: i < 8 ? i : 8,
                  child: Dismissible(
                    key: ValueKey('d-${e.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(color: Brand.bad.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(24)),
                      child: const Icon(Icons.delete_outline_rounded, color: Brand.bad),
                    ),
                    confirmDismiss: (_) async {
                      Haptics.warning();
                      return await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('¿Borrar este gasto?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
                              ],
                            ),
                          ) ??
                          false;
                    },
                    onDismissed: (_) {
                      setState(() => _items = [...items]..remove(e));
                      _delete(e);
                    },
                    child: SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: Brand.goldDeep.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                          child: Icon(expenseIcon(e.category), color: Brand.goldDeep),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(e.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                            Text(
                              [displayDate(e.spentOn), expenseCategories[e.category]?.split(' (').first ?? e.category, if (e.supplierName.isNotEmpty) e.supplierName].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodySmall,
                            ),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Money(money(e.total, e.currency), size: 15, weight: FontWeight.w700),
                          if (e.source != 'manual')
                            Icon(e.source == 'scan' ? Icons.document_scanner_rounded : Icons.mic_rounded, size: 14, color: t.colorScheme.onSurfaceVariant),
                        ]),
                      ]),
                    ),
                  ),
                ),
              )),
                ],
              );
            }),
          if (items != null && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Desliza a la izquierda para borrar.', textAlign: TextAlign.center, style: t.textTheme.bodySmall),
            ),
        ]),
      ),
    ));
  }
}
