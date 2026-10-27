import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models_pro.dart';
import '../services/pro_api.dart';
import '../services/pro_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Medios de cobro (lo que ve tu cliente en el enlace de pago) y cobranza automática.
class PaySettingsScreen extends StatefulWidget {
  const PaySettingsScreen({super.key});

  @override
  State<PaySettingsScreen> createState() => _PaySettingsScreenState();
}

class _PaySettingsScreenState extends State<PaySettingsScreen> {
  PaySettings? _s;
  String? _error;
  bool _saving = false;
  final _yape = TextEditingController();
  final _plin = TextEditingController();
  final _bank = TextEditingController();
  final _account = TextEditingController();
  final _cci = TextEditingController();
  final _holder = TextEditingController();
  final _note = TextEditingController();

  static const _allOffsets = [-7, -3, -1, 0, 1, 3, 7, 15, 30];

  bool get _isAdmin => AppState.instance.activeOrg?.isAdmin ?? true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_yape, _plin, _bank, _account, _cci, _holder, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await ProRepo.loadPaySettings();
      if (!mounted) return;
      _yape.text = s.yape;
      _plin.text = s.plin;
      _bank.text = s.bankName;
      _account.text = s.bankAccount;
      _cci.text = s.bankCci;
      _holder.text = s.holder;
      _note.text = s.note;
      setState(() => _s = s);
    } catch (e) {
      if (mounted) setState(() => _error = ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261101_negocio_pro.sql en Supabase.' : friendly(e));
    }
  }

  String? _validate() {
    final y = _yape.text.replaceAll(RegExp(r'\D'), '');
    final p = _plin.text.replaceAll(RegExp(r'\D'), '');
    final c = _cci.text.replaceAll(RegExp(r'\D'), '');
    if (y.isNotEmpty && !RegExp(r'^9\d{8}$').hasMatch(y)) return 'El celular de Yape debe tener 9 dígitos y empezar con 9.';
    if (p.isNotEmpty && !RegExp(r'^9\d{8}$').hasMatch(p)) return 'El celular de Plin debe tener 9 dígitos y empezar con 9.';
    if (c.isNotEmpty && c.length != 20) return 'El CCI tiene 20 dígitos.';
    return null;
  }

  Future<void> _save() async {
    final s = _s;
    if (s == null) return;
    final err = _validate();
    if (err != null) {
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    s
      ..yape = _yape.text
      ..plin = _plin.text
      ..bankName = _bank.text
      ..bankAccount = _account.text
      ..bankCci = _cci.text
      ..holder = _holder.text
      ..note = _note.text;
    setState(() => _saving = true);
    try {
      await ProRepo.savePaySettings(s);
      if (mounted) showSuccess(context, 'Guardado');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar. ${friendly(e)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _mercadoPago() async {
    final s = _s!;
    if (s.mpEnabled) {
      final off = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Desconectar Mercado Pago'),
          content: const Text('Tus clientes ya no verán la opción de pagar con tarjeta.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Desconectar')),
          ],
        ),
      );
      if (off != true) return;
      await _setMp(null);
      return;
    }
    final ctrl = TextEditingController();
    final token = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Cobrar con tarjeta (Mercado Pago)', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Sin mensualidad: Mercado Pago cobra una comisión solo por cada venta aprobada y el dinero llega a TU cuenta.\n'
            '1) Entra a mercadopago.com.pe/developers → Tus integraciones → crea una aplicación.\n'
            '2) Copia el Access Token de PRODUCCIÓN (empieza con APP_USR-) y pégalo aquí.\n'
            'Se guarda cifrado en el servidor; la app nunca lo vuelve a mostrar.',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse('https://www.mercadopago.com.pe/developers/panel/app'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Abrir panel de Mercado Pago'),
          ),
          TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Access Token (APP_USR-…)')),
          const SizedBox(height: 14),
          GradientButton(label: 'Conectar', icon: Icons.link_rounded, onPressed: () => Navigator.pop(ctx, ctrl.text.trim())),
        ]),
      ),
    );
    disposeAfterClose([ctrl]);
    if (token == null || token.isEmpty) return;
    await _setMp(token);
  }

  Future<void> _setMp(String? token) async {
    setState(() => _saving = true);
    try {
      final on = await PayApi.setMercadoPago(token);
      if (!mounted) return;
      setState(() => _s!.mpEnabled = on);
      showSuccess(context, on ? 'Mercado Pago conectado' : 'Desconectado');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _offsetLabel(int d) => d == 0 ? 'El día' : (d < 0 ? '${-d} ${d == -1 ? 'día' : 'días'} antes' : '$d ${d == 1 ? 'día' : 'días'} después');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _s;
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))];
    return Scaffold(
      appBar: AppBar(title: const Text('Cobros y recordatorios')),
      body: SafeArea(
        child: s == null
            ? Center(child: _error == null ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 3)) : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                if (!_isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SoftCard(color: Brand.warn.withValues(alpha: 0.10), child: const Text('Solo el propietario o un administrador puede cambiar estos datos.')),
                  ),
                Reveal(
                  child: SoftCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.qr_code_2_rounded, color: Brand.indigo),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Cómo te pagan', style: t.textTheme.titleMedium)),
                      ]),
                      const SizedBox(height: 4),
                      Text('Esto aparece en el enlace de pago que envías a tus clientes, con botón de copiar.', style: t.textTheme.bodySmall),
                      const SizedBox(height: 14),
                      TextField(controller: _yape, keyboardType: TextInputType.phone, inputFormatters: digits, decoration: const InputDecoration(labelText: 'Celular Yape', prefixIcon: Icon(Icons.phone_android_rounded))),
                      const SizedBox(height: 10),
                      TextField(controller: _plin, keyboardType: TextInputType.phone, inputFormatters: digits, decoration: const InputDecoration(labelText: 'Celular Plin', prefixIcon: Icon(Icons.phone_iphone_rounded))),
                      const SizedBox(height: 10),
                      TextField(controller: _holder, maxLength: 120, decoration: const InputDecoration(labelText: 'Titular (como aparece en Yape/banco)', counterText: '')),
                      const SizedBox(height: 10),
                      TextField(controller: _bank, maxLength: 60, decoration: const InputDecoration(labelText: 'Banco (p. ej. BCP)', counterText: '')),
                      const SizedBox(height: 10),
                      TextField(controller: _account, maxLength: 40, decoration: const InputDecoration(labelText: 'N.º de cuenta', counterText: '')),
                      const SizedBox(height: 10),
                      TextField(controller: _cci, keyboardType: TextInputType.number, inputFormatters: digits, decoration: const InputDecoration(labelText: 'CCI (20 dígitos)')),
                      const SizedBox(height: 10),
                      TextField(controller: _note, maxLength: 300, maxLines: 2, decoration: const InputDecoration(labelText: 'Nota para el cliente (opcional)', hintText: 'Envía la constancia al 987 654 321')),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Reveal(
                  index: 1,
                  child: SoftCard(
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: const Color(0xFF00B1EA).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.credit_card_rounded, color: Color(0xFF009EE3)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Tarjeta con Mercado Pago', style: t.textTheme.titleSmall),
                          Text(s.mpEnabled ? 'Conectado: tus clientes pueden pagar con tarjeta y el cobro se registra solo.' : 'Opcional. Sin mensualidad.', style: t.textTheme.bodySmall),
                        ]),
                      ),
                      TextButton(onPressed: _saving || !_isAdmin ? null : _mercadoPago, child: Text(s.mpEnabled ? 'Quitar' : 'Conectar')),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Reveal(
                  index: 2,
                  child: SoftCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: s.remindersEnabled,
                        onChanged: _isAdmin
                            ? (v) {
                                Haptics.select();
                                setState(() => s.remindersEnabled = v);
                              }
                            : null,
                        title: const Text('Cobranza automática por correo'),
                        subtitle: const Text('Cada mañana revisamos tus facturas al crédito y enviamos el recordatorio con el enlace de pago. Una sola vez por etapa.'),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        child: !s.remindersEnabled
                            ? const SizedBox(width: double.infinity)
                            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const SizedBox(height: 6),
                                Text('¿Cuándo recordar?', style: t.textTheme.labelLarge),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final d in _allOffsets)
                                    FilterChip(
                                      label: Text(_offsetLabel(d)),
                                      selected: s.offsets.contains(d),
                                      onSelected: (on) => setState(() {
                                        final next = [...s.offsets];
                                        if (on) {
                                          next.add(d);
                                        } else {
                                          next.remove(d);
                                        }
                                        if (next.isNotEmpty && next.length <= 8) s.offsets = next..sort();
                                      }),
                                    ),
                                ]),
                                const SizedBox(height: 10),
                                Text(
                                  'Requisitos: el cliente debe tener correo y tu dominio de correo debe estar verificado en Resend (si no, solo llegan a tu propio correo).',
                                  style: t.textTheme.bodySmall,
                                ),
                              ]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 18),
                GradientButton(label: _saving ? 'Guardando…' : 'Guardar', icon: Icons.check_rounded, busy: _saving, onPressed: _saving || !_isAdmin ? null : _save),
              ]),
      ),
    );
  }
}
