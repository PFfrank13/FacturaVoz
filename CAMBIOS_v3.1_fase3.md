# FacturaVoz v3.1 — Fase 3 (membresías por rubro + Copiloto Pro/Empresa)
**Misma lista de planes y precios para todos; cambia lo que desbloquea cada uno según el rubro** (tabla completa en `docs/PLANES.md`).
- **Básico** = esenciales del rubro. **Pro** = Básico + UN módulo estrella (bodega: puntos/descuentos a caseros; restaurante: reservas; técnicos: portal del cliente; salón: comisiones; consultorio: seguimientos; taller: agenda; mayorista: tienda de pedidos; academia: portal de apoderados; construcción: agenda) + Copiloto. **Empresa** = todo + Copiloto agente.
- **Copiloto Pro**: responde y propone con tus datos reales. **Copiloto Empresa**: además se adelanta ("Lo que yo haría hoy", riesgos, comparación) y recibe **Tareas** (Menú → Tareas del Copiloto): cobranza (mensajes de WhatsApp listos para copiar), lista de reposición, recordatorios de cobro y resumen semanal. Tú apruebas; nada se envía, cobra ni emite solo. Lo único que escribe son recordatorios.
- La regla vive en la base (`private.plan_matrix`, `plan_allows`, `has_feature`, `my_license` ya resuelto) y en la app (`planMatrix`); una prueba exige que sean idénticas.
- Complementos: lo que el Hub active en una licencia fuera del plan estándar se respeta.
- Los textos "Disponible en el plan X" ahora dependen de tu rubro.

**SQL nuevo (después de 20261117):** `20261118_v31_planes_por_rubro.sql`.
**Hub:** vuelve a cargar `docs/facturavoz-planes.json` (agrega `copiloto_agente`; BASICO/PRO/EMPRESA ahora marcan la unión por rubro).
**Backend nuevo:** `src/lib/agent.ts`, `api/agent/route.ts`, `api/agent/decide/route.ts`, nivel de Copiloto en `rubro-copilot.ts`; prueba `tests/agent.test.ts`.
**App nueva:** `screens/agent.dart`, `AgentApi` (pro_api.dart), `planMatrix` (rubros.dart), `planHas` por rubro (access.dart), entrada 'agente' en el catálogo.

Verificado: tsc OK · 118 pruebas del servidor · toda la cadena de migraciones + `test_v31_planes.sql` en Postgres 16 (Básico/Pro/Empresa por rubro, complemento, PRO sin agente, aprobación obligatoria, aislamiento entre empresas) · sintaxis Dart.
No verificado: `flutter analyze/test` (sin SDK aquí), llamadas reales a Groq del agente, y la pantalla en el teléfono.
La prueba de licencias anterior (`test_lic.sql`) sigue pasando igual.
