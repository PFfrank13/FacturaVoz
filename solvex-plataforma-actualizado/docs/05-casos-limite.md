# 5. Casos posibles e "imposibles": qué hace el sistema

Cada fila está cubierta por el código; las marcadas con ✔ tienen además prueba automática (`hub/test/`).

## Cobros y pagos

| Situación | Qué pasa |
|---|---|
| El cliente paga con tarjeta/Yape (Culqi) desde su enlace ✔ | El Hub cobra el monto que dice la base (nunca el del navegador), aprueba, emite recibo, extiende la licencia y avisa al producto en segundos. |
| El mismo enlace se usa dos veces o dos personas pagan a la vez ✔ | Un solo cobro en proceso por enlace; si el cobro ya está pagado, se responde "ya pagado". |
| Culqi cobra pero el navegador del cliente se cierra antes de la respuesta | El webhook de Culqi llega igual; el Hub consulta el cargo en la API de Culqi y lo aplica. |
| Llega un aviso falso de Culqi ✔ | Se ignora: el Hub solo cree lo que confirma la API de Culqi con su llave secreta. |
| Culqi reenvía el mismo aviso ✔ | Idempotente: el id del evento y el id del cargo son únicos. |
| Reembolso o contracargo en Culqi ✔ | El pago pasa a "reembolsado" y se revierte la vigencia (puede volver a gracia o corte). La conciliación horaria lo detecta aunque no llegue el aviso. |
| El cliente reporta un Yape desde su enlace ✔ | Queda "por verificar"; Finanzas confirma en su app y aprueba → reactivación al instante. |
| Reportan el mismo número de operación dos veces ✔ | Rechazado: el número de operación es único por medio de pago (salvo que el anterior se haya rechazado). |
| Paga menos de la cuota ✔ | Cobro "parcial", no extiende; cuando completa, extiende. |
| Paga de más ✔ | El excedente queda como saldo a favor y se aplica solo al siguiente cobro. |
| Paga un cobro ya pagado o anulado | El dinero queda como saldo a favor y aparece una alerta para revisar o reembolsar. |
| Paga una licencia cancelada | No se reactiva; el pago se registra y se avisa para decidir (reembolso o reapertura). |
| Se aprueba un pago por error ✔ | "Anular" (con confirmación 2FA y motivo): se revierte la vigencia; el pago queda en el historial. Nunca se borra. |
| Quien registra un pago intenta aprobarlo (con cuatro ojos activo) ✔ | Bloqueado; otra persona con permiso debe aprobarlo. |
| Se cambia el precio del plan | Las licencias existentes conservan su precio (se copia al crearlas). Para cambiar a un cliente, se edita su licencia (permiso de Finanzas). |
| Se anula un cobro que tenía saldo a favor aplicado | El saldo vuelve al cliente. |
| El equipo anula a propósito un cobro de renovación | No se vuelve a emitir solo para ese ciclo. |

## Vigencia, corte y reactivación

| Situación | Qué pasa |
|---|---|
| Vence a medianoche en Lima ✔ | Funciona hasta las 23:59:59 hora de Lima del último día pagado (no a las 19:00 por UTC). |
| Mensual que empezó un 31 ✔ | Renueva el 28/29 en febrero y vuelve al 31 en marzo (día ancla). |
| Paga durante la gracia ✔ | Continúa desde el vencimiento: no se regalan ni se pierden días. |
| Paga ya cortado ✔ | Se reactiva y el ciclo empieza el día del pago (o "continuar", si así lo configuras). |
| Termina la prueba sin pago ✔ | Corte directo (la prueba no tiene gracia). Al pagar, se activa. |
| Se le dio una extensión en días y luego paga ✔ | El ciclo pagado dura completo (el día ancla se ajusta). |
| Suspensión manual y luego paga ✔ | Se extienden las fechas pero sigue suspendida hasta que una persona la levante. |
| Licencia sin corte automático | Queda en "gracia" indefinidamente, visible en el tablero como deuda. |
| El servidor del Hub estuvo apagado 2 días | Al volver, el estado se calcula con las fechas: los cortes y reactivaciones correctos se registran y avisan en el primer minuto. |
| El webhook no llega al producto ✔ | Reintentos hasta ~28 h, alerta en el panel, consulta cada 5 min del producto y, sobre todo, el token ya traía la fecha de corte. |
| Llegan dos avisos desordenados | El producto aplica solo el token más reciente (`iat`). |
| Se mueve una licencia a otra instancia ✔ | La instancia anterior recibe un token firmado de "cancelada" para ese negocio; la nueva recibe el estado vigente. |
| Dos personas editan la misma licencia a la vez ✔ | La segunda recibe "otra persona la modificó; recarga" (control de versión). |
| Cambio de plan a mitad de ciclo | Aplica precio y funciones del plan nuevo desde ahora; la fecha de vencimiento no cambia. Si corresponde cobrar diferencia, se emite un cobro aparte. |

## Clientes finales de la barbería (terceros)

| Situación | Qué pasa |
|---|---|
| La barbería es cortada con citas ya pagadas por sus clientes | La web deja de aceptar reservas nuevas, pero el enlace personal de cada cita sigue funcionando para verla, cancelarla o pedir reembolso. Evita perjudicar a consumidores (riesgo INDECOPI). |
| La barbería cortada quiere llevarse sus datos | Puede entrar en modo restringido a exportar. Solvex no retiene datos como medida de presión. |
| La barbería se da de baja | Exporta sus datos; luego, a pedido, Solvex anonimiza y conserva solo lo contable. |

## Seguridad

| Situación | Qué pasa |
|---|---|
| Alguien prueba contraseñas ✔ | Mismo mensaje exista o no el correo; 5 fallos bloquean la cuenta 15 min (crece); 10 intentos por IP cada 15 min. |
| Roban la contraseña de alguien del equipo | Sin el código del celular no entra. |
| Roban la cookie de sesión | Vence por inactividad (30 min) y a las 10 h; "Cerrar las demás sesiones" la invalida; las acciones delicadas piden código 2FA de nuevo. |
| Un sitio malicioso intenta usar la sesión del panel (CSRF) ✔ | Bloqueado: cookie SameSite=Strict, token CSRF, solo JSON y verificación de origen. |
| Alguien intenta inyectar SQL o HTML ✔ | Consultas preparadas; todo el texto se escapa al mostrarse; CSP sin scripts en línea. |
| Intentan adivinar enlaces de pago o códigos de cliente ✔ | Enlaces de 256 bits; "pedir mi enlace" responde lo mismo exista o no y solo envía a los contactos registrados. |
| Se filtra la clave de API de una instancia ✔ | Se rota en el panel; si la instancia tenía IPs permitidas, la clave no sirve desde otra IP. |
| Alguien edita la base "por fuera" ✔ | Pagos cerrados y bitácoras no se pueden editar (triggers); si se saltan los triggers, la verificación de auditoría lo detecta. |
| Roban el archivo de la base o un respaldo ✔ | Los datos personales están cifrados; el respaldo está cifrado con otra llave. |
| Falsifican la respuesta del Hub ante el producto ✔ | El producto verifica la firma Ed25519 con la llave pública; cualquier cambio invalida el token. |
| El producto instalable se copia a otra computadora ✔ | Necesita activarse con la clave y cuenta contra el límite de equipos; el token está atado a la huella del equipo. |
| Alguien parcha el programa instalable para saltar la licencia | **No se puede impedir del todo** en una máquina que controla otra persona. Se mitiga dejando las funciones valiosas en el servidor. |
