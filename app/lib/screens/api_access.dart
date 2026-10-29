// API pública + webhooks (Fase 8 · módulo 20). Para conectar tu web, tu ERP o Zapier/Make.
// La clave se muestra UNA sola vez (en la base de datos solo queda su huella SHA-256). Los webhooks van firmados (HMAC).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models_v2.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'client_profile.dart' show shortDateTime;
import 'team.dart' show dbMessage;

const apiScopes = {
  'invoices:read': 'Leer comprobantes',
  'clients:read': 'Leer clientes',
  'products:read': 'Leer productos',
  'orders:write': 'Crear pedidos',
};
const webhookEvents = {
  'invoice.created': 'Comprobante creado',
  'invoice.updated': 'Comprobante actualizado',
  'invoice.paid': 'Comprobante pagado',
  'payment.created': 'Cobro registrado',
  'order.created': 'Pedido nuevo (tienda o API)',
};

class ApiAccessScreen extends StatefulWidget {
  const ApiAccessScreen({super.key});

  @override
  State<ApiAccessScreen> createState() => _ApiAccessScreenState();
}

class _ApiAccessScreenState extends State<ApiAccessScreen> {
  List<ApiKeyRow>? _keys;
  List<WebhookRow> _hooks = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final k = await V2Repo.apiKeys();
      final h = await V2Repo.webhooks();
      if (mounted) {
        setState(() {
          _keys = k;
          _hooks = h;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _newKey() async {
    final name = TextEditingController(text: 'Mi web');
    final scopes = {'invoices:read', 'clients:read', 'orders:write'};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nueva clave de API'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre (para reconocerla)')),
              for (final e in apiScopes.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: scopes.contains(e.key),
                  onChanged: (v) => set(() => v == true ? scopes.add(e.key) : scopes.remove(e.key)),
                  title: Text(e.value),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
          ],
        ),
      ),
    );
    final n = name.text;
    disposeAfterClose([name]);
    if (ok != true || scopes.isEmpty) return;
    try {
      final key = await V2Repo.createApiKey(n, scopes.toList());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Copia tu clave ahora'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Por seguridad no la volveremos a mostrar. Guárdala en un lugar seguro (nunca en el código de una página pública).'),
            const SizedBox(height: 12),
            SelectableText(key, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: key));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Copiar y cerrar'),
            ),
          ],
        ),
      );
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dbMessage(e))));
    }
  }

  Future<void> _newHook() async {
    final url = TextEditingController(text: 'https://');
    final events = {...webhookEvents.keys};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nuevo webhook'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL (https)')),
              for (final e in webhookEvents.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: events.contains(e.key),
                  onChanged: (v) => set(() => v == true ? events.add(e.key) : events.remove(e.key)),
                  title: Text(e.value),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    final u = url.text.trim();
    disposeAfterClose([url]);
    if (ok != true) return;
    if (!RegExp(r'^https://[^\s/]+\.[^\s]+$').hasMatch(u)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La URL debe empezar con https:// y ser pública.')));
      return;
    }
    try {
      await V2Repo.addWebhook(u, events.toList());
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dbMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final base = '${Config.apiBase}/api/v1';
    return Scaffold(
      appBar: AppBar(title: const Text('API y webhooks')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _keys == null
              ? const SkeletonList()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                  SoftCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Para programadores', style: t.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      SelectableText('GET  $base/invoices\nGET  $base/clients\nGET  $base/products\nPOST $base/orders\n\nCabecera: Authorization: Bearer <tu clave>',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      const SizedBox(height: 6),
                      Text('Límite: 120 llamadas por minuto por clave. Si tu plan se vence, la API responde 402.', style: t.textTheme.bodySmall),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  SectionTitle('Claves', action: 'Nueva', onAction: _newKey),
                  if (_keys!.isEmpty) Text('Sin claves.', style: t.textTheme.bodySmall),
                  for (final k in _keys!)
                    ListTile(
                      leading: Icon(Icons.key_rounded, color: k.revokedAt == null ? Brand.ok : t.colorScheme.onSurfaceVariant),
                      title: Text('${k.name} · ${k.prefix}…'),
                      subtitle: Text([
                        k.scopes.map((s) => apiScopes[s] ?? s).join(', '),
                        if (k.lastUsedAt != null) 'usada ${shortDateTime(k.lastUsedAt!)}',
                        if (k.revokedAt != null) 'REVOCADA',
                      ].join(' · ')),
                      trailing: k.revokedAt != null
                          ? null
                          : TextButton(
                              onPressed: () async {
                                await V2Repo.revokeApiKey(k.id).catchError((_) {});
                                _load();
                              },
                              child: const Text('Revocar'),
                            ),
                    ),
                  const SizedBox(height: 14),
                  SectionTitle('Webhooks', action: 'Nuevo', onAction: _newHook),
                  if (_hooks.isEmpty) Text('Avisamos a tu sistema cuando pasa algo (firmado: cabecera FacturaVoz-Signature = v1=HMAC-SHA256(secreto, timestamp + "." + cuerpo)).', style: t.textTheme.bodySmall),
                  for (final h in _hooks)
                    Card(
                      child: Column(children: [
                        SwitchListTile(
                          value: h.active,
                          onChanged: (v) async {
                            await V2Repo.setWebhookActive(h.id, v).catchError((_) {});
                            _load();
                          },
                          title: Text(h.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${h.events.map((e) => webhookEvents[e] ?? e).join(', ')}${h.lastStatus != null ? '\nÚltima respuesta: ${h.lastStatus}' : ''}'),
                        ),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: h.secret));
                              if (context.mounted) showSuccess(context, 'Secreto copiado');
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copiar secreto'),
                          ),
                          TextButton(
                            onPressed: () async {
                              await V2Repo.deleteWebhook(h.id).catchError((_) {});
                              _load();
                            },
                            child: const Text('Eliminar', style: TextStyle(color: Brand.bad)),
                          ),
                        ]),
                      ]),
                    ),
                ]),
    );
  }
}
