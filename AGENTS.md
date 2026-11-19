# FacturaVoz

Evolucionar este monorepo, no crear otro producto. Flutter `app/`, Next.js
`backend/`, PostgreSQL Supabase existente. Marca FacturaVoz; los nombres internos
`retail` y rubros históricos pueden seguir por compatibilidad.

## Selección de skills

Antes de modificar código, lee el `SKILL.md` pertinente bajo `.agents/skills/`.
Carga solo lo necesario, normalmente una o dos skills:

| Tarea | Skill |
|---|---|
| Contratos entre capas, refactor | facturavoz-architecture |
| Dart, pantalla móvil, navegación | facturavoz-flutter |
| Next.js, React, formulario web | facturavoz-web |
| SQL, RPC, RLS, migración | facturavoz-database |
| SUNAT, emisión, notas, XML/CDR/PDF fiscal | facturavoz-fiscal |
| Venta, cliente, cobro, caja, deuda, compra | facturavoz-commerce |
| Integración/E2E, revisión visual o regresión | facturavoz-quality |
| GitHub, CI, Vercel Preview | facturavoz-delivery |

Usa skills de plugins instalados cuando aporten instrucciones de plataforma;
no cargar todas por rutina. Consultar documentación oficial vigente para normas
fiscales, APIs o configuración cambiante. Una skill no otorga permisos externos.

## Límites y evidencia

Revisar Git antes de editar; conservar cambios y commits. Verificar consumidores
antes de retirar componentes. No alterar Hub, AWS, Caddy, web corporativa,
secretos, licencias reales ni históricos. Ensayar cambios DB sobre restauración;
no usar producción para pruebas. Publicar solo con autorización de la sesión;
no merge a main ni promoción implícita.

Priorizar recorridos completos: cliente → venta → cobro → emisión → PDF → historial.
PostgreSQL es la fuente de verdad. No confundir venta guardada, dinero cobrado y
aceptación fiscal. Ejecutar pruebas pertinentes y comunicar archivos, resultados
y limitaciones. Mock, widget, HTTP/SQL y E2E autenticado son evidencias diferentes.
