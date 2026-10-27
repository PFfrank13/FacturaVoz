# FacturaVoz v1.2 · "Revolución"

Objetivo: que el pequeño negocio **venda más, cobre más rápido y no pierda clientes**, sin trabajo extra.
Todo sigue sin costo fijo (Supabase, Vercel Hobby, Groq y Resend en plan gratis).

## 1. Funciones nuevas

| Función | Qué resuelve | Cómo funciona |
|---|---|---|
| **Tienda en línea con pedidos** | Vender por WhatsApp/Instagram sin anotar pedidos a mano | `/tienda/<tu-negocio>`: catálogo con precios con IGV y carrito. El cliente deja nombre y celular → llega a la app **en vivo** como cotización "Pedido web" (celebración + aviso por correo) → 1 toque para confirmar por WhatsApp y 1 toque para convertir en factura. Los precios los pone la base de datos, nunca el navegador. Antispam: 30 pedidos/hora por tienda y 3 por celular. |
| **Facturación recurrente** | Alquileres, mensualidades y mantenimientos que se olvidan facturar | Programa una vez (cliente, líneas, día del mes, crédito). Cada mes se crea sola como borrador (pg_cron 6:00 Lima, y también al abrir la pantalla). Si la app estuvo apagada meses, crea una sola y salta a la próxima fecha. Si una plantilla tiene datos malos, no deja facturas a medias y muestra "Revisar datos". También desde una factura: **"Facturar esto cada mes"**. |
| **Clientes 360** | Clientes que dejan de comprar sin que nadie lo note | Calcula cada cuántos días compra cada cliente y lo clasifica: **VIP, Fiel, Se está yendo, Perdido, Nuevo, Ocasional**. Muestra las **ventas en riesgo** y el % que aportan los VIP. Botón **"Recuperarlo"** abre WhatsApp con un mensaje cálido ya escrito, o prepara una cotización. |
| **Meta del mes con predicción** | Saber a mitad de mes si se llegará | Anillo de meta en Inicio: % logrado, **proyección de cierre al ritmo actual** y **cuánto vender por día** para llegar. Sugiere metas realistas (+10 % y +25 % sobre la proyección). |
| **Calculadora de margen** | Vender a pérdida sin saberlo | En cada producto: costo → margen real al instante (rojo si < 15 %), botones "Precio para 30/40/50 % de margen" y margen visible en el catálogo. |
| **Plan de rescate de caja con IA** | Qué hacer cuando falta plata | Si la proyección de caja sale negativa, un botón pide al Copiloto un plan de 3 pasos con nombres y montos: a quién cobrar primero, a qué cliente que se va escribir hoy y qué gasto postergar. |
| **Copiloto más inteligente** | — | Ahora conoce la meta, la proyección, los clientes en riesgo y los mejores clientes. Nuevas preguntas: "¿Llegaré a mi meta?", "¿Qué clientes están dejando de comprarme?", "Dame un plan de rescate". |

## 2. Interfaz
- **Inicio rediseñado**: cabecera "aurora" (luces que flotan suavemente), total del mes, **anillo de meta**, píldoras de proyección y **tendencia de 14 días** que se dibuja sola.
- **Accesos rápidos** con rebote y contadores: Facturar · Cotizar · Escanear · Gasto · Tienda (pedidos nuevos) · Clientes · Mensuales (borradores listos) · Copiloto.
- Avisos del día nuevos: **pedidos web nuevos** y **facturas mensuales listas**.
- Cotizaciones: filtro y etiqueta **"Pedido web"**, celebración en vivo al llegar un pedido y botón para confirmar al cliente por WhatsApp.
- Nuevos componentes reutilizables: `Aurora`, `Sparkline`, `QuickAction`, `TagChip` (en `ui/motion.dart`).

## 3. Cómo integrarlo
1. Supabase → SQL Editor → **`backend/supabase/migrations/20261102_revolucion.sql`** (requiere la 20261101).
   Si tienes pg_cron activo, programa sola la facturación recurrente diaria.
2. Copia el proyecto → `git push` (Vercel publica `/tienda/<slug>` y `/api/public/order`; no hay variables nuevas).
3. App: `flutter pub get` y luego, en PowerShell: `flutter analyze; flutter test`.
4. En la app: Ajustes → **Tienda en línea** → Abrir tienda → Compartir.

## 4. Verificación hecha
- Migración aplicada sobre réplica de PostgreSQL 16 con todas las anteriores (dos veces: idempotente).
  Probado como usuarios reales: pedido web con precio manipulado (se ignora y usa el de la base), producto oculto y de otra empresa
  (rechazados), celular inválido, tienda inexistente, límite por celular; recurrente atrasada 70 días (una sola factura, fecha de
  Lima, crédito correcto), plantilla con datos malos (sin factura a medias, error registrado, las demás siguen), meta solo para admin,
  aislamiento total entre empresas en tienda, recurrentes y actividad de clientes.
- Backend: 55 pruebas pasan (nueva: meta + clientes en riesgo del Copiloto) y verificación de tipos de las rutas nuevas.
- App: `test/growth_test.dart` (meta, tendencia, segmentación, precios, fechas, slug) además de las anteriores.
  ⚠️ Ejecuta `flutter analyze; flutter test` en tu PC: aquí no hay SDK de Flutter.
