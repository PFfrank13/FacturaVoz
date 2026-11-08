// Ajustes v2.0: tipo de negocio, modo simple, funciones a la vista, animaciones, equipo, plan, marca, impresora,
// control del dueño y reporte diario. Lo que el rol no puede cambiar no aparece (y RLS lo impide igual).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../access.dart';
import '../app_state.dart';
import '../config.dart';
import '../business_templates.dart';
import '../models_v2.dart';
import '../rubros.dart';
import '../services/rubro_repo.dart';
import '../services/voice.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'branding.dart';
import 'catalog.dart';
import 'license_gate.dart';
import 'menu.dart' show upgradeLabel;
import 'owner_control.dart';
import '../ux/commerce_navigation.dart';
import 'team.dart';
import 'trash.dart';

class BusinessSettingsCard extends StatefulWidget {
  const BusinessSettingsCard({super.key});

  @override
  State<BusinessSettingsCard> createState() => _BusinessSettingsCardState();
}

class _BusinessSettingsCardState extends State<BusinessSettingsCard> {
  OrgSettings? _s;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    V2Repo.changed.addListener(_load);
    PremiumVoice.instance.refreshUsage().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    V2Repo.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final s = await V2Repo.settings();
    if (mounted) setState(() => _s = s);
  }

  Future<void> _save(Future<void> Function() op, String ok) async {
    setState(() => _saving = true);
    try {
      await op();
      if (mounted) showSuccess(context, ok);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
    if (mounted) setState(() => _saving = false);
    _load();
  }

  Future<void> _animations() async {
    final current = MotionPrefs.userReduced.value;
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('Animaciones', style: Theme.of(ctx).textTheme.titleLarge)),
          for (final (key, title, sub) in const [
            ('auto', 'Automático', 'Se reducen solas si el teléfono es lento o si lo pide el sistema'),
            ('reduced', 'Animaciones reducidas', 'Más rápido y sin movimientos (ahorra batería)'),
            ('full', 'Completas', 'Todas las transiciones y efectos'),
          ])
            ListTile(
              leading: Icon(
                key == (current == null ? 'auto' : (current ? 'reduced' : 'full')) ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: Text(title),
              subtitle: Text(sub),
              onTap: () => Navigator.pop(ctx, key),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (v == null) return;
    await AppState.instance.setReducedMotion(switch (v) {
      'reduced' => true,
      'full' => false,
      _ => null,
    });
    if (mounted) setState(() {});
  }

  Future<void> _dailyReport(OrgSettings s) async {
    if (_saving) return;
    final email = TextEditingController(text: s.dailyReportTo);
    var on = s.dailyReport;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Reporte del día por correo'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: (v) => set(() => on = v),
              title: const Text('Enviarme el resumen cada noche'),
              subtitle: const Text('Ventas, cobros, fiados y caja. También llega al cerrar la caja.'),
            ),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo (vacío = el del dueño)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    final to = email.text.trim();
    disposeAfterClose([email]);
    if (ok != true) return;
    if (to.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(to)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ese correo no parece válido.')));
      return;
    }
    await _save(() => V2Repo.saveSettingsFields({'daily_report': on, 'daily_report_to': to.isEmpty ? null : to}), on ? 'Reporte diario activado' : 'Reporte diario desactivado');
  }

  Widget _row(IconData icon, String title, String subtitle, VoidCallback onTap, {Widget? trailing, Color? color}) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: c, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textTheme.titleSmall),
              Text(subtitle, style: t.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          trailing ?? Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = Access.instance;
    final s = _s;
    final admin = a.can('settings');
    final rm = MotionPrefs.userReduced.value;
    void go(Widget w) => pushPremium(context, w);
    final rows = <Widget>[
      if (admin && s != null)
        _row(
            Icons.dashboard_customize_rounded,
            'Experiencia comercial',
            commerceExperience(a.license.plan),
            () => go(const PlanScreen())),
      _row(
        Icons.text_increase_rounded,
        'Modo Fácil',
        AppState.instance.easyMode.value ? 'Letras y botones grandes' : 'Apagado: tamaño normal',
        () {},
        trailing: Switch(
          value: AppState.instance.easyMode.value,
          onChanged: (v) async {
            await AppState.instance.setEasyMode(v);
            if (mounted) setState(() {});
          },
        ),
      ),
      if (a.has('copiloto'))
        _row(
          Icons.record_voice_over_rounded,
          'Voz del Copiloto',
          switch (PremiumVoice.instance.usage.value) {
            null => 'Voz natural cuando tocas "Escuchar" o preguntas hablando',
            (final u, final l) => 'Voz natural usada hoy: $u de $l caracteres (lo repetido no se cobra)',
          },
          () {},
          trailing: const SizedBox.shrink(),
        ),
      _row(Icons.support_agent_rounded, 'Ayuda por WhatsApp', 'Escríbenos: el mensaje ya lleva tu versión, rubro y plan', () => openSupport(context)),
      _row(Icons.security_rounded, 'Seguridad', 'Alertas, bitácora, PIN, papelera y huella', () => showSecuritySheet(context)),
      if (admin && s != null && rubroFor(s.businessType) != null)
        _row(Icons.science_rounded, 'Datos de práctica', 'Productos y clientes de ejemplo de tu rubro (se borran con un toque)', () => showPracticeSheet(context, rubroFor(s.businessType)!)),
      if (admin) _row(Icons.tune_rounded, 'Funciones a la vista', 'Elige qué se ve primero (nada se borra)', () => go(const ModulesScreen())),
      _row(Icons.animation_rounded, 'Animaciones', rm == null ? 'Automático' : (rm ? 'Reducidas' : 'Completas'), _animations),
      if (a.can('team')) _row(Icons.groups_rounded, 'Equipo y permisos', 'Invita y elige qué ve cada uno', () => go(const TeamScreen())),
      _row(Icons.workspace_premium_rounded, 'Mi plan', a.license.dev
              ? 'Modo desarrollo (sin cobros)'
              : [
                  'Plan ${planName(a.license.plan)}',
                  if (planPriceText(a.license.plan).isNotEmpty) planPriceText(a.license.plan),
                  commerceExperience(a.license.plan),
                ].join(' · '), () => go(const PlanScreen())),
      if (admin) _row(Icons.palette_rounded, 'Logo y comprobantes', 'Logo, diseño del PDF y ancho del ticket', () => go(const BrandingScreen())),
      _row(Icons.print_rounded, 'Impresora de tickets', 'Bluetooth o red · 58 u 80 mm', () => go(const PrinterSettingsScreen())),
      if (a.can('team') && a.has('antifraude')) _row(Icons.shield_rounded, 'Dueño a distancia', 'PIN, alertas y bitácora', () => go(const AlertsScreen())),
      if (admin && s != null)
        _row(Icons.mark_email_read_rounded, 'Reporte del día por correo', s.dailyReport ? 'Activado${s.dailyReportTo.isNotEmpty ? ' · ${s.dailyReportTo}' : ''}' : 'Apagado', () => _dailyReport(s)),
      if (a.can('finance')) _row(Icons.restore_from_trash_rounded, 'Papelera', 'Recupera lo borrado (30 días)', () => go(const TrashScreen())),
      _row(Icons.apps_rounded, 'Todas las funciones', 'Busca y abre cualquier función', () => go(const AllFunctionsScreen())),
    ];
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(children: [
            Text('Tu negocio', style: t.textTheme.titleMedium),
            const Spacer(),
            TagChip(a.roleLabel, color: Brand.indigo, icon: Icons.badge_rounded),
          ]),
        ),
        if (s != null && !V2Repo.ready)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('Ejecuta las migraciones v2.0 (20261104 a 20261112) en Supabase para activar estas opciones.', style: t.textTheme.bodySmall?.copyWith(color: Brand.warn)),
          ),
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) Divider(indent: 70, height: 1, color: t.colorScheme.outline),
          r,
        ],
      ]),
    );
  }
}

/// Qué funciones se ven a primera vista (en Inicio, Vender y los hubs). Lo apagado sigue en "Todas las funciones".
class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  OrgSettings? _s;

  @override
  void initState() {
    super.initState();
    V2Repo.settings(refresh: true).then((s) {
      if (mounted) setState(() => _s = s);
    });
  }

  Future<void> _toggle(String key, bool v) async {
    final s = _s;
    if (s == null) return;
    setState(() => s.modules[key] = v);
    try {
      await V2Repo.saveSettings(s);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Funciones a la vista')),
      body: s == null
          ? const SkeletonList()
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
              Text('Plantilla: ${s.template.name}. Apagar algo solo lo esconde de la vista principal; nunca se borra.', style: t.textTheme.bodySmall),
              const SizedBox(height: 12),
              SoftCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final e in allModules.entries.where((e) => !const {'carta_qr', 'trabajos', 'agenda'}.contains(e.key)))
                    SwitchListTile(
                      value: s.shows(e.key),
                      onChanged: (v) => _toggle(e.key, v),
                      title: Text(e.value),
                      subtitle: s.template.modules.contains(e.key) ? const Text('Recomendado para tu negocio') : null,
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  setState(() => s.modules = {});
                  try {
                    await V2Repo.saveSettings(s);
                  } catch (_) {}
                },
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Volver a lo recomendado'),
              ),
            ]),
    );
  }
}


/// Pasos (estados) de los trabajos y campos extra del cliente: vienen de la plantilla y se pueden cambiar.
/// Ej. servicio técnico WiFi: Nuevo → Visita → Cotizado → Pendiente → En camino → Instalado → Cobrado.
class JobFlowScreen extends StatefulWidget {
  const JobFlowScreen({super.key});

  @override
  State<JobFlowScreen> createState() => _JobFlowScreenState();
}

class _JobFlowScreenState extends State<JobFlowScreen> {
  OrgSettings? _s;
  List<JobStatus> _steps = [];
  List<ClientField> _fields = [];
  bool _busy = false;

  static const _palette = [0xFF8A8CAB, 0xFF6A62E2, 0xFFC57A12, 0xFF9B8CF5, 0xFF4FA3D9, 0xFF23956F, 0xFFD94A5E];

  @override
  void initState() {
    super.initState();
    V2Repo.settings(refresh: true).then((s) {
      if (!mounted) return;
      setState(() {
        _s = s;
        _steps = [...s.statuses];
        _fields = [...s.fields];
      });
    });
  }

  String _key(String label) {
    var k = label.toLowerCase().replaceAll(RegExp(r'[áà]'), 'a').replaceAll(RegExp(r'[éè]'), 'e').replaceAll(RegExp(r'[íì]'), 'i').replaceAll(RegExp(r'[óò]'), 'o').replaceAll(RegExp(r'[úù]'), 'u').replaceAll('ñ', 'n');
    k = k.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    if (k.isEmpty) k = 'paso';
    var out = k;
    var n = 2;
    while (_steps.any((x) => x.key == out) || _fields.any((x) => x.key == out)) {
      out = '${k}_$n';
      n++;
    }
    return out.length > 30 ? out.substring(0, 30) : out;
  }

  Future<String?> _ask(String title, {String initial = ''}) async {
    final c = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, maxLength: 30),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Listo')),
        ],
      ),
    );
    final v = c.text.trim();
    disposeAfterClose([c]);
    return ok == true && v.isNotEmpty ? v : null;
  }

  Future<void> _save() async {
    final s = _s;
    if (s == null) return;
    if (!_steps.any((x) => x.done)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marca al menos un paso como "terminado".')));
      return;
    }
    setState(() => _busy = true);
    s.jobStatuses = _steps;
    s.clientFields = _fields;
    try {
      await V2Repo.saveSettings(s);
      if (mounted) {
        showSuccess(context, 'Guardado');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Pasos y campos')),
      body: s == null
          ? const SkeletonList(count: 3)
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
              Text('Pasos de tus ${s.jobsWord.toLowerCase()} (mantén presionado para reordenar)', style: t.textTheme.titleSmall),
              const SizedBox(height: 8),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: true,
                // onReorderItem (Flutter 3.41+): el índice nuevo ya viene ajustado.
                onReorderItem: (a, b) => setState(() => _steps.insert(b, _steps.removeAt(a))),
                children: [
                  for (final (i, st) in _steps.indexed)
                    ListTile(
                      key: ValueKey(st.key),
                      leading: CircleAvatar(radius: 8, backgroundColor: Color(st.color)),
                      title: Text(st.label),
                      subtitle: st.done ? const Text('Cuenta como terminado') : null,
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Terminado',
                          onPressed: () => setState(() => _steps[i] = JobStatus(st.key, st.label, done: !st.done, color: st.color)),
                          icon: Icon(st.done ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded, color: st.done ? Brand.ok : null),
                        ),
                        IconButton(
                          tooltip: 'Renombrar',
                          onPressed: () async {
                            final v = await _ask('Nombre del paso', initial: st.label);
                            if (v != null) setState(() => _steps[i] = JobStatus(st.key, v, done: st.done, color: st.color));
                          },
                          icon: const Icon(Icons.edit_rounded),
                        ),
                        if (_steps.length > 2)
                          IconButton(tooltip: 'Quitar', onPressed: () => setState(() => _steps.removeAt(i)), icon: const Icon(Icons.close_rounded)),
                      ]),
                    ),
                ],
              ),
              TextButton.icon(
                onPressed: _steps.length >= 12
                    ? null
                    : () async {
                        final v = await _ask('Nuevo paso');
                        if (v != null) setState(() => _steps.add(JobStatus(_key(v), v, color: _palette[_steps.length % _palette.length])));
                      },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Agregar paso'),
              ),
              const SizedBox(height: 18),
              Text('Datos extra del cliente', style: t.textTheme.titleSmall),
              Text('Aparecen en la ficha del cliente (ej.: plan de internet, placa, alergias).', style: t.textTheme.bodySmall),
              for (final (i, f) in _fields.indexed)
                ListTile(
                  title: Text(f.label),
                  trailing: IconButton(onPressed: () => setState(() => _fields.removeAt(i)), icon: const Icon(Icons.close_rounded)),
                ),
              TextButton.icon(
                onPressed: _fields.length >= 15
                    ? null
                    : () async {
                        final v = await _ask('Nuevo dato del cliente');
                        if (v != null) setState(() => _fields.add(ClientField(_key(v), v)));
                      },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Agregar dato'),
              ),
              const SizedBox(height: 16),
              GradientButton(label: 'Guardar', icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _save),
              TextButton(
                onPressed: () => setState(() {
                  _steps = [...s.template.statuses];
                  _fields = [...s.template.clientFields];
                }),
                child: const Text('Volver a los de mi plantilla'),
              ),
            ]),
    );
  }
}


/// Ajustes → Seguridad (E): alertas del dueño, bitácora, PIN, papelera y bloqueo con huella en un solo lugar.
void showSecuritySheet(BuildContext context) {
  final items = [for (final id in const ['alertas', 'bitacora', 'pin', 'papelera', 'seguridad']) if (featureById(id) case final f? when f.roleOk) f];
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final f in items)
          ListTile(
            leading: Icon(f.planOk ? f.icon : Icons.lock_rounded),
            title: Text(f.title),
            subtitle: Text(f.planOk ? f.subtitle : upgradeLabel(f)),
            onTap: () {
              Navigator.pop(c);
              openFeature(context, f);
            },
          ),
      ]),
    ),
  );
}

/// Datos de práctica del rubro: claramente marcados ("práctica") y se borran con un toque.
void showPracticeSheet(BuildContext context, RubroSpec spec) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Datos de práctica · ${spec.name}', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Agrega ${spec.practiceProducts.length} ${spec.word('products').toLowerCase()} y ${spec.practiceClients.length} ${spec.word('clients').toLowerCase()} de ejemplo para probar sin miedo. '
              'Quedan marcados como "práctica" y no cuentan como ventas mientras no emitas comprobantes con ellos.'),
          const SizedBox(height: 16),
          Row(children: [
            TextButton(
              onPressed: () async {
                Navigator.pop(c);
                await RubroRepo.clearPractice();
                if (context.mounted) showSuccess(context, 'Datos de práctica borrados');
              },
              child: const Text('Borrar los de práctica'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                Navigator.pop(c);
                final n = await RubroRepo.loadPractice([for (final p in spec.practiceProducts) (p.name, p.price, p.unit, p.cost)], spec.practiceClients);
                if (context.mounted) showSuccess(context, n == 0 ? 'Ya estaban cargados' : 'Listo: $n datos de práctica');
              },
              child: const Text('Cargar'),
            ),
          ]),
        ]),
      ),
    ),
  );
}


/// Ayuda (G): abre WhatsApp de soporte con el CONTEXTO (versión, rubro, plan, rol). Sin datos de clientes ni montos.
Future<void> openSupport(BuildContext context) async {
  final a = Access.instance;
  final text = 'Hola, necesito ayuda con FacturaVoz.\n'
      '— Versión ${Config.appVersion} · Rubro: ${rubroFor(a.rubro)?.name ?? 'sin elegir'} · Plan: ${a.license.dev ? 'desarrollo' : a.license.plan} · Rol: ${a.roleLabel}\n'
      'Mi consulta: ';
  final n = Config.supportWhatsapp.replaceAll(RegExp(r'\D'), '');
  if (n.isEmpty) {
    // Sin número configurado no se inventa uno: se avisa (se define al compilar con --dart-define=SUPPORT_WHATSAPP=…).
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El número de soporte aún no está configurado en esta versión de la app.')));
    return;
  }
  final uri = Uri.https('wa.me', '/${n.length == 9 ? '51$n' : n}', {'text': text});
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp.')));
  }
}
