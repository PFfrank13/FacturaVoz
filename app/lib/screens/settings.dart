import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/repo.dart';
import 'fiscal_setup.dart';
import 'legal.dart';
import 'profile_form.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
    ctrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        child: ListView(children: [
          ListTile(leading: const Icon(Icons.person_outline), title: Text(email), subtitle: const Text('Sesión iniciada')),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: const Text('Datos del negocio'),
            subtitle: const Text('Nombre, documento, moneda e impuesto'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileFormScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Facturación electrónica (SUNAT)'),
            subtitle: const Text('RUC, usuario SOL y certificado digital'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FiscalSetupScreen())),
          ),
          if (Config.privacyUrl.isNotEmpty)
            ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Política de privacidad'), onTap: openPrivacyPolicy),
          ListTile(leading: const Icon(Icons.logout), title: const Text('Cerrar sesión'), onTap: () => _signOut(context)),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('Eliminar mi cuenta', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => _deleteAccount(context),
          ),
        ]),
      ),
    );
  }
}
