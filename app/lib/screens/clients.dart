import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../ui/widgets.dart';

/// Clientes de la empresa activa: buscar y corregir nombre, documento, correo y dirección.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<ClientCard>? _all;
  String? _error;
  String _q = '';

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Repo.listClients();
      if (mounted) setState(() => _all = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  Future<void> _edit(ClientCard c) async {
    final name = TextEditingController(text: c.name);
    final tax = TextEditingController(text: c.taxId);
    final mail = TextEditingController(text: c.email);
    final addr = TextEditingController(text: c.address);
    String err = '';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Editar cliente', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('Los cambios valen para facturas nuevas. Los comprobantes ya emitidos a SUNAT no se modifican.', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(controller: name, maxLength: 120, decoration: const InputDecoration(labelText: 'Nombre o razón social', counterText: '')),
              const SizedBox(height: 10),
              TextField(
                controller: tax,
                maxLength: 30,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\-]'))],
                decoration: const InputDecoration(labelText: 'DNI o RUC', counterText: ''),
              ),
              const SizedBox(height: 10),
              TextField(controller: mail, maxLength: 120, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo', counterText: '')),
              const SizedBox(height: 10),
              TextField(controller: addr, maxLength: 200, decoration: const InputDecoration(labelText: 'Dirección', counterText: '')),
              if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: const TextStyle(color: Color(0xFFD94A5E)))),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Guardar',
                icon: Icons.check_rounded,
                onPressed: () {
                  if (name.text.trim().isEmpty) {
                    setS(() => err = 'El nombre es obligatorio');
                  } else if (mail.text.trim().isNotEmpty && !_emailRe.hasMatch(mail.text.trim())) {
                    setS(() => err = 'Ese correo no parece válido');
                  } else {
                    Navigator.pop(ctx, true);
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
    final values = (name.text, tax.text, mail.text, addr.text);
    for (final x in [name, tax, mail, addr]) {
      x.dispose();
    }
    if (saved != true) return;
    try {
      await Repo.updateClient(c, name: values.$1, taxId: values.$2, email: values.$3, address: values.$4);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente actualizado')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar. ${friendly(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final all = _all;
    final q = _q.trim().toLowerCase();
    final list = (all ?? const <ClientCard>[])
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.taxId.contains(q) || c.email.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Buscar por nombre, documento o correo', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              SoftCard(
                child: Column(children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
                ]),
              )
            else if (all == null)
              const SkeletonList()
            else if (all.isEmpty)
              const EmptyState(title: 'Aún no tienes clientes', body: 'Se guardan solos cuando creas tu primera factura.')
            else if (list.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 40), child: Text('Nada coincide con tu búsqueda.', textAlign: TextAlign.center, style: t.textTheme.bodyMedium))
            else
              for (final (i, c) in list.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Reveal(
                    key: ValueKey(c.ids.first),
                    index: i < 8 ? i : 8,
                    child: Pressable(
                      onTap: () => _edit(c),
                      child: SoftCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          CircleAvatar(
                            backgroundColor: t.colorScheme.primary.withValues(alpha: .12),
                            child: Text(c.name.characters.first.toUpperCase(), style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                [if (c.taxId.isNotEmpty) c.taxId, if (c.email.isNotEmpty) c.email].join('  ·  ').ifEmpty('Sin documento ni correo'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.bodySmall,
                              ),
                            ]),
                          ),
                          Icon(Icons.edit_outlined, size: 18, color: t.colorScheme.onSurfaceVariant),
                        ]),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
