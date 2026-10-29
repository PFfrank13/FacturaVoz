# Guía de pruebas en 15 minutos

Usa un teléfono Android con la app recién instalada y SUNAT en modo **beta** (pruebas). Marca ✅ o ❌ y anota qué pasó.

## 0. Preparación (2 min)
1. Ejecuta en Supabase las migraciones `20261104` a `20261112` en orden (ver `CAMBIOS_v2.0.md`).
2. Sube el backend a Vercel. Sin variables de Solvex Hub la app queda en **modo desarrollo** (todo habilitado).
3. Crea una cuenta nueva con correo y contraseña.

## A. Bodega (7 min)
| # | Paso | Esperado |
|---|---|---|
| A1 | Completa tus datos; en "Documento fiscal" escribe tu RUC y toca 🔎 | Se completan razón social y dirección (si hay proveedor DNI/RUC configurado; si no, mensaje claro y escribes a mano) |
| A2 | Presentación: elige **Bodega o tienda** y **Simple** | Barra: Vender · Clientes · 🎙 · Cobrar · Ajustes |
| A3 | Ajustes → Productos: crea "Arroz 1 kg" con precio, **foto** y **código de barras** (escanéalo) | Si activas "Mostrar en la tienda" sin foto o sin código, no te deja guardar y explica por qué |
| A4 | Vender → Venta rápida: toca Arroz 2 veces, escanea el código otra vez | Carrito con 3; total con IGV abajo |
| A5 | Toca **Cobrar** → revisa y guarda → **Emitir a SUNAT** (boleta, cliente sin RUC) | Número tipo **B001-00000001** grande; debajo "N.° interno …" |
| A6 | En el comprobante toca **Ticket** (impresora en PDF o Bluetooth) | Ticket 58/80 mm con tu logo, QR, "Valor resumen" y forma de pago |
| A7 | Cobrar → Fiados → "Anotar fiado": Rosa, 30, "arroz" | Rosa aparece con S/ 30; desliza → Abono |
| A8 | Mantén presionado el 🎙 y di: "anota que Rosa me debe 20 de azúcar" | El copiloto propone "Confirmar el fiado" y abre la hoja ya llena |
| A9 | Cobrar → Avisos de Yape: pega "¡Yape! ROSA QUISPE te envió un pago por S/ 50.00…" | Lee monto y nombre; si hay factura con ese saldo, ofrece registrarla |
| A10 | Cobrar → Caja del día: Apertura 100 → Cerrar caja contando 150 | Muestra si sobra/falta; llega correo (si Resend está configurado) |
| A11 | Inicio (modo completo) y Negocio | "Vendido este mes" (con IGV) e Inicio y Negocio cuentan las MISMAS ventas (Negocio sin IGV); borradores aparecen aparte |
| A12 | Negocio sin ventas en una empresa nueva | NO aparece "caja negativa"; aparece el mensaje de estado vacío |

## B. Servicio técnico WiFi (6 min)
| # | Paso | Esperado |
|---|---|---|
| B1 | Ajustes → Tu negocio → Tipo de negocio → **Servicios técnicos e instalaciones** | Pasos: Interesado → Visita → Cotizado → Pendiente → En camino → Instalado → Cobrado |
| B2 | Clientes → + : escribe un DNI y toca 🔎; guarda | Ficha 360 con botones Facturar · Cotizar · Cobrar · Agendar · WhatsApp |
| B3 | En la ficha: "Guardar ubicación" → "Estoy aquí" | Mapa con el punto y botón "Cómo llegar" |
| B4 | Agendar: "Instalar 200 Mbps" para mañana 10:00 | Aparece en Agenda y en "Para hoy" mañana |
| B5 | Ajustes → Equipo → Invitar `tecnico@…` como **Técnico** | Queda la invitación pendiente |
| B6 | En otro teléfono: "Iniciar con Empresa" → "Es mi primera vez" con ese correo | Bienvenida animada con su nombre, empresa y rol; solo ve Mis trabajos, Agenda, Clientes, Ajustes |
| B7 | Asigna el trabajo al técnico (ficha del trabajo → responsable) | El técnico lo ve; no ve otros trabajos ni montos de la empresa |
| B8 | Técnico: "Voy en camino", foto Antes/Después, material "Router" 1 | Estado cambia a En camino; fotos y materiales guardados |
| B9 | Dueño: arrastra el trabajo a **Instalado** y toca "Descontar del stock" | Stock del router baja 1; historial de estados |
| B10 | "Facturar" desde el trabajo | Factura con el servicio y materiales; queda enlazada al trabajo |

## C. Seguridad y licencias (2 min)
| # | Paso | Esperado |
|---|---|---|
| C1 | Ajustes → Dueño a distancia → PIN 1234 | Cajero que intenta anular una boleta debe escribir el PIN |
| C2 | Borra un cliente → toca **Deshacer** | Vuelve; también está en Ajustes → Papelera |
| C3 | Con Solvex Hub configurado: Mi plan → "Activar mi prueba de 3 días" | Plan EMPRESA de prueba; repetir con el mismo RUC → "ya usó su prueba" |
| C4 | Ajustes → Animaciones → Reducidas | Todo se mueve sin animaciones (también si el teléfono es lento y está en Automático) |

Si algo falla, anota: pantalla, qué tocaste y el mensaje (los códigos entre paréntesis ayudan a soporte).
