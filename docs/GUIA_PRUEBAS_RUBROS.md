# Prueba de 3 minutos por rubro

Antes: aplica las migraciones v3, entra como dueño, Ajustes → **Rubro** → elige el rubro → Ajustes → **Datos de
práctica → Cargar**. Al final: Ajustes → Datos de práctica → **Borrar los de práctica**.
En cada rubro revisa también: la **barra de abajo** (4 destinos + micrófono con las palabras del rubro), el **Inicio
limpio** (hoy, meta, 1–2 sugerencias, 3–4 accesos con la ⭐) y el **Menú** (áreas del rubro, candados del plan,
"Otras funciones").

| Rubro | Minuto 1 | Minuto 2 | Minuto 3 |
|---|---|---|---|
| **Bodega** | Barra: Inicio · Vender · Fiados · Caja. Vender → venta rápida de "Arroz 1 kg" → boleta. | Productos → pon stock 3 al arroz y vende 2 → Inicio → **Reposición** → "Enviar pedido al proveedor". | Fiados → anota 20 a "Sra. Rosa (práctica)" → Caja → cierre del día. Copiloto: "¿qué se me está acabando?" |
| **Restaurante** | Barra: Inicio · Mesas · Caja · Negocio. Abre la tienda con `?mesa=4` y pide 2 platos → aparecen en **Mesas**. | **Cuentas y platos** → total 120, entre 3, propina 10 % → la suma cuadra. | Pestaña Costo por plato (los de práctica traen costo) → el de menor margen primero. |
| **Servicios técnicos** | Barra: Inicio · Trabajos · Abonados · Cobrar. Crea instalación para "Abonado Pérez" y muévela en el tablero. | Factura 67,80 a ese abonado con vencimiento de ayer → **Mensualidades y corte** → aparece con atraso. | "Aviso previo" (WhatsApp) → el abonado dice "Avisado hoy" y **"Registrar corte" sigue apagado** (se habilita desde mañana; ver la prueba de la Fase 9 abajo) → tras el corte la ficha muestra "Cortado" → "Registrar reconexión". |
| **Salón** | Barra: Inicio · Citas · Clientes · Caja. Agenda una cita y márcala "No vino". | **Paquetes** → "4 sesiones" a "Clienta Ana (práctica)" → "Usar 1" (quedan 3). | El ranking de no-shows la muestra. Comisiones: Mi negocio → pestaña Comisiones. |
| **Consultorio** | Barra: Inicio · Agenda · Pacientes · Cobrar ("Pacientes" en lugar de Clientes). | **Historial privado** → elige al paciente → pide consentimiento → "Sí, firmó" → guarda una nota. | Entra con un usuario cajero: no ve la nota. Copiloto: "¿qué diagnóstico tiene…?" → responde que no maneja datos clínicos. |
| **Taller** | Barra: Inicio · Órdenes · Clientes · Cobrar. **Buscar por placa** "ABC123" → no existe → regístrala para "Carlos (práctica)". | Busca "abc-123" → aparece → abre la ficha → crea una orden y súbele una foto. | **Les toca volver** → recordar "Mantenimiento" en 90 días → WhatsApp. |
| **Mayorista** | Barra: Inicio · Pedidos · Clientes · Cobranza. Crea un pedido para "Minimarket Lucía (práctica)" y conviértelo en factura a crédito. | **Crédito por cliente** → fija límite 100 → aparece "Pasó el límite" (primero en la lista). | Precios → precio por mayor; nota de GRE (se emite en SUNAT). |
| **Academia** | Barra: Inicio · Alumnos · Pensiones · Horarios. En la ficha del apoderado llena "Grupo u horario" = "Mañana A" y "Alumno". | Factura recurrente de pensión con vencimiento pasado. | **Pensiones pendientes** → agrupado por "Mañana A" → "Avisar al apoderado". |
| **Construcción** | Barra: Inicio · Obras · Cobrar · Negocio. Crea la obra "Los Pinos" con hitos 3 000 + 2 000. | Factura el primer hito; registra un gasto de 800 en Gastos y luego, en Margen por obra, "Asignar gasto" a Los Pinos. | **Margen por obra** → contratado 5 000, facturado 3 000, gastado 800, te queda 2 200. |

Además (todos): Importar el libro de 1 500 comprobantes en una empresa de prueba y comparar la pantalla final;
Copiloto: preguntar algo que no existe ("¿cuánto le vendí a Pepito Inexistente?") → debe decir que no lo tiene.


## Pruebas de las Fases 7 a 15 (qué debes ver)

Cada una dura 1–2 minutos. Si algo no coincide, mándame captura y el rubro.

| Fase | Rubro | Qué hacer | Qué debe pasar |
|---|---|---|---|
| 7 | Todos | Abre varias pantallas (venta, ganancias, inicio, cobros, ficha de cliente). | Se ven igual que antes: bordes y tarjetas sin cambios. Solo cambió el código. |
| 8 | Restaurante | Mesas → arriba cambia de **Comandas** a **Mesas** (con 2 pedidos de la carta QR de la mesa 4 y 1 de la mesa 2). | Una tarjeta por mesa: platos, pedidos, minutos esperando y el paso más atrasado. Desde 20 min sin estar lista, el tiempo sale en rojo. Los pedidos "para llevar" no salen aquí. |
| 9 | Servicios técnicos | Mensualidades y corte → "Aviso previo" a un abonado con atraso. | Dice "Avisado hoy" y **Registrar corte está apagado**. Para probar el día siguiente sin esperar, en el SQL Editor: `update clients set extra = jsonb_set(extra, '{aviso_corte_fecha}', '"2026-10-29"') where name = 'Abonado Pérez (práctica)';` → recarga: dice "Avisado hace N días" y Registrar corte se enciende. Al reconectar, el aviso se borra. |
| 10 | Salón, consultorio, taller, servicios | Agenda → crea una cita para mañana con un cliente que tenga celular. | Debajo de la cita sale **Confirmar por WhatsApp**; abre el chat con el mensaje (nombre, "mañana", hora). No sale en citas pasadas, terminadas o sin celular. |
| 11 | Taller y servicios técnicos | Abre una orden → pásala a **Listo para recoger** (taller) o **Instalado** (servicios). | Aparece "¿Avisamos a X que ya está listo?" con botón **Avisar** (8 segundos). No sale si el cliente no tiene celular. |
| 12 | Mayorista | Fija límite 1 000 a un cliente que ya deba 800 → factura nueva **Al crédito** de 300 a ese cliente. | Aviso rojo: pasaría el límite por 100 y ya debe 800. Con total de 150 (cerca del 80 %), aviso amarillo. Con cliente sin límite, nada. **No bloquea**: igual puedes guardar. |
| 13 | Academia | Pensiones pendientes → con 2 apoderados de un grupo con atraso distinto. | Cada uno muestra "N días de atraso"; el más atrasado va primero. Tras "Avisar al apoderado" dice "Avisado hoy". |
| 14 | Construcción | Margen por obra → obra con contrato 10 000, facturado 2 000, gastos 5 000. | Texto amarillo: gastado 50 % pero facturado 20 %. Con gastos de 10 000 o más: texto rojo "Ya gastaste 100 % del contrato". Obra sin hitos: sin aviso. |
| 15 | Bodega | Reposición inteligente → baja hasta el final (con un producto con stock y sin ventas en 30 días). | Sección **No se movieron en 30 días** con ese producto y su stock. Productos con stock 0 o sin controlar stock no salen. |

Nota: en las Fases 9, 11, 12 y 13 ninguna función envía mensajes sola; WhatsApp siempre se abre para que tú toques Enviar.


## Prueba de la Fase 21 (tiempo real e instantáneo)

Antes: ejecuta `20261119_v31_tiempo_real.sql` en Supabase.

1. **Inicio** (con la app abierta en el teléfono): desde el panel web o desde otro teléfono crea una venta o registra un cobro → el total del mes, "Hoy" y la lista **cambian solos**, sin deslizar para actualizar.
2. **Clientes / Productos / Fiados / Gastos / Agenda / Caja**: abre uno, sal y vuelve a entrar → aparece **al instante** (sin esqueleto gris). Crea un cliente desde otro dispositivo → aparece en la lista sin tocar nada.
3. **Cambio de empresa**: cambia de empresa y entra a Clientes → solo ves los de la nueva (nunca los de la anterior).
4. **Saludo del Inicio**: en una fila propia, "Buenas tardes" y el nombre completos; debajo, **Copiloto** y **Menú** del mismo ancho. Prueba con letra grande (Ajustes del teléfono → tamaño de fuente).
5. **Fluidez**: el Inicio no debe "esperar" para mostrar bloques; las cifras aparecen ya (no cuentan desde cero) y solo se deslizan cuando cambian.

## Prueba de la Fase 23 (plan del rubro en Ajustes)

1. Ajustes → fila **Mi plan**: debe decir, por ejemplo, `Plan Pro · S/ 59 al mes · Bodega o tienda` (plan de tu licencia, su precio y el rubro elegido).
2. Toca **Mi plan** → arriba tu estado; en **Incluido en tu plan** lo que tu licencia da de verdad; abajo **Planes para <tu rubro>** con 3 tarjetas (Básico S/ 29, Pro S/ 59, Empresa S/ 119):
   - Básico = lo esencial del rubro; Pro = "Todo lo de Básico, más:" (su módulo estrella + Copiloto); Empresa = "Todo lo de Pro, más:" (el resto + Copiloto agente).
   - Tu plan lleva el borde violeta y "Tu plan"; los planes que ya incluyes salen en verde con ✓ y los de arriba en gris con candado.
3. Cambia de rubro (desde el SQL, ver `OPERACION_PRODUCCION.md` §8) y vuelve: las herramientas de cada tarjeta cambian.


## Prueba de las Fases 24 a 28 (producción, tiempo real, arranque)

Antes: en Supabase deben estar aplicadas `20261119`, `20261120` y `20261121` (ya lo están en tu proyecto).
Después de instalar: `dart run tool/post_create.dart`, `flutter clean`, `flutter run --release ...` (reinstala completo).

1. **Arranque**: abre la app, inicia sesión, ciérrala del todo y ábrela otra vez. La **segunda** apertura debe entrar directo a la pantalla principal, sin pantalla gris ni de carga larga. Anota los segundos.
2. **Cerrar sesión** y entrar con OTRA cuenta: no debe verse nada de la cuenta anterior.
3. **Tiempo real (dos dispositivos)**: crea un gasto en uno → **Ganancias**, **Impuestos** y **Gastos** del otro cambian solos. Invita a un miembro → **Equipo** lo muestra. Borra algo → **Papelera** lo muestra.
4. **Abrir al instante**: entra a Facturas, Cobranzas, Cotizaciones, Reportes, Equipo, POS; sal y vuelve → aparecen YA con lo último y se corrigen detrás. Cocina (restaurante): al abrir no vibra por pedidos que ya estaban.
5. **Cambio de empresa**: ninguna pantalla muestra datos de la empresa anterior.


## Prueba de la Fase 33 (vender como en el video)

1. **Abrir la app** (cuenta Bodega): entra directo a la cuadrícula de productos (Vender). Si no tienes productos: **Cargar productos de ejemplo** → aparecen con emoji y precio.
2. **Cobro en un toque**: toca 2 productos → barra de abajo → **Cobrar** → **Efectivo**. Debe abrir el detalle de esa venta como pagada. Con impresora Bluetooth configurada (Ajustes → Impresora) imprime el ticket solo. En Inicio/Cobranzas no debe quedar como deuda.
3. **Más opciones** en Cobrar abre el flujo anterior (cliente, factura, crédito).
4. **Restaurante**: abre en su primera pestaña (Inicio) → pestaña Mesas → **Tomar pedido** → Mesa 4 → 2 platos → **ver detalle** → nota "sin cebolla" → **Comanda** (sin precios) y **Precuenta** (dice NO ES COMPROBANTE). Sin impresora: salen como PDF de rollo.
5. **Pedido por QR** en Comandas: icono de impresora en la tarjeta → imprime la comanda.
6. Cuenta de **técnico** o rubro Servicios/Consultorio/Restaurante: la app abre en su primera pestaña como antes.
7. Cotizaciones, Cuaderno, Tienda y demás siguen en Menú → Otras funciones.
8. **Documento de cada rubro**: Taller → abre una orden → ícono de impresora → *Orden de trabajo* con firma. Servicios técnicos → *Orden de servicio*. Construcción → *Orden de obra*. Salón/Consultorio → abre una cita → *Cita*. Educación → *Horario / clase*. Bodega: no muestra ese botón (usa el ticket de venta).
9. **Aislamiento**: crea un producto en una empresa Bodega, cambia a una empresa de otro rubro (Ajustes → Empresas): ese producto NO aparece.

## Fase 33+ (corrección) — persistencia de comandas desde caja

**Antes:** ejecutar `20261122_v31_comandas_caja_persistentes.sql` en Supabase, tras `20261121`.

1. Restaurante → Mesas → Tomar pedido → Mesa 4 → dos platos con nota → **Guardar y comanda**: persiste con `nuevo` en Comandas aun si falla la impresión.
2. Volver a Comandas: muestra mesa, productos y notas. Avanza a Preparando → Listo → Entregado.
3. **Reimprimir** y **Precuenta** no crean nuevos pedidos. **Nuevo pedido** crea otra ronda.
4. Pedido sin mesa aparece como Para llevar. Cambiar de empresa no muestra los datos de la otra.
5. Cobro vincula factura interna con pedido; una precuenta continúa indicando NO ES COMPROBANTE DE PAGO.
6. Simular desconexión: reintentar sin duplicar. Si falta la RPC, muestra indicación para ejecutar migración 20261122.
