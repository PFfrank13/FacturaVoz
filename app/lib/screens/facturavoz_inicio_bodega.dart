import 'package:flutter/material.dart';

/// Inicio visual independiente para el producto único FacturaVoz.
///
/// No contiene clientes de API, consultas, credenciales ni reglas de licencia.
/// En la aplicación real, los datos y permisos deben proceder de sus servicios
/// existentes (my_license, my_access, RPC y repositorios autorizados).
enum FacturaVozPlan { basico, pro, empresa }

extension FacturaVozPlanLabel on FacturaVozPlan {
  String get nombre => switch (this) {
        FacturaVozPlan.basico => 'Bodega / Tienda',
        FacturaVozPlan.pro => 'Minimarket',
        FacturaVozPlan.empresa => 'Hiperbodega',
      };

  String get planNombre => switch (this) {
        FacturaVozPlan.basico => 'Básico',
        FacturaVozPlan.pro => 'Pro',
        FacturaVozPlan.empresa => 'Empresa',
      };

  String get titular => switch (this) {
        FacturaVozPlan.basico => 'Tu bodega, lista para vender',
        FacturaVozPlan.pro => 'Tu minimarket, bajo control',
        FacturaVozPlan.empresa => 'Tu hiperbodega, conectada',
      };

  String get descripcion => switch (this) {
        FacturaVozPlan.basico => 'Vende rápido y lleva el control de tu tienda.',
        FacturaVozPlan.pro => 'Ventas, stock y cobranza en un solo lugar.',
        FacturaVozPlan.empresa => 'Organiza tus operaciones en una sola vista.',
      };
}

@immutable
class FacturaVozInicioDatos {
  const FacturaVozInicioDatos({
    required this.nombreNegocio,
    required this.plan,
    this.ventasHoyCentimos,
    this.ventasMesCentimos,
    this.operacionesHoy,
    this.stockBajo,
    this.fiadosVencidos,
    this.metaMensualCentimos,
    this.cargando = false,
    this.puedeVerVentas = true,
    this.puedeVender = false,
    this.puedeAbrirCaja = false,
    this.puedeVerInventario = false,
    this.puedeVerFiados = false,
    this.puedeReponer = false,
    this.puedeUsarCopiloto = false,
  });

  final String nombreNegocio;
  final FacturaVozPlan plan;
  final int? ventasHoyCentimos;
  final int? ventasMesCentimos;
  final int? operacionesHoy;
  final int? stockBajo;
  final int? fiadosVencidos;
  final int? metaMensualCentimos;
  final bool cargando;
  final bool puedeVerVentas;
  final bool puedeVender;
  final bool puedeAbrirCaja;
  final bool puedeVerInventario;
  final bool puedeVerFiados;
  final bool puedeReponer;
  final bool puedeUsarCopiloto;
}

class FacturaVozInicioBodega extends StatelessWidget {
  const FacturaVozInicioBodega({
    super.key,
    required this.datos,
    this.onNuevaVenta,
    this.onCaja,
    this.onInventario,
    this.onFiados,
    this.onReponer,
    this.onCopiloto,
    this.onMenu,
    this.onMeta,
    this.onBuscar,
    this.onVerPlan,
    this.onRefresh,
  });

  final FacturaVozInicioDatos datos;
  final VoidCallback? onNuevaVenta;
  final VoidCallback? onCaja;
  final VoidCallback? onInventario;
  final VoidCallback? onFiados;
  final VoidCallback? onReponer;
  final VoidCallback? onCopiloto;
  final VoidCallback? onMenu;
  final VoidCallback? onMeta;
  final VoidCallback? onBuscar;
  final VoidCallback? onVerPlan;
  final Future<void> Function()? onRefresh;

  static const _fondo = Color(0xFF0A0E2E);
  static const _panel = Color(0xFF171B44);
  static const _suave = Color(0xFFD9D8FA);
  static const _verde = Color(0xFF19B991);

  String _dinero(int? centimos) {
    if (centimos == null) return '—';
    final n = centimos.abs();
    final parteEntera = (n ~/ 100).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${centimos < 0 ? '-' : ''}S/ $parteEntera.${(n % 100).toString().padLeft(2, '0')}';
  }

  String _saludo() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final copilotoHabilitado = datos.puedeUsarCopiloto && onCopiloto != null;
    final contenido = ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _cabecera(context, copilotoHabilitado),
        Padding(
          padding: const EdgeInsets.fromLTRB(19, 19, 19, 155),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fotoBodega(),
              const SizedBox(height: 25),
              _titulo('Tu tienda, a un toque', 'Las tareas de todos los días'),
              const SizedBox(height: 14),
              _accesos(context),
              const SizedBox(height: 27),
              _titulo('Así va tu negocio', 'Indicadores de tus operaciones'),
              const SizedBox(height: 13),
              _resumen(),
              if (copilotoHabilitado) ...[
                const SizedBox(height: 26),
                _copiloto(),
              ],
              const SizedBox(height: 23),
              Center(
                child: Text(
                  'FacturaVoz · ${datos.plan.planNombre}',
                  style: const TextStyle(color: Color(0xFF9297C4), fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return ColoredBox(
      color: _fondo,
      child: onRefresh == null
          ? contenido
          : RefreshIndicator(onRefresh: onRefresh!, child: contenido),
    );
  }

  Widget _cabecera(BuildContext context, bool copilotoHabilitado) {
    final nombre = datos.nombreNegocio.trim().isEmpty
        ? 'Mi negocio'
        : datos.nombreNegocio.trim();
    final mensuales = datos.puedeVerVentas
        ? _dinero(datos.ventasMesCentimos)
        : 'Sin acceso';
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(39)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF262267), Color(0xFF6044BE), Color(0xFFAF68E5)],
          stops: [0, .55, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 21, 22, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_saludo(),
                      style: const TextStyle(color: _suave, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.45,
                      )),
                ]),
              ),
              if (onBuscar != null)
                _circulo(Icons.search_rounded, 'Buscar', onBuscar!),
              if (onBuscar != null) const SizedBox(width: 9),
              if (onMenu != null)
                _circulo(Icons.person_rounded, 'Mi cuenta y menú', onMenu!),
            ]),
            const SizedBox(height: 19),
            Row(children: [
              if (copilotoHabilitado) ...[
                Expanded(
                  child: _pillAccion(
                    Icons.auto_awesome_rounded,
                    'Copiloto',
                    onCopiloto!,
                  ),
                ),
                const SizedBox(width: 11),
              ],
              if (onMenu != null)
                Expanded(
                  child: _pillAccion(Icons.menu_rounded, 'Menú', onMenu!),
                ),
              if (!copilotoHabilitado && onVerPlan != null) ...[
                const SizedBox(width: 11),
                Expanded(
                  child: _pillAccion(
                    Icons.workspace_premium_outlined,
                    'Mi plan',
                    onVerPlan!,
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 24),
            Text('Vendido este mes (con IGV)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .87),
                  fontSize: 14,
                )),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: Text(
                    mensuales,
                    key: ValueKey(mensuales),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.3,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              if (onMeta != null && datos.puedeVerVentas) ...[
                const SizedBox(width: 10),
                _metaBoton(),
              ],
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _pastilla(
                Icons.today_rounded,
                datos.puedeVerVentas
                    ? 'Hoy ${_dinero(datos.ventasHoyCentimos)}'
                    : 'Ventas restringidas',
              ),
              if (datos.puedeVerVentas && datos.operacionesHoy != null)
                _pastilla(
                  Icons.receipt_outlined,
                  '${datos.operacionesHoy} ${datos.operacionesHoy == 1 ? 'venta' : 'ventas'}',
                ),
            ]),
            const SizedBox(height: 10),
            if (datos.cargando)
              const LinearProgressIndicator(
                backgroundColor: Color(0x557E74C4),
                color: Color(0xFFFFFFFF),
                minHeight: 3,
              )
            else if (datos.ventasMesCentimos == null && datos.puedeVerVentas)
              Text('Esperando datos del negocio',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .74),
                    fontSize: 11,
                  )),
          ]),
        ),
      ),
    );
  }

  Widget _pillAccion(IconData icon, String label, VoidCallback accion) =>
      Material(
        color: Colors.white.withValues(alpha: .17),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: accion,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 13),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    )),
              ),
            ]),
          ),
        ),
      );

  Widget _circulo(IconData icon, String tooltip, VoidCallback accion) =>
      IconButton(
        tooltip: tooltip,
        onPressed: accion,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: .18),
          minimumSize: const Size(43, 43),
        ),
        icon: Icon(icon, size: 22),
      );

  Widget _metaBoton() => InkWell(
        onTap: onMeta,
        customBorder: const CircleBorder(),
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: .75), width: 1.6),
            color: Colors.white.withValues(alpha: .07),
          ),
          child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.flag_rounded, color: Colors.white, size: 21),
            SizedBox(height: 5),
            Text('Fijar meta', style: TextStyle(color: Colors.white, fontSize: 11)),
          ]),
        ),
      );

  Widget _pastilla(IconData icon, String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .17),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 6),
          Text(texto,
              style: const TextStyle(color: Colors.white, fontSize: 11.5)),
        ]),
      );

  Widget _fotoBodega() => ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: SizedBox(
          height: 173,
          child: Stack(fit: StackFit.expand, children: [
            Image.asset(
              'assets/photos/bodega.webp',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF36478D), Color(0xFF2A225B)],
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xE80D153C), Color(0x9B181B46), Color(0x25181B46)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(19),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _etiquetaFoto(),
                  const SizedBox(height: 13),
                  Text(
                    datos.plan.titular,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      height: 1.14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    datos.plan.descripcion,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Color(0xFFE4E5FC),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );

  Widget _etiquetaFoto() => Container(
        decoration: BoxDecoration(
          color: _verde,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.storefront_rounded, color: Colors.white, size: 14),
          const SizedBox(width: 7),
          Text('${datos.plan.nombre} · ${datos.plan.planNombre}',
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11,
              )),
        ]),
      );

  Widget _titulo(String titulo, String subtitulo) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 4),
          Text(subtitulo,
              style: const TextStyle(color: Color(0xFFAEB1D6), fontSize: 12)),
        ],
      );

  Widget _accesos(BuildContext context) {
    final acciones = <_AccesoItem>[
      if (datos.puedeVender && onNuevaVenta != null)
        _AccesoItem(
          Icons.add_shopping_cart_rounded,
          'Nueva venta',
          const [Color(0xFF7366FF), Color(0xFF3678F3)],
          onNuevaVenta!,
        ),
      if (datos.puedeVerFiados && onFiados != null)
        _AccesoItem(
          Icons.menu_book_rounded,
          'Fiados',
          const [Color(0xFF008AA9), Color(0xFF20B4C9)],
          onFiados!,
        ),
      if (datos.puedeReponer && onReponer != null)
        _AccesoItem(
          Icons.local_shipping_outlined,
          'Reponer',
          const [Color(0xFF098AC5), Color(0xFF1176AD)],
          onReponer!,
        ),
      if (datos.puedeAbrirCaja && onCaja != null)
        _AccesoItem(
          Icons.account_balance_wallet_rounded,
          'Caja',
          const [Color(0xFF6AB500), Color(0xFF23833D)],
          onCaja!,
        ),
      if (datos.puedeVerInventario && onInventario != null &&
          !(datos.puedeVerFiados && datos.puedeReponer))
        _AccesoItem(
          Icons.inventory_2_outlined,
          'Inventario',
          const [Color(0xFF1CB3CF), Color(0xFF087EA8)],
          onInventario!,
        ),
      if (onMenu != null)
        _AccesoItem(
          Icons.menu_rounded,
          'Ver todas',
          const [Color(0xFF3B3775), Color(0xFF242154)],
          onMenu!,
        ),
    ];
    if (acciones.isEmpty) {
      return const _InfoVacia('No hay accesos habilitados para tu rol y plan.');
    }
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 320 ? 5 : width >= 245 ? 4 : 3;
      final tileWidth = (width - 8 * (columns - 1)) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 14,
        children: [
          for (final item in acciones)
            SizedBox(width: tileWidth, child: _acceso(item)),
        ],
      );
    });
  }

  Widget _acceso(_AccesoItem item) => Semantics(
        button: true,
        label: item.titulo,
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(17),
          child: Column(children: [
            Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: item.colores,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: item.colores.first.withValues(alpha: .24),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(item.icono, color: Colors.white, size: 27),
            ),
            const SizedBox(height: 8),
            Text(item.titulo,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                )),
          ]),
        ),
      );

  Widget _resumen() {
    final indicadores = <_ResumenItem>[
      if (datos.puedeVerVentas)
        _ResumenItem(
          Icons.show_chart_rounded,
          'Ventas de hoy',
          _dinero(datos.ventasHoyCentimos),
        ),
      if (datos.puedeVerInventario)
        _ResumenItem(
          Icons.inventory_2_outlined,
          'Stock bajo',
          datos.stockBajo == null ? 'Sin consultar' : '${datos.stockBajo} productos',
        ),
      if (datos.puedeVerFiados)
        _ResumenItem(
          Icons.menu_book_rounded,
          'Fiados vencidos',
          datos.fiadosVencidos == null
              ? 'Sin consultar'
              : '${datos.fiadosVencidos} cuentas',
        ),
    ];
    if (indicadores.isEmpty) {
      return const _InfoVacia('Las cifras se muestran según tus permisos.');
    }
    return Column(children: [
      for (var i = 0; i < indicadores.length; i++) ...[
        _indicador(indicadores[i]),
        if (i != indicadores.length - 1) const SizedBox(height: 9),
      ],
    ]);
  }

  Widget _indicador(_ResumenItem item) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF303760)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF34306A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icono, color: const Color(0xFFCBC1FF), size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(item.titulo,
              style: const TextStyle(color: _suave, fontSize: 12.5))),
          Flexible(child: Text(item.valor,
              maxLines: 2,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ))),
        ]),
      );

  Widget _copiloto() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF191B49),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: const Color(0xFF5C519B)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_awesome_rounded, color: Color(0xFFBAA4FF), size: 21),
            SizedBox(width: 8),
            Text('Tu copiloto te acompaña',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                )),
          ]),
          const SizedBox(height: 9),
          const Text(
            'Consulta tus ventas, revisa lo pendiente y prepara tus próximas acciones.',
            style: TextStyle(color: _suave, fontSize: 12.5, height: 1.4),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCopiloto,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Abrir Copiloto'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD4C4FF),
              ),
            ),
          ),
        ]),
      );
}

class _AccesoItem {
  const _AccesoItem(this.icono, this.titulo, this.colores, this.onTap);
  final IconData icono;
  final String titulo;
  final List<Color> colores;
  final VoidCallback onTap;
}

class _ResumenItem {
  const _ResumenItem(this.icono, this.titulo, this.valor);
  final IconData icono;
  final String titulo;
  final String valor;
}

class _InfoVacia extends StatelessWidget {
  const _InfoVacia(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xFF191D45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFBFC1E5), fontSize: 12),
        ),
      );
}
