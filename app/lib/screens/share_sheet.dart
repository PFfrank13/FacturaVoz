import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/motion.dart';
import '../ui/theme.dart';

/// Hoja para compartir un enlace (cotización o cobro): WhatsApp, copiar o abrir.
/// Devuelve true si el usuario lo compartió o copió.
Future<bool> shareLinkSheet(BuildContext context, {required String title, required String subtitle, required String url, required String message}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final t = Theme.of(ctx);
      Widget opt(IconData icon, Color c, String label, String sub, Future<bool> Function() run) => ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(icon, color: c),
            ),
            title: Text(label, style: t.textTheme.titleSmall),
            subtitle: Text(sub, style: t.textTheme.bodySmall),
            onTap: () async {
              final ok = await run();
              if (ctx.mounted) Navigator.pop(ctx, ok);
            },
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text(title, style: t.textTheme.titleLarge)),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: Text(subtitle, style: t.textTheme.bodySmall)),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(Radii.md)),
              child: Row(children: [
                Icon(Icons.link_rounded, size: 18, color: t.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall)),
              ]),
            ),
            const SizedBox(height: 6),
            opt(Icons.chat_rounded, const Color(0xFF25D366), 'Enviar por WhatsApp', 'Elige el chat del cliente', () async {
              return launchUrl(Uri.https('wa.me', '/', {'text': '$message\n$url'}), mode: LaunchMode.externalApplication);
            }),
            opt(Icons.copy_rounded, Brand.indigo, 'Copiar enlace', 'Para pegarlo en cualquier app', () async {
              await Clipboard.setData(ClipboardData(text: url));
              Haptics.success();
              return true;
            }),
            opt(Icons.open_in_new_rounded, Brand.lilac, 'Ver como el cliente', 'Abre la página en el navegador', () async {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              return false;
            }),
          ]),
        ),
      );
    },
  );
  return r ?? false;
}
