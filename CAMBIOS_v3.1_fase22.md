# FacturaVoz v3.1 · Fase 22 — Más pantallas en tiempo real

Mismo sistema de la Fase 21 (`LiveReload` + `LiveCache`), ahora también en:
- **Avisos de pago (Yape/Plin)**: se actualizan solos cuando llega un aviso o cambian facturas/cobros.
- **Tareas del Copiloto** (Empresa): una tarea aprobada, hecha o fallida cambia sin recargar.
- **Les toca volver** (recordatorios del taller, salón y consultorio).
- **Facturas recurrentes**: al abrir sigue generando lo que toque hoy; luego se actualiza sola.

Todas muestran al instante lo último visto (solo en memoria, por empresa) y refrescan detrás.
Con esto el tiempo real cubre: Inicio, Clientes, Productos, Fiados, Caja, Gastos, Trabajos, Agenda, Avisos de pago, Tareas del Copiloto, Recordatorios y Recurrentes (más Cobros y Cotizaciones, que ya lo tenían).
Sin cambios en base de datos (usa la migración 20261119 de la Fase 21).
Verificado: sintaxis e imports. Falta: `flutter analyze` y probar en el teléfono.
