import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../errors.dart';
import '../services/api.dart';

/// Alta de la empresa en el servicio de facturación: RUC (del perfil), usuario SOL secundario y certificado digital.
/// Los secretos se envían por HTTPS a tu servidor de facturación y NO se guardan en esta app ni en la base de datos.
class FiscalSetupScreen extends StatefulWidget {
  const FiscalSetupScreen({super.key});

  @override
  State<FiscalSetupScreen> createState() => _FiscalSetupScreenState();
}

class _FiscalSetupScreenState extends State<FiscalSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _solUser = TextEditingController();
  final _solPass = TextEditingController();
  final _certPass = TextEditingController();
  String _env = 'beta';
  String? _certName;
  List<int>? _certBytes;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _solUser.dispose();
    _solPass.dispose();
    _certPass.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pfx', 'p12', 'pem'],
      withData: true,
    );
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.bytes!.length > 100000) {
      setState(() => _error = 'El archivo es demasiado grande para ser un certificado.');
      return;
    }
    setState(() {
      _certName = f.name;
      _certBytes = f.bytes!.toList();
      _error = '';
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_certBytes == null) {
      setState(() => _error = 'Selecciona tu certificado digital.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final isPem = _certName!.toLowerCase().endsWith('.pem');
      await FiscalApi.setup(
        solUser: _solUser.text.trim(),
        solPassword: _solPass.text,
        certificate: Uint8List.fromList(_certBytes!),
        certificateFormat: isPem ? 'pem' : 'pfx',
        certificatePassword: _certPass.text,
        env: _env,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Facturación electrónica configurada.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppState.instance.profile!;
    final rucOk = RegExp(r'^\d{11}$').hasMatch(p.taxId.trim());
    return Scaffold(
      appBar: AppBar(title: const Text('Facturación electrónica')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(rucOk ? 'RUC ${p.taxId.trim()}' : 'Falta el RUC'),
                subtitle: Text(rucOk ? p.businessName : 'Escríbelo en Ajustes → Datos del negocio → Documento fiscal.'),
              ),
              if (!p.isFiscalReady)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Completa también ubigeo, departamento, provincia, distrito y dirección en «Datos del negocio».'),
                ),
              DropdownButtonFormField<String>(
                initialValue: _env,
                decoration: const InputDecoration(labelText: 'Entorno'),
                items: const [
                  DropdownMenuItem(value: 'beta', child: Text('Pruebas (SUNAT beta, sin validez)')),
                  DropdownMenuItem(value: 'prod', child: Text('Producción (comprobantes reales)')),
                ],
                onChanged: (v) => setState(() => _env = v ?? 'beta'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _solUser,
                maxLength: 30,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Usuario SOL secundario', helperText: 'Solo el usuario, sin el RUC'),
                validator: (v) => RegExp(r'^[A-Za-z0-9ñÑ_.-]+$').hasMatch((v ?? '').trim()) ? null : 'Usuario no válido',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _solPass,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Clave del usuario SOL secundario'),
                validator: (v) => (v ?? '').isEmpty ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.upload_file),
                label: Text(_certName ?? 'Seleccionar certificado digital (.pfx / .p12)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _certPass,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Contraseña del certificado'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Usa un usuario SOL secundario con permiso de emisión electrónica, nunca tu clave SOL principal. '
                'Estos datos se envían cifrados a tu servidor de facturación y no se guardan en la app.',
                style: TextStyle(fontSize: 12),
              ),
              if (_error.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 16),
              FilledButton(onPressed: (_busy || !rucOk || !p.isFiscalReady) ? null : _save, child: Text(_busy ? 'Registrando…' : 'Guardar y conectar')),
            ],
          ),
        ),
      ),
    );
  }
}
