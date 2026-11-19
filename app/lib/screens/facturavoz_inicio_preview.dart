import 'package:flutter/material.dart';

import 'facturavoz_inicio_bodega.dart';

/// Vista de diseño: no abre sesión ni consulta servicios cloud.
/// No altera la aplicación principal (lib/main.dart).
void main() => runApp(const FacturaVozPreview());

class FacturaVozPreview extends StatefulWidget {
  const FacturaVozPreview({super.key});

  @override
  State<FacturaVozPreview> createState() => _FacturaVozPreviewState();
}

class _FacturaVozPreviewState extends State<FacturaVozPreview> {
  FacturaVozPlan _plan = FacturaVozPlan.basico;
  final _mensajes = GlobalKey<ScaffoldMessengerState>();
  final _navegacion = GlobalKey<NavigatorState>();

  void _aviso(String texto) {
    _mensajes.currentState?.showSnackBar(
      SnackBar(
        content: Text(texto),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _seleccionarPlan() {
    final context = _navegacion.currentContext;
    if (context == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A1C48),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Comparar el diseño por plan',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final p in FacturaVozPlan.values)
              ListTile(
                leading: Icon(
                  p == FacturaVozPlan.basico
                      ? Icons.store_rounded
                      : p == FacturaVozPlan.pro
                          ? Icons.shopping_basket_rounded
                          : Icons.warehouse_rounded,
                ),
                title: Text('${p.planNombre} · ${p.nombre}'),
                trailing: _plan == p ? const Icon(Icons.check_circle) : null,
                onTap: () {
                  setState(() => _plan = p);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
            const Text(
              'El selector es solo visual. No cambia licencias ni datos reales.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Color(0xFFB6B6DD)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _destino(IconData icono, String texto, VoidCallback onTap,
      {bool seleccionado = false}) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icono,
                  size: 21,
                  color: seleccionado
                      ? const Color(0xFFE3D5FF)
                      : const Color(0xFFB0B3DE)),
              const SizedBox(height: 4),
              Text(texto,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: seleccionado
                        ? Colors.white
                        : const Color(0xFFB0B3DE),
                  )),
            ]),
          ),
        ),
      );

  Widget _dock() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 0, 13, 8),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF20224F),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFF3D416F)),
              boxShadow: const [
                BoxShadow(color: Color(0x77000016), blurRadius: 20),
              ],
            ),
            child: Row(children: [
              _destino(Icons.dashboard_rounded, 'Inicio',
                  () => _aviso('Ya estás en Inicio'), seleccionado: true),
              _destino(Icons.point_of_sale_rounded, 'Vender',
                  () => _aviso('Preview: venta no ejecutada')),
              Expanded(
                child: Center(
                  child: Container(
                    width: 57,
                    height: 57,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        Color(0xFF6557FF), Color(0xFF367BFB),
                      ]),
                      boxShadow: [
                        BoxShadow(color: Color(0x663669F3), blurRadius: 15),
                      ],
                    ),
                    child: IconButton(
                      tooltip: 'Facturación por voz (solo vista)',
                      onPressed: () => _aviso('Preview: voz no activada'),
                      icon: const Icon(Icons.mic_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
              _destino(Icons.menu_book_rounded, 'Fiados',
                  () => _aviso('Preview: fiados no consultados')),
              _destino(Icons.account_balance_wallet_outlined, 'Caja',
                  () => _aviso('Preview: caja no modificada')),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final premium = _plan != FacturaVozPlan.basico;
    return MaterialApp(
      title: 'FacturaVoz · Inicio de diseño',
      scaffoldMessengerKey: _mensajes,
      navigatorKey: _navegacion,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E2E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7557F3),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        extendBody: true,
        body: FacturaVozInicioBodega(
          datos: FacturaVozInicioDatos(
            nombreNegocio: 'Mi tienda',
            plan: _plan,
            // null = datos aún no consultados. No simular ventas ni saldos.
            ventasHoyCentimos: null,
            ventasMesCentimos: null,
            operacionesHoy: null,
            stockBajo: null,
            fiadosVencidos: null,
            puedeVerVentas: true,
            puedeVender: true,
            puedeAbrirCaja: true,
            puedeVerInventario: true,
            // Exclusivamente en esta vista simulamos el plan para comparar UI.
            puedeVerFiados: premium,
            puedeReponer: premium,
            puedeUsarCopiloto: premium,
          ),
          onNuevaVenta: () => _aviso('Preview: venta no registrada'),
          onCaja: () => _aviso('Preview: caja no modificada'),
          onInventario: () => _aviso('Preview: inventario no consultado'),
          onFiados: () => _aviso('Preview: fiados no consultados'),
          onReponer: () => _aviso('Preview: compras no registradas'),
          onCopiloto: () => _aviso('Preview: IA no invocada'),
          onMeta: () => _aviso('Preview: metas no modificadas'),
          onMenu: _seleccionarPlan,
          onVerPlan: _seleccionarPlan,
          onBuscar: () => _aviso('Preview: búsqueda no ejecutada'),
        ),
        bottomNavigationBar: _dock(),
      ),
    );
  }
}
