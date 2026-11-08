// Licencia de Solvex Hub en la app (Fase 5). La app solo MUESTRA el estado: quien bloquea de verdad es la base de datos
// (license_guard + políticas restrictivas). Aquí: pantalla de bloqueo, aviso de pago y detalle del plan.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../access.dart';
import '../app_state.dart';
import '../services/repo.dart';
import '../services/v2_api.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'orgs.dart';

const _featureNames = <String, String>{
  'facturar': 'Facturas y boletas SUNAT',
  'clientes': 'Clientes',
  'cobros': 'Cobros',
  'voz': 'Dictado por voz',
  'cotizaciones': 'Cotizaciones',
  'tienda': 'Tienda en línea',
  'stock': 'Inventario',
  'recurrentes': 'Facturación recurrente',
  'copiloto': 'Copiloto con IA',
  'copiloto_agente': 'Tareas del Copiloto (agente)',
  'trabajos': 'Trabajos y seguimiento',
  'agenda': 'Agenda y citas',
  'reportes': 'Reportes e impuestos',
  'multisucursal': 'Varias empresas',
  'fiados': 'Libreta de fiados',
  'caja': 'Caja y cierre del día',
  'cuaderno_ia': 'Del cuaderno a la factura',
  'portal_cliente': 'Portal del cliente',
  'precios': 'Precios y promociones',
  'fidelizacion': 'Puntos y cupones',
  'carta_qr': 'Carta QR y comandas',
  'conciliacion': 'Conciliación bancaria',
  'comisiones': 'Comisiones',
  'avisos_pago': 'Avisos de Yape/Plin',
  'multimoneda': 'Ventas en dólares',
  'api_publica': 'API y webhooks',
  'encuestas': 'Encuestas',
  'antifraude': 'Dueño a distancia',
};

String featureName(String key) => _featureNames[key] ?? key;

Future<void> openPayUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final u = Uri.tryParse(url);
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http')) {
    messenger.showSnackBar(const SnackBar(content: Text('Escríbenos para renovar tu plan.')));
    return;
  }
  if (!await launchUrl(u, mode: LaunchMode.externalApplication)) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir la página de pago.')));
  }
}

/// Tras iniciar sesión, el propietario introduce la licencia entregada por Solvex.
/// La pantalla nunca confía en la clave: el backend valida firma, empresa y plan.
class LicenseGateScreen extends StatefulWidget {
  const LicenseGateScreen({super.key});
  @override
  State<LicenseGateScreen> createState() => _LicenseGateScreenState();
}

class _LicenseGateScreenState extends State<LicenseGateScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String _error = '';
  @override
  void dispose() { _key.dispose(); super.dispose(); }

  Future<void> _activate() async {
    final code = _key.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Escribe la licencia que te entregó Solvex.');
      return;
    }
    setState(() { _busy = true; _error = ''; });
    try {
      await V2Api.activateLicense(code);
      _key.clear(); // no conservamos el código en el teléfono
      await Access.instance.load();
      if (!mounted) return;
      if (!Access.instance.licenseReady) {
        setState(() => _error = 'Licencia recibida, pero aún no está activa. Verifica su estado en Solvex Hub.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('AppException: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() { _busy = true; _error = ''; });
    try {
      await Access.instance.load();
      if (mounted && !Access.instance.canEnter) {
        setState(() => _error = 'Todavía no vemos una licencia activa para esta empresa.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = Access.instance;
    final l = a.license;
    final org = Repo.activeOrgId;
    final pending = !l.enforced || l.dev || l.source != 'hub' || l.status == 'pendiente';
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(25)),
              child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 48),
            )),
            const SizedBox(height: 20),
            Text(pending ? 'Activa tu FacturaVoz' : 'Tu licencia requiere atención',
              style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 9),
            Text(pending
              ? 'Cuenta creada correctamente. Para empezar a vender, introduce la licencia que Solvex te entregó para tu negocio.'
              : (l.message.isNotEmpty ? l.message : 'Tu plan no está activo. Puedes renovarlo o introducir un código actualizado.'),
              style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (org != null) ...[
              Text('Identificador de tu empresa', style: t.textTheme.labelLarge),
              const SizedBox(height: 7),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: org));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ID de empresa copiado. Compártelo con Solvex, no tu contraseña.')));
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(org, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 10),
              Text('Solvex debe asignar tu plan a este ID antes de enviarte el código.',
                style: t.textTheme.bodySmall),
            ],
            const SizedBox(height: 20),
            if (a.isAdmin) ...[
              TextField(
                controller: _key, enabled: !_busy, obscureText: _hide,
                autocorrect: false, enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: 'Código de licencia Solvex',
                  hintText: 'Código que recibiste de Solvex',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: _hide ? 'Mostrar código' : 'Ocultar código',
                    onPressed: () => setState(() => _hide = !_hide),
                    icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  ),
                ),
                onSubmitted: (_) {
                  if (!_busy) {
                    _activate();
                  }
                },
              ),
              const SizedBox(height: 16),
              GradientButton(label: 'Activar mi licencia', icon: Icons.check_circle_rounded,
                busy: _busy, onPressed: _busy ? null : _activate),
              if (l.payUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton.icon(onPressed: () => openPayUrl(context, l.payUrl),
                  icon: const Icon(Icons.payments_rounded), label: const Text('Renovar mi plan')),
              ],
            ] else
              const SoftCard(child: Text('Pídele al propietario o administrador de esta empresa que active la licencia.')),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_error, style: const TextStyle(color: Brand.bad), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded), label: const Text('Ya activé: comprobar licencia')),
            if (AppState.instance.orgs.length > 1)
              TextButton.icon(onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OrgsScreen())),
                icon: const Icon(Icons.swap_horiz_rounded), label: const Text('Cambiar de empresa')),
            TextButton(onPressed: () async {
              AppState.instance.clear();
              await Supabase.instance.client.auth.signOut();
            }, child: const Text('Cerrar sesión')),
          ]),
        ),
      ))),
    );
  }
}

/// La red es indispensable para comprobar la licencia tras iniciar sesión.
class LicenseVerificationScreen extends StatelessWidget {
  const LicenseVerificationScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(
    child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 52),
        const SizedBox(height: 18),
        const Text('No pudimos verificar tu licencia', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        const Text('Comprueba tu conexión con Supabase. No se registrarán ventas sin confirmar el plan.',
          textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: Access.instance.load,
          icon: const Icon(Icons.refresh_rounded), label: const Text('Volver a comprobar')),
        TextButton(onPressed: () async {
          AppState.instance.clear();
          await Supabase.instance.client.auth.signOut();
        }, child: const Text('Cerrar sesión')),
      ],
    )),
  )));
}

/// Texto y color del aviso de licencia, o null si no hay que mostrar nada.
(String, Color)? licenseBannerInfo(LicenseInfo l) {
  if (!l.enforced || l.dev) return null;
  final days = l.daysLeft();
  return switch (l.mode) {
    'restricted' => ('Modo solo lectura: puedes ver y exportar tus datos, pero no registrar ventas ni cobros. Renueva tu plan.', Brand.bad),
    'warning' => (l.message.isNotEmpty ? l.message : 'Tu pago está pendiente. Evita cortes renovando a tiempo.', Brand.warn),
    _ when l.isTrial && days != null && days <= 3 => ('Prueba gratis: ${days == 0 ? 'último día' : 'te quedan $days días'}.', Brand.indigo),
    _ => null,
  };
}

/// Aviso delgado arriba de la app: prueba (días que quedan), pago pendiente o modo solo lectura.
class LicenseBanner extends StatelessWidget {
  const LicenseBanner({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Access.instance,
        builder: (context, _) {
          final a = Access.instance;
          final l = a.license;
          final b = licenseBannerInfo(l);
          if (b == null) return const SizedBox.shrink();
          return Material(
            color: b.$2.withValues(alpha: 0.12),
            child: SafeArea(
              bottom: false,
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanScreen())),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(children: [
                    Icon(Icons.workspace_premium_rounded, color: b.$2, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(b.$1, style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600, color: b.$2))),
                    if (a.isAdmin && l.payUrl.isNotEmpty)
                      TextButton(onPressed: () => openPayUrl(context, l.payUrl), child: const Text('Pagar'))
                    else
                      Icon(Icons.chevron_right_rounded, color: b.$2),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

/// Detalle verificado del plan entregado por Solvex Hub.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mi plan')),
      body: ListenableBuilder(
        listenable: Access.instance,
        builder: (context, _) {
          final a = Access.instance;
          final l = a.license;
          final days = l.daysLeft();
          final included = <String>[
            for (final k in _featureNames.keys)
              if (a.has(k)) k,
          ];
          final users = a.limit('max_users');
          return RefreshIndicator(
            onRefresh: Access.instance.load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              Reveal(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(Radii.xl)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.source == 'local' ? 'Plan ${l.plan} · Local' : l.dev ? 'Pendiente de activación' : 'Plan ${l.plan}', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      l.source == 'local'
                          ? 'Desarrollo independiente · funciones del plan habilitadas para pruebas'
                          : l.dev
                              ? 'Activación de la licencia pendiente.'
                              : [
                              if (l.isTrial) 'Prueba gratis' else 'Estado: ${l.status}',
                              if (days != null) (days == 0 ? 'vence hoy' : 'quedan $days días'),
                            ].join(' · '),
                      style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.88)),
                    ),
                    if (users > 0) ...[
                      const SizedBox(height: 4),
                      Text('Hasta $users usuarios', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.88))),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              if (l.source != 'local' && a.isAdmin && l.payUrl.isNotEmpty) GradientButton(label: 'Pagar o mejorar mi plan', icon: Icons.payments_rounded, onPressed: () => openPayUrl(context, l.payUrl)),
              const SizedBox(height: 18),
              const SectionTitle('Incluido en tu plan'),
              SoftCard(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final k in included) TagChip(featureName(k), color: Brand.ok, icon: Icons.check_rounded),
                ]),
              ),
              const SizedBox(height: 18),
              SectionTitle(l.source == 'local' ? 'Modo de desarrollo' : 'Gestión de tu suscripción'),
              SoftCard(child: Text(l.source == 'local'
                ? 'Esta empresa usa temporalmente planes locales. Solo se muestran las funciones de su plan y se mantienen los permisos de usuario, la seguridad y la separación de empresas. No requiere activación comercial durante el desarrollo.'
                : 'Las funciones y los límites dependen de la licencia activa. Para ampliar el plan, contacta con el proveedor.',
              )),
              const SizedBox(height: 14),
              Text('Tu rol en esta empresa: ${a.roleLabel}.', style: t.textTheme.bodySmall, textAlign: TextAlign.center),
            ]),
          );
        },
      ),
    );
  }
}

