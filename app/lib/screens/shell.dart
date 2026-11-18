import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../models_v2.dart';
import '../rubros.dart';
import '../services/quick_launch.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/design_tokens.dart';
import 'assistant.dart';
import 'catalog.dart';
import 'clients_hub.dart';
import 'cash_day.dart';
import 'collections.dart';
import 'fiados.dart';
import 'home.dart';
import 'hubs_v3.dart';
import 'inicio.dart';
import 'invoice_detail.dart';
import 'jobs.dart';
import 'kitchen.dart';
import 'license_gate.dart';
import 'new_invoice.dart';
import 'pos.dart';
import 'products.dart';
import 'profit.dart';
import 'quotes.dart';
import 'rubro_picker.dart';
import 'settings.dart';

/// Estructura principal v2.0 (Fase 7): máximo 5 destinos + micrófono central en un dock de cristal flotante.
///   Completo: INICIO · VENDER · [mic] · CLIENTES · COBRAR Y PAGAR · MI NEGOCIO
///   Simple:   VENDER · CLIENTES · [mic] · COBRAR · AJUSTES   (+ "Todas las funciones" desde el avatar)
///   Técnico:  MIS TRABAJOS · AGENDA · [mic] · CLIENTES · AJUSTES
/// Toque en el micrófono = vender por voz. Mantener presionado = Copiloto de IA.
/// Las pestañas que el rol o el plan no permiten no se muestran (la base de datos igual lo impide).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _Dest {
  const _Dest(this.id, this.icon, this.label, this.semantics);
  final String id;
  final IconData icon;
  final String label;
  final String semantics;
}

const _dHome = _Dest('home', Icons.space_dashboard_rounded, 'Inicio', 'Inicio');
const _dSell = _Dest('sell', Icons.point_of_sale_rounded, 'Vender', 'Vender');
const _dClients = _Dest('clients', Icons.people_alt_rounded, 'Clientes', 'Clientes');
const _dCollect = _Dest('collect', Icons.account_balance_wallet_rounded, 'Cobrar', 'Cobrar y pagar');
const _dBusiness = _Dest('business', Icons.insights_rounded, 'Negocio', 'Mi negocio');
const _dSettings = _Dest('settings', Icons.settings_rounded, 'Ajustes', 'Ajustes');
const _dJobs = _Dest('jobs', Icons.assignment_rounded, 'Trabajos', 'Mis trabajos');
const _dAgenda = _Dest('agenda', Icons.calendar_month_rounded, 'Agenda', 'Agenda');
const _dFiados = _Dest('fiados', Icons.menu_book_rounded, 'Fiados', 'Fiados');
const _dCash = _Dest('cash', Icons.account_balance_wallet_rounded, 'Caja', 'Caja');
const _dStock = _Dest('stock', Icons.inventory_2_rounded, 'Inventario', 'Inventario');
const _dBodegaSettings = _Dest('settings', Icons.settings_rounded, 'Configuración', 'Configuración');

/// Íconos de los destinos por rubro (B2). La etiqueta la pone cada rubro ("Pacientes", "Obras", "Mesas"…).
const _rubroIcons = <String, IconData>{
  'home': Icons.space_dashboard_rounded,
  'sell': Icons.point_of_sale_rounded,
  'clients': Icons.people_alt_rounded,
  'collect': Icons.account_balance_wallet_rounded,
  'business': Icons.insights_rounded,
  'jobs': Icons.assignment_rounded,
  'agenda': Icons.calendar_month_rounded,
  'quotes': Icons.request_quote_rounded,
  'fiados': Icons.menu_book_rounded,
  'tables': Icons.table_restaurant_rounded,
  'cash': Icons.lock_clock_rounded,
};

/// ¿El rol puede abrir este destino? (la base de datos igual lo impide)
bool _destAllowed(String id, Access a) => switch (id) {
      'sell' => a.can('sell') && a.has('facturar'),
      'quotes' => a.can('sell') && a.has('cotizaciones'),
      'collect' => a.can('collect') && a.has('cobros'),
      'fiados' => a.can('collect') && a.has('fiados'),
      'cash' => a.can('collect') && a.has('caja'),
      'stock' => a.has('stock') && (a.rubro != 'bodega' ||
          a.can('sell') || a.can('products_edit')),
      'business' => a.can('finance') && a.has('reportes'),
      'jobs' => a.can('jobs') && a.has('trabajos'),
      'agenda' => a.can('jobs') && a.has('agenda'),
      'clients' => a.can('clients') && a.has('clientes'),
      'tables' => a.can('sell') && a.has('carta_qr'),
      _ => true,
    };

/// Punto de corte para usar la navegación lateral fija en escritorio/tablet.
bool bodegaUsesPermanentSidebar(double width) => FvTokens.isWide(width);

/// Navegación visible de Bodega según la licencia y el rol verificados.
/// Es la fuente única tanto del Drawer como de sus pruebas de regresión.
List<String> bodegaDrawerIds(Access access) => [
  'home',
  if (_destAllowed('sell', access)) 'sell',
  if (_destAllowed('fiados', access)) 'fiados',
  if (_destAllowed('cash', access)) 'cash',
  if (_destAllowed('stock', access)) 'stock',
  'settings',
];

class _MainShellState extends State<MainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _tab = ''; // se resuelve al construir: la app abre donde se vende
  final Set<String> _built = {};
  OrgSettings? _settings;
  RealtimeChannel? _licChan;
  String? _orgSeen;

  @override
  void initState() {
    super.initState();
    _orgSeen = Repo.activeOrgId;
    V2Repo.changed.addListener(_reloadSettings);
    AppState.instance.addListener(_onApp);
    _reloadSettings();
    _watchLicense();
    QuickLaunch.instance.bind(_onShortcut);
  }

  @override
  void dispose() {
    V2Repo.changed.removeListener(_reloadSettings);
    AppState.instance.removeListener(_onApp);
    _licChan?.unsubscribe();
    QuickLaunch.instance.unbind();
    super.dispose();
  }

  void _onApp() {
    if (_orgSeen == Repo.activeOrgId) return;
    _orgSeen = Repo.activeOrgId;
    _reloadSettings();
    _watchLicense();
  }

  bool _gateShown = false;

  Future<void> _reloadSettings() async {
    final s = await V2Repo.settings();
    Access.instance.rubro = s.businessType;
    if (mounted) setState(() => _settings = s);
    _maybeGate(s);
  }

  /// "Otro / personalizado" ya no existe: el dueño elige su rubro una vez (nada se pierde mientras tanto).
  void _maybeGate(OrgSettings s) {
    if (_gateShown || !V2Repo.ready || !s.onboardingDone || rubroFor(s.businessType) != null) return;
    _gateShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => RubroPickerScreen(current: s.businessType, gate: true, onDone: () => Navigator.of(ctx).pop()),
      ));
    });
  }

  /// Si el Hub cambia la licencia (pago, corte), la app se entera al instante.
  void _watchLicense() {
    _licChan?.unsubscribe();
    _licChan = null;
    final org = Repo.activeOrgId;
    if (org == null) return;
    try {
      _licChan = Supabase.instance.client
          .channel('lic-$org')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'org_licenses',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'org_id', value: org),
            callback: (_) => Access.instance.load(),
          )
          .subscribe();
    } catch (_) {}
  }

  void _onShortcut(String type) {
    if (!mounted) return;
    switch (type) {
      case 'new_invoice':
        _newInvoice();
      case 'search':
        openUniversalSearch(context);
      case 'copilot':
        if (Access.instance.has('copiloto')) openCopilot(context);
      case 'fiados':
        final f = featureById('fiados');
        if (f != null && f.allowed) openFeature(context, f);
    }
  }

  List<_Dest> _dests() {
    final a = Access.instance;
    final simple = _settings?.simpleMode ?? false;
    // Una sola navegación para Bodega, independientemente del plan. Cada destino
    // procede del entitlement firmado por el Hub y de los permisos del rol.
    if ((a.rubro ?? _settings?.businessType) == 'bodega') {
      const destinations = <String, _Dest>{
        'home': _dHome,
        'sell': _dSell,
        'fiados': _dFiados,
        'cash': _dCash,
        'stock': _dStock,
        'settings': _dBodegaSettings,
      };
      return [for (final id in bodegaDrawerIds(a)) destinations[id]!];
    }
    if (a.role == 'tecnico') return [for (final d in const [_dJobs, _dAgenda, _dClients, _dSettings]) if (_destAllowed(d.id, a)) d];
    // v3: cada rubro tiene su barra (4 destinos + micrófono) y sus palabras.
    final spec = rubroFor(_settings?.businessType);
    if (spec != null) {
      final out = [
        for (final n in spec.nav)
          if (_destAllowed(n.id, a)) _Dest(n.id, _rubroIcons[n.id] ?? Icons.circle_outlined, n.label, n.label),
      ];
      if (out.length < 4 && !out.any((d) => d.id == 'clients') && _destAllowed('clients', a)) out.add(_Dest('clients', _rubroIcons['clients']!, spec.word('clients'), spec.word('clients')));
      if (out.length < 4) out.add(_dSettings);
      return out.take(4).toList();
    }
    final out = <_Dest>[];
    if (!simple) out.add(_dHome);
    if (_destAllowed('sell', a)) out.add(_dSell);
    if (_destAllowed('clients', a)) out.add(_dClients);
    if (_destAllowed('collect', a)) out.add(_dCollect);
    if (simple) {
      out.add(_dSettings);
    } else if (_destAllowed('business', a)) {
      out.add(_dBusiness);
    } else {
      out.add(_dSettings);
    }
    return out.take(5).toList();
  }

  /// Pantalla con la que abre la app: cada rubro abre en SU primera pestaña (la que definió su barra). Solo si la barra
  /// incluye Vender (p. ej. Bodega) abre ahí, para vender sin pasos. Restaurante, servicios, etc. NO se saltan a nada.
  String _landing(List<_Dest> d) {
    // A bodega starts at its ordered dashboard; selling is one visible tap away.
    if (Access.instance.rubro == 'bodega' && d.any((x) => x.id == 'home')) {
      return 'home';
    }
    return d.any((x) => x.id == 'sell') ? 'sell' : d.first.id;
  }

  void _go(String id) {
    if (id == _tab) return;
    if (!_dests().any((d) => d.id == id)) {
      // Ese destino no está en la barra de este rubro: se abre como pantalla.
      final f = featureById(const {'sell': 'facturar', 'collect': 'cobranza', 'business': 'negocio', 'clients': 'clientes', 'jobs': 'trabajos', 'agenda': 'agenda'}[id] ?? id);
      if (f != null && f.allowed) openFeature(context, f);
      return;
    }
    Haptics.select();
    setState(() {
      _tab = id;
      _built.add(id);
    });
  }

  Future<void> _newInvoice() async {
    if (!Access.instance.has('facturar') || !Access.instance.has('voz')) return;
    if (!Access.instance.can('sell')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu rol no permite registrar ventas.')),
      );
      return;
    }
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewInvoiceScreen()));
    AppState.instance.bump();
    if (id != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
      AppState.instance.bump();
    }
  }

  Widget _page(String id) {
    // v3: con rubro, Inicio limpio y los hubs agrupados (E). Sin rubro, la estructura v2 de siempre.
    if (rubroFor(_settings?.businessType) != null) {
      switch (id) {
        case 'home':
          return const InicioScreen();
        case 'collect':
          return const OwedHubScreen();
        case 'business':
          return const BusinessHubScreen();
      }
    }
    return _pageV2(id);
  }

  Widget _pageV2(String id) => switch (id) {
        'home' => HomeScreen(embedded: true, onNavigate: (i) => _go(const ['home', 'sell', 'collect', 'business'][i.clamp(0, 3)])),
        'sell' => const PosScreen(embedded: true),
        'clients' => const ClientsHubScreen(embedded: true),
        'collect' => const CollectionsScreen(embedded: true),
        'business' => const ProfitScreen(embedded: true),
        'jobs' => JobsScreen(embedded: true, mine: Access.instance.role == 'tecnico'),
        'agenda' => const AgendaScreen(embedded: true),
        'quotes' => const QuotesScreen(embedded: true),
        'fiados' => FiadosScreen(embedded: Access.instance.rubro == 'bodega'),
        'cash' => CashDayScreen(embedded: Access.instance.rubro == 'bodega'),
        'stock' => const ProductsScreen(embedded: true),
        'tables' => const KitchenScreen(),
        _ => const SettingsScreen(embedded: true),
      };

  /// Drawer móvil único; sin otra barra de navegación duplicada.
  Widget _bodegaNavigation(List<_Dest> destinations) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final selected = destinations.indexWhere((d) => d.id == _tab);
    final orgName = AppState.instance.activeOrg?.name ?? 'Tu negocio';
    return NavigationDrawer(
      key: const ValueKey('bodega-navigation-drawer'),
      backgroundColor: cs.surface,
      indicatorColor: cs.primary.withValues(alpha: 0.09),
      selectedIndex: selected < 0 ? 0 : selected,
      onDestinationSelected: (index) {
        Navigator.of(context).pop();
        if (index >= 0 && index < destinations.length) _go(destinations[index].id);
      },
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 22, 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  height: 42, width: 42,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.storefront_rounded, color: cs.onPrimary),
                ),
                const SizedBox(width: 12),
                const Text('FACTURAVOZ', style: TextStyle(
                  fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 20),
              Text(orgName, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: t.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 5),
              Text('Bodega / Tienda  ·  ${Access.instance.license.plan == 'BASICO' ? 'Básico' : Access.instance.license.plan}',
                style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        const Padding(
          padding: EdgeInsets.fromLTRB(26, 20, 18, 8),
          child: Text('ESPACIO DE TRABAJO', style: TextStyle(
            fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
        ),
        for (final d in destinations)
          NavigationDrawerDestination(
            icon: Icon(d.icon, color: cs.onSurfaceVariant, size: 21),
            selectedIcon: Icon(d.icon, color: cs.primary, size: 21),
            label: Text(d.label, style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 12, 18, 24),
          child: Text('Funciones habilitadas para tu plan y rol.',
            style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ],
    );
  }

  /// En tablet/escritorio sólo un rail; el POS conserva el resto de ancho.
  Widget _bodegaRail(List<_Dest> destinations) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final selected = destinations.indexWhere((d) => d.id == _tab);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(right: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.45))),
      ),
      child: NavigationRail(
        key: const ValueKey('bodega-navigation-rail'),
        backgroundColor: cs.surface,
        selectedIndex: selected < 0 ? 0 : selected,
        labelType: NavigationRailLabelType.selected,
        groupAlignment: -1,
        useIndicator: true,
        indicatorColor: cs.primary.withValues(alpha: 0.09),
        selectedIconTheme: IconThemeData(color: cs.primary, size: 23),
        unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 22),
        selectedLabelTextStyle: t.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800, color: cs.onSurface),
        unselectedLabelTextStyle: t.textTheme.labelSmall,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 22),
          child: Tooltip(
            message: 'FacturaVoz · Solvex',
            child: Icon(Icons.storefront_rounded, color: cs.primary, size: 27),
          ),
        ),
        destinations: [
          for (final d in destinations)
            NavigationRailDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.icon),
              label: Text(d.label),
              padding: const EdgeInsets.symmetric(vertical: 2),
            ),
        ],
        onDestinationSelected: (index) {
          if (index >= 0 && index < destinations.length) _go(destinations[index].id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ListenableBuilder(
      listenable: Access.instance,
      builder: (context, _) {
        final dests = _dests();
        final isBodega = (Access.instance.rubro ?? _settings?.businessType) == 'bodega';
        final pinnedSidebar = isBodega &&
            bodegaUsesPermanentSidebar(MediaQuery.sizeOf(context).width);
        if (!dests.any((d) => d.id == _tab)) _tab = _landing(dests);
        _built.add(_tab);
        final first = _landing(dests);
        final activeTitle = dests.firstWhere((d) => d.id == _tab, orElse: () => dests.first).label;
        final canVoiceSell = Access.instance.has('voz') &&
            Access.instance.has('facturar') && Access.instance.can('sell');
        final canCopilot = Access.instance.has('copiloto');
        return PopScope(
          canPop: _tab == first,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _go(first);
          },
          child: Scaffold(
            key: _scaffoldKey,
            // La navegación de Bodega tiene un único dueño: este Scaffold.
            drawer: isBodega && !pinnedSidebar
                ? _bodegaNavigation(dests) : null,
            appBar: isBodega ? AppBar(
              automaticallyImplyLeading: !pinnedSidebar,
              backgroundColor: Theme.of(context).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              shape: Border(bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.8,
              )),
              leading: pinnedSidebar ? null : IconButton(
                key: const ValueKey('bodega-open-menu'),
                tooltip: 'Abrir menú',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              title: Text(activeTitle,
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.35)),
              actions: [
                if (canCopilot)
                  IconButton(
                    key: const ValueKey('bodega-open-copilot'),
                    tooltip: 'Copiloto IA',
                    icon: const Icon(Icons.auto_awesome_rounded),
                    onPressed: () => openCopilot(context),
                  ),
                const SizedBox(width: 8),
              ],
            ) : null,
            body: Row(children: [
              if (pinnedSidebar)
                _bodegaRail(dests),
              Expanded(child: Column(children: [
                const LicenseBanner(),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: licenseBannerInfo(Access.instance.license) != null,
                    child: Stack(children: [
                      for (final d in dests)
                        if (_built.contains(d.id))
                          _TabSlot(
                            key: ValueKey('tab-${d.id}'),
                            active: d.id == _tab,
                            child: RepaintBoundary(child: _page(d.id)),
                          ),
                    ]),
                  ),
                ),
              ])),
            ]),
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            // Evitar que el micrófono cubra Cobrar en el POS o Abrir/Cerrar caja.
            floatingActionButton: isBodega && !keyboard &&
                _tab != 'sell' && _tab != 'cash' && (canCopilot || canVoiceSell)
                ? Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
                        blurRadius: 21,
                        offset: const Offset(0, 7),
                      )],
                    ),
                    child: FloatingActionButton.small(
                      key: const ValueKey('bodega-voice-action'),
                      heroTag: 'bodega-voice-action',
                      tooltip: canCopilot ? 'Hablar con Copiloto IA' : 'Vender por voz',
                      elevation: 0,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onPressed: canCopilot ? () => openCopilot(context) : _newInvoice,
                      child: const Icon(Icons.mic_rounded),
                    ),
                  )
                : null,
            // Los otros ocho rubros conservan su shell hasta su rediseño propio.
            bottomNavigationBar: isBodega ? null : AnimatedSlide(
              offset: keyboard ? const Offset(0, 1.4) : Offset.zero,
              duration: Motion.d(context, Motion.fast),
              curve: Motion.standard,
              child: _Dock(
                dests: dests,
                current: _tab,
                onTap: _go,
                onMic: _newInvoice,
                onMicLong: () => openCopilot(context),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Contenedor de una pestaña del shell.
///
/// IMPORTANTE: el fundido (AnimatedOpacity/AnimatedScale) va FUERA de TickerMode. Si TickerMode(enabled: false)
/// envuelve la animación de salida, su ticker queda silenciado y la pestaña que se oculta se queda pintada
/// encima (opacidad 1) mientras los toques van a la de abajo: la app "se congela".
/// Al terminar de ocultarse pasa a Offstage: no se pinta ni recibe toques, pero conserva su estado.
class _TabSlot extends StatefulWidget {
  const _TabSlot({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_TabSlot> createState() => _TabSlotState();
}

class _TabSlotState extends State<_TabSlot> {
  late bool _offstage = !widget.active;

  @override
  void didUpdateWidget(covariant _TabSlot old) {
    super.didUpdateWidget(old);
    if (widget.active) {
      _offstage = false; // vuelve a pintarse y entra con el fundido
    } else if (old.active && reduceMotion(context)) {
      _offstage = true; // sin animaciones no hay onEnd que esperar
    }
  }

  void _onFadeEnd() {
    if (mounted && !widget.active && !_offstage) setState(() => _offstage = true);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final active = widget.active;
    return Offstage(
      offstage: _offstage,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: Duration(milliseconds: reduce ? 0 : 220),
        curve: Curves.easeOutCubic,
        onEnd: _onFadeEnd,
        child: AnimatedScale(
          scale: active ? 1 : 0.985,
          duration: Duration(milliseconds: reduce ? 0 : 280),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !active,
            // Solo las animaciones internas de la pestaña oculta se pausan (ahorra batería y CPU).
            child: TickerMode(enabled: active, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.dests, required this.current, required this.onTap, required this.onMic, required this.onMicLong});
  final List<_Dest> dests;
  final String current;
  final ValueChanged<String> onTap;
  final VoidCallback onMic;
  final VoidCallback onMicLong;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final left = dests.take((dests.length + 1) ~/ 2).toList();
    final right = dests.skip(left.length).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + bottom),
      child: SizedBox(
        height: 84,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xl),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                height: 68,
                decoration: BoxDecoration(
                  color: (dark ? Brand.darkCard : Colors.white).withValues(alpha: dark ? 0.78 : 0.82),
                  borderRadius: BorderRadius.circular(Radii.xl),
                  border: Border.all(color: (dark ? Colors.white : Brand.indigo).withValues(alpha: 0.08)),
                  boxShadow: Brand.softShadow(dark, a: 0.16),
                ),
                // Dos mitades iguales: el hueco del micrófono queda SIEMPRE al centro, aunque haya 3 a un lado y 2 al otro.
                child: Row(children: [
                  Expanded(child: Row(children: [for (final d in left) _item(context, d)])),
                  if (Access.instance.has('voz') && Access.instance.has('facturar') && Access.instance.can('sell')) const SizedBox(width: 72),
                  Expanded(child: Row(children: [for (final d in right) _item(context, d)])),
                ]),
              ),
            ),
          ),
          if (Access.instance.has('voz') && Access.instance.has('facturar') && Access.instance.can('sell')) Positioned(
            top: 0,
            child: Semantics(
              button: true,
              label: Access.instance.has('copiloto')
                  ? 'Vender por voz. Mantén presionado para el copiloto.'
                  : 'Vender por voz.',
              child: GestureDetector(
                onLongPress: () {
                  Haptics.heavy();
                  if (Access.instance.has('copiloto')) onMicLong();
                },
                child: DictateMini(onPressed: onMic),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, _Dest d) {
    final t = Theme.of(context);
    final on = d.id == current;
    final c = on ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant;
    final dur = Motion.d(context, Motion.medium);
    return Expanded(
      child: Semantics(
        selected: on,
        button: true,
        label: d.semantics,
        child: InkResponse(
          onTap: () => onTap(d.id),
          radius: 34,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // FittedBox: en teléfonos angostos (5 destinos) la píldora se achica en vez de desbordarse.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedContainer(
                duration: dur,
                curve: Motion.shadow,
                padding: EdgeInsets.symmetric(horizontal: on ? 12 : 6, vertical: 5),
                decoration: BoxDecoration(color: on ? t.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent, borderRadius: BorderRadius.circular(Radii.pill)),
                child: AnimatedScale(scale: on ? 1.08 : 1, duration: dur, curve: Motion.spring, child: Icon(d.icon, size: 23, color: c)),
              ),
            ),
            const SizedBox(height: 3),
            // Una línea, se achica si no entra: nunca se parte ni desborda en pantallas chicas.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: Motion.d(context, Motion.fast),
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: c),
                  child: Text(d.label, maxLines: 1, softWrap: false),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Botón de micrófono del dock (más pequeño que el de la pantalla de dictado, con halo suave).
class DictateMini extends StatefulWidget {
  const DictateMini({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<DictateMini> createState() => _DictateMiniState();
}

class _DictateMiniState extends State<DictateMini> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        Haptics.soft();
        widget.onPressed();
      },
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: Duration(milliseconds: _down ? 100 : 420),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: Brand.coralGradient,
            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
            boxShadow: [BoxShadow(color: Brand.goldDeep.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
