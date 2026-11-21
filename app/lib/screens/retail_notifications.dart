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

class RetailNotificationBell extends StatelessWidget {
  const RetailNotificationBell({super.key});

  @override
  Widget build(BuildContext context) => _NotificationFeed<bool>(
    read: V2Repo.hasUnreadAlerts,
    empty: false,
    builder: (context, snap, notice) {
      final theme = Theme.of(context);
      final pending = notice != null || snap.data == true;
      final dark = theme.brightness == Brightness.dark;
      return IconButton(
        key: const ValueKey('bodega-notifications'),
        tooltip: pending ? 'Notificaciones pendientes' : 'Notificaciones',
        onPressed: () =>
            pushPremium(context, const RetailNotificationsScreen()),
        icon: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dark ? const Color(0xFF213B38) : const Color(0xFFEBF4EB),
            border: Border.all(
              color: dark ? const Color(0xFF4C6962) : const Color(0xFFCBDED2),
            ),
          ),
          child: SizedBox.square(
            dimension: 38,
            child: Center(
              child: Badge(
                isLabelVisible: pending,
                backgroundColor: theme.colorScheme.error,
                smallSize: 8,
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: 22,
                  color: dark ? FvLuxe.mintInk : FvLuxe.forest,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
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
