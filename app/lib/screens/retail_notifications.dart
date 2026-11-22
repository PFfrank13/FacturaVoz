import 'package:dynamic_notification_island/dynamic_notification_island.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../logic/data_scope.dart';
import '../models_v2.dart';
import '../services/live.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/design_tokens.dart';
import '../ui/glass_widgets.dart';
import '../ui/motion.dart';
import 'client_profile.dart' show shortDateTime;
import 'license_gate.dart';

typedef _FeedBuilder<T> =
    Widget Function(BuildContext, AsyncSnapshot<T>, (String, Color)?);

typedef _CompanyScope = ({String? user, String? organization, int generation});

_CompanyScope get _currentScope => (
  user: Supabase.instance.client.auth.currentUser?.id,
  organization: Repo.activeOrgId,
  generation: dataScope.value,
);

// owner_alerts is an organization-wide inbox. Both its read and update policies
// require an administrator, in addition to the catalog's plan and team gates.
bool get _canReadBusinessAlerts {
  final access = Access.instance;
  return Supabase.instance.client.auth.currentUser != null &&
      Repo.activeOrgId != null &&
      access.isAdmin &&
      access.can('team') &&
      access.has('antifraude');
}

class _NotificationFeed<T> extends StatefulWidget {
  const _NotificationFeed({
    required this.read,
    required this.empty,
    required this.builder,
  });
  final Future<T> Function() read;
  final T empty;
  final _FeedBuilder<T> builder;

  @override
  State<_NotificationFeed<T>> createState() => _NotificationFeedState<T>();
}

class _NotificationFeedState<T> extends State<_NotificationFeed<T>> {
  final _changes = Listenable.merge([
    Access.instance,
    AppState.instance,
    dataScope,
    LiveHub.instance.tick('owner_alerts'),
  ]);
  (_CompanyScope, bool)? _scope;
  int? _revision;
  Future<T>? _alerts;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _changes,
    builder: (context, _) {
      final company = _currentScope;
      final canRead = _canReadBusinessAlerts;
      final scope = (company, canRead);
      final revision = LiveHub.instance.tick('owner_alerts').value;
      if (scope != _scope || revision != _revision) {
        _scope = scope;
        _revision = revision;
        _alerts = canRead ? widget.read() : null;
      }
      final access = Access.instance;
      final notice =
          company.user != null &&
              company.organization != null &&
              access.canEnter
          ? licenseBannerInfo(access.license)
          : null;
      if (!canRead) {
        return widget.builder(
          context,
          AsyncSnapshot.withData(ConnectionState.done, widget.empty),
          notice,
        );
      }
      return FutureBuilder<T>(
        // FutureBuilder normally retains the previous data while it refreshes.
        // Drop it immediately when the company, account or access level changes.
        key: ValueKey(scope),
        future: _alerts,
        builder: (context, snap) => widget.builder(context, snap, notice),
      );
    },
  );
}

/// The bell and the island consume the same scoped, single-row query.
class RetailNotificationHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const RetailNotificationHeader({
    super.key,
    required this.title,
    required this.onMenu,
    this.menuLabel = 'Abrir menú',
    this.allowIsland = true,
    this.onVoice,
    this.onCopilot,
  });

  final String title, menuLabel;
  final bool allowIsland;
  final VoidCallback onMenu;
  final VoidCallback? onVoice, onCopilot;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) => _NotificationFeed<OwnerAlert?>(
    read: V2Repo.latestUnreadAlert,
    empty: null,
    builder: (context, snapshot, plan) => _RetailNotificationToolbar(
      key: ValueKey((_currentScope, _canReadBusinessAlerts)),
      header: this,
      snapshot: snapshot,
      plan: plan,
    ),
  );
}

class _RetailNotificationToolbar extends StatefulWidget {
  const _RetailNotificationToolbar({
    super.key,
    required this.header,
    required this.snapshot,
    required this.plan,
  });

  final RetailNotificationHeader header;
  final AsyncSnapshot<OwnerAlert?> snapshot;
  final (String, Color)? plan;

  @override
  State<_RetailNotificationToolbar> createState() =>
      _RetailNotificationToolbarState();
}

class _RetailNotificationToolbarState extends State<_RetailNotificationToolbar>
    with WidgetsBindingObserver {
  bool _baselineLoaded = false;
  bool _planLoaded = false;
  String? _previousPlan;
  DateTime? _latestDate;
  String? _latestId;
  String? _preferred;
  int _announcement = 0;
  int _silentThroughRevision = -1;
  bool _wasActive = false;
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _lifecycle = state;
      _silentThroughRevision = LiveHub.instance.tick('owner_alerts').value;
      _announcement = 0;
      _planLoaded = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Only a strictly newer unread row can interrupt the user. A read or deletion
  // can uncover an older row, and a table tick can repeat the same row.
  bool _observeAlert(OwnerAlert? alert) {
    final date = alert?.createdAt;
    final newer =
        alert != null &&
        date != null &&
        (_latestDate == null ||
            date.isAfter(_latestDate!) ||
            (date.isAtSameMomentAs(_latestDate!) &&
                alert.id.compareTo(_latestId!) > 0));
    if (newer) {
      _latestDate = date;
      _latestId = alert.id;
    }
    final announce = _baselineLoaded && newer;
    _baselineLoaded = true;
    return announce;
  }

  void _openCenter() {
    if (ModalRoute.isCurrentOf(context) == false) return;
    pushPremium(context, const RetailNotificationsScreen());
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.header;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final active =
        h.allowIsland &&
        ModalRoute.isCurrentOf(context) != false &&
        (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);
    // A newly mounted island must not replay an announcement after navigation,
    // reopening the drawer, or resuming the app.
    final revision = LiveHub.instance.tick('owner_alerts').value;
    if (!active || !_wasActive) {
      _announcement = 0;
      _silentThroughRevision = revision;
      _planLoaded = false;
    }
    _wasActive = active;
    final alert = widget.snapshot.data;
    final plan = widget.plan;
    final businessNotice = alert == null
        ? null
        : DynamicIslandNotice(
            id: 'alert:${alert.id}',
            title: alert.title,
            message: alert.body,
            category: switch (alert.severity) {
              'bad' => 'Atención',
              'warn' => 'Aviso',
              _ => 'Negocio',
            },
            icon: switch (alert.severity) {
              'bad' => Icons.report_rounded,
              'warn' => Icons.warning_amber_rounded,
              'good' => Icons.check_circle_rounded,
              _ => Icons.notifications_active_rounded,
            },
            accent: switch (alert.severity) {
              'bad' => const Color(0xffff7a6e),
              'warn' => const Color(0xffffc069),
              'good' => const Color(0xff3ee6b0),
              _ => const Color(0xff7cc8ff),
            },
          );
    final planNotice = plan == null
        ? null
        : DynamicIslandNotice(
            id: 'plan:${plan.$1}',
            title: 'Tu plan',
            message: plan.$1,
            category: 'Licencia',
            icon: Icons.workspace_premium_rounded,
            accent: plan.$2,
          );

    if (widget.snapshot.connectionState == ConnectionState.done &&
        !widget.snapshot.hasError) {
      if (_observeAlert(alert)) {
        _preferred = businessNotice?.id;
        if (active && revision > _silentThroughRevision) _announcement++;
      }
    }
    if (_planLoaded && planNotice != null && planNotice.id != _previousPlan) {
      _preferred = planNotice.id;
      if (active) _announcement++;
    }
    _previousPlan = planNotice?.id;
    _planLoaded = true;
    final notice = planNotice != null && planNotice.id == _preferred
        ? planNotice
        : businessNotice ?? planNotice;

    // On phones the island lives in the status strip, centered over the
    // camera, like the system one. Without a strip it sits in the toolbar.
    final strip = statusBarIslandGeometry(MediaQuery.of(context));
    Widget island(Size size, IslandPlacement placement) =>
        DynamicNotificationIsland(
          notice: notice,
          announcement: _announcement == 0 ? null : _announcement,
          compactLabel: notice == null
              ? 'Actividad'
              : 'Vista previa de notificaciones',
          compactSize: size,
          placement: placement,
          onOpen: _openCenter,
        );

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      toolbarHeight: h.preferredSize.height,
      backgroundColor: Colors.transparent,
      flexibleSpace: Stack(
        fit: StackFit.expand,
        children: [
          const FvGlassTopBar(),
          if (strip != null && active)
            Positioned(
              top: strip.top,
              left: 0,
              right: 0,
              child: Center(
                child: island(strip.size, IslandPlacement.statusBar),
              ),
            ),
        ],
      ),
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      shape: const Border(),
      excludeHeaderSemantics: true,
      title: LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth >= 420 ? 132.0 : 104.0;
          final showIsland = strip == null && constraints.maxWidth >= 272;
          final sideWidth =
              (constraints.maxWidth - (showIsland ? slot : 0)) / 2;
          final groupActions =
              h.onVoice != null && h.onCopilot != null && sideWidth < 156;
          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('bodega-open-menu'),
                      tooltip: h.menuLabel,
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: h.onMenu,
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          h.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (showIsland)
                SizedBox(
                  width: slot,
                  child: active
                      ? Center(
                          child: island(
                            Size(slot - 8, 34),
                            IslandPlacement.toolbar,
                          ),
                        )
                      : null,
                ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (groupActions)
                      PopupMenuButton<int>(
                        tooltip: 'Acciones de voz',
                        icon: const Icon(Icons.mic_none_rounded),
                        onSelected: (action) =>
                            action == 0 ? h.onVoice!() : h.onCopilot!(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 0,
                            child: Text('Vender por voz'),
                          ),
                          PopupMenuItem(value: 1, child: Text('Copiloto IA')),
                        ],
                      )
                    else ...[
                      if (h.onVoice != null)
                        IconButton(
                          key: const ValueKey('bodega-voice-header'),
                          tooltip: 'Vender por voz',
                          icon: const Icon(Icons.mic_none_rounded),
                          onPressed: h.onVoice,
                        ),
                      if (h.onCopilot != null)
                        IconButton(
                          key: const ValueKey('bodega-open-copilot'),
                          tooltip: 'Copiloto IA',
                          icon: const Icon(Icons.auto_awesome_rounded),
                          onPressed: h.onCopilot,
                        ),
                    ],
                    IconButton(
                      key: const ValueKey('bodega-notifications'),
                      tooltip: notice == null
                          ? 'Notificaciones'
                          : 'Notificaciones pendientes',
                      onPressed: _openCenter,
                      icon: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: .09),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: cs.primary.withValues(alpha: .23),
                          ),
                        ),
                        child: SizedBox.square(
                          dimension: 34,
                          child: Center(
                            child: Badge(
                              isLabelVisible: notice != null,
                              backgroundColor: cs.error,
                              child: Icon(
                                Icons.notifications_none_rounded,
                                size: 21,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RetailNotificationsScreen extends StatefulWidget {
  const RetailNotificationsScreen({super.key});

  @override
  State<RetailNotificationsScreen> createState() =>
      _RetailNotificationsScreenState();
}

class _RetailNotificationsScreenState extends State<RetailNotificationsScreen> {
  bool _saving = false;

  Future<void> _markAllRead() async {
    if (_saving || !_canReadBusinessAlerts) return;
    final scope = _currentScope;
    setState(() => _saving = true);
    try {
      await V2Repo.markAlertsRead();
      if (scope == _currentScope) {
        LiveHub.instance.tick('owner_alerts').value++;
      }
    } catch (_) {
      if (mounted && scope == _currentScope) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar. Vuelve a intentarlo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const FvGlassTopBar(),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: FvLuxe.ambient(theme.brightness)),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _NotificationFeed<List<OwnerAlert>>(
                read: () => V2Repo.alerts(unreadFirst: true),
                empty: const [],
                builder: (context, snap, notice) {
                  final alerts = snap.data ?? const <OwnerAlert>[];
                  final pending = alerts.any((a) => a.readAt == null);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      if (notice != null) ...[
                        _NoticeTile(
                          icon: Icons.workspace_premium_outlined,
                          title: 'Tu plan',
                          body: notice.$1,
                          accent: notice.$2,
                          onTap: () => pushPremium(context, const PlanScreen()),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (snap.hasError)
                        _NoticeTile(
                          title: 'No se pudieron cargar las alertas',
                          body: 'Toca para reintentar.',
                          icon: Icons.refresh_rounded,
                          accent: theme.colorScheme.primary,
                          onTap: () =>
                              LiveHub.instance.tick('owner_alerts').value++,
                        )
                      else if (!snap.hasData)
                        const LinearProgressIndicator(
                          semanticsLabel: 'Cargando notificaciones',
                        )
                      else if (alerts.isEmpty && notice == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: FvGlassSurface(
                            blur: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 36,
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.notifications_none_rounded,
                                  size: 38,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Estás al día',
                                  style: theme.textTheme.headlineSmall,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _canReadBusinessAlerts
                                      ? 'Aquí aparecerán las alertas de tu negocio y los avisos de tu plan.'
                                      : 'Aquí aparecerán los avisos de tu plan.',
                                  style: theme.textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (alerts.isNotEmpty) ...[
                        Text(
                          'Alertas del negocio',
                          style: theme.textTheme.titleLarge,
                        ),
                        if (pending)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: _saving ? null : _markAllRead,
                              icon: const Icon(
                                Icons.done_all_rounded,
                                size: 18,
                              ),
                              label: const Text('Marcar todas como leídas'),
                            ),
                          ),
                        const SizedBox(height: 8),
                        for (final a in alerts)
                          Padding(
                            key: ValueKey(a.id),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _NoticeTile(
                              icon: a.severity == 'bad'
                                  ? Icons.gpp_maybe_outlined
                                  : Icons.shield_outlined,
                              accent: switch (a.severity) {
                                'bad' => theme.colorScheme.error,
                                'warn' =>
                                  theme.brightness == Brightness.dark
                                      ? FvLuxe.goldSoft
                                      : FvLuxe.gold,
                                _ => theme.colorScheme.primary,
                              },
                              title: a.title,
                              body: a.body,
                              unread: a.readAt == null,
                              time: a.createdAt == null
                                  ? null
                                  : shortDateTime(a.createdAt!),
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    this.time,
    this.unread = false,
    this.onTap,
  });
  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final String? time;
  final bool unread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: .12),
          child: Icon(icon, color: accent, size: 21),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.isNotEmpty) Text(body, style: theme.textTheme.bodyMedium),
            if (time != null || unread)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  [if (unread) 'Sin leer', ?time].join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
