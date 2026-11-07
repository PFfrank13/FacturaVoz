import 'package:flutter/material.dart';

abstract final class RetailIdentity {
  static const platform = 'Solvex Retail';
  static const pos = 'Solvex Retail POS';
  static const control = 'Solvex Retail Control';
  static const maker = 'Solvex Software Labs';
}

/// Original vector mark: two opposing shelves form an S inside a retail tile.
class RetailMark extends StatelessWidget {
  const RetailMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(label: RetailIdentity.platform,
    image: true, child: CustomPaint(size: Size.square(size), painter: const _MarkPainter()));
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 64, 64), const Radius.circular(16)), Paint()..color = const Color(0xFF102F32));
    final upper = Path()..moveTo(16, 15)..lineTo(48, 15)..lineTo(48, 24)..lineTo(25, 24)..lineTo(25, 29)..lineTo(16, 29)..close();
    final lower = Path()..moveTo(16, 35)..lineTo(39, 35)..lineTo(39, 30)..lineTo(48, 30)..lineTo(48, 49)..lineTo(16, 49)..lineTo(16, 40)..lineTo(39, 40)..lineTo(39, 44)..lineTo(16, 44)..close();
    canvas.drawPath(upper, Paint()..color = const Color(0xFFC9F27A));
    canvas.drawPath(lower, Paint()..color = Colors.white);
  }
  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => false;
}

class RetailWordmark extends StatelessWidget {
  const RetailWordmark({super.key, this.caption = 'POS / OPERACIÓN DE TIENDA'});
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
