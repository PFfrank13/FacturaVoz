// Ámbito de datos (orden de producción §9). Cambia cada vez que cambia la empresa activa, la sesión o el usuario.
// Una consulta guarda el ámbito con el que empezó y SOLO aplica su resultado si el ámbito sigue siendo el mismo:
// Empresa A carga lento → cambias a B → la respuesta de A llega → se descarta (nunca se muestra A con B activa).
import 'package:flutter/foundation.dart';

/// Se incrementa en AppState.switchOrg() y AppState.clear() (cierre de sesión).
final dataScope = ValueNotifier<int>(0);

/// Marca de una consulta: ámbito global + empresa + usuario con los que empezó.
class ScopeTicket {
  ScopeTicket(this.scope, this.org, this.user);
  final int scope;
  final String? org;
  final String? user;

  bool matches(int scopeNow, String? orgNow, String? userNow) => scope == scopeNow && org == orgNow && user == userNow;
}
