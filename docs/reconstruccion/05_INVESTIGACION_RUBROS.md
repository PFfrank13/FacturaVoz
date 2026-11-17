# Investigación por rubro (Prompt Maestro §8, §9)

Para cada rubro: cómo es su día, qué hace cada persona, qué exige la norma peruana y qué tiene FacturaVoz hoy.
Las normas citadas tienen fuente al final. Lo que no tiene fuente es práctica operativa de negocios pequeños
y medianos (no es una norma) y está marcado como tal. **No es asesoría legal**: lo dudoso dice "revisa con tu contador".

## Normas que valen para los nueve rubros
| Tema | Qué exige | Qué hace FacturaVoz |
|---|---|---|
| Comprobantes electrónicos (SUNAT) | Boletas y facturas electrónicas. La anulación de boletas se informa con resumen diario de baja; la RS 000048‑2026 fija **7 días calendario** para esa baja y lleva las notas de crédito/débito a una relación **uno a uno** con el comprobante en SEE‑OSE. Vigencia postergada al **1 de enero de 2027** [1]. | Emite con Greenter/Lycet. Hoy las notas ya son una por comprobante. Pendiente: resumen diario de baja (ya figuraba en la hoja de ruta). |
| Libro de Reclamaciones (Indecopi) | Obligatorio en los establecimientos y, con la Ley 32495, también en tiendas y plataformas en línea; Indecopi ofrece una herramienta gratuita [2][3]. | Pendiente: libro virtual para la tienda en línea (en la hoja de ruta). |
| Datos personales (Ley 29733 y su nuevo reglamento, DS 016‑2024‑JUS) | Consentimiento, finalidad, seguridad, registro de bancos de datos; reglas reforzadas para datos sensibles (salud) y de menores [4][5]. | RLS por empresa (0 fugas en 57 tablas, prueba `test_v3_rls_audit`); historial privado en consultorio; documento `PRIVACIDAD_Y_TERMINOS.md`. Falta: acceso a datos de alumnos por grupo (educación). |

## Matriz por rubro

### Bodega / tienda
| Pregunta | Respuesta |
|---|---|
| Inicio de jornada | Abrir caja con sencillo, revisar lo que falta en anaquel (práctica operativa). |
| Operaciones | Venta rápida con escáner o búsqueda, fiado a vecinos conocidos, reposición con proveedores que pasan por la tienda. |
| Quién trabaja | Dueño (casi siempre en caja), a veces un cajero o familiar; en tiendas medianas, un almacenero. |
| Cobro | Efectivo y Yape/Plin (la confirmación es visual, por eso la app pide "He verificado el abono"). |
| Excepciones | Producto sin código, venta sin stock registrado (no se bloquea la venta: el stock queda negativo y se corrige con ajuste), devolución. |
| Cierre | Arqueo de efectivo, comparación con lo vendido, fiados del día. |
| Indispensable (Básico) | Venta, comprobante, caja, fiados, inventario, compras, reportes. **Ya en la matriz real.** |
| Pro | Fidelización (módulo estrella) + Copiloto. |
| Empresa | Multisucursal, antifraude, conciliación, API. |
| Interfaz más rápida | VENDER siempre visible; carrito → cobro en dos toques; buscador y escáner en la misma pantalla. |

### Restaurante
| Pregunta | Respuesta |
|---|---|
| Operación | Mesas y zonas, carta (QR), comanda a cocina, cuenta dividida, propina, cierre de caja. |
| Roles | Mesero (toma pedidos), cocinero (ve comandas), cajero, encargado de salón. **Cocinero no existe como rol base**: hoy se aproxima con Vendedor (marcado ⚠). |
| Norma | Comprobante por consumo; los precios de la carta deben incluir impuestos y cargos (Código de Protección al Consumidor, Ley 29571; revisa con tu contador si cobras recargo). |
| FacturaVoz hoy | Carta QR y comandas, cuenta dividida y costo por plato. Falta: estados de comanda por cocinero sin permiso de venta. |

### Servicios técnicos / internet
| Pregunta | Respuesta |
|---|---|
| Operación | Solicitud → cliente → diagnóstico → cotización → orden → técnico → ejecución con fotos → cobro → seguimiento; mensualidades a abonados. |
| Norma | Si es un proveedor de internet, la suspensión por falta de pago sigue las condiciones de uso de OSIPTEL, que exigen **informar al abonado antes de suspender** [6][7]. La app ya tiene "aviso previo, corte y reconexión". |
| Roles | Técnico/instalador (solo sus órdenes: la base ya lo hace con `my_tech_org_ids`), supervisor, cobranza. |

### Salón / barbería
| Operación | Agenda con duración por servicio, evitar doble reserva, señas, paquetes de sesiones, no‑shows, comisiones por estilista. |
|---|---|
| Roles | Barbero/estilista (su agenda y comisiones), recepcionista (agenda y cobro). |
| FacturaVoz hoy | Agenda, paquetes con no‑shows, comisiones en Pro (módulo estrella). |

### Consultorio
| Operación | Citas, atención, historial clínico separado de lo administrativo, cobro y comprobante. |
|---|---|
| Norma | La historia clínica se rige por la **NTS 139‑MINSA/2018** (gestión, custodia y confidencialidad) [8]; los datos de salud son sensibles para la Ley 29733 [4]. |
| FacturaVoz hoy | Historial privado por autor; el Copiloto nunca habla de diagnósticos. **No es un sistema de historia clínica**: no debe presentarse como tal sin cumplir la NTS 139. Rol "Profesional de salud" marcado ⚠ (ver sus pacientes, no los de otros). |

### Taller mecánico (§9.6)
| Operación | Recepción del vehículo → búsqueda por placa → diagnóstico → presupuesto → aprobación del cliente → asignación a mecánico → reparación → consumo de repuestos → revisión → entrega → cobro → seguimiento. |
|---|---|
| Roles | Asesor de servicio (recibe y cotiza), mecánico (sus órdenes), jefe de taller (supervisa ⚠), almacenero de repuestos (⚠), cajero. |
| Básico (matriz real) | Órdenes (trabajos), clientes, vehículos (búsqueda por placa), cotizaciones, cobros, stock de repuestos. |
| Pro | Agenda (módulo estrella) + Copiloto. Recordatorios de mantenimiento ("Les toca volver"). |
| Empresa | Multisucursal, auditoría (bitácora), integraciones (API). |

### Mayorista / distribuidor (§9.7)
| Operación | Cliente → lista de precios por volumen → pedido → validación de stock y crédito → preparación → entrega → factura → cobranza. |
|---|---|
| Norma | El traslado de mercadería requiere **guía de remisión electrónica**; la RS 000108‑2026 (vigente desde el 1‑6‑2026) ajustó reglas del remitente, sobre todo en comercio exterior [9][10]. |
| FacturaVoz hoy | Pedidos (cotizaciones), precios por mayor, crédito con límite por cliente, cobranza. **Falta emitir la GRE desde la app** (hoy se emite en SUNAT y se anota). Despachador marcado ⚠. |

### Educación / academia (§9.8)
| Operación | Prospecto → inscripción → matrícula → grupo → clases → pensiones → cobranza → reportes → renovación. |
|---|---|
| Separación | Académico (coordinador, docente) separado de lo administrativo y financiero (recepción, administrativo, cajero): ya en la matriz de roles. |
| Norma | Datos de menores requieren el consentimiento de padres o tutores bajo el nuevo reglamento de la Ley 29733 [4][5]. |
| FacturaVoz hoy | Pensiones por grupo y aviso al apoderado. **Falta**: acceso del docente solo a sus grupos (⚠, necesita migración). |

### Construcción / contratista (§9.9)
| Operación | Cliente → presupuesto → aprobación → obra → hitos → materiales → trabajadores → avances → valorizaciones → cobros → cierre. |
|---|---|
| Roles | Jefe de obra (sus obras ⚠), supervisor y operario (sus tareas: rol técnico), compras (⚠), finanzas. |
| FacturaVoz hoy | Obras como trabajos, hitos, gastos asignados a obra y margen por obra. |

## Qué cambió en el código por esta investigación
- Los roles que la base no cubre quedaron como roles aproximados (⚠) con la diferencia escrita, en vez de inventar permisos (`nav/role_matrix.dart`).
- Bodega: la venta sin stock no se bloquea (coincide con la migración 20261128 y con la práctica de mostrador).
- Consultorio: no se presenta como historia clínica.

## Fuentes
1. Sovos — RS N.° 000048‑2026/SUNAT, boletas de venta electrónicas: https://sovos.com/es/cambios-regulatorios/iva/peru-boleta-venta-electronica-rs-000048-2026-sunat/
2. Indecopi — Comercios electrónicos obligados a contar con Libro de Reclamaciones: https://www.gob.pe/institucion/indecopi/noticias/1286430-comercios-electronicos-tambien-estan-obligados-a-contar-con-libro-de-reclamaciones-activo-y-visible
3. LP Derecho — Ley 32495, plataformas digitales y libro de reclamaciones: https://lpderecho.pe/ley-32495-plataformas-digitales-comercio-electronico-libro-reclamaciones/
4. MINJUSDH — Nuevo reglamento de la Ley de Protección de Datos Personales: https://www.gob.pe/institucion/minjus/noticias/1067368-ejecutivo-aprueba-nuevo-reglamento-de-la-ley-de-proteccion-de-datos-personales
5. DS 016‑2024‑JUS (texto): https://www.congreso.gob.pe/Docs/DGP/DIDP/files/ds_016-2024-jus.pdf
6. OSIPTEL — Nota de prensa sobre suspensión gradual por falta de pago: https://www.osiptel.gob.pe/media/vljduzzf/np-osiptel-habilito-suspension-gradual-falta-pago.pdf
7. Infomercado — Operadoras deben informar antes de suspender servicios: https://infomercado.pe/operadoras-deben-informar-a-los-usuarios-antes-de-suspender-servicios-bs/
8. El Peruano — NTS N.° 139‑MINSA/2018/DGAIN, Gestión de la Historia Clínica: https://busquedas.elperuano.pe/dispositivo/NL/1626125-1
9. SUNAT — RS N.° 000108‑2026/SUNAT: https://www.sunat.gob.pe/legislacion/superin/2026/000108-2026.pdf
10. ByB Consultores — Análisis de la RS 000108‑2026: https://bybconsultores.pe/?p=11575
