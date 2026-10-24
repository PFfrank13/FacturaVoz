# Facturación electrónica SUNAT (Lycet + Greenter)

## Cómo funciona
```
App Flutter ──Bearer──▶ /api/fiscal/emit (Vercel)
                          1. valida usuario, datos fiscales y totales (IGV por línea, SON …)
                          2. reserva serie+correlativo en Supabase (atómico, idempotente)
                          3. ──Basic Auth──▶ Caddy (tu VPS Oracle) ──▶ Lycet/Greenter: XML UBL 2.1 + firma + envío SOAP a SUNAT
                          4. guarda estado, hash, XML y CDR (solo el servidor escribe)
App ◀── estado ── lee su comprobante (RLS) y genera el PDF con QR en el teléfono
```
- **Secretos** (clave SOL secundaria, certificado): solo en tu VPS (`empresas.json` + `.pem`). No están en Supabase, ni en la app.
- **RUC**: se toma de `fiscal_companies` (escrita por el servidor al configurar), no del perfil editable. Un RUC solo puede ser reclamado por una cuenta.
- **Reintentos**: si SUNAT no responde, el comprobante queda `error`/`pending` y «Reintentar» reenvía EXACTAMENTE el mismo contenido y número.
  Si SUNAT responde «ya registrado» (1033) se recupera su CDR. Si lo **rechaza** (códigos 2000-3999), se corrige y se reenvía con el mismo número.
- **Estados**: `accepted` (CDR 0 o 4xxx con observaciones) · `rejected` · `error` · `pending`. Un `accepted` ya no cambia.
- **PDF**: con comprobante = representación impresa construida solo con lo enviado a SUNAT (QR, hash, estado). Sin comprobante = «Nota de venta — sin validez tributaria». Beta o no aceptado = franja de aviso.

## Qué se probó y qué NO
Probado aquí: SQL (Postgres real), cálculo/“SON …”/validadores (35 pruebas), **XML UBL firmado generado por Lycet/Greenter real** para
factura, boleta con DNI, boleta sin documento y operación exonerada (totales coherentes), rutas `/api/fiscal/*` con Supabase y Lycet simulados.

**No probado (no hay salida a SUNAT desde aquí):** el envío real a SUNAT. Antes de vender: `infra/lycet/smoke-beta.sh` (debe dar CDR `0`),
luego una factura, una boleta y una exonerada en beta desde la app. Verifica en beta en especial:
1. **Boleta individual** (`invoice/send` con tipo 03): SUNAT admite envío individual o por resumen diario; si tu cuenta/entorno exigiera resumen diario, hay que añadir ese flujo.
2. **Boleta sin documento** (`tipoDoc "-"`, `numDoc "-"`) y el tope de S/ 700.
3. Unidad `NIU` para servicios (alternativa `ZZ` disponible en la app).

## Notas de crédito (anulación total)
Desde el detalle de un comprobante **aceptado**: «Anular con nota de crédito» (motivo 01 anulación de la operación o 06 devolución total).
- La nota copia exactamente los importes, líneas y cliente que SUNAT aceptó (no recalcula) y referencia `SERIE-CORRELATIVO` del original.
- Serie automática: `F001 → FC01`, `B001 → BC01`. Misma reserva idempotente que los comprobantes (reintento = mismo número).
- Validado: Lycet/Greenter generó el XML firmado de nota (factura, boleta y exonerada) con referencia, motivo e importes correctos. El **envío a SUNAT beta sigue sin probarse**.
- Una nota por comprobante. No hay notas parciales (descuentos, devolución parcial), ni notas de débito.
- Requiere migración `20261025_credit_notes.sql` (también mueve `delete_my_account` al esquema `private`).

## Alcance actual (v1) y lo que falta
Incluye: factura y boleta, PEN/USD, gravado 18 % / exonerado / inafecto, contado, una serie F y una B por empresa.
**No incluye** (planifícalos): notas de crédito parciales y notas de débito, comunicación de baja,
resumen diario de boletas, guías de remisión, ventas a crédito/cuotas, descuentos/ICBPER/detracción, multi-moneda distinta de PEN/USD,
varias series, y consulta masiva de CDR pendientes (hoy se reintenta a mano desde cada comprobante).
Un error en un comprobante aceptado se corrige anulándolo con nota de crédito total y emitiendo uno nuevo.

## Responsabilidad y cumplimiento
- Cada cliente debe estar afiliado a «SEE – Del contribuyente», tener certificado digital y usuario SOL secundario (ver `infra/lycet/INSTALACION.md`).
  Confirma los requisitos vigentes con SUNAT/contador. Si vas a emitir **por cuenta de terceros** como servicio, consulta si necesitas
  figurar como PSE/OSE autorizado: esta arquitectura guarda sus certificados en tu servidor.
- Conservación: la ley exige guardar XML y CDR varios años. La cuenta con comprobantes de **producción** no se puede auto-eliminar (contacta soporte); respalda Supabase (plan Pro).
- Protege el VPS como una bóveda: quien entre puede firmar comprobantes de tus clientes.
