// Atajos del ícono de la app (mantener presionado el ícono en Android/iPhone): Vender por voz, Buscar, Copiloto, Fiados.
// Es la alternativa SIN código nativo a los "widgets" de pantalla de inicio (ver HOJA_DE_RUTA.md).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:quick_actions/quick_actions.dart';

class QuickLaunch {
  QuickLaunch._();
  static final QuickLaunch instance = QuickLaunch._();

  final QuickActions _qa = const QuickActions();
  void Function(String type)? _handler;
  String? _pending;
  bool _ready = false;

  /// Se llama una vez cuando el shell ya está en pantalla.
  void bind(void Function(String type) handler) {
    _handler = handler;
    if (_pending != null) {
      final p = _pending!;
      _pending = null;
      handler(p);
    }
    if (_ready || kIsWeb) return;
    _ready = true;
    try {
      _qa.initialize((type) {
        final h = _handler;
        if (h == null) {
          _pending = type;
        } else {
          h(type);
        }
      });
      _qa.setShortcutItems(<ShortcutItem>[
        ShortcutItem(type: 'new_invoice', localizedTitle: 'Vender por voz'),
        ShortcutItem(type: 'search', localizedTitle: 'Buscar'),
        ShortcutItem(type: 'fiados', localizedTitle: 'Fiados'),
        ShortcutItem(type: 'copilot', localizedTitle: 'Copiloto'),
      ]);
    } catch (_) {
      // Plataformas sin soporte: simplemente no hay atajos.
    }
  }

  void unbind() => _handler = null;
}
