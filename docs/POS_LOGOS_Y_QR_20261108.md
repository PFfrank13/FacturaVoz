# Venta rápida — assets de cobro (noviembre 2026)

La pantalla de medios de cobro muestra los símbolos de las marcas **solo como identificación visual**, no afirma que FacturaVoz sea socio oficial o que haya validado un pago a través de ellas.

- **Yape**: icono alojado por Wikimedia Commons en
  https://commons.wikimedia.org/wiki/File:Icono_de_la_aplicaci%C3%B3n_Yape.png
  (crédito: Banco de Crédito del Perú; publicado en Wikimedia Commons con licencia
  Creative Commons Attribution-ShareAlike 4.0, sin modificación del archivo original).
- **Plin**: imagen oficial publicada por BBVA Perú en su página de Plin:
  https://www.bbva.pe/personas/servicios-digitales/plin.html
  (marca de BBVA y/o sus titulares, se muestra únicamente como identificación).
- **Visa / Mastercard**: indicadores estilizados de compatibilidad visual en el método "Tarjeta";
  ningún procesamiento bancario se ejecuta por mostrar el logo. Confirmación manual del
  terminal real, cuando exista.
- **Efectivo**: icono genérico, no una marca de tercero.

Los logos se cargan desde la web con fallback interno cuando el dispositivo está sin conexión.
Si se van a redistribuir offline como recursos empaquetados, obtener antes versiones oficiales
y verificar derechos de uso y guías de marca aplicables.

## QR de cobro real
El negocio debe exportar la imagen de QR desde su cuenta bancaria propia y subirla en
Ajustes → Medios de cobro. No crear un QR a partir del número de teléfono: generaría un
QR visual que puede ser **inservible o peligroso**. La app registra el pago únicamente cuando
el cajero marca que comprobó el abono; no se comunica automáticamente con Yape/Plin.

## Facturación
El registro del pago y la emisión SUNAT son dos operaciones independientes. La pantalla
de confirmación permite abrir el formulario de boleta (03) o factura (01), pero no marca
un comprobante como emitido antes de obtener la confirmación de SUNAT.
