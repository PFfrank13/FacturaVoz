import 'package:flutter/material.dart';

abstract final class RetailIdentity {
  static const platform = 'FacturaVoz';
  static const pos = 'FacturaVoz';
  static const control = 'FacturaVoz';
  static const maker = 'Solvex Software Labs';
}

/// Retain the original application asset and technical component API.
class RetailMark extends StatelessWidget {
  const RetailMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(label: RetailIdentity.platform,
    image: true, child: ClipRRect(borderRadius: BorderRadius.circular(size * .29),
      child: Image.asset('assets/branding/facturavoz_icon.png', width: size,
        height: size, fit: BoxFit.contain)));
}

class RetailWordmark extends StatelessWidget {
  const RetailWordmark({super.key, this.caption = 'VENTAS Y FACTURACIÓN'});
  final String caption;
  @override
  Widget build(BuildContext context) => Row(children: [
    const RetailMark(), const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(RetailIdentity.platform, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      Text(caption, style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.1)),
    ])),
  ]);
}
