import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../errors.dart';
import '../growth.dart';
import '../models.dart';
import '../models_growth.dart';
import '../services/growth_repo.dart';
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'products.dart';
import 'store_v2.dart';

/// Tienda en línea: tu catálogo como página web. Los clientes arman su pedido y te llega como cotización,
/// en vivo, lista para convertir en factura con un toque.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  StoreSettings? _s;
  List<Product>? _products;
  String? _error;
  bool _saving = false;
  final _slug = TextEditingController();
  final _headline = TextEditingController();
  final _whatsapp = TextEditingController();

  bool get _isAdmin => AppState.instance.activeOrg?.isAdmin ?? true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _slug.dispose();
    _headline.dispose();
    _whatsapp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await GrowthRepo.loadStore();
      final p = await Repo.listProducts(activeOnly: true);
      if (!mounted) return;
      _slug.text = s.slug.isNotEmpty ? s.slug : slugify(AppState.instance.activeOrg?.name ?? AppState.instance.profile?.businessName ?? 'mi tienda');
      _headline.text = s.headline;
      _whatsapp.text = s.whatsapp;
      setState(() {
        _s = s;
        _products = p;
      });
    } catch (e) {
      if (mounted) setState(() => _error = ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261102_revolucion.sql en Supabase.' : friendly(e));
    }
  }

  String? _validate() {
    final slug = _slug.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$').hasMatch(slug)) return 'El enlace solo puede tener letras, números y guiones (3 a 40).';
    final w = _whatsapp.text.replaceAll(RegExp(r'\D'), '');
    if (w.isNotEmpty && !RegExp(r'^9\d{8}$').hasMatch(w)) return 'El WhatsApp debe tener 9 dígitos y empezar con 9.';
    return null;
  }

  Future<void> _save({bool? enable}) async {
    final s = _s;
    if (s == null) return;
    final err = _validate();
    if (err != null) {
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _saving = true);
    final next = StoreSettings(slug: _slug.text.trim().toLowerCase(), enabled: enable ?? s.enabled, headline: _headline.text, whatsapp: _whatsapp.text, exists: true);
    try {
      await GrowthRepo.saveStore(next);
      if (!mounted) return;
      setState(() => _s = next);
      showSuccess(context, next.enabled ? '¡Tienda abierta!' : 'Guardado', icon: next.enabled ? Icons.storefront_rounded : Icons.check_rounded);
    } catch (e) {
      final msg = e.toString().contains('23505') || e.toString().contains('duplicate') ? 'Ese enlace ya lo usa otro negocio. Prueba con otro.' : friendly(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    final url = GrowthRepo.storeUrl(_slug.text.trim().toLowerCase());
    final business = AppState.instance.activeOrg?.name ?? '';
    await launchUrl(
      Uri.https('wa.me', '/', {'text': '¡Ya puedes hacer tus pedidos de $business en línea! Elige lo que necesitas aquí: $url'}),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _toggleProduct(Product p, bool v) async {
    Haptics.select();
    try {
      await GrowthRepo.setInStore(p.id, v);
      final list = await Repo.listProducts(activeOnly: true);
      if (mounted) setState(() => _products = list);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _s;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final rate = AppState.instance.profile?.taxRate ?? 18;
    final url = GrowthRepo.storeUrl(_slug.text.trim().toLowerCase());
    return Scaffold(
      appBar: AppBar(title: const Text('Tienda en línea')),
      body: SafeArea(
        child: s == null
            ? Center(child: _error == null ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 3)) : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                Reveal(
                  child: Aurora(
                    borderRadius: BorderRadius.circular(28),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.storefront_rounded, color: Colors.white, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(s.enabled ? 'Tu tienda está abierta' : 'Abre tu tienda en 1 minuto',
                                style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                          ),
                          if (s.enabled) const PulseDot(color: Colors.white),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          'Comparte el enlace por WhatsApp, Instagram o un QR en tu local. Tus clientes eligen y te llega el pedido al instante, listo para convertir en factura.',
                          style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.indigoDeep),
                              onPressed: _saving || !_isAdmin ? null : () => _save(enable: !s.enabled),
                              icon: Icon(s.enabled ? Icons.pause_rounded : Icons.rocket_launch_rounded),
                              label: Text(s.enabled ? 'Cerrar tienda' : 'Abrir tienda'),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                ),
                if (s.enabled) ...[
                  const SizedBox(height: 12),
                  Reveal(
                    index: 1,
                    child: SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Tu enlace', style: t.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        SelectableText(url, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: FilledButton.icon(onPressed: _share, icon: const Icon(Icons.chat_rounded), label: const Text('Compartir'))),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Copiar',
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: url));
                              Haptics.success();
                            },
                            icon: const Icon(Icons.copy_rounded),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Ver como cliente',
                            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                            icon: const Icon(Icons.open_in_new_rounded),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Reveal(
                  index: 2,
                  child: SoftCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Datos de la tienda', style: t.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _slug,
                        maxLength: 40,
                        onChanged: (_) => setState(() {}),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]'))],
                        decoration: const InputDecoration(labelText: 'Nombre del enlace', prefixText: '/tienda/', counterText: ''),
                      ),
                      const SizedBox(height: 10),
                      TextField(controller: _headline, maxLength: 140, decoration: const InputDecoration(labelText: 'Frase de bienvenida', hintText: 'Tortas por encargo · delivery en Miraflores', counterText: '')),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _whatsapp,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Tu WhatsApp (para que el cliente te avise)', prefixIcon: Icon(Icons.phone_iphone_rounded)),
                      ),
                      const SizedBox(height: 14),
                      GradientButton(label: _saving ? 'Guardando…' : 'Guardar', icon: Icons.check_rounded, busy: _saving, onPressed: _saving || !_isAdmin ? null : () => _save()),
                      const SizedBox(height: 8),
                      // v2.0: color, carta/tienda, recojo/delivery, pedido mínimo, reservas en línea.
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoreOptionsScreen())),
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('Más opciones: carta, delivery, reservas'),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 18),
                SectionTitle('Productos en la tienda', action: 'Catálogo', onAction: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductsScreen()));
                  _load();
                }),
                if (_products == null)
                  const SkeletonList(count: 3)
                else if (_products!.isEmpty)
                  const EmptyState(title: 'Tu catálogo está vacío', body: 'Agrega productos con su precio en Ajustes → Productos y servicios; aparecerán aquí.')
                else
                  SoftCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [
                      for (final p in _products!)
                        SwitchListTile(
                          value: p.inStore,
                          onChanged: _isAdmin ? (v) => _toggleProduct(p, v) : null,
                          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${money(round2(p.unitPrice * (1 + rate / 100)), cur)} con IGV${p.tracksStock ? ' · stock ${qtyText(p.stock ?? 0)}' : ''}'),
                        ),
                    ]),
                  ),
              ]),
      ),
    );
  }
}
