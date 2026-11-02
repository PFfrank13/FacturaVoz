// Equipo y permisos (Fase 2) + ventas por vendedor y comisiones (Fase 8 · módulo 17).
// Roles: propietario, administrador, finanzas, cajero, técnico, vendedor. Los permisos viven en la base de datos (RLS);
// esta pantalla solo los asigna. El límite de usuarios del plan también lo aplica la base de datos.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/live.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Mensaje claro de la base de datos (límite del plan, permisos) o el genérico.
String dbMessage(Object e) {
  if (e is PostgrestException && (e.code == 'P0001' || e.code == 'P0002' || e.code == '42501' || e.code == '22023')) return e.message;
  return V2Repo.missingHint(e);
}

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> with LiveReload<TeamScreen> {
  List<TeamMember>? _members;
  List<TeamInvite> _invites = const [];
  String? _error;

  @override
  List<String> get liveTables => const ['organization_members', 'org_invites'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _members = LiveCache.get<List<TeamMember>>('team.m');
    _invites = LiveCache.get<List<TeamInvite>>('team.i') ?? const [];
    startLive();
    _load();
  }

  @override
  void dispose() {
    stopLive();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await V2Repo.team();
      final i = await V2Repo.invites().catchError((_) => <TeamInvite>[]);
      LiveCache.put('team.m', m);
      LiveCache.put('team.i', i);
      if (mounted) {
        setState(() {
          _members = m;
          _invites = i;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _invite() async {
    final r = await showModalBottomSheet<String>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: (_) => const _InviteSheet());
    if (r == null || !mounted) return;
    showSuccess(context, r == 'added' ? 'Agregado: ya puede entrar' : 'Invitación lista', icon: Icons.group_add_rounded);
    _load();
  }

  Future<void> _edit(TeamMember m) async {
    final changed = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: (_) => _MemberSheet(member: m));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final limit = Access.instance.limit('max_users');
    final count = (_members?.length ?? 0) + _invites.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Equipo y permisos')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _invite, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Invitar')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _members == null
              ? const SkeletonList()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
                    Text(
                      'Cada persona entra con su propio correo y ve solo lo que su rol permite.${limit > 0 ? ' Tu plan permite $limit usuarios ($count usados).' : ''}',
                      style: t.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final (i, m) in _members!.indexed)
                      Reveal(
                        key: ValueKey(m.userId),
                        index: i < 8 ? i : 8,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Pressable(
                            onTap: m.role == 'owner' ? () {} : () => _edit(m),
                            child: SoftCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(children: [
                                CircleAvatar(child: Text(m.shownName.isEmpty ? '?' : m.shownName.characters.first.toUpperCase())),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(m.shownName, style: t.textTheme.titleSmall),
                                    Text(m.email, style: t.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    if (m.commissionPct != null || m.salesGoal != null)
                                      Text(
                                        [if (m.commissionPct != null) 'Comisión ${m.commissionPct!.toStringAsFixed(1)} %', if (m.salesGoal != null) 'Meta ${money(m.salesGoal!, 'PEN')}'].join(' · '),
                                        style: t.textTheme.labelSmall,
                                      ),
                                  ]),
                                ),
                                TagChip(Access.roleName(m.effectiveRole), color: m.role == 'owner' ? Brand.goldDeep : Brand.indigo),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    if (_invites.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const SectionTitle('Invitaciones pendientes'),
                      for (final inv in _invites)
                        ListTile(
                          leading: const Icon(Icons.mark_email_unread_rounded),
                          title: Text(inv.displayName.isNotEmpty ? inv.displayName : inv.email),
                          subtitle: Text('${inv.email} · ${Access.roleName(inv.role == 'admin' ? 'admin' : (inv.staffRole ?? 'cajero'))}\nDebe entrar con "Iniciar con Empresa" usando este correo.'),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Cancelar invitación',
                            onPressed: () async {
                              await V2Repo.cancelInvite(inv.id).catchError((_) {});
                              _load();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    const SectionTitle('¿Qué ve cada rol?'),
                    for (final e in staffRoles.entries)
                      ListTile(dense: true, leading: const Icon(Icons.badge_outlined), title: Text(e.value.$1), subtitle: Text(e.value.$2)),
                    const ListTile(dense: true, leading: Icon(Icons.admin_panel_settings_outlined), title: Text('Administrador'), subtitle: Text('Todo, menos borrar la empresa. Puede invitar y cambiar permisos.')),
                  ]),
                ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  String _role = 'cajero';
  bool _busy = false;
  String _msg = '';

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final r = await V2Repo.invite(email: _email.text, staffRole: _role == 'admin' ? 'cajero' : _role, admin: _role == 'admin', name: _name.text);
      if (mounted) Navigator.of(context).pop(r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _msg = dbMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final owner = AppState.instance.activeOrg?.role == 'owner';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(shrinkWrap: true, children: [
        Text('Invitar a tu equipo', style: t.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Le dices su correo y que entre con el botón "Iniciar con Empresa". Sin claves compartidas.', style: t.textTheme.bodySmall),
        const SizedBox(height: 14),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre (para saludarlo)')),
        const SizedBox(height: 10),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo *')),
        const SizedBox(height: 14),
        Text('Rol', style: t.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final e in [
          ...staffRoles.entries.map((e) => (e.key, e.value.$1, e.value.$2)),
          if (owner) ('admin', 'Administrador', 'Todo, incluso invitar y cambiar permisos.'),
        ])
          Pressable(
            onTap: () => setState(() => _role = e.$1),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _role == e.$1 ? t.colorScheme.primary : t.colorScheme.outline, width: _role == e.$1 ? 2 : 1),
              ),
              child: Row(children: [
                Icon(_role == e.$1 ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: t.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.$2, style: t.textTheme.titleSmall), Text(e.$3, style: t.textTheme.bodySmall)])),
              ]),
            ),
          ),
        if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg, style: const TextStyle(color: Brand.bad))),
        const SizedBox(height: 12),
        GradientButton(label: 'Invitar', icon: Icons.send_rounded, busy: _busy, onPressed: _busy ? null : _send),
      ]),
    );
  }
}

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({required this.member});
  final TeamMember member;

  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  late String _role = widget.member.role == 'admin' ? 'admin' : (widget.member.staffRole ?? 'cajero');
  late final _name = TextEditingController(text: widget.member.displayName);
  late final _pct = TextEditingController(text: widget.member.commissionPct?.toString() ?? '');
  late final _goal = TextEditingController(text: widget.member.salesGoal?.toStringAsFixed(0) ?? '');
  bool _busy = false;
  String _msg = '';

  @override
  void dispose() {
    _name.dispose();
    _pct.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await V2Repo.setRole(widget.member.userId,
          staffRole: _role == 'admin' ? null : _role, admin: _role == 'admin', commission: parseDecimal(_pct.text), goal: parseDecimal(_goal.text), name: _name.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _msg = dbMessage(e);
        });
      }
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Quitar del equipo?'),
        content: Text('${widget.member.shownName} ya no podrá entrar a esta empresa. Sus ventas se conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Brand.bad), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.removeMember(Repo.activeOrgId!, widget.member.userId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _msg = friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final owner = AppState.instance.activeOrg?.role == 'owner';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(shrinkWrap: true, children: [
        Text(widget.member.shownName, style: t.textTheme.titleLarge),
        Text(widget.member.email, style: t.textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre visible')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in staffRoles.entries) ChoiceChip(label: Text(e.value.$1), selected: _role == e.key, onSelected: (_) => setState(() => _role = e.key)),
          if (owner) ChoiceChip(label: const Text('Administrador'), selected: _role == 'admin', onSelected: (_) => setState(() => _role = 'admin')),
        ]),
        const SizedBox(height: 6),
        Text(staffRoles[_role]?.$2 ?? 'Todo, incluso invitar y cambiar permisos.', style: t.textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _pct, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Comisión %'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _goal, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Meta mensual'))),
        ]),
        if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg, style: const TextStyle(color: Brand.bad))),
        const SizedBox(height: 14),
        GradientButton(label: 'Guardar', icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _save),
        TextButton(onPressed: _remove, child: const Text('Quitar del equipo', style: TextStyle(color: Brand.bad))),
      ]),
    );
  }
}

// ═════════════════════════ Comisiones y ranking ═════════════════════════
class CommissionsScreen extends StatefulWidget {
  const CommissionsScreen({super.key});

  @override
  State<CommissionsScreen> createState() => _CommissionsScreenState();
}

class _CommissionsScreenState extends State<CommissionsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<SellerRow>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _rows = null);
    try {
      final r = await V2Repo.sellerRanking(todayIso(_month), todayIso(DateTime(_month.year, _month.month + 1)));
      if (mounted) {
        setState(() {
          _rows = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const months = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final rows = _rows;
    final best = rows == null || rows.isEmpty ? 1.0 : rows.map((r) => r.total).reduce((a, b) => a > b ? a : b);
    return Scaffold(
      appBar: AppBar(title: const Text('Ventas por vendedor')),
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            onPressed: () {
              setState(() => _month = DateTime(_month.year, _month.month - 1));
              _load();
            },
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text('${months[_month.month - 1]} ${_month.year}', style: t.textTheme.titleMedium),
          IconButton(
            onPressed: _month.isBefore(DateTime(DateTime.now().year, DateTime.now().month))
                ? () {
                    setState(() => _month = DateTime(_month.year, _month.month + 1));
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : rows == null
                  ? const SkeletonList(count: 3)
                  : rows.isEmpty
                      ? const EmptyState(title: 'Sin ventas este mes', body: 'Cada venta queda a nombre de quien la emitió.')
                      : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                          for (final (i, r) in rows.indexed)
                            Reveal(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: SoftCard(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Text(i == 0 ? '🥇' : (i == 1 ? '🥈' : (i == 2 ? '🥉' : '${i + 1}.')), style: const TextStyle(fontSize: 22)),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text(r.name, style: t.textTheme.titleSmall)),
                                      Money(money(r.total, cur), weight: FontWeight.w800),
                                    ]),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: r.goal != null && r.goal! > 0 ? (r.total / r.goal!).clamp(0, 1).toDouble() : (r.total / best).clamp(0, 1).toDouble(),
                                      minHeight: 8,
                                      borderRadius: BorderRadius.circular(Radii.sm),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      [
                                        '${r.count} ventas',
                                        if (r.goal != null && r.goal! > 0) '${(r.total / r.goal! * 100).round()} % de su meta',
                                        if (r.pct != null) 'comisión ${money(r.commission, cur)} (${r.pct!.toStringAsFixed(1)} %)',
                                      ].join(' · '),
                                      style: t.textTheme.bodySmall,
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                          Text('Solo ventas emitidas (sin borradores ni rechazadas). Las comisiones y metas se configuran en Equipo.', style: t.textTheme.bodySmall, textAlign: TextAlign.center),
                        ]),
        ),
      ]),
    );
  }
}
