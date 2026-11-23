// Vencimientos y mermas (v3.6): qué vence pronto, qué ya venció con stock y las mermas con su motivo.
// Misma base que el ERP web (Inventario). Investigación: docs/INVESTIGACION_RETAIL.md, filas 3 y 4.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/live.dart';
import '../services/repo.dart';
import '../services/stock_lots.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import '../ui/retail_layout.dart';
import '../ui/retail_visual.dart';
import '../ui/widgets.dart';

String get _cur => AppState.instance.profile?.currency.isNotEmpty == true ? AppState.instance.profile!.currency : 'PEN';
const _months = ['ene.', 'feb.', 'mar.', 'abr.', 'may.', 'jun.', 'jul.', 'ago.', 'set.', 'oct.', 'nov.', 'dic.'];

/// «27 nov. 2026».
String dayMonthYear(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
/// 'AAAA-MM-DD'.
String isoDay(DateTime d) => isoDate(d);

String daysText(int d) => d < 0
    ? (d == -1 ? 'venció ayer' : 'venció hace ${-d} días')
    : d == 0 ? 'vence hoy' : d == 1 ? 'vence mañana' : 'vence en $d días';

Color bucketColor(String bucket) => switch (bucket) {
      'vencido' => const Color(0xFFE5484D),
      'semana' => const Color(0xFFF5A524),
      'mes' => const Color(0xFF5B9BFF),
      _ => const Color(0xFF2FBF8F),
    };

class StockLotsScreen extends StatefulWidget {
  const StockLotsScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<StockLotsScreen> createState() => _StockLotsScreenState();
}

class _StockLotsScreenState extends State<StockLotsScreen> with LiveReload<StockLotsScreen> {
  List<LotStatus>? _lots;
  String? _error;
  String? _activeOrg;
  int _gen = 0;

  bool get _canEdit => Access.instance.can('products_edit');

  @override
  List<String> get liveTables => const ['product_lots', 'stock_losses', 'products'];

  @override
  Future<void> reloadLive() => _load();

  void _onCompanyChange() {
    final org = Repo.activeOrgId;
    if (!mounted || org == _activeOrg) return;
    _activeOrg = org;
    _gen++;
    setState(() { _lots = null; _error = null; });
    _load();
  }

  @override
  void initState() {
    super.initState();
    _activeOrg = Repo.activeOrgId;
    AppState.instance.addListener(_onCompanyChange);
    _load();
    startLive();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onCompanyChange);
    stopLive();
    super.dispose();
  }

  Future<void> _load() async {
    final org = Repo.activeOrgId;
    final gen = ++_gen;
    try {
      final lots = await StockLotsRepo.status();
      if (!mounted || org != Repo.activeOrgId || gen != _gen) return;
      setState(() { _lots = lots; _error = null; });
    } catch (e) {
      if (mounted && org == Repo.activeOrgId && gen == _gen) setState(() => _error = friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lots = _lots;
    final active = lots == null ? const <LotStatus>[] : activeLots(lots);
    final urgent = active.where((l) => l.daysLeft <= 30).toList();
    final expired = active.where((l) => l.daysLeft < 0).toList();
    final week = active.where((l) => l.daysLeft >= 0 && l.daysLeft <= 7).toList();
    final atRisk = [...expired, ...week].fold<double>(0, (a, l) => a + l.remaining * (l.unitCost ?? l.unitPrice ?? 0));
    final body = _error != null
        ? Center(child: DsStateView.error(message: _error!, onRetry: _load))
        : lots == null
            ? const SkeletonList()
            : RefreshIndicator(
                onRefresh: _load,
                child: RetailResponsiveFrame(maxWidth: 1040, child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
                  Reveal(child: RetailVisual.hero(
                    context: context,
                    chapter: RetailChapter.inventory,
                    eyebrow: 'Inventario · Vencimientos',
                    title: expired.isNotEmpty ? 'Retira lo vencido' : week.isNotEmpty ? 'Vende primero lo que vence' : 'Nada por vencer esta semana',
                    subtitle: 'Se calcula con tus compras y lo que queda en stock: se asume que vendes primero lo que vence antes.',
                    icon: Icons.event_busy_rounded,
                    footer: Row(children: [
                      Expanded(child: RetailVisual.microStat('Vencidos con stock', '${expired.length}')),
                      const SizedBox(width: 10),
                      Expanded(child: RetailVisual.microStat('Vencen en 7 días', '${week.length}')),
                      const SizedBox(width: 10),
                      Expanded(child: RetailVisual.microStat('En riesgo', money(atRisk, _cur))),
                    ]),
                  )),
                  const SizedBox(height: 14),
                  if (urgent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        lots.isEmpty
                            ? 'Aún no hay fechas de vencimiento. Anótalas al recibir una compra o en la ficha de cada producto.'
                            : 'Ningún lote vence en los próximos 30 días.',
                        textAlign: TextAlign.center, style: t.textTheme.bodyMedium,
                      ),
                    ),
                  for (final l in urgent) _LotTile(lot: l, canEdit: _canEdit, onChanged: _load),
                ])),
              );
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded ? null : AppBar(title: const Text('Vencimientos y mermas')),
      body: body,
    );
  }
}

class _LotTile extends StatelessWidget {
  const _LotTile({required this.lot, required this.canEdit, required this.onChanged});
  final LotStatus lot;
  final bool canEdit;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bucket = expiryBucket(lot.daysLeft);
    final offer = suggestedPrice(lot.unitPrice, lot.unitCost, lot.daysLeft);
    final unit = lot.unit == 'KGM' ? 'kg' : 'u.';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, right: 10),
              decoration: BoxDecoration(color: bucketColor(bucket), shape: BoxShape.circle)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lot.productName, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${qtyText(lot.remaining)} $unit · ${daysText(lot.daysLeft)} (${dayMonthYear(lot.expiresOn)})${lot.lotCode == null ? '' : ' · lote ${lot.lotCode}'}',
                style: t.textTheme.bodySmall),
              if (offer != null) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Rebájalo a ${money(offer, _cur)} para venderlo antes de que venza.',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
              ),
            ])),
          ]),
          if (canEdit) Align(
            alignment: Alignment.centerRight,
            child: bucket == 'vencido'
                ? FilledButton.icon(
                    icon: const Icon(Icons.delete_sweep_rounded), label: const Text('Retirar como merma'),
                    onPressed: () async { if (await showLossSheet(context, productId: lot.productId, productName: lot.productName, stock: null, lots: [lot], reason: 'vencido', quantity: lot.remaining, lotId: lot.lotId) == true) await onChanged(); },
                  )
                : TextButton.icon(
                    icon: const Icon(Icons.remove_circle_outline_rounded), label: const Text('Registrar merma'),
                    onPressed: () async { if (await showLossSheet(context, productId: lot.productId, productName: lot.productName, stock: null, lots: [lot], reason: 'danado', lotId: lot.lotId) == true) await onChanged(); },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Hoja para registrar una merma con motivo. [stock] null = el servidor valida contra el stock real.
/// Devuelve true si se registró.
Future<bool?> showLossSheet(BuildContext context, {
  required String productId, required String productName, required double? stock, List<LotStatus> lots = const [],
  String reason = 'vencido', double? quantity, String? lotId,
}) {
  return showModalBottomSheet<bool>(
    context: context, isScrollControlled: true, showDragHandle: true,
    builder: (_) => _LossSheet(productId: productId, productName: productName, stock: stock, lots: lots, reason: reason, quantity: quantity, lotId: lotId),
  );
}

class _LossSheet extends StatefulWidget {
  const _LossSheet({required this.productId, required this.productName, required this.stock, required this.lots, required this.reason, this.quantity, this.lotId});
  final String productId;
  final String productName;
  final double? stock;
  final List<LotStatus> lots;
  final String reason;
  final double? quantity;
  final String? lotId;

  @override
  State<_LossSheet> createState() => _LossSheetState();
}

class _LossSheetState extends State<_LossSheet> {
  late final _qty = TextEditingController(text: widget.quantity == null ? '' : qtyText(widget.quantity!));
  final _note = TextEditingController();
  late String _reason = widget.reason;
  late String? _lot = widget.lotId;
  final String _requestId = Repo.newRequestId(); // el mismo id en reintentos: nunca descuenta dos veces
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final q = parseDecimal(_qty.text);
    final limit = widget.stock ?? widget.lots.where((l) => l.lotId == _lot).map((l) => l.remaining).firstOrNull ?? 1e9;
    final problem = lossProblem(q, _reason, _note.text, limit);
    if (problem != null) return setState(() => _error = problem);
    setState(() { _busy = true; _error = null; });
    try {
      final left = await StockLotsRepo.recordLoss(requestId: _requestId, productId: widget.productId, quantity: q!, reason: _reason, lotId: _lot, note: _note.text);
      Haptics.success();
      LiveCache.clear();
      AppState.instance.bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Merma registrada. Quedan ${qtyText(left)} en stock.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = friendly(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Merma: ${widget.productName}', style: t.textTheme.titleLarge),
        if (widget.stock != null) Text('Stock actual: ${qtyText(widget.stock!)}', style: t.textTheme.bodySmall),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in lossReasons.entries)
            ChoiceChip(label: Text(e.value), selected: _reason == e.key, onSelected: _busy ? null : (_) => setState(() => _reason = e.key)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _qty, autofocus: widget.quantity == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(labelText: 'Cantidad'),
        ),
        if (widget.lots.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _lot,
            decoration: const InputDecoration(labelText: 'Lote'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Sin lote')),
              for (final l in widget.lots)
                DropdownMenuItem<String?>(value: l.lotId, child: Text('${dayMonthYear(l.expiresOn)}${l.lotCode == null ? '' : ' · ${l.lotCode}'}')),
            ],
            onChanged: _busy ? null : (v) => setState(() => _lot = v),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _note, maxLength: 200,
          decoration: InputDecoration(labelText: _reason == 'otro' ? 'Motivo (obligatorio)' : 'Nota (opcional)'),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: t.colorScheme.error))),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
          label: const Text('Registrar merma'),
        ),
      ])),
    );
  }
}

/// Hoja para anotar la fecha de vencimiento de mercadería que ya está en el anaquel.
Future<bool?> showAddLotSheet(BuildContext context, {required String productId, required String productName, required String unit}) async {
  DateTime? date;
  final qty = TextEditingController();
  final code = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context, isScrollControlled: true, showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Fecha de vencimiento: $productName', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event_rounded),
          label: Text(date == null ? 'Elegir fecha' : 'Vence el ${dayMonthYear(date!)}'),
          onPressed: () async {
            final now = DateTime.now();
            final p = await showDatePicker(context: ctx, initialDate: date ?? now.add(const Duration(days: 30)), firstDate: now.subtract(const Duration(days: 365)), lastDate: DateTime(now.year + 10));
            if (p != null) setS(() => date = p);
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Cantidad que vence ese día (${unit == 'KGM' ? 'kg' : 'unidades'})')),
        const SizedBox(height: 12),
        TextField(controller: code, maxLength: 40, decoration: const InputDecoration(labelText: 'Lote (opcional)')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
      ]),
    )),
  );
  final q = parseDecimal(qty.text);
  final c = code.text;
  disposeAfterClose([qty, code]);
  if (ok != true || !context.mounted) return null;
  if (date == null || q == null || q <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elige la fecha y la cantidad.')));
    return false;
  }
  try {
    await StockLotsRepo.addLot(productId: productId, expiresOn: date!, quantity: q, code: c);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fecha de vencimiento guardada.')));
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    return false;
  }
}
