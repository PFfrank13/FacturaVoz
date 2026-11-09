import 'package:flutter/material.dart';

/// Shared presentation for the existing retail workflows.
/// This file does not create routes, transactions, or synthetic business data.
abstract final class RetailVisual {
  static const navy = Color(0xFF0D1231);
  static const surface = Color(0xFF1B2149);
  static const violet = Color(0xFF945EFB);
  static const mint = Color(0xFF48E6C6);

  static Widget hero({
    required BuildContext context,
    required String eyebrow,
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? footer,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF552BBA), Color(0xFF30266A), Color(0xFF142D60)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF8265C8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF633CE0).withValues(alpha: .18),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Stack(children: [
        const Positioned(
          right: -38, top: -60,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(
                color: Color(0x557CA6FF), width: 22)),
            ),
            child: SizedBox(width: 170, height: 170),
          ),
        ),
        const Positioned(
          right: 48, bottom: -38,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x183CF4D7),
            ),
            child: SizedBox(width: 106, height: 106),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .25)),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const Spacer(),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(eyebrow.toUpperCase(), style: const TextStyle(
                    color: Color(0xFFE8DDFF), fontSize: 10,
                    fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                ),
              ),
            ]),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(
              color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900,
              height: 1.12, letterSpacing: -.35)),
            const SizedBox(height: 7),
            Text(subtitle, style: const TextStyle(
              color: Color(0xFFE5E0F8), fontSize: 12.5, height: 1.4)),
            if (footer != null) ...[
              const SizedBox(height: 17),
              const Divider(color: Color(0x665F6EBA), height: 1),
              const SizedBox(height: 13),
              footer,
            ],
          ]),
        ),
      ]),
    );
  }

  static Widget section({
    required int number,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8956EF), Color(0xFF4F45AF)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('$number', style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11.5, height: 1.3,
            color: Color(0xFFABADD0))),
        ])),
        const SizedBox(width: 7),
        Icon(icon, color: const Color(0xFFAA85F5), size: 22),
      ]),
    );
  }

  static Widget panel(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(15),
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark ? const Color(0xFF4B4C80) : const Color(0xFFE5DCF4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .10 : .04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Compact step tracker for the physical-store sale, no fake completion state.
  static Widget journey({required int step, required String label}) {
    assert(step >= 1 && step <= 4);
    return Semantics(
      label: 'Paso $step de 4: $label',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 1; i <= 4; i++)
            Expanded(child: Padding(
              padding: EdgeInsets.only(right: i == 4 ? 0 : 5),
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: i <= step ? violet : const Color(0xFF42466D),
                  borderRadius: BorderRadius.circular(8)),
              ),
            )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('PASO $step DE 4', style: const TextStyle(
            color: Color(0xFFCDBBFD), fontSize: 10, fontWeight: FontWeight.w900,
            letterSpacing: .9)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, textAlign: TextAlign.end,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFC2C1D9),
              fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
      ]),
    );
  }

  static Widget microStat(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(
        fontSize: 10, letterSpacing: .8, fontWeight: FontWeight.w800,
        color: Color(0xFFBAB5E3))),
      const SizedBox(height: 4),
      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
    ]);
  }
}
