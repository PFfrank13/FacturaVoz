# Dynamic Notification Island

Isla de notificaciones **dentro de Flutter** para FacturaVoz. No es la API nativa de Live Activities / Dynamic Island de iOS ni una notificación del sistema: es una superficie de la propia aplicación que se integra visualmente con la franja superior del teléfono.

La idea original de una gota con cuello elástico procede de [rit3zh/expo-dynamic-notifications](https://github.com/rit3zh/expo-dynamic-notifications/tree/5de059a5cbefbe28c14efbe785166665a7c70bc5) (revisión `5de059a5`); su licencia acompaña al paquete en [LICENSE](LICENSE). La geometría, los muelles y la composición actuales son propios.

## Ubicación

- `IslandPlacement.statusBar`: la píldora vive en la franja de la hora y la batería, centrada. `statusBarIslandGeometry(MediaQuery.of(context))` calcula su sitio:
  - iPhone con Dynamic Island (franja ≥ 51 pt): en reposo mide exactamente lo mismo que la isla física de los iPhone 15–17 Pro y Pro Max, 126 × 37 pt a 11 pt del borde, negra y sin contenido.
  - Notch o cámara perforada de Android: mismas proporciones, con la altura ajustada a la franja (26–37 pt).
  - Sin franja (web, escritorio, horizontal): devuelve `null` y la isla va en la barra de la app (`IslandPlacement.toolbar`).
- Mientras hay un aviso pendiente, la píldora se ensancha 32 pt por lado para mostrar el icono y la onda fuera de la cámara, como una Live Activity de iOS.
- La píldora es negra pura para fundirse con la cámara.

## Movimiento

- Al anunciarse un aviso, la tarjeta brota de la píldora: primero cae como una gota unida por un cuello líquido, luego se ensancha con un muelle con ligero rebote (rigidez 250, amortiguamiento 0,72) y se asienta en unos 450 ms. Al cerrarse vuelve con un muelle críticamente amortiguado.
- La tarjeta queda **debajo** de la franja de estado: la hora, la señal y la batería, que el sistema siempre dibuja encima, siguen legibles.
- El contenido aparece cuando la tarjeta ya tiene casi todo su ancho, así el texto nunca se ve recortado ni se reacomoda.
- Deslizar hacia arriba comprime la tarjeta siguiendo el dedo y la velocidad al soltar pasa al muelle. Hacia abajo ofrece resistencia elástica.
- Con «reducir movimiento» los cambios son instantáneos. Los lectores de pantalla tienen tiempo ilimitado y un botón para cerrar.

## Uso

`notice` contiene el aviso autorizado vigente (título, mensaje, color, icono, categoría y texto de acción). Un cambio de `announcement` lo anuncia. Tocar la píldora vuelve a mostrarlo, tocar la tarjeta abre su destino.
