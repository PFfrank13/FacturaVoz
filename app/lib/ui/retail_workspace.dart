import 'package:flutter/material.dart';

/// Contenido operacional centrado y legible en tablet, escritorio y ultrawide.
///
/// El ancho de telefonos pequeños permanece fluido. No modifica el scroll,
/// las acciones inferiores ni los permisos de cada pantalla.
class RetailWorkspace extends StatelessWidget {
  const RetailWorkspace({
    super.key,
    required this.child,
    this.maxWidth = 960,
  }) : assert(maxWidth > 0);

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
