import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Empresas del usuario y su equipo. Cambiar de empresa cambia los clientes y facturas que se ven.
class OrgsScreen extends StatefulWidget {
  const OrgsScreen({super.key});

  @override
  State<OrgsScreen> createState() => _OrgsScreenState();
}

class _OrgsScreenState extends State<OrgsScreen> {
  List<OrgMember>? _members;
  String? _membersFor;
  String? _error;
  bool _busy = false;

  AppState get _s => AppState.instance;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onState);
    _loadMembers();
  }

  @override
  void dispose() {
    _s.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _loadMembers() async {
    final org = _s.activeOrg;
    if (org == null) return;
    setState(() {
      _error = null;
      _membersFor = org.id;
    });
    try {
      final m = await Repo.listMembers(org.id);
      if (mounted && _membersFor == org.id) setState(() => _members = m);
    } catch (e) {
      if (mounted) setState(() => _error = _dbMessage(e));
    }
  }

  String _dbMessage(Object e) => e is PostgrestException && e.message.isNotEmpty ? e.message : friendly(e);

  Future<void> _create() async {
    final name = TextEditingController();
    final tax = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Nueva empresa', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: name,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre o razón social', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tax,
            maxLength: 30,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'RUC (opcional)', counterText: ''),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Crear empresa')),
        ]),
      ),
    );
    final n = name.text, t = tax.text;
    disposeAfterClose([name, tax]);
    if (ok != true || n.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final id = await Repo.createOrg(n, t);
      await _s.refreshOrgs();
      final created = _s.orgs.where((o) => o.id == id).firstOrNull;
      if (created != null) await _s.switchOrg(created);
      await _loadMembers();
      _snack('Empresa creada. Completa sus datos.');
      if (mounted && !(_s.profile?.isComplete ?? true)) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _snack(_dbMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite(Org org) async {
    final email = TextEditingController();
    var role = 'member';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Agregar persona', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Debe haberse registrado antes en FacturaVoz con ese correo.', style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.alternate_email_rounded)),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Miembro'), selected: role == 'member', onSelected: (_) => set(() => role = 'member')),
              if (org.role == 'owner')
                ChoiceChip(label: const Text('Administrador'), selected: role == 'admin', onSelected: (_) => set(() => role = 'admin')),
            ]),
            const SizedBox(height: 6),
            Text(
              role == 'admin' ? 'Puede agregar personas y eliminar borradores de todos.' : 'Puede crear y ver facturas de la empresa.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Agregar')),
          ]),
        ),
      ),
    );
    final e = email.text;
    disposeAfterClose([email]);
    if (ok != true || e.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await Repo.addMember(org.id, e, role);
      await _loadMembers();
      _snack('Persona agregada');
    } catch (err) {
      _snack(_dbMessage(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Org org, OrgMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Quitar de la empresa'),
        content: Text('${m.email} dejará de ver las facturas de ${org.name}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.removeMember(org.id, m.userId);
      await _loadMembers();
    } catch (e) {
      _snack(_dbMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final active = _s.activeOrg;
    return Scaffold(
      appBar: AppBar(title: const Text('Empresas y equipo')),
      floatingActionButton: _s.orgs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Nueva empresa'),
            ),
      body: SafeArea(
        child: _s.orgs.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: EmptyState(
                  title: 'Multi-empresa aún no está activo',
                  body: 'Ejecuta la migración 20261027_multitenant.sql en Supabase y vuelve a abrir la app.',
                ),
              )
            : ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [
                  Text('Tus empresas', style: t.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  for (var i = 0; i < _s.orgs.length; i++)
                    Reveal(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Pressable(
                          onTap: () async {
                            await _s.switchOrg(_s.orgs[i]);
                            if (!mounted) return;
                            if (!(_s.profile?.isComplete ?? true)) {
                              Navigator.of(context).popUntil((r) => r.isFirst);
                              return;
                            }
                            _members = null;
                            _loadMembers();
                          },
                          child: SoftCard(
                            padding: const EdgeInsets.all(16),
                            child: Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle),
                                child: Icon(Icons.apartment_rounded, color: t.colorScheme.primary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(_s.orgs[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                                  Text(
                                    [_s.orgs[i].roleLabel, if (_s.orgs[i].taxId.isNotEmpty) 'RUC ${_s.orgs[i].taxId}'].join(' · '),
                                    style: t.textTheme.bodySmall,
                                  ),
                                ]),
                              ),
                              if (_s.orgs[i].id == active?.id) const StatusPill('Activa', tone: PillTone.ok),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  if (active != null) ...[
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: Text('Equipo de ${active.name}', style: t.textTheme.titleMedium)),
                      if (active.isAdmin)
                        TextButton.icon(onPressed: _busy ? null : () => _invite(active), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Agregar')),
                    ]),
                    const SizedBox(height: 8),
                    if (_error != null)
                      Text(_error!, style: TextStyle(color: t.colorScheme.error))
                    else if (_members == null)
                      const SkeletonList(count: 2)
                    else
                      SoftCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(children: [
                          for (final m in _members!)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: t.colorScheme.primaryContainer,
                                child: Text(m.email.isEmpty ? '?' : m.email.characters.first.toUpperCase(),
                                    style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
                              ),
                              title: Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(switch (m.role) { 'owner' => 'Propietario', 'admin' => 'Administrador', _ => 'Miembro' }),
                              trailing: (active.isAdmin && m.role != 'owner')
                                  ? IconButton(
                                      tooltip: 'Quitar',
                                      icon: const Icon(Icons.person_remove_outlined),
                                      onPressed: () => _remove(active, m),
                                    )
                                  : null,
                            ),
                        ]),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Los clientes y facturas son por empresa. Cada empresa tiene su propio emisor, RUC, series y certificado SUNAT. Solo propietario y administradores los editan; cualquier miembro puede emitir.',
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
