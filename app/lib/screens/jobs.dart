// Trabajos y agenda (Fase 1): tablero por estados (arrastrar y soltar), agenda por día, ficha del trabajo con
// técnico asignado, fotos de antes/después, materiales (descuentan stock), equipos instalados, hitos de obra,
// historial de estados y "Facturar este trabajo". El flujo de estados es configurable por tipo de negocio
// (p. ej. servicio técnico WiFi: nuevo → visita → cotizado → pendiente → en camino → instalado → cobrado).
// El técnico solo ve SUS trabajos: lo garantiza la base de datos (RLS), no solo esta pantalla.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../business_templates.dart';
import '../errors.dart';
import '../logic/appointments.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/location.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/mini_map.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'catalog.dart';
import 'client_profile.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';
import 'trash.dart';

String get _uid => Supabase.instance.client.auth.currentUser?.id ?? '';

Color _statusColor(JobStatus s) => Color(s.color);

// ═════════════════════════ Tablero / lista ═════════════════════════
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, this.embedded = false, this.mine = false});
  final bool embedded;
  final bool mine;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  List<Job>? _jobs;
  OrgSettings? _s;
  String? _error;
  bool _board = true;
  late bool _mine = widget.mine;
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await V2Repo.settings();
      final jobs = await V2Repo.jobs(openOnly: !_showDone);
      if (mounted) {
        setState(() {
          _s = s;
          _jobs = jobs;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _new() async {
    final id = await showJobForm(context);
    if (id != null) _load();
  }

  Future<void> _move(Job j, JobStatus to) async {
    if (j.status == to.key) return;
    Haptics.soft();
    final before = j.status;
    setState(() => j.status = to.key);
    try {
      await V2Repo.setJobStatus(j.id!, to.key);
      if (mounted && to.done) showSuccess(context, '¡${_s?.jobWord ?? 'Trabajo'} terminado!');
    } catch (e) {
      if (mounted) {
        setState(() => j.status = before);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final s = _s;
    final all = (_jobs ?? const <Job>[]).where((j) => !_mine || j.assignedTo == _uid).toList();
    final title = widget.mine ? 'Mis ${(s?.jobsWord ?? 'trabajos').toLowerCase()}' : (s?.jobsWord ?? 'Trabajos');
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(title), actions: [
              IconButton(tooltip: _board ? 'Ver lista' : 'Ver tablero', onPressed: () => setState(() => _board = !_board), icon: Icon(_board ? Icons.view_list_rounded : Icons.view_column_rounded)),
            ]),
      floatingActionButton: widget.embedded || !Access.instance.can('all_jobs')
          ? null
          : FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add_rounded), label: Text('Nuevo ${(s?.jobWord ?? 'trabajo').toLowerCase()}')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.embedded)
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + 14, 16, 0),
            child: Row(children: [
              Expanded(child: Text(title, style: t.textTheme.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(tooltip: _board ? 'Ver lista' : 'Ver tablero', onPressed: () => setState(() => _board = !_board), icon: Icon(_board ? Icons.view_list_rounded : Icons.view_column_rounded)),
              const AvatarButton(),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Wrap(spacing: 8, children: [
            if (Access.instance.can('all_jobs')) FilterChip(label: const Text('Solo míos'), selected: _mine, onSelected: (v) => setState(() => _mine = v)),
            FilterChip(
              label: const Text('Ver terminados'),
              selected: _showDone,
              onSelected: (v) {
                setState(() => _showDone = v);
                _load();
              },
            ),
            if (widget.embedded && Access.instance.can('all_jobs')) ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('Nuevo'), onPressed: _new),
          ]),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _jobs == null || s == null
                  ? const SkeletonList(count: 4)
                  : all.isEmpty
                      ? EmptyState(
                          title: widget.mine ? 'No tienes ${s.jobsWord.toLowerCase()} asignados' : 'Sin ${s.jobsWord.toLowerCase()} por ahora',
                          body: 'Crea uno desde aquí o desde la ficha de un cliente (botón Agendar).',
                        )
                      : RefreshIndicator(onRefresh: _load, child: _board ? _boardView(context, s, all) : _listView(context, s, all)),
        ),
      ]),
    );
  }

  Widget _boardView(BuildContext context, OrgSettings s, List<Job> all) {
    final t = Theme.of(context);
    final statuses = s.statuses;
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 150),
      children: [
        for (final st in statuses)
          DragTarget<Job>(
            onWillAcceptWithDetails: (d) => d.data.status != st.key,
            onAcceptWithDetails: (d) => _move(d.data, st),
            builder: (context, cand, _) {
              final items = all.where((j) => j.status == st.key || (!statuses.any((x) => x.key == j.status) && st == statuses.first)).toList();
              return AnimatedContainer(
                duration: Motion.d(context, Motion.fast),
                width: 270,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cand.isNotEmpty ? _statusColor(st).withValues(alpha: 0.14) : t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: _statusColor(st), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(st.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall)),
                      Text('${items.length}', style: t.textTheme.labelLarge),
                    ]),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final j = items[i];
                        final card = _JobCard(job: j, onTap: () => _open(j));
                        return LongPressDraggable<Job>(
                          data: j,
                          hapticFeedbackOnStart: true,
                          feedback: Material(color: Colors.transparent, child: SizedBox(width: 254, child: Opacity(opacity: 0.92, child: card))),
                          childWhenDragging: Opacity(opacity: 0.35, child: card),
                          child: card,
                        );
                      },
                    ),
                  ),
                ]),
              );
            },
          ),
      ],
    );
  }

  Widget _listView(BuildContext context, OrgSettings s, List<Job> all) {
    final sorted = [...all]..sort((a, b) => (a.scheduledAt ?? DateTime(2100)).compareTo(b.scheduledAt ?? DateTime(2100)));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final j = sorted[i];
        final st = s.statusOf(j.status);
        final next = _nextStatus(s, j);
        return Reveal(
          key: ValueKey(j.id),
          index: i < 8 ? i : 8,
          child: SwipeActions(
            left: next == null ? null : SwipeAction(icon: Icons.arrow_forward_rounded, label: next.label, color: _statusColor(next), onTrigger: () => _move(j, next)),
            child: _JobCard(job: j, status: st, onTap: () => _open(j)),
          ),
        );
      },
    );
  }

  Future<void> _open(Job j) async {
    await pushPremium(context, JobDetailScreen(jobId: j.id!));
    _load();
  }
}

JobStatus? _nextStatus(OrgSettings s, Job j) {
  final list = s.statuses;
  final i = list.indexWhere((x) => x.key == j.status);
  if (i < 0 || i + 1 >= list.length) return null;
  return list[i + 1];
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onTap, this.status});
  final Job job;
  final VoidCallback onTap;
  final JobStatus? status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final j = job;
    final late = j.scheduledAt != null && !j.done && j.scheduledAt!.isBefore(DateTime.now().subtract(const Duration(hours: 2)));
    return Pressable(
      onTap: onTap,
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        radius: 18,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(j.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall)),
            if (status != null) TagChip(status!.label, color: _statusColor(status!)),
          ]),
          if (j.clientName.isNotEmpty) Text(j.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            TagChip(jobKinds[j.kind] ?? j.kind, color: Brand.lilac),
            if (j.scheduledAt != null) TagChip(shortDateTime(j.scheduledAt!), color: late ? Brand.bad : Brand.indigo, icon: late ? Icons.warning_amber_rounded : Icons.schedule_rounded),
            if (j.assignedTo == _uid) const TagChip('Mío', color: Brand.ok, icon: Icons.person_rounded),
          ]),
        ]),
      ),
    );
  }
}

// ═════════════════════════ Agenda ═════════════════════════
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  List<Job>? _jobs;
  String? _error;
  final _strip = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _jobs = null);
    try {
      final r = await V2Repo.jobs(from: _day, to: _day.add(const Duration(days: 1)));
      if (mounted) {
        setState(() {
          _jobs = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _new() async {
    final at = DateTime(_day.year, _day.month, _day.day, DateTime.now().hour + 1);
    final id = await showJobForm(context, at: at, kind: 'cita');
    if (id != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final today = DateUtils.dateOnly(DateTime.now());
    const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final list = (_jobs ?? const <Job>[]).where((j) => Access.instance.can('all_jobs') || j.assignedTo == _uid).toList();
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Agenda')),
      floatingActionButton: widget.embedded ? null : FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text('Agendar')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.embedded)
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + 14, 16, 0),
            child: Row(children: [
              Expanded(child: Text('Agenda', style: t.textTheme.headlineMedium)),
              IconButton.filledTonal(tooltip: 'Agendar', onPressed: _new, icon: const Icon(Icons.add_rounded)),
              const SizedBox(width: 8),
              const AvatarButton(),
            ]),
          ),
        const SizedBox(height: 10),
        SizedBox(
          height: 78,
          child: ListView.builder(
            controller: _strip,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: 45,
            itemBuilder: (context, i) {
              final d = today.add(Duration(days: i - 7));
              final on = DateUtils.isSameDay(d, _day);
              return Pressable(
                onTap: () {
                  Haptics.select();
                  setState(() => _day = d);
                  _load();
                },
                child: AnimatedContainer(
                  duration: Motion.d(context, Motion.fast),
                  width: 54,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: on ? t.colorScheme.primary : t.colorScheme.surface,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(color: DateUtils.isSameDay(d, today) ? t.colorScheme.primary : t.colorScheme.outline),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(days[d.weekday - 1], style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: on ? Colors.white : t.colorScheme.onSurfaceVariant)),
                    Text('${d.day}', style: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w800, color: on ? Colors.white : t.colorScheme.onSurface)),
                  ]),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : _jobs == null
                  ? const SkeletonList(count: 3)
                  : list.isEmpty
                      ? ListView(children: [
                          EmptyState(title: 'Día libre', body: DateUtils.isSameDay(_day, today) ? 'No tienes visitas ni citas hoy.' : 'Nada agendado para este día.'),
                          Center(child: TextButton.icon(onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text('Agendar algo'))),
                        ])
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final j = list[i];
                              final time = j.scheduledAt == null ? '' : shortDateTime(j.scheduledAt!).split(' ').last;
                              return Reveal(
                                key: ValueKey(j.id),
                                index: i,
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  SizedBox(width: 56, child: Padding(padding: const EdgeInsets.only(top: 14), child: Text(time, style: t.textTheme.titleSmall))),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                        _JobCard(job: j, onTap: () => pushPremium(context, JobDetailScreen(jobId: j.id!)).then((_) => _load())),
                                        if (needsConfirmation(at: j.scheduledAt, done: j.done, phone: j.clientPhone))
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              icon: const Icon(Icons.chat_rounded, size: 18),
                                              label: const Text('Confirmar por WhatsApp'),
                                              onPressed: () => openWhatsApp(
                                                context,
                                                j.clientPhone,
                                                confirmationMessage(
                                                  clientName: j.clientName,
                                                  business: AppState.instance.activeOrg?.name ?? AppState.instance.profile?.businessName ?? '',
                                                  what: j.title,
                                                  at: j.scheduledAt!,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ]),
                                    ),
                                  ),
                                ]),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}

// ═════════════════════════ Ficha del trabajo ═════════════════════════
class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen({super.key, required this.jobId});
  final String jobId;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  Job? _j;
  OrgSettings? _s;
  List<JobMaterial> _materials = const [];
  List<MediaFile> _media = const [];
  List<JobMilestone> _milestones = const [];
  List<JobEvent> _events = const [];
  List<TeamMember> _team = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await V2Repo.job(widget.jobId);
      if (j == null) {
        if (mounted) setState(() => _error = 'Este trabajo ya no existe o no está asignado a ti.');
        return;
      }
      final s = await V2Repo.settings();
      final res = await Future.wait<Object?>([
        V2Repo.materials(j.id!).catchError((_) => <JobMaterial>[]),
        V2Repo.media(jobId: j.id!).catchError((_) => <MediaFile>[]),
        V2Repo.milestones(j.id!).catchError((_) => <JobMilestone>[]),
        V2Repo.jobEvents(j.id!).catchError((_) => <JobEvent>[]),
        Access.instance.can('team') ? V2Repo.team().catchError((_) => <TeamMember>[]) : Future.value(<TeamMember>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _j = j;
        _s = s;
        _materials = res[0] as List<JobMaterial>;
        _media = res[1] as List<MediaFile>;
        _milestones = res[2] as List<JobMilestone>;
        _events = res[3] as List<JobEvent>;
        _team = res[4] as List<TeamMember>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _run(Future<void> Function() op, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await op();
      if (ok != null && mounted) showSuccess(context, ok);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setStatus(JobStatus st) async {
    await _run(() => V2Repo.setJobStatus(_j!.id!, st.key), ok: st.done ? '¡Terminado!' : 'Estado: ${st.label}');
    final j = _j;
    if (!mounted || j == null || !readyStatusKeys.contains(st.key)) return;
    final phone = j.contactPhone.isNotEmpty ? j.contactPhone : j.clientPhone;
    if (phone.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text('¿Avisamos a ${j.clientName.split(' ').first} que ya está listo?'),
      action: SnackBarAction(
        label: 'Avisar',
        onPressed: () => openWhatsApp(
          context,
          phone,
          readyMessage(clientName: j.clientName, business: AppState.instance.activeOrg?.name ?? AppState.instance.profile?.businessName ?? '', what: j.title),
        ),
      ),
    ));
  }

  Future<void> _photo(String kind) async {
    final j = _j;
    if (j == null) return;
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 72);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      await _run(() async {
        final path = await V2Repo.upload('trabajos/${j.id}', bytes);
        await V2Repo.addMedia(jobId: j.id, clientId: j.clientId, path: path, kind: kind);
      }, ok: 'Foto guardada');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  Future<void> _addMaterial() async {
    final j = _j;
    if (j == null) return;
    List<Product> products = const [];
    try {
      products = await Repo.listProducts(activeOnly: true);
    } catch (_) {}
    if (!mounted) return;
    final desc = TextEditingController(), qty = TextEditingController(text: '1');
    Product? picked;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Material usado'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Autocomplete<Product>(
              optionsBuilder: (v) => v.text.trim().isEmpty ? const Iterable<Product>.empty() : products.where((p) => p.name.toLowerCase().contains(v.text.toLowerCase())).take(8),
              displayStringForOption: (p) => p.name,
              onSelected: (p) => set(() {
                picked = p;
                desc.text = p.name;
              }),
              fieldViewBuilder: (ctx, ctrl, focus, submit) => TextField(
                controller: ctrl,
                focusNode: focus,
                onChanged: (v) {
                  desc.text = v;
                  picked = null;
                },
                decoration: const InputDecoration(labelText: 'Producto o material'),
              ),
            ),
            TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cantidad')),
            if (picked?.tracksStock == true) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Stock actual: ${qtyText(picked!.stock!)}')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    final d = desc.text.trim();
    final q = parseDecimal(qty.text) ?? 0;
    disposeAfterClose([desc, qty]);
    if (ok != true || d.isEmpty || q <= 0) return;
    await _run(() => V2Repo.addMaterial(j.id!, productId: picked?.id, description: d, quantity: q, unitPrice: picked?.unitPrice ?? 0));
  }

  Future<void> _consume() async {
    final j = _j;
    if (j == null) return;
    await _run(() async {
      final n = await V2Repo.consumeMaterials(j.id!);
      if (mounted) showSuccess(context, n == 0 ? 'Nada pendiente por descontar' : 'Se descontaron $n materiales del inventario');
    });
  }

  Future<void> _addMilestone() async {
    final j = _j;
    if (j == null) return;
    final title = TextEditingController(), amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo hito (avance)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Ej.: Adelanto 30 %, Tarrajeo, Entrega final')),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Monto a cobrar (con IGV)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
        ],
      ),
    );
    final tt = title.text.trim();
    final a = parseDecimal(amount.text) ?? 0;
    disposeAfterClose([title, amount]);
    if (ok != true || tt.isEmpty || a <= 0) return;
    await _run(() => V2Repo.addMilestone(j.id!, title: tt, amount: a, position: _milestones.length));
  }

  Future<void> _invoiceMilestone(JobMilestone m) async {
    setState(() => _busy = true);
    try {
      final id = await V2Repo.invoiceMilestone(m.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
    if (mounted) setState(() => _busy = false);
    _load();
  }

  Future<void> _invoice() async {
    final j = _j;
    if (j == null) return;
    final p = AppState.instance.profile;
    final items = <LineItem>[
      LineItem(description: j.title, quantity: 1, unitPrice: j.amount ?? 0),
      for (final m in _materials)
        if (m.unitPrice > 0) LineItem(description: m.description, quantity: m.quantity, unitPrice: m.unitPrice),
    ];
    final draft = InvoiceDraft(
      clientName: j.clientName,
      taxRate: p?.taxRate ?? 18,
      currency: (p?.currency ?? '').isEmpty ? 'PEN' : p!.currency,
      items: items,
      notes: j.title,
    );
    if (j.clientId != null) {
      final c = await V2Repo.client(j.clientId!);
      if (c != null) draft.clientTaxId = c.taxId;
    }
    if (!mounted) return;
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NewInvoiceScreen(initial: draft)));
    if (id != null) {
      j.invoiceId = id;
      await _run(() => V2Repo.saveJob(j).then((_) {}));
      if (mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
    }
  }

  Future<void> _assign() async {
    final j = _j;
    if (j == null) return;
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Asignar a')),
          ListTile(leading: const Icon(Icons.person_off_rounded), title: const Text('Nadie'), onTap: () => Navigator.pop(ctx, '')),
          for (final m in _team)
            ListTile(
              leading: const Icon(Icons.engineering_rounded),
              title: Text(m.shownName),
              subtitle: Text(Access.roleName(m.effectiveRole)),
              trailing: m.userId == j.assignedTo ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, m.userId),
            ),
        ]),
      ),
    );
    if (v == null) return;
    j.assignedTo = v.isEmpty ? null : v;
    await _run(() => V2Repo.saveJob(j).then((_) {}), ok: 'Asignado');
  }

  Future<void> _onMyWay() async {
    final j = _j;
    if (j == null) return;
    final phone = j.contactPhone.isNotEmpty ? j.contactPhone : j.clientPhone;
    final s = _s;
    final onWay = s?.statuses.where((x) => x.key == 'en_camino').firstOrNull;
    if (onWay != null && j.status != onWay.key) await V2Repo.setJobStatus(j.id!, onWay.key).catchError((_) {});
    if (!mounted) return;
    await openWhatsApp(context, phone, 'Hola ${j.clientName.split(' ').first}, le escribe ${AppState.instance.activeOrg?.name ?? ''}. Vamos en camino para "${j.title}". ¡Hasta pronto!');
    _load();
  }

  Future<void> _techNote() async {
    final j = _j;
    if (j == null) return;
    final c = TextEditingController(text: j.techNote);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Informe del técnico'),
        content: TextField(controller: c, maxLines: 5, maxLength: 2000, decoration: const InputDecoration(hintText: 'Qué se hizo, qué falta, observaciones')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    final v = c.text;
    disposeAfterClose([c]);
    if (ok != true) return;
    j.techNote = v;
    await _run(() => V2Repo.saveJob(j).then((_) {}), ok: 'Informe guardado');
  }

  Future<void> _delete() async {
    final j = _j;
    if (j == null) return;
    final nav = Navigator.of(context);
    try {
      await V2Repo.deleteJob(j.id!);
      if (!mounted) return;
      showUndo(context, rowId: j.id!, label: 'Trabajo movido a la papelera');
      nav.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final j = _j;
    final s = _s;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final a = Access.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(s?.jobWord ?? 'Trabajo'),
        actions: [
          if (j != null && a.can('all_jobs'))
            IconButton(
              tooltip: 'Editar',
              onPressed: () async {
                await showJobForm(context, job: j);
                _load();
              },
              icon: const Icon(Icons.edit_rounded),
            ),
          if (j != null && a.can('all_jobs'))
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'del') _delete();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Mover a la papelera'))],
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : j == null || s == null
              ? const SkeletonList(count: 4)
              : AbsorbPointer(
                  absorbing: _busy,
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                      Reveal(
                        child: Text(j.title, style: t.textTheme.headlineSmall),
                      ),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        TagChip(jobKinds[j.kind] ?? j.kind, color: Brand.lilac),
                        if (j.scheduledAt != null) TagChip(shortDateTime(j.scheduledAt!), color: Brand.indigo, icon: Icons.schedule_rounded),
                        if (j.amount != null) TagChip(money(j.amount!, cur), color: Brand.ok, icon: Icons.payments_rounded),
                        if (j.invoiceId != null) const TagChip('Facturado', color: Brand.ok, icon: Icons.receipt_long_rounded),
                      ]),
                      const SizedBox(height: 16),
                      // Estados: se tocan para avanzar (con historial automático).
                      SizedBox(
                        height: 46,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: s.statuses.length,
                          separatorBuilder: (_, _) => const Icon(Icons.chevron_right_rounded, size: 18),
                          itemBuilder: (context, i) {
                            final st = s.statuses[i];
                            final on = st.key == j.status;
                            final c = _statusColor(st);
                            return Center(
                              child: StatusMorph(
                                status: '${st.key}-$on',
                                child: ChoiceChip(
                                  label: Text(st.label),
                                  selected: on,
                                  selectedColor: c.withValues(alpha: 0.22),
                                  avatar: on ? Icon(Icons.check_rounded, size: 16, color: c) : null,
                                  onSelected: on ? null : (_) => _setStatus(st),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      SoftCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (j.clientName.isNotEmpty)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.person_rounded),
                              title: Text(j.clientName),
                              subtitle: Text(j.contactPhone.isNotEmpty ? j.contactPhone : j.clientPhone),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: j.clientId == null ? null : () => pushPremium(context, ClientProfileScreen(clientId: j.clientId!)),
                            ),
                          if (a.can('team'))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.engineering_rounded),
                              title: Text(_team.where((m) => m.userId == j.assignedTo).map((m) => m.shownName).firstOrNull ?? (j.assignedTo == null ? 'Sin asignar' : 'Asignado')),
                              subtitle: const Text('Técnico / responsable'),
                              trailing: const Icon(Icons.edit_rounded),
                              onTap: _assign,
                            ),
                          if (j.address.isNotEmpty || j.lat != null) ...[
                            if (j.lat != null && j.lng != null) ...[const SizedBox(height: 6), MiniMap(lat: j.lat!, lng: j.lng!, height: 140)],
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.place_rounded),
                              title: Text(j.address.isEmpty ? 'Ubicación guardada' : j.address),
                              trailing: const Icon(Icons.directions_rounded),
                              onTap: () => j.lat != null && j.lng != null ? openDirections(j.lat!, j.lng!) : openMapSearch(j.address),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.tonalIcon(onPressed: _onMyWay, icon: const Icon(Icons.directions_car_rounded), label: const Text('Voy en camino')),
                            OutlinedButton.icon(onPressed: _techNote, icon: const Icon(Icons.edit_note_rounded), label: const Text('Informe')),
                            if (a.can('sell') && j.invoiceId == null) FilledButton.icon(onPressed: _invoice, icon: const Icon(Icons.receipt_long_rounded), label: const Text('Facturar')),
                            if (j.invoiceId != null)
                              OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: j.invoiceId!))),
                                icon: const Icon(Icons.receipt_rounded),
                                label: const Text('Ver comprobante'),
                              ),
                          ]),
                        ]),
                      ),
                      if (j.notes.isNotEmpty || j.techNote.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SoftCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (j.notes.isNotEmpty) ...[Text('Indicaciones', style: t.textTheme.titleSmall), Text(j.notes)],
                            if (j.techNote.isNotEmpty) ...[const SizedBox(height: 8), Text('Informe del técnico', style: t.textTheme.titleSmall), Text(j.techNote)],
                          ]),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SectionTitle('Fotos de antes y después'),
                      _photos(context),
                      const SizedBox(height: 18),
                      SectionTitle('Materiales', action: _materials.any((m) => m.productId != null && !m.discounted) ? 'Descontar del stock' : null, onAction: _consume),
                      SoftCard(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Column(children: [
                          for (final m in _materials)
                            ListTile(
                              dense: true,
                              title: Text(m.description),
                              subtitle: Text('${qtyText(m.quantity)}${m.unitPrice > 0 ? ' × ${money(m.unitPrice, cur)}' : ''}${m.discounted ? ' · descontado' : ''}'),
                              trailing: m.discounted
                                  ? const Icon(Icons.inventory_rounded, color: Brand.ok)
                                  : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => _run(() => V2Repo.deleteMaterial(m.id))),
                            ),
                          TextButton.icon(onPressed: _addMaterial, icon: const Icon(Icons.add_rounded), label: const Text('Agregar material')),
                        ]),
                      ),
                      if (j.kind == 'obra' || _milestones.isNotEmpty || s.businessType == 'construccion') ...[
                        const SizedBox(height: 18),
                        SectionTitle('Avance por hitos'),
                        SoftCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (_milestones.isNotEmpty) ...[
                              Builder(builder: (context) {
                                final total = _milestones.fold(0.0, (x, m) => x + m.amount);
                                final billed = _milestones.where((m) => m.invoiceId != null).fold(0.0, (x, m) => x + m.amount);
                                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Facturado ${money(billed, cur)} de ${money(total, cur)}', style: t.textTheme.titleSmall),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(value: total <= 0 ? 0 : billed / total, minHeight: 8, borderRadius: BorderRadius.circular(Radii.sm)),
                                ]);
                              }),
                              const SizedBox(height: 8),
                            ],
                            for (final m in _milestones)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(m.invoiceId != null ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: m.invoiceId != null ? Brand.ok : null),
                                title: Text(m.title),
                                subtitle: Text(money(m.amount, cur)),
                                trailing: m.invoiceId != null
                                    ? TextButton(
                                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: m.invoiceId!))),
                                        child: const Text('Ver'),
                                      )
                                    : (a.can('sell') ? FilledButton.tonal(onPressed: () => _invoiceMilestone(m), child: const Text('Facturar')) : null),
                              ),
                            TextButton.icon(onPressed: _addMilestone, icon: const Icon(Icons.add_rounded), label: const Text('Agregar hito')),
                          ]),
                        ),
                      ],
                      if (_events.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        SectionTitle('Historial'),
                        for (final e in _events.reversed)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.history_rounded, size: 20),
                            title: Text('${s.statusOf(e.from).label} → ${s.statusOf(e.to).label}'),
                            subtitle: e.at == null ? null : Text(shortDateTime(e.at!)),
                          ),
                      ],
                    ]),
                  ),
                ),
    );
  }

  Widget _photos(BuildContext context) {
    final before = _media.where((m) => m.kind == 'antes').toList();
    final after = _media.where((m) => m.kind == 'despues').toList();
    final other = _media.where((m) => m.kind != 'antes' && m.kind != 'despues').toList();
    Widget col(String title, List<MediaFile> list, String kind) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            for (final m in list.take(4)) Padding(padding: const EdgeInsets.only(bottom: 6), child: AspectRatio(aspectRatio: 4 / 3, child: StorageImage(path: m.path))),
            OutlinedButton.icon(onPressed: () => _photo(kind), icon: const Icon(Icons.add_a_photo_rounded, size: 18), label: const Text('Foto')),
          ]),
        );
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [col('Antes', before, 'antes'), const SizedBox(width: 10), col('Después', after, 'despues')]),
      if (other.isNotEmpty) ...[
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [for (final m in other) StorageImage(path: m.path)],
        ),
      ],
    ]);
  }
}

// ═════════════════════════ Formulario ═════════════════════════
Future<String?> showJobForm(BuildContext context, {Job? job, String? clientId, String? clientName, String address = '', DateTime? at, String? kind}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _JobForm(job: job, clientId: clientId, clientName: clientName, address: address, at: at, kind: kind),
    );

class _JobForm extends StatefulWidget {
  const _JobForm({this.job, this.clientId, this.clientName, this.address = '', this.at, this.kind});
  final Job? job;
  final String? clientId;
  final String? clientName;
  final String address;
  final DateTime? at;
  final String? kind;

  @override
  State<_JobForm> createState() => _JobFormState();
}

class _JobFormState extends State<_JobForm> {
  late final Job _j = widget.job ??
      Job(
        title: '',
        clientId: widget.clientId,
        clientName: widget.clientName ?? '',
        address: widget.address,
        scheduledAt: widget.at,
        kind: widget.kind ?? 'servicio',
      );
  late final _title = TextEditingController(text: _j.title);
  late final _address = TextEditingController(text: _j.address);
  late final _phone = TextEditingController(text: _j.contactPhone);
  late final _amount = TextEditingController(text: _j.amount?.toStringAsFixed(2) ?? '');
  late final _notes = TextEditingController(text: _j.notes);
  List<ClientProfile> _clients = const [];
  OrgSettings? _s;
  bool _busy = false;
  int _shake = 0;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    V2Repo.settings().then((s) {
      if (!mounted) return;
      setState(() {
        _s = s;
        if (widget.job == null && widget.kind == null) _j.kind = s.template.defaultJobKind;
      });
    });
    if (_j.clientId == null) {
      V2Repo.clients().then((c) {
        if (mounted) setState(() => _clients = c);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _address, _phone, _amount, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final base = _j.scheduledAt ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    final d = await showDatePicker(context: context, initialDate: base, firstDate: now.subtract(const Duration(days: 365)), lastDate: now.add(const Duration(days: 730)));
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (tm == null) return;
    setState(() => _j.scheduledAt = DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
  }

  Future<void> _here() async {
    try {
      final p = await currentLocation();
      setState(() {
        _j.lat = p.lat;
        _j.lng = p.lng;
        _msg = 'Ubicación guardada ✓';
      });
    } catch (e) {
      setState(() => _msg = friendly(e));
    }
  }

  Future<void> _save() async {
    _j
      ..title = _title.text.trim()
      ..address = _address.text
      ..contactPhone = _phone.text
      ..amount = parseDecimal(_amount.text)
      ..notes = _notes.text;
    if (_j.title.isEmpty) {
      setState(() {
        _shake++;
        _msg = 'Escribe qué hay que hacer.';
      });
      return;
    }
    if (_j.id == null && (_s?.statuses.isNotEmpty ?? false) && !(_s!.statuses.any((x) => x.key == _j.status))) _j.status = _s!.statuses.first.key;
    setState(() => _busy = true);
    try {
      final id = await V2Repo.saveJob(_j);
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _msg = V2Repo.missingHint(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final word = _s?.jobWord ?? 'Trabajo';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(shrinkWrap: true, children: [
        Text(_j.id == null ? 'Nuevo: ${word.toLowerCase()} o cita' : 'Editar ${word.toLowerCase()}', style: t.textTheme.titleLarge),
        const SizedBox(height: 12),
        Shake(trigger: _shake, child: TextField(controller: _title, autofocus: _j.id == null, decoration: const InputDecoration(labelText: '¿Qué hay que hacer? *', hintText: 'Ej.: Instalar internet 200 Mbps'))),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: jobKinds.containsKey(_j.kind) ? _j.kind : 'servicio',
          decoration: const InputDecoration(labelText: 'Tipo'),
          items: [for (final e in jobKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _j.kind = v ?? 'servicio'),
        ),
        const SizedBox(height: 10),
        if (_j.clientId == null && widget.clientId == null)
          Autocomplete<ClientProfile>(
            optionsBuilder: (v) => v.text.trim().isEmpty ? const Iterable<ClientProfile>.empty() : _clients.where((c) => c.name.toLowerCase().contains(v.text.toLowerCase())).take(8),
            displayStringForOption: (c) => c.name,
            onSelected: (c) => setState(() {
              _j.clientId = c.id;
              _j.clientName = c.name;
              if (_address.text.isEmpty) _address.text = c.address;
              if (_phone.text.isEmpty) _phone.text = c.phone;
            }),
            fieldViewBuilder: (ctx, ctrl, focus, submit) => TextField(controller: ctrl, focusNode: focus, decoration: const InputDecoration(labelText: 'Cliente (opcional)', prefixIcon: Icon(Icons.person_search_rounded))),
          )
        else
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_rounded), title: Text(_j.clientName.isEmpty ? 'Cliente' : _j.clientName)),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: Text(_j.scheduledAt == null ? 'Sin fecha (tócalo para agendar)' : shortDateTime(_j.scheduledAt!)),
          trailing: _j.scheduledAt == null ? null : IconButton(onPressed: () => setState(() => _j.scheduledAt = null), icon: const Icon(Icons.close_rounded)),
          onTap: _pickWhen,
        ),
        TextField(
          controller: _address,
          decoration: InputDecoration(
            labelText: 'Dirección',
            suffixIcon: IconButton(tooltip: 'Estoy aquí', onPressed: _here, icon: Icon(_j.lat != null ? Icons.location_on_rounded : Icons.my_location_rounded)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Celular de contacto')),
        const SizedBox(height: 10),
        if (Access.instance.can('sell'))
          TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio acordado (opcional)')),
        const SizedBox(height: 10),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Indicaciones')),
        if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg, style: t.textTheme.bodySmall)),
        const SizedBox(height: 14),
        GradientButton(label: 'Guardar', icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _save),
      ]),
    );
  }
}

/// Atajo usado desde otras pantallas.
Future<void> openJobs(BuildContext context) {
  final f = featureById('trabajos');
  return f == null ? Future.value() : openFeature(context, f);
}
