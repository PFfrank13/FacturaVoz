---
name: facturavoz-fiscal
description: "Integración fiscal peruana existente de FacturaVoz: emisión, estados, XML/CDR, notas y PDF. Usar al cambiar reglas SUNAT o su presentación."
---

# facturavoz-fiscal

## Archivos de entrada
- [backend/src/app/api/fiscal/emit/route.ts](../../../backend/src/app/api/fiscal/emit/route.ts)
- [backend/src/lib/fiscal/payload.ts](../../../backend/src/lib/fiscal/payload.ts)
- [backend/src/lib/fiscal/lycet.ts](../../../backend/src/lib/fiscal/lycet.ts)
- [backend/tests/fiscal.test.ts](../../../backend/tests/fiscal.test.ts)
- [app/lib/services/pdf_builder.dart](../../../app/lib/services/pdf_builder.dart)
- [app/lib/screens/invoice_detail.dart](../../../app/lib/screens/invoice_detail.dart)

## Trabajo
Consulta antes de definir reglas https://cpe.sunat.gob.pe/guias-y-manuales y https://orientacion.sunat.gob.pe/guias-manuales-y-servicios-web . Registra fecha/versión de la regla aplicable. El portal consultado el 2026-11-07 publica guías UBL 2.1 y validaciones fechadas 26.08.2026; vuelve a comprobar, no congeles esos datos como norma eterna. Conserva Lycet y contratos actuales; no alteres AWS/Caddy. Separa venta, PDF, XML firmado, envío, pendiente, rechazo y aceptación respaldada por respuesta/CDR. No envíes documentos reales para probar. IA nunca inventa RUC, importes ni estados.

## Aceptación
Pruebas unitarias de payload/cálculo y fixture de error/reintento; integración autorizada de pruebas antes de emisión real. PDF coincide con persistencia; estados fiscales provienen de evidencia del proveedor. Ninguna cifra normativa sin fuente oficial vigente.
