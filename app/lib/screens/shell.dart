import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import 'assistant.dart';
import 'collections.dart';
import 'home.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';
import 'profit.dart';
import 'quotes.dart';

/// Estructura principal: 4 pestañas + micrófono central en un dock de cristal flotante.
/// Toque en el micrófono = nueva factura por voz. Mantener presionado = Copiloto de IA.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  final Set<int> _built = {0};

  void _go(int i) {
    if (i == _tab) return;
    Haptics.select();
    setState(() {
      _tab = i;
      _built.add(i);
    });
  }

  Future<void> _newInvoice() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewInvoiceScreen()));
    AppState.instance.bump();
    if (id != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
      AppState.instance.bump();
    }
  }

  Widget _page(int i) => switch (i) {
        0 => HomeScreen(embedded: true, onNavigate: _go),
        1 => const QuotesScreen(embedded: true),
        2 => const CollectionsScreen(embedded: true),
        _ => const ProfitScreen(embedded: true),
      };

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0); // "atrás" vuelve a Inicio antes de salir
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(children: [
          for (var i = 0; i < 4; i++)
            if (_built.contains(i))
              // Clave estable: al construir otra pestaña no se pierde el estado de las demás.
              _TabSlot(key: ValueKey('tab-$i'), active: i == _tab, child: _page(i)),
        ]),
        bottomNavigationBar: AnimatedSlide(
          offset: keyboard ? const Offset(0, 1.4) : Offset.zero,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: _Dock(
            index: _tab,
            onTap: _go,
            onMic: _newInvoice,
            onMicLong: () => openCopilot(context),
          ),
        ),
      ),
    );
  }
}

/// Contenedor de una pestaña del shell.
///
/// IMPORTANTE: el fundido (AnimatedOpacity/AnimatedScale) va FUERA de TickerMode. Si TickerMode(enabled: false)
/// envuelve la animación de salida, su ticker queda silenciado y la pestaña que se oculta se queda pintada
/// encima (opacidad 1) mientras los toques van a la de abajo: la app "se congela".
/// Al terminar de ocultarse pasa a Offstage: no se pinta ni recibe toques, pero conserva su estado.
class _TabSlot extends StatefulWidget {
  const _TabSlot({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_TabSlot> createState() => _TabSlotState();
}

class _TabSlotState extends State<_TabSlot> {
  late bool _offstage = !widget.active;

  @override
  void didUpdateWidget(covariant _TabSlot old) {
    super.didUpdateWidget(old);
    if (widget.active) {
      _offstage = false; // vuelve a pintarse y entra con el fundido
    } else if (old.active && reduceMotion(context)) {
      _offstage = true; // sin animaciones no hay onEnd que esperar
    }
  }

  void _onFadeEnd() {
    if (mounted && !widget.active && !_offstage) setState(() => _offstage = true);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final active = widget.active;
    return Offstage(
      offstage: _offstage,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: Duration(milliseconds: reduce ? 0 : 220),
        curve: Curves.easeOutCubic,
        onEnd: _onFadeEnd,
        child: AnimatedScale(
          scale: active ? 1 : 0.985,
          duration: Duration(milliseconds: reduce ? 0 : 280),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !active,
            // Solo las animaciones internas de la pestaña oculta se pausan (ahorra batería y CPU).
            child: TickerMode(enabled: active, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.index, required this.onTap, required this.onMic, required this.onMicLong});
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onMic;
  final VoidCallback onMicLong;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 10 + bottom),
      child: SizedBox(
        height: 84,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                height: 68,
                decoration: BoxDecoration(
                  color: (dark ? Brand.darkCard : Colors.white).withValues(alpha: dark ? 0.78 : 0.82),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: (dark ? Colors.white : Brand.indigo).withValues(alpha: 0.08)),
                  boxShadow: Brand.softShadow(dark, a: 0.16),
                ),
                child: Row(children: [
                  _item(context, 0, Icons.receipt_long_rounded, 'Inicio'),
                  _item(context, 1, Icons.request_quote_rounded, 'Cotizar'),
                  const SizedBox(width: 76),
                  _item(context, 2, Icons.account_balance_wallet_rounded, 'Cobrar'),
                  _item(context, 3, Icons.insights_rounded, 'Negocio'),
                ]),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Semantics(
              button: true,
              label: 'Dictar factura. Mantén presionado para el copiloto.',
              child: GestureDetector(
                onLongPress: () {
                  Haptics.heavy();
                  onMicLong();
                },
                child: DictateMini(onPressed: onMic),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, int i, IconData icon, String label) {
    final t = Theme.of(context);
    final on = i == index;
    final c = on ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        selected: on,
        button: true,
        label: label,
        child: InkResponse(
          onTap: () => onTap(i),
          radius: 36,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(horizontal: on ? 16 : 10, vertical: 5),
              decoration: BoxDecoration(color: on ? t.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent, borderRadius: BorderRadius.circular(99)),
              child: AnimatedScale(scale: on ? 1.08 : 1, duration: const Duration(milliseconds: 280), curve: Curves.easeOutBack, child: Icon(icon, size: 23, color: c)),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: c),
              child: Text(label),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Botón de micrófono del dock (más pequeño que el de la pantalla de dictado, con halo suave).
class DictateMini extends StatefulWidget {
  const DictateMini({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<DictateMini> createState() => _DictateMiniState();
}

class _DictateMiniState extends State<DictateMini> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        Haptics.soft();
        widget.onPressed();
      },
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: Duration(milliseconds: _down ? 100 : 420),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: Brand.coralGradient,
            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
            boxShadow: [BoxShadow(color: Brand.goldDeep.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
