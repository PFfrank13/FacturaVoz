import 'package:flutter/material.dart';

/// A two-ink, 24-unit icon family for the retail workspace.
class RetailIcon extends StatelessWidget {
  const RetailIcon(
    this.icon, {
    super.key,
    required this.ink,
    required this.accent,
    this.size = 24,
  });

  final IconData icon;
  final Color ink, accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final symbol = switch (icon) {
      Icons.trending_up_rounded || Icons.analytics_rounded => _Symbol.chart,
      Icons.inventory_2_rounded ||
      Icons.inventory_2_outlined => _Symbol.inventory,
      Icons.menu_book_rounded => _Symbol.ledger,
      Icons.receipt_long_rounded ||
      Icons.receipt_long_outlined => _Symbol.receipt,
      Icons.point_of_sale_rounded ||
      Icons.point_of_sale_outlined => _Symbol.register,
      Icons.account_balance_wallet_rounded ||
      Icons.account_balance_wallet_outlined => _Symbol.wallet,
      Icons.storefront_outlined || Icons.storefront_rounded => _Symbol.store,
      Icons.local_shipping_rounded => _Symbol.delivery,
      Icons.home_outlined || Icons.home_rounded => _Symbol.home,
      _ => null,
    };
    if (symbol == null) return Icon(icon, size: size, color: ink);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _IconPainter(symbol, ink, accent)),
      ),
    );
  }
}

enum _Symbol {
  chart,
  inventory,
  ledger,
  receipt,
  register,
  wallet,
  store,
  delivery,
  home,
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.symbol, this.ink, this.accent);
  final _Symbol symbol;
  final Color ink, accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = accent;
    void stroke(Path path) => canvas.drawPath(path, line);
    void face(Path path) {
      canvas.drawPath(path, fill);
      stroke(path);
    }

    RRect rect(
      double left,
      double top,
      double right,
      double bottom,
      double radius,
    ) => RRect.fromLTRBR(left, top, right, bottom, Radius.circular(radius));
    void segment(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), line);

    switch (symbol) {
      case _Symbol.home:
        face(
          Path()
            ..moveTo(3, 10)
            ..lineTo(12, 3)
            ..lineTo(21, 10)
            ..lineTo(19, 10)
            ..lineTo(19, 20)
            ..lineTo(14, 20)
            ..lineTo(14, 14)
            ..lineTo(10, 14)
            ..lineTo(10, 20)
            ..lineTo(5, 20)
            ..lineTo(5, 10)
            ..close(),
        );
      case _Symbol.chart:
        canvas.drawRRect(rect(4, 13, 7, 20, 1), fill);
        canvas.drawRRect(rect(10, 10, 13, 20, 1), fill);
        canvas.drawRRect(rect(16, 7, 19, 20, 1), fill);
        stroke(
          Path()
            ..moveTo(3, 11)
            ..lineTo(9, 6)
            ..lineTo(13, 8)
            ..lineTo(20, 3)
            ..moveTo(16, 3)
            ..lineTo(20, 3)
            ..lineTo(20, 7),
        );
      case _Symbol.inventory:
        face(
          Path()
            ..moveTo(3, 8)
            ..lineTo(12, 3)
            ..lineTo(21, 8)
            ..lineTo(12, 13)
            ..close(),
        );
        stroke(
          Path()
            ..moveTo(3, 8)
            ..lineTo(3, 16.5)
            ..lineTo(12, 21)
            ..lineTo(21, 16.5)
            ..lineTo(21, 8)
            ..moveTo(12, 13)
            ..lineTo(12, 21),
        );
        segment(7.5, 5.5, 16.5, 10.5);
      case _Symbol.ledger:
        final cover = Path()
          ..moveTo(4, 4)
          ..lineTo(16, 4)
          ..quadraticBezierTo(18, 4, 18, 6)
          ..lineTo(18, 19)
          ..lineTo(6, 19)
          ..quadraticBezierTo(4, 19, 4, 17)
          ..close();
        face(cover);
        stroke(
          Path()
            ..moveTo(20.5, 7)
            ..lineTo(20.5, 21)
            ..lineTo(7, 21),
        );
        segment(7.5, 4, 7.5, 18);
        segment(10.5, 8, 14.5, 8);
      case _Symbol.receipt:
        face(
          Path()
            ..moveTo(5, 3)
            ..lineTo(19, 3)
            ..lineTo(19, 21)
            ..lineTo(15.5, 18.5)
            ..lineTo(12, 21)
            ..lineTo(8.5, 18.5)
            ..lineTo(5, 21)
            ..close(),
        );
        segment(8.5, 8, 15.5, 8);
        segment(8.5, 12, 13, 12);
      case _Symbol.register:
        canvas.drawRRect(rect(5, 3, 17, 11, 1.8), fill);
        canvas.drawRRect(rect(5, 3, 17, 11, 1.8), line);
        segment(11, 11, 11, 14);
        stroke(
          Path()
            ..moveTo(4, 14)
            ..lineTo(18, 14)
            ..lineTo(21, 18)
            ..lineTo(21, 21)
            ..lineTo(3, 21)
            ..lineTo(3, 17)
            ..close(),
        );
        segment(15, 17.5, 17.5, 17.5);
      case _Symbol.wallet:
        stroke(
          Path()
            ..moveTo(3, 8)
            ..lineTo(15, 3)
            ..quadraticBezierTo(17, 2.5, 17, 5)
            ..lineTo(17, 7),
        );
        canvas.drawRRect(rect(3, 7, 21, 20, 2.6), fill);
        canvas.drawRRect(rect(3, 7, 21, 20, 2.6), line);
        stroke(
          Path()
            ..moveTo(21, 11)
            ..lineTo(17, 11)
            ..quadraticBezierTo(14, 13, 17, 15)
            ..lineTo(21, 15),
        );
      case _Symbol.store:
        stroke(
          Path()
            ..moveTo(5, 11)
            ..lineTo(5, 20)
            ..lineTo(19, 20)
            ..lineTo(19, 11)
            ..moveTo(10, 20)
            ..lineTo(10, 15)
            ..lineTo(14, 15)
            ..lineTo(14, 20),
        );
        face(
          Path()
            ..moveTo(5, 4)
            ..lineTo(19, 4)
            ..lineTo(21, 10)
            ..quadraticBezierTo(19, 14, 16, 10)
            ..quadraticBezierTo(12, 14, 8, 10)
            ..quadraticBezierTo(5, 14, 3, 10)
            ..close(),
        );
      case _Symbol.delivery:
        canvas.drawRRect(rect(2.5, 5, 14, 17, 1.5), fill);
        canvas.drawRRect(rect(2.5, 5, 14, 17, 1.5), line);
        stroke(
          Path()
            ..moveTo(14, 8)
            ..lineTo(18, 8)
            ..lineTo(21.5, 12)
            ..lineTo(21.5, 17)
            ..lineTo(14, 17),
        );
        segment(15, 12, 21, 12);
        canvas.drawCircle(const Offset(6.7, 18.4), 2, line);
        canvas.drawCircle(const Offset(17.7, 18.4), 2, line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      symbol != old.symbol || ink != old.ink || accent != old.accent;
}
