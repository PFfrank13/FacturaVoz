import 'package:flutter/material.dart';

/// Mantiene formularios y listados legibles en escritorio y pantallas ultrawide,
/// sin reducir el ancho disponible en teléfonos o tablets compactas.
///
/// El hijo conserva todo el alto y el comportamiento de scroll del contenedor.
/// No usa MediaQuery: respeta el ancho real disponible (drawer, split view, etc.).
class RetailResponsiveFrame extends StatelessWidget {
  const RetailResponsiveFrame({
    super.key,
    required this.child,
    this.maxWidth = 1120,
  }) : assert(maxWidth > 0);

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Usa dos columnas solo cuando el ancho realmente asignado permite dos
/// tarjetas completas; split view y ventanas estrechas siguen a una.
int retailCardColumnCount(double availableWidth, {double twoColumnMinWidth = 880}) =>
    availableWidth.isFinite && availableWidth >= twoColumnMinWidth ? 2 : 1;
