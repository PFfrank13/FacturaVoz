// Licencia de Solvex Hub en la app (Fase 5). La app solo MUESTRA el estado: quien bloquea de verdad es la base de datos
// (license_guard + políticas restrictivas). Aquí: pantalla de bloqueo, aviso de pago y detalle del plan.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../access.dart';
import '../app_state.dart';
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

/// Pantalla completa cuando la licencia está BLOQUEADA (no se puede usar la empresa).
class LicenseGateScreen extends StatelessWidget {
  const LicenseGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = Access.instance;
    final l = a.license;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Reveal(
                  child: Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(color: Brand.warn.withValues(alpha: 0.14), shape: BoxShape.circle),
                      child: const Icon(Icons.lock_clock_rounded, size: 46, color: Brand.warn),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Reveal(
                  index: 1,
                  child: Text(l.isTrial ? 'Tu prueba gratis terminó' : 'Tu plan está pausado', textAlign: TextAlign.center, style: t.textTheme.headlineSmall),
                ),
                const SizedBox(height: 10),
                Reveal(
                  index: 2,
                  child: Text(
                    l.message.isNotEmpty
                        ? l.message
                        : 'Tus datos están a salvo y nada se borró. Para seguir vendiendo con ${AppState.instance.activeOrg?.name ?? 'tu empresa'}, renueva tu plan.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(height: 24),
                if (a.isAdmin && l.payUrl.isNotEmpty)
                  Reveal(index: 3, child: GradientButton(label: 'Renovar mi plan', icon: Icons.payments_rounded, onPressed: () => openPayUrl(context, l.payUrl)))
                else if (!a.isAdmin)
                  Reveal(index: 3, child: SoftCard(child: Text('Avísale al dueño de la empresa para que renueve el plan.', textAlign: TextAlign.center, style: t.textTheme.bodyMedium))),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Access.instance.load();
                    if (context.mounted && Access.instance.license.mode == 'blocked') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aún no vemos el pago. Puede tardar unos minutos.')));
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Ya pagué: revisar de nuevo'),
                ),
                if (AppState.instance.orgs.length > 1)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgsScreen())),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Cambiar de empresa'),
                  ),
                TextButton(
                  onPressed: () async {
                    AppState.instance.clear();
                    await Supabase.instance.client.auth.signOut();
                  },
                  child: const Text('Cerrar sesión'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
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

/// Detalle del plan: qué incluye, hasta cuándo, botón de pago y activar la prueba en Solvex Hub.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  bool _busy = false;

  Future<void> _trial() async {
    setState(() => _busy = true);
    try {
      final r = await V2Api.requestTrial();
      await Access.instance.load();
      if (!mounted) return;
      final msg = switch (r.status) {
        'ok' => '¡Listo! Tu prueba de 3 días está activa.',
        'used' => r.message.isNotEmpty ? r.message : 'Este RUC ya usó su prueba gratis. Elige un plan para continuar.',
        _ => r.message.isNotEmpty ? r.message : 'No se pudo activar la prueba ahora. Inténtalo más tarde.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    if (mounted) setState(() => _busy = false);
  }

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
          final missing = _featureNames.keys.where((k) => !included.contains(k)).toList();
          final users = a.limit('max_users');
          return RefreshIndicator(
            onRefresh: Access.instance.load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              Reveal(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(Radii.xl)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.dev ? 'Modo desarrollo' : 'Plan ${l.plan}', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      l.dev
                          ? 'Solvex Hub aún no está conectado: todo está habilitado sin cobros.'
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
              if (a.isAdmin && l.payUrl.isNotEmpty) GradientButton(label: 'Pagar o mejorar mi plan', icon: Icons.payments_rounded, onPressed: () => openPayUrl(context, l.payUrl)),
              if (a.isAdmin && l.source == 'local' && !l.trialRequested) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _trial,
                  icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.rocket_launch_rounded),
                  label: const Text('Activar mi prueba de 3 días con mi RUC'),
                ),
                const SizedBox(height: 4),
                Text('Una prueba por RUC. Necesitas haber guardado el RUC de la empresa en Datos del negocio.', style: t.textTheme.bodySmall, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 18),
              const SectionTitle('Incluido en tu plan'),
              SoftCard(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final k in included) TagChip(featureName(k), color: Brand.ok, icon: Icons.check_rounded),
                ]),
              ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 18),
                const SectionTitle('Disponible en planes superiores'),
                SoftCard(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final k in missing) TagChip(featureName(k), color: t.colorScheme.onSurfaceVariant, icon: Icons.lock_outline_rounded),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              Text('Tu rol en esta empresa: ${a.roleLabel}.', style: t.textTheme.bodySmall, textAlign: TextAlign.center),
            ]),
          );
        },
      ),
    );
  }
}
