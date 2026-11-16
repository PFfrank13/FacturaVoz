import 'package:flutter/material.dart';
import '../ui/onboarding_steps.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../ui/widgets.dart';
import '../logic/doc_voice.dart' show rucValid;
import '../services/v2_api.dart';

/// Datos del emisor y ajustes de facturación. En el primer uso es obligatorio:
/// moneda e impuesto los elige el usuario (no se asumen).
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.onboarding = false});
  final bool onboarding;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _taxId;
  late final TextEditingController _address;
  late final TextEditingController _taxLabel;
  late final TextEditingController _taxRate;
  late final TextEditingController _trade;
  late final TextEditingController _ubigeo;
  late final TextEditingController _dep;
  late final TextEditingController _prov;
  late final TextEditingController _dist;
  late final TextEditingController _serF;
  late final TextEditingController _serB;
  String? _currency;
  bool _rucBusy = false;
  String _rucMsg = '';

  /// RUC → razón social, dirección y ubigeo desde SUNAT (si el servidor tiene proveedor configurado).
  Future<void> _fillFromRuc() async {
    final ruc = _taxId.text.replaceAll(RegExp(r'\D'), '');
    if (ruc.length != 11 || !rucValid(ruc)) {
      setState(() => _rucMsg = 'Escribe un RUC válido de 11 dígitos.');
      return;
    }
    setState(() {
      _rucBusy = true;
      _rucMsg = '';
    });
    final r = await V2Api.lookup(ruc);
    if (!mounted) return;
    setState(() {
      _rucBusy = false;
      if (r.ok) {
        final d = r.data!;
        _name.text = d.name;
        if (d.address.isNotEmpty) _address.text = d.address;
        if (d.ubigeo.isNotEmpty) _ubigeo.text = d.ubigeo;
        if (d.department.isNotEmpty) _dep.text = d.department;
        if (d.province.isNotEmpty) _prov.text = d.province;
        if (d.district.isNotEmpty) _dist.text = d.district;
        _rucMsg = '✓ Datos de SUNAT completados. Revísalos antes de guardar.${!d.rucActive || !d.rucHabido ? ' Ojo: RUC ${d.status} ${d.condition}.' : ''}';
      } else {
        _rucMsg = r.message;
      }
    });
  }
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final p = AppState.instance.profile ?? Profile();
    _name = TextEditingController(text: p.businessName);
    _taxId = TextEditingController(text: p.taxId);
    _address = TextEditingController(text: p.address);
    _taxLabel = TextEditingController(text: p.taxLabel);
    _taxRate = TextEditingController(text: p.taxRate == null ? '' : qtyText(p.taxRate!));
    _trade = TextEditingController(text: p.tradeName);
    _ubigeo = TextEditingController(text: p.ubigeo);
    _dep = TextEditingController(text: p.department);
    _prov = TextEditingController(text: p.province);
    _dist = TextEditingController(text: p.district);
    _serF = TextEditingController(text: p.seriesFactura);
    _serB = TextEditingController(text: p.seriesBoleta);
    _currency = currencySymbols.containsKey(p.currency) ? p.currency : null;
  }

  @override
  void dispose() {
    for (final c in [_name, _taxId, _address, _taxLabel, _taxRate, _trade, _ubigeo, _dep, _prov, _dist, _serF, _serB]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    final p = Profile(
      businessName: _name.text,
      taxId: _taxId.text,
      address: _address.text,
      currency: _currency!,
      taxLabel: _taxLabel.text,
      taxRate: parseDecimal(_taxRate.text),
      tradeName: _trade.text,
      ubigeo: _ubigeo.text,
      department: _dep.text,
      province: _prov.text,
      district: _dist.text,
      seriesFactura: _serF.text,
      seriesBoleta: _serB.text,
    );
    try {
      await Repo.saveProfile(p);
      AppState.instance.setProfile(p);
      if (mounted && !widget.onboarding) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e is PostgrestException ? 'No se pudo guardar. Revisa los datos.' : friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(String title, IconData icon, List<Widget> children) {
    final t = Theme.of(context);
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: t.textTheme.titleSmall),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Configura tu negocio' : 'Datos del negocio'),
        automaticallyImplyLeading: !widget.onboarding,
        actions: widget.onboarding
            ? [
                IconButton(
                  tooltip: 'Cerrar sesión',
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    AppState.instance.clear();
                    await Supabase.instance.client.auth.signOut();
                  },
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.onboarding) const Padding(padding: EdgeInsets.only(bottom: 16), child: OnboardingSteps(current: 2)),
              if (widget.onboarding)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text('Estos datos aparecerán en tus facturas. Puedes cambiarlos cuando quieras.',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              _card('Tu negocio', Icons.storefront_outlined, [
              TextFormField(
                controller: _name,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Nombre o razón social *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _taxId,
                maxLength: 30,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Documento fiscal (RUC, NIF, RFC…)',
                  suffixIcon: IconButton(
                    tooltip: 'Completar con los datos de SUNAT',
                    onPressed: _rucBusy ? null : _fillFromRuc,
                    icon: _rucBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore_rounded),
                  ),
                ),
                validator: (v) {
                  final d = (v ?? '').trim();
                  // Solo se valida el dígito verificador cuando parece un RUC peruano (11 dígitos).
                  if (RegExp(r'^\d{11}$').hasMatch(d) && !rucValid(d)) return 'Ese RUC no es válido (revisa los dígitos)';
                  return null;
                },
              ),
              if (_rucMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_rucMsg, style: Theme.of(context).textTheme.bodySmall)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _address,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
              ]),
              const SizedBox(height: 14),
              _card('Moneda e impuesto', Icons.payments_outlined, [
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(labelText: 'Moneda *'),
                items: currencySymbols.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text('${e.key} (${e.value})')))
                    .toList(),
                onChanged: (v) => setState(() => _currency = v),
                validator: (v) => v == null ? 'Elige una moneda' : null,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _taxLabel,
                      maxLength: 20,
                      decoration: const InputDecoration(labelText: 'Impuesto (IGV, IVA…) *'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: _taxRate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Tasa % *'),
                      validator: (v) {
                        final n = parseDecimal(v ?? '');
                        return (n == null || n < 0 || n > 100) ? '0 a 100' : null;
                      },
                    ),
                  ),
                ],
              ),
              // Desplegable rápido de tasas usuales en Perú (se puede escribir otra).
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final (label, tax, rate) in const [('IGV 18 %', 'IGV', '18'), ('Exonerado / inafecto 0 %', 'IGV', '0')])
                  ActionChip(
                    label: Text(label),
                    onPressed: () => setState(() {
                      _taxLabel.text = tax;
                      _taxRate.text = rate;
                    }),
                  ),
              ]),
              ]),
              if (!widget.onboarding) ...[
                const SizedBox(height: 14),
                _card('Facturación electrónica (SUNAT)', Icons.verified_outlined, [
                const Text('Solo si vas a emitir facturas y boletas válidas. El RUC va en «Documento fiscal».'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _trade,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Nombre comercial'),
                ),
                TextFormField(
                  controller: _ubigeo,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ubigeo del domicilio fiscal (6 dígitos)'),
                  validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^\d{6}$').hasMatch(v!.trim()) ? null : '6 dígitos',
                ),
                Row(children: [
                  Expanded(child: TextFormField(controller: _dep, decoration: const InputDecoration(labelText: 'Departamento'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(controller: _prov, decoration: const InputDecoration(labelText: 'Provincia'))),
                ]),
                const SizedBox(height: 12),
                TextFormField(controller: _dist, decoration: const InputDecoration(labelText: 'Distrito')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _serF,
                      maxLength: 4,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Serie factura'),
                      validator: (v) => RegExp(r'^F[A-Za-z0-9]{3}$').hasMatch((v ?? '').trim()) ? null : 'Ej. F001',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _serB,
                      maxLength: 4,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Serie boleta'),
                      validator: (v) => RegExp(r'^B[A-Za-z0-9]{3}$').hasMatch((v ?? '').trim()) ? null : 'Ej. B001',
                    ),
                  ),
                ]),
                ]),
              ],
              if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 18),
              GradientButton(label: _busy ? 'Guardando…' : 'Guardar', icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _save),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
