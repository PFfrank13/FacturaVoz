import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
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

const _navy = Color(0xFF0B1030);
const _panel = Color(0xFF1D2353);
const _violet = Color(0xFF9658FA);
const _border = Color(0xFF6B5EA5);

/// Brand-inspired marks matching the supplied visual reference. No invented
/// bank QR or claim that the payment network authorized a transaction.
class PosPaymentBrand extends StatelessWidget {
  const PosPaymentBrand(this.method, {super.key, this.size = 53});
  final String method;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (method == 'yape' || method == 'plin') {
      final imageUrl = method == 'yape'
          ? 'https://upload.wikimedia.org/wikipedia/commons/0/08/Icono_de_la_aplicaci%C3%B3n_Yape.png'
          : 'https://www.bbva.pe/content/dam/public-web/peru/images/promo-sliders/promo-plin.im1585949297034im.png?imwidth=960';
      return SizedBox(
        width: size, height: size,
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          semanticLabel: method == 'yape' ? 'Yape' : 'Plin',
          errorBuilder: (_, _, _) => _offlineBrand(),
          loadingBuilder: (_, child, progress) => progress == null ? child : _offlineBrand(),
        ),
      );
    }
    return _offlineBrand();
  }

  Widget _offlineBrand() {
    if (method == 'yape') {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .22),
          gradient: const LinearGradient(colors: [Color(0xFFA41BC3), Color(0xFF6110A2)]),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(top: size * .08, right: size * .22, child: Container(
            width: size * .31, height: size * .31,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFF04D7CC), shape: BoxShape.circle),
            child: Text('S/', style: TextStyle(fontSize: size * .135, color: const Color(0xFF3B188C), fontWeight: FontWeight.w900)),
          )),
          Positioned(bottom: size * .15, child: Text('yape', style: TextStyle(
            color: Colors.white, fontSize: size * .28,
            fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -1.3,
            decoration: TextDecoration.underline, decorationColor: Colors.white,
          ))),
        ]),
      );
    }
    if (method == 'plin') {
      return Container(
        width: size, height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF00D7D0),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(size * .4), topRight: Radius.circular(size * .4),
            bottomLeft: Radius.circular(size * .09), bottomRight: Radius.circular(size * .42),
          ),
        ),
        child: Text('plin', style: TextStyle(color: Colors.white, fontSize: size * .31, fontWeight: FontWeight.w900)),
      );
    }
    if (method == 'tarjeta') {
      return SizedBox(width: size * 1.5, height: size, child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('VISA', style: TextStyle(fontSize: size * .22, fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic, letterSpacing: -1.5, color: Colors.white)),
          SizedBox(height: size * .08),
          SizedBox(width: size * .65, height: size * .25, child: Stack(children: [
            Positioned(left: 0, child: Container(width: size * .32, height: size * .25,
              decoration: const BoxDecoration(color: Color(0xFFEA001B), shape: BoxShape.circle))),
            Positioned(right: 0, child: Container(width: size * .32, height: size * .25,
              decoration: BoxDecoration(color: const Color(0xFFF8A500).withValues(alpha: .91), shape: BoxShape.circle))),
          ])),
        ],
      ));
    }
    final ico = switch (method) {
      'efectivo' => Icons.payments_rounded,
      'transferencia' => Icons.account_balance_rounded,
      _ => Icons.credit_card_rounded,
    };
    return Icon(ico, size: size * .66, color: const Color(0xFFB4A7FF));
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
    final note = _method == 'efectivo'
        ? 'Efectivo recibido: ${money(_tendered! / 100, widget.currency)} · '
            'Vuelto: ${money(posChangeDue(chargeCents: _chargeCents, tenderedCents: _tendered!) / 100, widget.currency)}'
        : '${posMethodLabel(_method!)}: abono confirmado manualmente por el cajero';
    Navigator.of(context).pop(PosPaymentApproval(_method!, note));
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16), Color color = _panel}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _border.withValues(alpha: .55)),
      ),
      child: child,
    );
  }

  Widget _methodTile(String method) {
    final selected = _method == method;
    return Material(
      color: selected ? const Color(0xFF4A237A) : _panel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() { _method = method; _verified = false; }),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? _violet : _border, width: selected ? 2 : 1),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            PosPaymentBrand(method, size: 51),
            const SizedBox(height: 8),
            Text(posMethodLabel(method), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final method = _method;
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _navy,
        colorScheme: ColorScheme.fromSeed(seedColor: _violet, brightness: Brightness.dark),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(method == null ? 'Método de cobro' : 'Cobro ${posMethodLabel(method).toLowerCase()}'),
          backgroundColor: _navy,
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
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total a cobrar', style: TextStyle(color: Color(0xFFB8B7D4))),
                const SizedBox(height: 5),
                Text(money(widget.total, widget.currency), style: const TextStyle(
                  fontSize: 33, fontWeight: FontWeight.w900, color: Colors.white)),
                if (widget.items.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('Resumen del pedido (${widget.items.length})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
                GridView.count(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2, childAspectRatio: 1.52,
                  mainAxisSpacing: 10, crossAxisSpacing: 10,
                  children: [for (final method in const ['efectivo', 'yape', 'plin', 'tarjeta']) _methodTile(method)],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() { _method = 'transferencia'; _verified = false; }),
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('Transferencia bancaria'),
                ),
                const SizedBox(height: 14),
                const Text('El efectivo calcula el vuelto. Yape, Plin y tarjeta necesitan confirmación del cajero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFA9A9CB), fontSize: 12)),
              ] else ...[
                _card(color: const Color(0xFF3E1C78), child: Column(children: [
                  PosPaymentBrand(method, size: 78),
                  const SizedBox(height: 10),
                  Text('Paga con ${posMethodLabel(method)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(money(widget.total, widget.currency),
                    style: const TextStyle(fontSize: 31, fontWeight: FontWeight.w900, color: Colors.white)),
                  if (_merchant?.holder.isNotEmpty == true)
                    Text(_merchant!.holder, textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFD2CAEE))),
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
                    const Text('QR de cobro configurado por el negocio',
                      style: TextStyle(color: Color(0xFFD2CAEE), fontSize: 11)),
                  ],
                  if (_requiresAccount && _account.isEmpty && _qrPath.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text('Primero configura el medio de cobro en Ajustes. No se generará un QR ficticio.',
                        textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFFFC2C2))),
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
                      decoration: InputDecoration(prefixText: posCurrencyPrefix(widget.currency),
                        border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Text(_sufficient
                        ? 'Vuelto: ${money(posChangeDue(chargeCents: _chargeCents, tenderedCents: _tendered!) / 100, widget.currency)}'
                        : 'El monto recibido es insuficiente.',
                      style: TextStyle(fontWeight: FontWeight.w900,
                        color: _sufficient ? const Color(0xFF4EFAC0) : const Color(0xFFFFA0A0))),
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
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: _violet, foregroundColor: Colors.white,
                  ),
                  onPressed: _canConfirm ? _confirm : null,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Confirmar pago', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
        )),
      ),
    );
  }
}
