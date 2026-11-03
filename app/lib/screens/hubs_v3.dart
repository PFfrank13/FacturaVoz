// Reorganización v3 (E). Nada se borra: cada pantalla anterior sigue existiendo y aquí se agrupan.
//   "Nueva venta" (una sola puerta): por voz · caja rápida · foto del cuaderno · cotización.
//   "Lo que me deben": Cobranza + Fiados + Avisos de Yape/Plin.
//   "Mi negocio": Ganancia + ¿Cuánto me queda? + Reportes + Comisiones (pestañas).
import 'package:flutter/material.dart';

import '../access.dart';
import '../rubros.dart';
import '../app_state.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import 'catalog.dart';
import 'collections.dart';
import 'fiados.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';
import 'notices.dart';
import 'profit.dart';
import 'reports.dart';
import 'taxes.dart';
import 'team.dart' show CommissionsScreen;

/// Nueva venta: una sola puerta con las cuatro formas de vender (solo las que tu plan y rol permiten).
Future<void> showNewSaleSheet(BuildContext context) {
  Future<void> voice() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewInvoiceScreen()));
    AppState.instance.bump();
    if (id != null && context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
      AppState.instance.bump();
    }
  }

  final spec = rubroFor(Access.instance.rubro);
  final example = switch (spec?.id) {
    'bodega' => '2 gaseosas a 3 soles',
    'restaurante' => '1 menú y 2 jugos',
    'servicios_tecnicos' => 'reparación de laptop',
    'salon' => 'corte de cabello para Ana',
    'consultorio' => 'consulta para Ana',
    'taller' => 'servicio de frenos',
    'mayorista' => '10 cajas de leche',
    'educacion' => 'matrícula del curso',
    'construccion' => 'adelanto de obra',
    _ => 'venta para Ana',
  };
  final options = <(IconData, String, String, Future<void> Function())>[
    (Icons.mic_rounded, 'Dictar o escribir', 'Por ejemplo: "$example"', voice),
    if (featureById('pos') case final f? when f.allowed) (Icons.point_of_sale_rounded, 'Caja rápida', 'Toca productos o escanea el código de barras', () => openFeature(context, f)),
    if (featureById('cuaderno') case final f? when f.allowed) (Icons.menu_book_rounded, 'Foto del cuaderno', 'Tu nota o cuaderno → venta', () => openFeature(context, f)),
    if (featureById('cotizaciones') case final f? when f.allowed) (Icons.request_quote_rounded, 'Cotización o pedido', 'Cotiza, comparte y conviértela en venta', () => openFeature(context, f)),
  ];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Nueva venta', style: Theme.of(c).textTheme.titleLarge)),
        for (final (icon, title, sub, go) in options)
          ListTile(
            leading: CircleAvatar(backgroundColor: Brand.indigo.withValues(alpha: 0.12), child: Icon(icon, color: Brand.indigo)),
            title: Text(title),
            subtitle: Text(sub),
            onTap: () {
              Navigator.pop(c);
              Haptics.tap();
              go();
            },
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

class _TabSpec {
  const _TabSpec(this.label, this.builder);
  final String label;
  final WidgetBuilder builder;
}

class _TabsScaffold extends StatelessWidget {
  const _TabsScaffold({required this.title, required this.tabs});
  final String title;
  final List<_TabSpec> tabs;

  @override
  Widget build(BuildContext context) {
    if (tabs.length == 1) return tabs.first.builder(context);
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: Navigator.of(context).canPop(),
          bottom: TabBar(isScrollable: tabs.length > 3, tabAlignment: tabs.length > 3 ? TabAlignment.start : null, tabs: [for (final t in tabs) Tab(text: t.label)]),
        ),
        body: TabBarView(children: [for (final t in tabs) t.builder(context)]),
      ),
    );
  }
}

/// "Lo que me deben": Cobranza + Fiados + Avisos de Yape/Plin.
class OwedHubScreen extends StatelessWidget {
  const OwedHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Access.instance;
    final tabs = [
      if (a.has('cobros') && a.can('collect')) _TabSpec('Cobranza', (_) => const CollectionsScreen(embedded: true)),
      if (featureById('fiados')?.allowed ?? false) _TabSpec('Fiados', (_) => const FiadosScreen()),
      if (featureById('avisos')?.allowed ?? false) _TabSpec('Avisos Yape/Plin', (_) => const PaymentNoticesScreen()),
    ];
    if (tabs.isEmpty) return const Scaffold(body: Center(child: Text('Tu rol no tiene acceso a los cobros.')));
    return _TabsScaffold(title: 'Lo que me deben', tabs: tabs);
  }
}

/// "Mi negocio": Ganancia + ¿Cuánto me queda? + Reportes + Comisiones.
class BusinessHubScreen extends StatelessWidget {
  const BusinessHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      if (featureById('negocio')?.allowed ?? false) _TabSpec('Mi negocio', (_) => const ProfitScreen(embedded: true)),
      if (featureById('impuestos')?.allowed ?? false) _TabSpec('¿Cuánto me queda?', (_) => const TaxesScreen()),
      if (featureById('reportes')?.allowed ?? false) _TabSpec('Reportes', (_) => const ReportsScreen()),
      if (featureById('comisiones')?.allowed ?? false) _TabSpec('Comisiones', (_) => const CommissionsScreen()),
    ];
    if (tabs.isEmpty) return const Scaffold(body: Center(child: Text('Tu rol no tiene acceso a los números del negocio.')));
    return _TabsScaffold(title: 'Mi negocio', tabs: tabs);
  }
}
