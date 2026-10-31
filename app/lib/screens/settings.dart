import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../config.dart';
import '../services/repo.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../ui/motion.dart';
import 'clients.dart';
import 'expenses.dart';
import 'clients360.dart';
import 'pay_settings.dart';
import 'recurring.dart';
import 'store.dart';
import 'fiscal_setup.dart';
import 'import_screen.dart';
import 'legal.dart';
import 'orgs.dart';
import 'products.dart';
import 'reports.dart';
import 'security.dart';
import 'profile_form.dart';
import 'catalog.dart' show SearchButton;
import 'settings_v2.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.embedded = false});

  /// true como pestaña del shell (modo simple / técnico): sin flecha atrás y con espacio para el dock.
  final bool embedded;

  /// Intercala separadores entre las filas visibles.
  List<Widget> _joined(BuildContext context, List<Widget> tiles) {
    final line = Theme.of(context).colorScheme.outline;
    return [
      for (final (i, w) in tiles.indexed) ...[
        if (i > 0) Divider(indent: 72, color: line),
        w,
      ],
    ];
  }

  Future<void> _pickTheme(BuildContext context) async {
    final m = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Apariencia', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {AppState.instance.themeMode.value},
              onSelectionChanged: (s) => Navigator.pop(ctx, s.first),
            ),
          ]),
        ),
      ),
    );
    if (m != null) await AppState.instance.setTheme(m);
  }

  Future<void> _signOut(BuildContext context) async {
    final nav = Navigator.of(context);
    AppState.instance.clear();
    await Supabase.instance.client.auth.signOut();
    nav.popUntil((r) => r.isFirst);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Se borrarán tu cuenta, clientes y facturas de forma permanente. Escribe ELIMINAR para confirmar.'),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim() == 'ELIMINAR'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    disposeAfterClose([ctrl]);
    if (ok != true) return;
    try {
      await Repo.deleteAccount();
      AppState.instance.clear();
      nav.popUntil((r) => r.isFirst);
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message.contains('conservar')
            ? 'No se puede eliminar: tienes comprobantes electrónicos que la ley exige conservar. Escribe a soporte.'
            : 'No se pudo eliminar la cuenta. Inténtalo de nuevo.'),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo eliminar la cuenta. Inténtalo de nuevo.')));
    }
  }

  Widget _tile(BuildContext context, {required IconData icon, required String title, String? subtitle, required VoidCallback onTap, Color? color}) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.md)),
            child: Icon(icon, color: c, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textTheme.titleSmall?.copyWith(color: color)),
              if (subtitle != null) Text(subtitle, style: t.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Listenable.merge([AppState.instance, Access.instance]), builder: (context, _) => _page(context));

  Widget _page(BuildContext context) {
    final t = Theme.of(context);
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final org = AppState.instance.activeOrg;
    final a = Access.instance;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        automaticallyImplyLeading: !embedded,
        actions: const [SearchButton(), SizedBox(width: 12)],
      ),
      body: SafeArea(
        bottom: !embedded,
        child: ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: EdgeInsets.fromLTRB(16, 4, 16, embedded ? 150 : 32), children: [
          Reveal(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(Radii.xl), boxShadow: Brand.softShadow(false, a: 0.3)),
              child: Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                  child: Text(email.isEmpty ? '?' : email.characters.first.toUpperCase(),
                      style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(org?.name ?? 'Mi cuenta',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(height: 4),
          // v2.0: tipo de negocio, modo simple, animaciones, equipo, plan, logo, impresora, PIN, reporte diario…
          const Reveal(index: 1, child: BusinessSettingsCard()),
          const SizedBox(height: 14),
          Reveal(
            index: 2,
            child: SoftCard(
              padding: EdgeInsets.zero,
              child: Column(children: _joined(context, [
                _tile(context,
                    icon: Icons.apartment_rounded,
                    title: 'Empresas',
                    subtitle: org?.name ?? 'Cambia de empresa o crea otra',
                    onTap: () => go(const OrgsScreen())),
                _tile(context,
                    icon: Icons.inventory_2_rounded,
                    title: 'Productos y servicios',
                    subtitle: 'Catálogo, precios, código de barras y stock',
                    onTap: () => go(const ProductsScreen())),
                if (a.can('settings'))
                  _tile(context,
                      icon: Icons.qr_code_2_rounded,
                      title: 'Cobros y recordatorios',
                      subtitle: 'Yape, Plin, banco, tarjeta y cobranza automática',
                      onTap: () => pushPremium(context, const PaySettingsScreen())),
                if (a.can('settings') && a.has('tienda'))
                  _tile(context,
                      icon: Icons.storefront_rounded,
                      title: 'Tienda en línea',
                      subtitle: 'Tu catálogo como página web: recibe pedidos por WhatsApp',
                      onTap: () => pushPremium(context, const StoreScreen())),
                if (a.can('finance') && a.has('recurrentes'))
                  _tile(context,
                      icon: Icons.event_repeat_rounded,
                      title: 'Facturación recurrente',
                      subtitle: 'Alquileres y mensualidades que se facturan solos',
                      onTap: () => pushPremium(context, const RecurringScreen())),
                if (a.can('finance'))
                  _tile(context,
                      icon: Icons.groups_rounded,
                      title: 'Clientes 360',
                      subtitle: 'Mejores clientes y los que se están yendo',
                      onTap: () => pushPremium(context, const Clients360Screen())),
                if (a.can('finance'))
                  _tile(context,
                      icon: Icons.shopping_bag_rounded,
                      title: 'Gastos',
                      subtitle: 'Compras y pagos del negocio (o escanéalos)',
                      onTap: () => go(const ExpensesScreen())),
                _tile(context,
                    icon: Icons.palette_outlined,
                    title: 'Apariencia',
                    subtitle: switch (AppState.instance.themeMode.value) {
                      ThemeMode.light => 'Claro',
                      ThemeMode.dark => 'Oscuro',
                      _ => 'Igual que el sistema',
                    },
                    onTap: () => _pickTheme(context)),
                if (!kIsWeb)
                  _tile(context,
                      icon: Icons.fingerprint_rounded,
                      title: 'Seguridad',
                      subtitle: 'PIN y huella para entrar',
                      onTap: () => go(const SecurityScreen())),
                _tile(context,
                    icon: Icons.contacts_rounded,
                    title: 'Clientes (lista simple)',
                    subtitle: 'Contactos, documentos y correos',
                    onTap: () => go(const ClientsScreen())),
                if (a.can('import'))
                  _tile(context,
                      icon: Icons.cloud_upload_rounded,
                      title: 'Importar facturas antiguas',
                      subtitle: 'Desde Excel (.xlsx) o CSV de SUNAT o tu sistema anterior',
                      onTap: () => go(const ImportScreen())),
                if (a.can('finance'))
                  _tile(context,
                      icon: Icons.insights_rounded,
                      title: 'Reportes',
                      subtitle: 'Ventas por mes y exportar a Excel',
                      onTap: () => go(const ReportsScreen())),
                if (a.can('settings'))
                  _tile(context,
                      icon: Icons.business_outlined,
                      title: 'Datos del negocio',
                      subtitle: 'Nombre, documento, moneda e impuesto',
                      onTap: () => go(const ProfileFormScreen())),
                if (a.can('settings'))
                  _tile(context,
                      icon: Icons.verified_outlined,
                      title: 'Facturación electrónica (SUNAT)',
                      subtitle: 'RUC, usuario SOL y certificado digital',
                      onTap: () => go(const FiscalSetupScreen())),
              ])),
            ),
          ),
          const SizedBox(height: 14),
          Reveal(
            index: 3,
            child: SoftCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                if (Config.privacyUrl.isNotEmpty) ...[
                  _tile(context, icon: Icons.privacy_tip_outlined, title: 'Política de privacidad', onTap: openPrivacyPolicy),
                  Divider(indent: 72, color: t.colorScheme.outline),
                ],
                _tile(context, icon: Icons.logout_rounded, title: 'Cerrar sesión', onTap: () => _signOut(context)),
                Divider(indent: 72, color: t.colorScheme.outline),
                _tile(context, icon: Icons.delete_forever_outlined, title: 'Eliminar mi cuenta', color: Brand.bad, onTap: () => _deleteAccount(context)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
