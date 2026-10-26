import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../whatsapp.dart';

/// Cobros de una factura emitida: saldo, barra de avance, historial, registrar cobro y vencimiento.
class PaymentsCard extends StatefulWidget {
  const PaymentsCard({super.key, required this.invoice, required this.onChanged});
  final InvoiceRecord invoice;

  /// Se llama tras registrar/anular un cobro o cambiar el vencimiento (la pantalla recarga la factura).
  final Future<void> Function() onChanged;

  @override
  State<PaymentsCard> createState() => _PaymentsCardState();
}

class _PaymentsCardState extends State<PaymentsCard> {
  List<Payment>? _list;
  String? _error;
  bool _busy = false;
  String? _due;

  double get _total => widget.invoice.totals.total;
  double get _paid => round2((_list ?? const <Payment>[]).fold<double>(0, (a, p) => a + p.amount));
  double get _balance => (round2(_total - _paid)).clamp(0, double.infinity).toDouble();

  @override
  void initState() {
    super.initState();
    _due = widget.invoice.dueDate;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Repo.listPayments(widget.invoice.id);
      if (mounted) {
        setState(() {
          _list = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _add() async {
    final amount = TextEditingController(text: _balance > 0 ? qtyText(_balance) : '');
    final note = TextEditingController();
    var method = 'efectivo';
    var err = '';
    final cur = widget.invoice.currency;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Registrar cobro', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Saldo pendiente: ${money(_balance, cur)}', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(labelText: 'Monto cobrado', prefixText: '${currencySymbols[cur] ?? cur} '),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in paymentMethods.entries)
                  ChoiceChip(label: Text(e.value), selected: method == e.key, onSelected: (_) => setS(() => method = e.key)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: note, maxLength: 200, decoration: const InputDecoration(labelText: 'Nota (opcional)', counterText: '')),
              if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: Brand.bad))),
              const SizedBox(height: 14),
              GradientButton(
                label: 'Guardar cobro',
                icon: Icons.check_rounded,
                onPressed: () {
                  final v = parseDecimal(amount.text);
                  if (v == null || v <= 0) {
                    setS(() => err = 'Escribe un monto mayor a cero');
                  } else if (round2(v) > _balance + 0.004) {
                    setS(() => err = 'El monto supera el saldo pendiente (${money(_balance, cur)})');
                  } else {
                    Navigator.pop(ctx, true);
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
    final v = parseDecimal(amount.text);
    final text = note.text;
    disposeAfterClose([amount, note]);
    if (ok != true || v == null) return;
    setState(() => _busy = true);
    try {
      await Repo.addPayment(invoiceId: widget.invoice.id, amount: v, method: method, note: text);
      await _load();
      // Si ya está saldada, pasa a "Pagada" (la base solo lo permite desde "Enviada").
      if (_balance <= 0.004 && widget.invoice.status == 'sent') {
        try {
          await Repo.setStatus(widget.invoice.id, 'paid');
        } catch (_) {}
      }
      HapticFeedback.lightImpact();
      await widget.onChanged();
    } catch (e) {
      _snack('No se pudo registrar el cobro. ${friendly(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Payment p) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Anular este cobro?'),
        content: Text('Se quitarán ${money(p.amount, widget.invoice.currency)} cobrados el ${displayDate(p.paidOn)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Anular')),
        ],
      ),
    );
    if (go != true) return;
    setState(() => _busy = true);
    try {
      await Repo.deletePayment(p.id);
      await _load();
      await widget.onChanged();
    } catch (e) {
      _snack(friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remind() async {
    final inv = widget.invoice;
    final ctrl = TextEditingController();
    var err = '';
    final digits = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Recordar por WhatsApp', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Se abre WhatsApp con el mensaje listo; tú decides si lo envías.', style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]'))],
              decoration: const InputDecoration(labelText: 'Celular del cliente', hintText: '987 654 321', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: Brand.bad))),
            const SizedBox(height: 14),
            GradientButton(
              label: 'Abrir WhatsApp',
              icon: Icons.send_rounded,
              onPressed: () {
                final d = normalizePhone(ctrl.text);
                if (d == null) {
                  setS(() => err = 'Escribe un celular válido (9 dígitos, o con código de país)');
                } else {
                  Navigator.pop(ctx, d);
                }
              },
            ),
          ]),
        ),
      ),
    );
    disposeAfterClose([ctrl]);
    if (digits == null) return;
    final msg = reminderText(
      clientName: inv.clientName,
      businessName: AppState.instance.profile?.businessName ?? '',
      number: inv.fiscalNumber ?? inv.number,
      currency: inv.currency,
      total: _total,
      balance: _balance,
      dueDate: _due,
      today: todayIso(),
    );
    final ok = await launchUrl(whatsappUri(digits, msg), mode: LaunchMode.externalApplication);
    if (!ok) _snack('No se pudo abrir WhatsApp en este dispositivo.');
  }

  Future<void> _pickDue() async {
    final inv = widget.invoice;
    final issue = DateTime.tryParse(inv.issueDate) ?? DateTime.now();
    final initial = DateTime.tryParse(_due ?? '') ?? issue.add(const Duration(days: 15));
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(issue) ? issue : initial,
      firstDate: issue,
      lastDate: issue.add(const Duration(days: 730)),
      helpText: 'Fecha de vencimiento',
    );
    if (d == null) return;
    final iso = todayIso(d);
    try {
      await Repo.setDueDate(inv.id, iso);
      if (mounted) setState(() => _due = iso);
      await widget.onChanged();
    } catch (e) {
      _snack('No se pudo guardar el vencimiento. ${friendly(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final inv = widget.invoice;
    final cur = inv.currency;
    final settled = _list != null && _balance <= 0.004;
    final overdue = !settled && _due != null && _due!.compareTo(todayIso()) < 0;
    final progress = _total <= 0 ? 0.0 : (_paid / _total).clamp(0.0, 1.0);

    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Cobros', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (settled) const StatusPill('Saldada', tone: PillTone.ok) else if (overdue) const StatusPill('Vencida', tone: PillTone.bad),
        ]),
        const SizedBox(height: 12),
        if (_error != null)
          Text(_error!, style: t.textTheme.bodySmall)
        else if (_list == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
        else ...[
          Row(children: [
            Expanded(child: _kv(t, 'Total', money(_total, cur))),
            Expanded(child: _kv(t, 'Cobrado', money(_paid, cur))),
            Expanded(child: _kv(t, 'Saldo', money(_balance, cur), strong: true, color: settled ? Brand.ok : (overdue ? Brand.bad : null))),
          ]),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: v, minHeight: 8, color: settled ? Brand.ok : t.colorScheme.primary, backgroundColor: t.colorScheme.outline.withValues(alpha: .4)),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickDue,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(Icons.event_rounded, size: 18, color: overdue ? Brand.bad : t.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(_due == null ? 'Agregar fecha de vencimiento' : 'Vence el ${displayDate(_due!)}', style: t.textTheme.bodyMedium?.copyWith(color: overdue ? Brand.bad : null)),
                const Spacer(),
                Icon(Icons.edit_calendar_outlined, size: 18, color: t.colorScheme.onSurfaceVariant),
              ]),
            ),
          ),
          if (_list!.isNotEmpty) ...[
            Divider(color: t.colorScheme.outline),
            for (final p in _list!)
              InkWell(
                onLongPress: _busy ? null : () => _remove(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: Brand.ok),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${displayDate(p.paidOn)} · ${paymentMethods[p.method] ?? p.method}${p.note.isEmpty ? '' : ' · ${p.note}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall,
                      ),
                    ),
                    Money(money(p.amount, cur), size: 14),
                  ]),
                ),
              ),
            Text('Mantén pulsado un cobro para anularlo (solo administradores).', style: t.textTheme.bodySmall?.copyWith(fontSize: 11)),
          ],
          if (!settled) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(onPressed: _busy ? null : _add, icon: const Icon(Icons.add_card_rounded), label: const Text('Registrar cobro')),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(onPressed: _remind, icon: const Icon(Icons.chat_outlined), label: const Text('Recordar por WhatsApp')),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _kv(ThemeData t, String k, String v, {bool strong = false, Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: t.textTheme.bodySmall),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(v, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, fontSize: strong ? 16 : 14, color: color)),
        ),
      ]);
}
