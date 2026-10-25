# Multi-empresa (Fase 1)

Orden de migraciones en Supabase → SQL Editor (cada una completa, en este orden):
1. `schema.sql` → 2. `20261023_mobile_prod.sql` → 3. `20261024_fiscal_sunat.sql` → 4. `20261025_credit_notes.sql`
5. `20261026_harden_fiscal.sql` (cierra políticas abiertas y devuelve el permiso de lectura fiscal)
6. `20261027_multitenant.sql` (organizaciones, equipo y permisos por rol)
7. `20261028_multitenant_fiscal.sql` (Fase 2: emisor, RUC, series y certificado por empresa)

Qué hace la Fase 1
- Clientes, facturas y líneas pertenecen a una **empresa**; un usuario puede estar en varias.
- Roles: `owner` (todo), `admin` (agrega personas, borra borradores ajenos), `member` (crea y ve).
- Cada usuario existente recibe su empresa personal con todos sus datos; los nuevos, al registrarse.
- Equipo: se agrega por correo (la persona ya debe tener cuenta). Sin invitaciones por correo todavía.
- La numeración correlativa es por empresa.

Fase 2 (ya incluida)
- Razón social, dirección, ubigeo, series, moneda e impuesto son **de la empresa** (se editan en Ajustes → Datos del negocio).
- RUC, certificado y usuario SOL se conectan **por empresa** (solo propietario/administrador). Un RUC pertenece a una sola empresa.
- Correlativos por empresa y serie: dos personas del mismo equipo nunca repiten número.
- Cualquier miembro puede emitir facturas/boletas y notas de crédito de su empresa.

Despliegue: ejecuta el SQL 7 y haz push del código **en seguida** (el backend nuevo exige las funciones nuevas; el antiguo las anteriores).

Límites conocidos
- Si un usuario borra su cuenta se borran las facturas que él creó (se bloquea si tiene comprobantes en producción).
- Los miembros se agregan por correo solo si ya tienen cuenta (sin invitaciones por correo todavía).
