// Pestaña VENDER (Fase 7): todo lo que es vender en un solo lugar. Lo que el tipo de negocio usa aparece primero;
// lo demás está en "Más funciones". Nada se borró: Cotizaciones (antes pestaña propia) vive aquí.
import 'package:flutter/material.dart';

import '../access.dart';
import '../app_state.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/growth_repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'catalog.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';

class SellHubScreen extends StatefulWidget {
  const SellHubScreen({super.key, this.embedded = false, this.settings});
  final bool embedded;
  final OrgSettings? settings;

  @override
  State<SellHubScreen> createState() => _SellHubScreenState();
}

class _SellHubScreenState extends State<SellHubScreen> {
  Map<String, dynamic>? _today;
  int _webOrders = 0;
  final _debounce = Debouncer(600);

  @override
  void initState() {
    super.initState();
    AppState.instance.dataVersion.addListener(_soon);
    _load();
  }

  @override
  void dispose() {
    AppState.instance.dataVersion.removeListener(_soon);
    _debounce.dispose();
    super.dispose();
  }

  void _soon() => _debounce(() {
        if (mounted) _load();
      });

  Future<void> _load() async {
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final today = todayIso();
    final tomorrow = todayIso(DateTime.now().add(const Duration(days: 1)));
    final r = await V2Repo.salesSummary(today, tomorrow, cur);
    final orders = await GrowthRepo.countNewStoreOrders();
    if (mounted) {
      setState(() {
        _today = r;
        _webOrders = orders;
      });
    }
  }

  Future<void> _voiceSale() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewInvoiceScreen()));
    AppState.instance.bump();
    if (id != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final s = widget.settings;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final ids = ['pos', 'cotizaciones', 'cuaderno', 'carta', 'productos', 'tienda', 'recurrentes', 'precios', 'puntos'];
    final all = [
      for (final id in ids)
        if (featureById(id) case final f? when f.allowed) f,
    ];
    // Primero lo que la plantilla del negocio usa; siempre se ven Cotizaciones y Productos.
    final first = all.where((f) => f.module == null || f.id == 'cotizaciones' || s == null || s.shows(f.module!)).toList();
    final rest = all.where((f) => !first.contains(f)).toList();
    final sales = (_today?['sales_total'] as num?)?.toDouble() ?? 0;
    final count = (_today?['sales_count'] as num?)?.toInt() ?? 0;
    final drafts = (_today?['drafts_count'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Vender')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.fromLTRB(16, widget.embedded ? top + 14 : 8, 16, 170), children: [
          if (widget.embedded)
            Reveal(
              child: Row(children: [
                Expanded(child: Text('Vender', style: t.textTheme.headlineMedium)),
                const SearchButton(),
                const SizedBox(width: 8),
                const AvatarButton(),
              ]),
            ),
          const SizedBox(height: 14),
          SectorPhotoBanner(rubro: Access.instance.rubro,
            title: 'Vende a tu manera', subtitle: sectorTagline(Access.instance.rubro), height: 140),
          const SizedBox(height: 14),
          Reveal(
            index: 1,
            child: Pressable(
              onTap: Access.instance.can('sell') ? _voiceSale : () {},
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: Brand.coralGradient, borderRadius: BorderRadius.circular(Radii.xl), boxShadow: Brand.softShadow(false, a: 0.22)),
                child: Row(children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
                    child: const Icon(Icons.mic_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Vender por voz', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('"Boleta para Rosa, 2 kilos de arroz a 4 soles"', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_today != null)
            Reveal(
              index: 2,
              child: SoftCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.today_rounded, color: Brand.ok),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Hoy: '),
                      TextSpan(text: money(sales, cur), style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: ' en $count ${count == 1 ? 'venta' : 'ventas'}'),
                      if (drafts > 0) TextSpan(text: ' · $drafts sin emitir', style: const TextStyle(color: Brand.warn, fontWeight: FontWeight.w700)),
                    ])),
                  ),
                ]),
              ),
            ),
          if (_webOrders > 0) ...[
            const SizedBox(height: 10),
            Reveal(
              index: 3,
              child: Pressable(
                onTap: () {
                  final f = featureById('cotizaciones');
                  if (f != null) openFeature(context, f);
                },
                child: SoftCard(
                  color: Brand.ok.withValues(alpha: 0.10),
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const Icon(Icons.storefront_rounded, color: Brand.ok),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$_webOrders ${_webOrders == 1 ? 'pedido web nuevo' : 'pedidos web nuevos'}: atiéndelos', style: t.textTheme.titleSmall)),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SectionTitle('Para vender'),
          Reveal(index: 4, child: _grid(context, first)),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionTitle('Más funciones', action: 'Ver todo', onAction: () => pushPremium(context, const AllFunctionsScreen())),
            Reveal(index: 5, child: _grid(context, rest)),
          ] else
            Center(
              child: TextButton.icon(
                onPressed: () => pushPremium(context, const AllFunctionsScreen()),
                icon: const Icon(Icons.apps_rounded),
                label: const Text('Todas las funciones'),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _grid(BuildContext context, List<FeatureEntry> list) {
    final t = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 600 ? 4 : (c.maxWidth > 340 ? 3 : 2);
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final f in list)
          SizedBox(
            width: w,
            height: 104,
            child: Pressable(
              onTap: () => openFeature(context, f),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: Brand.softShadow(t.brightness == Brightness.dark, a: 0.06),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Icon(f.icon, color: featureColor(f.id), size: 26),
                  Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.15)),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}
