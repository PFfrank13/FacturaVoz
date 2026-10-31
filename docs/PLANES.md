# Planes × rubro (v3)

Los **mismos 3 planes** para todos (Básico, Pro, Empresa; precios propuestos en `docs/facturavoz-planes.json`).
Lo que una persona ve = **funciones de su rubro ∩ funciones de su plan ∩ permisos de su rol**.

- **Núcleo del rubro**: va incluido en TODOS los planes, también en Básico (sin esto el rubro no funciona).
  Lo aplica la base de datos (`private.has_feature` + `private.rubro_core`) y la app (`planHas(…, rubro:)`).
- Lo que el plan no trae **se ve con candado** y dice "Disponible en el plan X"; al tocarlo abre *Mi plan* para mejorar.
- Lo que el rol no permite **no se ve** (y la base de datos igual lo bloquea).
- **Modo desarrollo** (sin Solvex Hub configurado): todo habilitado y marcado como "desarrollo" en *Mi plan*.

## Regla única (v3.1)
Mismos 3 planes y precios para todos los rubros. Lo que cada plan **desbloquea** cambia según el rubro:

- **Básico**: lo esencial del rubro. Siempre: facturar/boletear por voz, clientes, cobros, cotizaciones, reportes, caja y avisos de Yape/Plin.
- **Pro**: Básico + **UN módulo estrella** del rubro (el que más tiempo ahorra) + **Copiloto** (responde y propone con tus datos reales, con voz).
- **Empresa**: **todo** + **Copiloto agente** ("Tareas del Copiloto": le encargas algo, lo prepara y tú lo apruebas) + equipo grande, antifraude, conciliación, API, sucursales.

| Rubro | Básico (esenciales del rubro) | Pro: módulo estrella | Empresa |
|---|---|---|---|
| Bodega | stock, fiados | **Puntos y descuentos a caseros** (fidelización) | todo + agente |
| Restaurante | carta QR, stock | **Reservas y agenda** | todo + agente |
| Servicios técnicos | trabajos, agenda, mensualidades | **Portal del cliente** | todo + agente |
| Salón | agenda | **Comisiones del personal** | todo + agente |
| Consultorio | agenda | **Controles y seguimientos** (recurrentes) | todo + agente |
| Taller | órdenes (trabajos), stock | **Agenda de citas** | todo + agente |
| Mayorista | stock, listas de precios | **Tienda en línea de pedidos** | todo + agente |
| Academia | pensiones (recurrentes), horarios | **Portal de apoderados** | todo + agente |
| Construcción | obras (trabajos) | **Agenda de visitas y avances** | todo + agente |

La tabla está en la base (`private.plan_matrix`) y en la app (`planMatrix`, `rubros.dart`); una prueba exige que sean idénticas.

## Copiloto: Pro vs Empresa
| | Pro | Empresa |
|---|---|---|
| Responde con TUS datos (ventas, deudas, stock, impuestos) | Sí | Sí |
| Voz natural, factura/cotiza/gasto/fiado por voz | Sí | Sí |
| Se adelanta ("Lo que yo haría hoy", riesgos, comparación con el mes pasado) | No | **Sí** |
| **Tareas del Copiloto**: cobranza, lista de reposición, recordatorios, resumen semanal; tú apruebas | No | **Sí** |

Seguridad del agente: lista cerrada de acciones; cifras y mensajes salen de la base (el modelo solo elige qué hacer);
**nada se ejecuta sin tu aprobación**; lo único que escribe son recordatorios; no envía mensajes, no cobra, no emite a SUNAT
y no borra. Cada tarea queda en la bitácora (`agente.proposed/approved/done/rejected`).

## Complementos (add-ons) y Solvex Hub
Las marcas de `facturavoz-planes.json` son la **unión** de lo que cada plan da a algún rubro. Una función que el Hub active
en UNA licencia y que no sea parte del plan estándar se respeta como complemento (ej.: "tienda" para una bodega en Básico).
Pro de un salón con `tienda: true` NO la desbloquea (tienda ya es del Pro de mayoristas, no es un complemento).
Cambios en el Hub: vuelve a cargar `facturavoz-planes.json` (agrega `copiloto_agente`).

Límites por plan (en la base): usuarios (`max_users` 1 / 5 / 20), sucursales (1 / 1 / 5), voz premium por día
(300 / 2 000 / 6 000 caracteres), consultas DNI/RUC por día (60 / 200 / 600 por empresa; 40 por persona).
