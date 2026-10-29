# Privacidad, términos y Ley 29733 (borradores para revisar con un abogado)

> Estos textos son una **base de trabajo**, no asesoría legal. Antes de publicarlos, revísalos con un abogado
> peruano. Reemplaza lo que está entre [corchetes].

## 1. Política de privacidad (borrador)

**Responsable:** [Razón social de Solvex], RUC [número], domicilio [dirección], correo [correo de privacidad].

**Qué datos tratamos y para qué**
1. *Tus datos de cuenta* (correo, nombre, teléfono): crear tu cuenta, darte acceso y soporte.
2. *Datos de tu negocio* (RUC, dirección, logo, comprobantes, productos): emitir tus comprobantes ante SUNAT y
   mostrarte tus reportes. Tú eres el responsable de los datos de **tus** clientes; nosotros actuamos como
   **encargados** del tratamiento por cuenta tuya.
3. *Datos de tus clientes* (nombre, DNI/RUC, dirección, celular, correo): emitir comprobantes, cobrar y avisar.
   La consulta de DNI/RUC usa un proveedor externo (APISPERU) solo con el número.
4. *Voz y textos que dictas*: se envían a Groq para transcribir y entender el pedido; no los usamos para otros fines.
   Si pides "Escuchar", el texto de la respuesta se envía a ElevenLabs para generar el audio.
5. *Datos de salud* (solo rubro Consultorio, "Historial privado"): son **datos sensibles**. Solo los ve quien los
   escribe y el dueño/administrador; no se envían a la inteligencia artificial ni salen en reportes. El negocio debe
   tener el **consentimiento por escrito** del paciente.

**Encargados y transferencias internacionales:** Supabase (base de datos), Vercel (servidor), Groq (IA), ElevenLabs
(voz), Resend (correo), APISPERU (consulta DNI/RUC). Algunos están fuera del Perú (transferencia internacional).

**Cuánto tiempo:** mientras tengas cuenta. Los comprobantes electrónicos se conservan el plazo que exige SUNAT.
Lo borrado va a la papelera 30 días; luego se elimina.

**Seguridad:** cifrado en tránsito, control de acceso por empresa y por rol en la base de datos (RLS), bitácora
inalterable, PIN del dueño para acciones sensibles, claves de servicios solo en el servidor.

**Tus derechos (ARCO):** acceso, rectificación, cancelación y oposición. Ver "Cómo ejercerlos" abajo.

## 2. Términos de uso (borrador, puntos clave)
- El servicio se paga por suscripción (planes Básico, Pro, Empresa); hay prueba gratuita de 3 días por RUC.
- Tú eres responsable de la veracidad de tus comprobantes y de tus obligaciones tributarias. Los cálculos de
  impuestos de la app son **estimados referenciales**: confírmalos con tu contador.
- El Copiloto puede equivocarse: toda acción se confirma antes de ejecutarse.
- Si no pagas, la cuenta pasa a modo restringido (solo lectura para exportar) y luego se bloquea; tus datos se
  conservan [N] días para que los descargues.
- Prohibido usar la app para emitir comprobantes falsos o tratar datos sin consentimiento.

## 3. Cómo ejercer los derechos de la Ley 29733 (flujos en la app)
| Derecho | Cómo |
|---|---|
| **Acceso** (qué datos tengo) | Ajustes → Reportes/Excel (comprobantes), ficha de cada cliente; para todo lo demás: Ajustes → Ayuda por WhatsApp o [correo de privacidad]. Respuesta en máx. 20 días hábiles. |
| **Rectificación** | Editar en la app (datos del negocio, clientes, productos). Comprobantes emitidos no se editan: se corrigen con nota de crédito. |
| **Cancelación** | Ajustes → Cuenta → **Eliminar mi cuenta** (`delete_my_account`). Lo que la ley tributaria obliga a conservar se guarda bloqueado hasta su plazo. |
| **Oposición** | Desactivar el reporte diario, recordatorios y encuestas en Ajustes; pedir por WhatsApp/correo dejar de recibir comunicaciones. |
| **Clientes de tu negocio** | Si un cliente tuyo pide borrar sus datos: elimina su ficha (va a papelera 30 días). Si tiene comprobantes, esos se conservan por obligación tributaria. |

## 4. Lo que TÚ (Solvex) debes hacer antes de vender
1. **Inscribir los bancos de datos personales** (usuarios y clientes de los negocios) en el Registro Nacional de
   Protección de Datos Personales (ANPD – MINJUSDH).
2. Publicar la política de privacidad y los términos (URL en `PRIVACY_URL` y `TERMS_URL` al compilar la app).
3. Firmar/aceptar los acuerdos de tratamiento de datos (DPA) de Supabase, Vercel, Groq, ElevenLabs y Resend.
4. Comunicar la **transferencia internacional** de datos a la ANPD si corresponde.
5. Tener un **Libro de Reclamaciones virtual** para FacturaVoz (y la tienda de cada negocio: Ley 32495).
6. Plan de respuesta a incidentes (quién avisa a quién en 48 h si hay una fuga).
7. Para el rubro Consultorio: modelo de **consentimiento por escrito** para que los negocios lo usen con sus pacientes.
