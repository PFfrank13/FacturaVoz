# Skills de FacturaVoz — verificación 2026-11-07

## Disponibles para este proyecto

Instaladas desde el catálogo oficial `openai/skills`: `gh-fix-ci` y
`security-best-practices`. Archivos personales en `%USERPROFILE%/.codex/skills`,
con enlaces de directorio en `%USERPROFILE%/.agents/skills` para descubrimiento.
`gh-fix-ci` necesita además GitHub CLI autenticado; `gh` no está instalado.
La guía de seguridad cubre TypeScript/Python, no sustituye una revisión Dart.

Creadas en `.agents/skills`: `facturavoz-architecture`, `facturavoz-flutter`,
`facturavoz-web`, `facturavoz-database`, `facturavoz-fiscal`,
`facturavoz-commerce`, `facturavoz-quality` y `facturavoz-delivery`.
Cada una tiene SKILL.md, metadatos de interfaz, referencias reales y aceptación.

Ya disponibles: skills de Supabase, Vercel, Figma, computer-use y herramientas
GitHub. Se reutilizan; no se instalaron duplicados. `skill-installer` y
`skill-creator` son herramientas de sistema utilizadas para esta configuración.
No se encontró una skill Flutter/SUNAT en el catálogo oficial consultado.

## Evidencia y límites

- Ocho SKILL.md aprobados por `skill-creator/scripts/quick_validate.py`.
- 42 referencias relativas comprobadas; metadatos con invocación implícita.
- AGENTS.md selecciona por tarea; no carga todas las instrucciones siempre.
- Revisión de los 21 archivos nuevos/modificados iniciales sin patrones de
  claves privadas, tokens GitHub/Supabase secretos ni JWT. Es una comprobación
  de patrones, no una certificación exhaustiva de ausencia de secretos.
- Archivos accesibles y ubicación de descubrimiento verificadas. No se ha
  observado aún su aparición en el selector de una sesión nueva de Codex.

La documentación oficial indica detección automática de skills nuevas o
actualizadas. Abrir un turno nuevo; si no aparecen, reiniciar Codex, como indica
también el instalador. No hace falta reiniciar el ERP.

## Selección no destructiva

Ejercicio manual del agente, leyendo las instrucciones sin ejecutar operaciones:

| Solicitud de prueba | Selección | Límite aplicado |
|---|---|---|
| Cobrar queda oculto por teclado Flutter | facturavoz-flutter | Pruebas de widget, sin cobro real |
| Documento de cliente se pierde en Next.js | facturavoz-web + facturavoz-commerce | Revisar formulario, esquema y acción |
| Doble solicitud a RPC PostgreSQL | facturavoz-database + facturavoz-quality | Restauración aislada, sin escritura productiva |

Esto verifica la selección razonada y lectura; no mide la activación automática
del selector de Codex. La segunda selección se aplicó después al defecto real:
el formulario ahora acepta documento opcional de borrador y la acción lo
transmite a `create_invoice`, en lugar de enviar siempre null.
La prueba nueva valida normalización, compatibilidad y límite del esquema;
no demuestra persistencia remota ni emisión SUNAT.

Validación del cambio web: 174 pruebas aprobadas en 20 archivos, TypeScript,
ESLint y build Next.js correctos (44 páginas generadas). No se modificó Flutter
en esta fase ni se presenta esta evidencia como prueba visual o fiscal real.

## Referencias oficiales

- https://github.com/openai/skills/tree/main/skills/.curated
- https://learn.chatgpt.com/docs/build-skills
- https://cpe.sunat.gob.pe/guias-y-manuales

No se cambiaron producción, secretos, Hub, AWS, Caddy ni web corporativa.
Pendiente del producto: comprobar cliente/venta/cobro/emisión/PDF/historial de
extremo a extremo y completar selección de clientes y estados fiscales.
