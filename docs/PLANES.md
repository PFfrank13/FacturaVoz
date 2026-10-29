# Planes × rubro (v3)

Los **mismos 3 planes** para todos (Básico, Pro, Empresa; precios propuestos en `docs/facturavoz-planes.json`).
Lo que una persona ve = **funciones de su rubro ∩ funciones de su plan ∩ permisos de su rol**.

- **Núcleo del rubro**: va incluido en TODOS los planes, también en Básico (sin esto el rubro no funciona).
  Lo aplica la base de datos (`private.has_feature` + `private.rubro_core`) y la app (`planHas(…, rubro:)`).
- Lo que el plan no trae **se ve con candado** y dice "Disponible en el plan X"; al tocarlo abre *Mi plan* para mejorar.
- Lo que el rol no permite **no se ve** (y la base de datos igual lo bloquea).
- **Modo desarrollo** (sin Solvex Hub configurado): todo habilitado y marcado como "desarrollo" en *Mi plan*.

## Siempre incluido (todos los rubros, todos los planes)
Facturar/boletear por voz, clientes, cobros, reportes, caja, fiados, avisos de Yape/Plin, inventario, cotizaciones,
libro de Excel (importador) y "Les toca volver". El **Copiloto** (y su voz premium) es de Pro y Empresa.

## Matriz

| Rubro | Básico (núcleo) | Pro (paquete principal del rubro) | Empresa (todo) |
|---|---|---|---|
| Bodega | Venta rápida, fiados, caja, inventario, **reposición inteligente**, avisos Yape/Plin | + tienda en línea, puntos, precios y promociones, cuaderno→factura, Copiloto | + equipo hasta 20, PIN/alertas del dueño, conciliación bancaria, API, sucursales |
| Restaurante | Carta QR y comandas, **cuentas y costo por plato**, caja, inventario | + reservas (agenda), encuestas, puntos, tienda, Copiloto | + equipo, antifraude, conciliación, API |
| Servicios técnicos | Trabajos, agenda, mensualidades, **corte por mora** | + portal del cliente, cuaderno, Copiloto, comisiones | + equipo de técnicos (hasta 20), antifraude, conciliación, API |
| Salón | Agenda, caja, **paquetes y no-shows**, recordatorios | + comisiones, puntos, encuestas, tienda, Copiloto | + equipo, antifraude |
| Consultorio | Agenda, **historial privado**, paquetes | + recurrentes, portal, encuestas, Copiloto | + equipo, antifraude, conciliación |
| Taller | Órdenes (trabajos), cotizaciones, inventario, **buscar por placa**, recordatorios | + agenda, portal, Copiloto | + equipo, antifraude, conciliación, API |
| Mayorista | Pedidos, inventario, listas de precios, **crédito con límite** | + tienda, recurrentes, comisiones, multimoneda, Copiloto | + **API y webhooks**, conciliación, antifraude, sucursales |
| Academia | Mensualidades, horarios (agenda), **pensiones pendientes**, paquetes | + portal de apoderados, encuestas, Copiloto | + equipo, conciliación |
| Construcción | Obras (trabajos), cotizaciones, **margen por obra** | + agenda, recurrentes, Copiloto | + conciliación, antifraude, equipo |

Límites por plan (en la base): usuarios (`max_users` 1 / 5 / 20), sucursales (1 / 1 / 5), voz premium por día
(300 / 2 000 / 6 000 caracteres), consultas DNI/RUC por día (60 / 200 / 600 por empresa; 40 por persona).

## Complementos (add-ons) por licencia
El Hub puede encender cualquier función suelta en la licencia de una empresa (`features.<clave> = true`), sin cambiar de
plan: p. ej. "tienda" para una bodega en Básico. La app y la base leen la misma licencia.

## Qué cambiar en Solvex Hub
Nada obligatorio: las claves de funciones no cambiaron. El núcleo por rubro se resuelve en FacturaVoz.
