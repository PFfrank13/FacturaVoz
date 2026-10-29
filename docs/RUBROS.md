# Rubros de FacturaVoz v3

Investigación hecha el **29/10/2026**. Cada rubro es una app completa: su barra de abajo (4 destinos + micrófono),
sus palabras, su Inicio, su Menú, sus medios de cobro, su comprobante, sus datos de práctica, su Copiloto y su
**función estrella**. Lo que no es del rubro **no se borró**: está en Menú → *Otras funciones* y en el buscador.

> **"Otro / personalizado" ya no existe.** Las empresas que lo tenían ven una pantalla para elegir rubro la próxima vez
> que el dueño abre la app. Hasta que elija, todo sigue funcionando igual que antes (nada se bloquea ni se pierde).
>
> Lo normativo que no es 100 % seguro para cada caso dice **"revisa con tu contador"**. FacturaVoz no da asesoría
> tributaria ni legal.

Definición técnica: `app/lib/rubros.dart` (app) · `private.rubro_core()` en `20261115_v3_rubros.sql` (base) ·
`backend/src/lib/rubro-copilot.ts` (Copiloto). Una prueba automática verifica que app y base digan lo mismo.

---

## 1. Bodega o tienda
| | |
|---|---|
| Barra | Inicio · Vender · 🎙 · Fiados · Caja |
| Palabras | Cliente → **Casero** · Trabajo → Pedido |
| Inicio | Venta rápida · Fiados · Reposición · Caja |
| Cobros (orden) | Efectivo, Yape, Plin, Tarjeta |
| Comprobante | Plantilla *minimal*, ticket de **58 mm** |
| Núcleo (todos los planes) | inventario, fiados, caja, avisos de Yape/Plin |
| ⭐ Función estrella | **Reposición inteligente**: qué se acaba según lo que vendes (últimos 30 días) y cuánto pedir para 1 semana / 2 semanas / 1 mes; arma el pedido para el proveedor por WhatsApp. |
| Copiloto | "¿Cuánto vendí hoy?", "¿Quién me debe más fiado?", "¿Qué se me está acabando?" |

Normas:
- **Nuevo RUS**: solo boletas de venta y tickets (no facturas); categorías hasta S/ 5 000 (cuota S/ 20) y hasta
  S/ 8 000 (cuota S/ 50) de ingresos o compras mensuales. Fuente: [SUNAT – Orientación NRUS](https://orientacion.sunat.gob.pe/node/94). Revisa tu régimen con tu contador.
- **Boletas de más de S/ 700**: deben llevar nombres, apellidos y DNI del comprador. Fuente: [SUNAT – Boleta de venta](https://orientacion.sunat.gob.pe/03-boleta-de-venta).

## 2. Restaurante o cafetería
| | |
|---|---|
| Barra | Inicio · Mesas · 🎙 · Caja · Negocio |
| Palabras | Cliente → Comensal · Producto → Plato · Productos → Carta · Trabajo → Reserva |
| Inicio | Carta QR y comandas · Cuentas y platos · Venta rápida · Caja |
| Cobros | Efectivo, Yape, Plin, Tarjeta |
| Comprobante | *Moderno*, ticket 80 mm |
| Núcleo | carta QR/comandas, caja, inventario |
| ⭐ | **Cuenta dividida, propina y costo por plato**: divide la cuenta entre N (la suma siempre cuadra), separa la propina voluntaria (no entra al comprobante) y ordena los platos por margen (precio sin IGV − costo de insumos). |

Normas:
- **IGV reducido MYPE restaurantes/hoteles (Ley 32219, modifica Ley 31556)**: 8 % de IGV (+2 % IPM = 10 %) en 2025 y
  2026; 12 % (+2 % IPM = 14 %) en 2027. Requisitos (MYPE, ≥ 70 % de ingresos de la actividad, sin vinculación que
  supere el tope): **revisa con tu contador**. Fuente: [El Peruano – Ley 32219](https://busquedas.elperuano.pe/dispositivo/NL/2357993-3).
- Propina: es del personal y es voluntaria; el "recargo al consumo" es otra figura. **Revisa con tu contador** cómo
  declararla. Referencia: [LP Derecho – recargo al consumo](https://lpderecho.pe/recargo-consumo-propina-camuflada-obligatoria-restaurantes-hoteles/).

## 3. Servicios técnicos e internet / instalaciones
| | |
|---|---|
| Barra | Inicio · Trabajos · 🎙 · Abonados · Cobrar |
| Palabras | Cliente → **Abonado** · Trabajo → Instalación |
| Inicio | Trabajos (tablero) · Mensualidades y corte · Facturación recurrente · Agenda |
| Cobros | Yape, Plin, Transferencia, Efectivo |
| Núcleo | trabajos, agenda, facturación recurrente |
| ⭐ | **Mensualidades y corte por mora**: quién no pagó y cuántos días lleva, **aviso previo** por WhatsApp con un toque, registro de **corte** y **reconexión** (queda en la ficha del abonado). Equipos con número de serie ya existían en la ficha. |

Normas:
- Operadores registrados: las condiciones de uso de OSIPTEL exigen **avisar antes de suspender** por falta de pago.
  La app siempre propone el aviso previo antes del corte. Revisa tu caso con tu asesor. Referencia (antecedente
  2020): [Infomercado – Osiptel](https://infomercado.pe/operadoras-deben-informar-a-los-usuarios-antes-de-suspender-servicios-bs/).
- **Detracción** "demás servicios gravados" 12 % en operaciones de más de S/ 700. Fuente: [SUNAT – Detracciones](https://emprender.sunat.gob.pe/principales-impuestos/impuesto-general-las-ventas-igv/sistema-detracciones-igv), tasas: [kom.pe (2026)](https://kom.pe/calculadora-detracciones/). Revisa con tu contador.

## 4. Salón o barbería
| | |
|---|---|
| Barra | Inicio · Citas · 🎙 · Clientes · Caja |
| Palabras | Trabajo → Cita · Producto → Servicio |
| Inicio | Agenda · Paquetes y sesiones · Venta rápida · Comisiones |
| Núcleo | agenda, caja |
| ⭐ | **Paquetes, no-shows y comisiones**: vende paquetes de N sesiones, descuenta cada visita (la base no deja "devolver" sesiones a mano), ranking de quién faltó a sus citas (90 días) y comisiones por estilista. |

Normas: comisiones a estilistas (planilla o recibo por honorarios): **revisa con tu contador**.

## 5. Consultorio o profesional independiente
| | |
|---|---|
| Barra | Inicio · Agenda · 🎙 · Pacientes · Cobrar |
| Palabras | Cliente → **Paciente** · Trabajo → Cita |
| Inicio | Agenda · Historial privado · Paquetes · Cobranza |
| Núcleo | agenda |
| ⭐ | **Historial privado**: notas por paciente que **solo ve quien las escribe y el dueño/admin** (RLS en la base). No se pueden editar (se agrega otra), **no las lee el Copiloto**, no salen en reportes ni exportaciones, y la app **pide registrar el consentimiento firmado** antes de la primera nota. |

Normas:
- Datos de salud = **datos sensibles** (Ley 29733): requieren **consentimiento por escrito**; medidas de seguridad y
  confidencialidad. Referencia: [DPL News – Directiva Minsa sobre datos de salud](https://dplnews.com/fijan-criterios-para-el-tratamiento-de-los-datos-personales-en-salud/).
- Profesionales de 4.ª categoría emiten **recibo por honorarios** en SUNAT; retención de 8 % si el recibo supera
  S/ 1 500; suspensión de retenciones si proyectas menos de S/ 48 125 (2026). Fuente: [Infobae (21/06/2026)](https://www.infobae.com/peru/2026/06/21/suspension-de-cuarta-categoria-quienes-pueden-pedirla-y-como-hacerlo/). Revisa con tu contador.

## 6. Taller mecánico
| | |
|---|---|
| Barra | Inicio · Órdenes · 🎙 · Clientes · Cobrar |
| Palabras | Trabajo → **Orden** · Producto → Repuesto o servicio |
| Inicio | Buscar por placa · Órdenes · Les toca volver · Cotizaciones |
| Núcleo | trabajos, cotizaciones, inventario |
| ⭐ | **Buscar por placa** (escrita o dictada): el carro, su dueño y su historial; si no existe, se registra en 2 toques. **Les toca volver**: recordatorios de mantenimiento con aviso por WhatsApp. Presupuesto con fotos: ya existía (fotos del trabajo + cotización por WhatsApp). |

Normas: mantenimiento y reparación de bienes muebles: detracción 12 % (> S/ 700). Revisa con tu contador.

## 7. Mayorista o distribuidor
| | |
|---|---|
| Barra | Inicio · Pedidos · 🎙 · Clientes · Cobranza |
| Inicio | Cotizaciones y pedidos · Crédito por cliente · Cobranza · Precios |
| Núcleo | cotizaciones, inventario, listas de precios |
| ⭐ | **Crédito con límite**: cuánto debe cada cliente, su límite, cuánto le queda, quién se pasó (primero). Pedidos recurrentes = facturación recurrente; listas de precios por mayor ya existían. |

Normas:
- **Guía de remisión**: debe ser **electrónica (GRE)**. El periodo sin sanciones para guías físicas del remitente
  terminó el 31/08/2026 (transportista: hasta 28/02/2027). Fuente: [B&B Consultores – RS 000031-2026](https://bybconsultores.pe/comprobantes-de-pago/sunat-amplia-periodo-inaplicacion-sanciones-guias-remision-fisicas-gre/).
  **FacturaVoz aún no emite GRE**: hazla gratis en SUNAT y anota su número en el pedido (ver Hoja de ruta).
- Agentes de retención: 3 % del IGV en facturas > S/ 700. Revisa con tu contador.

## 8. Academia o educación
| | |
|---|---|
| Barra | Inicio · Alumnos · 🎙 · Pensiones · Horarios |
| Palabras | Cliente → **Alumno o apoderado** · Trabajo → Matrícula · Producto → Curso |
| Inicio | Pensiones pendientes · Facturación recurrente · Agenda · Cobranza |
| Núcleo | facturación recurrente, agenda |
| ⭐ | **Morosidad por grupo**: deudas de pensiones agrupadas por "Grupo u horario" (dato del alumno), con aviso al apoderado por WhatsApp. |

Normas: algunos servicios educativos pueden estar exonerados o inafectos de IGV según quién los presta y si están
dentro del sistema educativo (Ley General de Educación). No encontramos una regla general para academias
preuniversitarias: **revisa con tu contador antes de emitir**. Referencia: [SUNAT – Informe 013-2018](https://www.sunat.gob.pe/legislacion/oficios/2018/informe-oficios/i013-2018-7T0000.pdf).

## 9. Construcción o contratista
| | |
|---|---|
| Barra | Inicio · Obras · 🎙 · Cobrar · Negocio |
| Palabras | Trabajo → **Obra** · Producto → Partida o material |
| Inicio | Obras · Margen por obra · Cotizaciones · Gastos |
| Núcleo | trabajos, cotizaciones |
| ⭐ | **Margen por obra**: contratado (suma de hitos / valorizaciones), facturado, gastado (gastos y subcontratistas asignados a la obra — columna nueva `expenses.job_id`) y lo que de verdad queda. |

Normas: **contratos de construcción: detracción 4 %** en operaciones de más de S/ 700 (Anexo 3 del SPOT). Fuentes:
[SUNAT](https://emprender.sunat.gob.pe/principales-impuestos/impuesto-general-las-ventas-igv/sistema-detracciones-igv), [kom.pe (vigente 2026)](https://kom.pe/calculadora-detracciones/). Revisa con tu contador.

---

## Tienda en línea (todos los rubros)
Desde la Ley 32495 las plataformas de comercio electrónico deben tener **Libro de Reclamaciones**. Referencia:
[LP Derecho – Ley 32495](https://lpderecho.pe/ley-32495-plataformas-digitales-comercio-electronico-libro-reclamaciones/). La tienda aún no trae un libro de reclamaciones virtual: está en la Hoja de ruta (revisa con tu asesor mientras tanto).
