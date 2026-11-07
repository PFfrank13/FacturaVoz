# Decisiones pendientes — Solvex Retail

- Marca provisional: disponibilidad comercial y jurídica no verificada; no afirmar registro ni exclusividad.
- Arquitectura vigente: cloud-first. PostgreSQL es la única fuente de operaciones confirmadas. No construir una base empresarial independiente por dispositivo.
- Venta offline completa y autorización de licencias desconectadas: fuera del alcance actual, únicamente mejora futura pendiente de decisión. No modificar Hub ni sus licencias.
- Versionado: precio/version de catálogo capturados en ticket; conflicto explícito al cambiar servidor. Nunca último cambio gana para stock/caja/deuda. Falta contrato servidor de versiones.
- Mantener org_id como tenant existente. Tienda/almacén/caja/dispositivo requieren evolución aditiva, no duplicar empresas ni renombrar tablas.
- Estado de pago: efectivo registrado, digital manual, pendiente de verificación y confirmado por proveedor deben persistirse por separado; no inventar confirmación externa con el RPC actual.
- Identificadores Android/iOS, paquetes, rutas y dominios permanecen. Una futura migración necesita compatibilidad, rollback y autorización externa.
- Tablet Android de referencia y hardware real no disponibles para certificar tiempos/impresión.
- Puerta 1 pendiente: jornada comercial real con datos sintéticos en laboratorio aislado, reconciliación de caja/inventario sin duplicados/pérdidas, concurrencia, recuperación de respuesta perdida y aislamiento de empresas. Se elimina el requisito de siete días offline. Etapas 2–4 siguen secuenciales; futuras cadenas/distribución no se adelantan.
