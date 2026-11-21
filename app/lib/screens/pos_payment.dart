import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../ui/retail_visual.dart';
import '../ui/theme.dart';
import '../ui/design_tokens.dart';
import '../ui/glass_widgets.dart';
import '../ui/motion.dart';
import '../models_pro.dart';
import '../services/pro_repo.dart';
import 'client_profile.dart' show StorageImage;
import 'pos_payment_logic.dart';

/// A cash register confirmation, not bank settlement or automatic QR verification.
class PosPaymentApproval {
  const PosPaymentApproval(this.method, this.note);
  final String method;
  final String note;
}

/// Identifica el medio de pago también cuando el dispositivo está sin conexión.
class PosPaymentBrand extends StatelessWidget {
  const PosPaymentBrand(this.method, {super.key, this.size = 53});
  final String method;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = switch (method) {
      'efectivo' => Icons.payments_outlined,
      'transferencia' => Icons.account_balance_outlined,
      'yape' || 'plin' => Icons.qr_code_2_rounded,
      _ => Icons.credit_card_outlined,
    };
    final accent = switch (method) {
      'yape' => Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFE5BBF0) : const Color(0xFF762C80),
      'tarjeta' || 'transferencia' => scheme.secondary,
      _ => scheme.primary,
    };
    return Semantics(image: true, label: posMethodLabel(method),
      child: Container(width: size, height: size,
        decoration: BoxDecoration(color: Color.alphaBlend(accent.withValues(alpha: .11), scheme.surface),
          borderRadius: BorderRadius.circular(size * .26)),
        child: Icon(glyph, size: size * .57, color: accent)));
  }
}

String posMethodLabel(String method) => switch (method) {
  'efectivo' => 'Efectivo',
  'yape' => 'Yape',
  'plin' => 'Plin',
  'tarjeta' => 'Tarjeta',
  'transferencia' => 'Transferencia',
  _ => method,
};

/// Componente visual independiente; no aprueba pagos ni registra cobros.
class PosPaymentMethodCard extends StatelessWidget {
  const PosPaymentMethodCard({
    super.key, required this.method, required this.selected,
    required this.onSelected,
  });

  final String method;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      selected: selected,
      button: true,
      label: 'Seleccionar ${posMethodLabel(method)}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onSelected();
          },
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: still ? Duration.zero : FvTokens.transition,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 9),
            decoration: BoxDecoration(
              color: selected && !highContrast ? null : t.colorScheme.surface,
              gradient: selected && !highContrast
                  ? FvLuxe.editorial(t.brightness) : null,
              border: Border.all(
                color: selected ? t.colorScheme.primary
                    : t.colorScheme.outlineVariant,
                width: selected ? 1.7 : .8,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: selected ? FvTokens.shadow(t.brightness) : null,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              PosPaymentBrand(method, size: 45),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: Text(posMethodLabel(method), maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.labelLarge?.copyWith(
                    color: t.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600))),
                if (selected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle_rounded, color: t.colorScheme.primary,
                    size: 17),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Steps 2 and 3 of the POS reference: method → collection evidence.
/// Returns only after explicit cashier confirmation; caller commits the sale.
Future<PosPaymentApproval?> choosePosPayment(
  BuildContext context, {
  required String currency,
  required double total,
  required List<LineItem> items,
}) => Navigator.of(context).push<PosPaymentApproval>(MaterialPageRoute(
  builder: (_) => _PaymentFlow(currency: currency, total: total, items: items),
));

/// Compatibility entry point for integrations that already selected a method.
Future<PosPaymentApproval?> confirmPosPayment(
  BuildContext context, {
  required String method,
  required String currency,
  required double total,
}) => Navigator.of(context).push<PosPaymentApproval>(MaterialPageRoute(
  builder: (_) => _PaymentFlow(currency: currency, total: total, items: const [], initialMethod: method),
));

class _PaymentFlow extends StatefulWidget {
  const _PaymentFlow({required this.currency, required this.total, required this.items, this.initialMethod});
  final String currency;
  final double total;
  final List<LineItem> items;
  final String? initialMethod;

  @override
  State<_PaymentFlow> createState() => _PaymentFlowState();
}

class _PaymentFlowState extends State<_PaymentFlow> {
  PaySettings? _merchant;
  bool _loading = true;
  bool _verified = false;
  String? _method;
  final _tender = TextEditingController();

  @override
  void initState() {
    super.initState();
    _method = widget.initialMethod;
    _tender.text = widget.total.toStringAsFixed(2);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final pay = await ProRepo.loadPaySettings();
      if (mounted) setState(() => _merchant = pay);
    } catch (_) {
      // Fail closed for QR and bank payments if merchant details cannot load.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tender.dispose();
    super.dispose();
  }

  String get _account => switch (_method) {
    'yape' => _merchant?.yape ?? '',
    'plin' => _merchant?.plin ?? '',
    'transferencia' => _merchant?.bankAccount ?? '',
    _ => '',
  };

  String get _qrPath => switch (_method) {
    'yape' => _merchant?.yapeQrPath ?? '',
    'plin' => _merchant?.plinQrPath ?? '',
    _ => '',
  };

  bool get _requiresAccount => const {'yape', 'plin', 'transferencia'}.contains(_method);
  int get _chargeCents => posMoneyToCents(widget.total);
  int? get _tendered => parsePosCents(_tender.text);
  bool get _sufficient => _tendered != null && _tendered! >= _chargeCents;

  bool get _canConfirm {
    if (_loading) { return false; }
    if (_method == 'efectivo') { return _sufficient; }
    if (_method == 'tarjeta') return _verified;
    return _verified && (!_requiresAccount || _account.isNotEmpty || _qrPath.isNotEmpty);
  }

  void _confirm() {
    if (!_canConfirm || _method == null) return;
    HapticFeedback.mediumImpact();
    final note = _method == 'efectivo'
        ? 'Efectivo recibido: ${money(_tendered! / 100, widget.currency)} · '
            'Vuelto: ${money(posChangeDue(chargeCents: _chargeCents, tenderedCents: _tendered!) / 100, widget.currency)}'
        : '${posMethodLabel(_method!)}: abono confirmado manualmente por el cajero';
    Navigator.of(context).pop(PosPaymentApproval(_method!, note));
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16), Color? color}) {
    final t = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? t.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.colorScheme.outlineVariant, width: .65),
        boxShadow: FvTokens.shadow(t.brightness),
      ),
      child: child,
    );
  }

  Widget _methodTile(String method) => PosPaymentMethodCard(
    method: method,
    selected: _method == method,
    onSelected: () => setState(() {
      _method = method;
      _verified = false;
    }),
  );

  @override
  Widget build(BuildContext context) {
    final method = _method;
    final t = Theme.of(context);
    final c = DsColors.of(context);
    return Scaffold(
        appBar: AppBar(
          flexibleSpace: const FvGlassTopBar(),
          title: Text(method == null ? 'Método de cobro' : 'Cobro ${posMethodLabel(method).toLowerCase()}'),
          leading: IconButton(
            tooltip: method == null ? 'Volver' : 'Cambiar método',
            onPressed: () {
              if (method != null) {
                setState(() { _method = null; _verified = false; });
              } else {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(children: [
            Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              RetailVisual.journey(step: 3,
                label: method == null ? 'Elegir medio de pago' : 'Verificar y confirmar'),
              const SizedBox(height: 15),
              _card(
                color: t.brightness == Brightness.dark
                    ? const Color(0xFF203746) : FvLuxe.jadeSoft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total a cobrar', style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 5),
                Text(money(widget.total, widget.currency), style: t.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800, letterSpacing: -.9,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: t.colorScheme.onSurface)),
                if (widget.items.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('Resumen del pedido (${widget.items.length})',
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final item in widget.items.take(12))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(child: Text(item.description, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text('×${qtyText(item.quantity)}'),
                        const SizedBox(width: 12),
                        Text(money(item.quantity * item.unitPrice, widget.currency)),
                      ]),
                    ),
                ],
              ])),
              const SizedBox(height: 20),
              if (method == null) ...[
                const Text('Elige cómo te pagará el cliente',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 14),
                LayoutBuilder(builder: (context, layout) {
                  final columns = layout.maxWidth >= 620 ? 4
                      : layout.maxWidth >= 460 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: MediaQuery.textScalerOf(context).scale(1.0) > 1.3 ? 150 : 128,
                      mainAxisSpacing: 12, crossAxisSpacing: 12,
                    ),
                    itemCount: 4,
                    itemBuilder: (context, i) =>
                      _methodTile(const ['efectivo', 'yape', 'plin', 'tarjeta'][i]),
                  );
                }),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() { _method = 'transferencia'; _verified = false; }),
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('Transferencia bancaria'),
                ),
                const SizedBox(height: 14),
                Text('El efectivo calcula el vuelto. Yape, Plin y tarjeta necesitan confirmación del cajero.',
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall?.copyWith(color: c.muted)),
              ] else ...[
                _card(color: t.colorScheme.surfaceContainerHigh, child: Column(children: [
                  PosPaymentBrand(method, size: 78),
                  const SizedBox(height: 10),
                  Text('Paga con ${posMethodLabel(method)}', style: t.textTheme.titleMedium?.copyWith(
                    color: c.ink, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(money(widget.total, widget.currency),
                    style: t.textTheme.displaySmall?.copyWith(
                      color: c.ink, fontWeight: FontWeight.w800)),
                  if (_merchant?.holder.isNotEmpty == true)
                    Text(_merchant!.holder, textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium?.copyWith(color: c.muted)),
                  if (_requiresAccount && _account.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(_account, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    TextButton.icon(
                      onPressed: () { Clipboard.setData(ClipboardData(text: _account)); },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copiar número o cuenta'),
                    ),
                  ],
                  if ((method == 'yape' || method == 'plin') && _qrPath.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: 186, height: 186, color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: StorageImage(path: _qrPath),
                    ),
                    Text('QR de cobro configurado por el negocio',
                      style: t.textTheme.bodySmall?.copyWith(color: c.muted)),
                  ],
                  if (_requiresAccount && _account.isEmpty && _qrPath.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text('Primero configura el medio de cobro en Ajustes. No se generará un QR ficticio.',
                        textAlign: TextAlign.center, style: TextStyle(color: c.bad)),
                    ),
                ])),
                const SizedBox(height: 16),
                if (method == 'efectivo')
                  _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Efectivo recibido', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _tender,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixText: posCurrencyPrefix(widget.currency),
                        hintText: 'Monto recibido',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(_sufficient
                        ? 'Vuelto: ${money(posChangeDue(chargeCents: _chargeCents, tenderedCents: _tendered!) / 100, widget.currency)}'
                        : 'El monto recibido es insuficiente.',
                      style: TextStyle(fontWeight: FontWeight.w900,
                        color: _sufficient ? c.ok : c.bad)),
                  ]))
                else _card(child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _verified,
                  onChanged: (_requiresAccount && _account.isEmpty && _qrPath.isEmpty) || _loading
                    ? null : (v) => setState(() => _verified = v ?? false),
                  title: Text(method == 'tarjeta'
                    ? 'El terminal POS autorizó el pago'
                    : 'He verificado el abono en mi cuenta'),
                  subtitle: const Text('No se conecta automáticamente al banco. Confirma únicamente después de recibir el pago.'),
                )),
              ],
            ],
          )),
          if (method != null)
            SafeArea(top: false, minimum: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: FvTactileScale(
                enabled: _canConfirm,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: t.colorScheme.onSurface,
                    foregroundColor: t.colorScheme.surface,
                  ),
                  onPressed: _canConfirm ? _confirm : null,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Confirmar pago', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ]),
        )),
    );
  }
}
