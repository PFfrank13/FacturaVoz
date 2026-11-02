# FacturaVoz v3.1 · Fase 21 — Encabezado, fluidez y tiempo real

Tras ver la captura del Inicio en el teléfono.

**1. Saludo descuadrado (corregido)**
- En `HomeHeader` el saludo compartía fila con 4 botones y quedaba aplastado ("Buena / s / tardes", nombre cortado).
- Ahora: fila 1 = saludo + nombre (1 línea, con "…" si no cabe) + buscar + perfil; fila 2 = **Copiloto** y **Menú** del mismo ancho, con el texto centrado.

**2. Fluidez / "se espera a que cargue"**
- `Reveal` (entrada de cada bloque) esperaba hasta 60 ms × posición y duraba 550 ms: ahora ≤ 48 ms de espera y 180 ms de duración, con desplazamiento más corto.
- `CountUp`: ya no cuenta desde cero al aparecer; muestra el valor al instante y solo se desliza (450 ms) cuando cambia.
- `Aurora` (fondo animado del Inicio) se repintaba 60 veces por segundo: ahora ~11 (el movimiento es lento, no se nota).
- `Sparkline` (gráfico de 14 días): 450 ms en vez de 1 300 ms.

**3. Tiempo real e instantáneo**
- `services/live.dart` (nuevo):
  - `LiveHub`: escucha los cambios de la empresa activa en Supabase Realtime (un canal por tabla; si una tabla no está publicada, solo esa deja de avisar) y junta ráfagas de cambios en un aviso (250 ms).
  - `LiveCache`: guarda en memoria lo último que cada pantalla cargó, por empresa; se borra al cambiar de empresa y al cerrar sesión; **nunca se guarda en disco**.
  - `LiveReload`: para que una pantalla se recargue sola cuando cambian sus tablas.
  - `LiveCache.warmUp()`: al iniciar sesión precarga en segundo plano clientes, productos, fiados y trabajos.
- Pantallas con tiempo real + caché: **Inicio, Clientes, Productos, Fiados, Caja del día, Gastos, Trabajos y Agenda**. (Cobros y Cotizaciones ya tenían tiempo real propio.)
- **Inicio** ahora muestra cada pieza apenas llega (el total del mes no espera a la lista de 100 comprobantes).
- Migración `20261119_v31_tiempo_real.sql`: publica clients, products, expenses, service_reminders, agent_tasks y recurring_invoices en Realtime (idempotente; probada dos veces sobre toda la cadena en PG16).

**Límites honestos**
- La **primera vez** tras abrir la app sigue habiendo una consulta de red; la caché evita la espera en las visitas siguientes y `warmUp` la adelanta para las 4 pantallas más usadas. Las demás pantallas (reportes, cotizaciones, etc.) siguen cargando al abrirse.
- Los borrados duros no avisan por Realtime con filtro por empresa; en esta app casi todo se borra de forma suave (papelera), que sí avisa.
- Sin tocar RLS ni permisos: Realtime respeta las políticas de cada tabla.

Verificado: sintaxis, imports, migración. Falta en tu máquina: `flutter analyze`, `flutter test` (nueva: `test/live_cache_test.dart`) y probar en el teléfono con la guía (sección Fase 21).
