import 'package:flutter/material.dart';

String posMethodLabel(String method) => switch (method) {
  'efectivo' => 'Efectivo',
  'yape' => 'Yape',
  'plin' => 'Plin',
  'tarjeta' => 'Tarjeta',
  'transferencia' => 'Transferencia',
  _ => method,
};

/// Marcas locales que se muestran al elegir, verificar y registrar un cobro.
class PosPaymentBrand extends StatelessWidget {
  const PosPaymentBrand(this.method, {super.key, this.size = 53});

  final String method;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = method == 'transferencia'
        ? scheme.secondary
        : scheme.primary;
    final radius = BorderRadius.circular(size * .22);
    final mark = switch (method) {
      'yape' => ClipRRect(
        borderRadius: radius,
        child: Image.asset('assets/payments/yape.png', fit: BoxFit.contain),
      ),
      'plin' => Image.asset('assets/payments/plin.png', fit: BoxFit.contain),
      'tarjeta' => const CustomPaint(painter: _BankCardPainter()),
      _ => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: Color.alphaBlend(
            accent.withValues(alpha: .11),
            scheme.surface,
          ),
        ),
        child: Icon(
          switch (method) {
            'efectivo' => Icons.payments_outlined,
            'transferencia' => Icons.account_balance_outlined,
            _ => Icons.credit_card_outlined,
          },
          color: accent,
          size: size * .57,
        ),
      ),
    };
    return Semantics(
      image: true,
      label: posMethodLabel(method),
      excludeSemantics: true,
      child: SizedBox.square(dimension: size, child: mark),
    );
  }
}

/// Tarjeta bancaria genérica, en proporción física, sin emisor ni red específica.
class _BankCardPainter extends CustomPainter {
  const _BankCardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 56, size.height / 56);
    const face = Rect.fromLTWH(1, 10, 54, 35);
    final outline = RRect.fromRectAndRadius(face, const Radius.circular(6));
    final ink = Paint();
    canvas.drawRRect(
      outline,
      ink
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF475D85), Color(0xFF263755), Color(0xFF192542)],
        ).createShader(face),
    );
    ink.shader = null;
    canvas.drawRRect(
      outline.deflate(.45),
      ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..color = const Color(0xFF8496B1),
    );
    ink.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(7, 19, 12, 9),
        const Radius.circular(2),
      ),
      ink..color = const Color(0xFFF3CD88),
    );
    final chip = Path()
      ..moveTo(7, 23.5)
      ..lineTo(10.5, 23.5)
      ..lineTo(12, 21.5)
      ..lineTo(12, 19)
      ..moveTo(12, 28)
      ..lineTo(12, 25.5)
      ..lineTo(10.5, 23.5)
      ..moveTo(19, 23.5)
      ..lineTo(15.5, 23.5);
    canvas.drawPath(
      chip,
      ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..color = const Color(0xFF8B643B),
    );
    ink
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.25
      ..color = const Color(0xFFE5EDF5);
    for (final radius in [4.0, 7.0, 10.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(40, 22), radius: radius),
        -.62,
        1.24,
        false,
        ink,
      );
    }
    ink.style = PaintingStyle.fill;
    for (var group = 0; group < 4; group++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(7.0 + group * 11, 35, 7.5, 2),
          const Radius.circular(1),
        ),
        ink,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BankCardPainter oldDelegate) => false;
}
