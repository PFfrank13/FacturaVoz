---
name: facturavoz-delivery
description: "Entregar cambios FacturaVoz con GitHub, CI y Vercel Preview sobre recursos existentes; usar al publicar o diagnosticar despliegues."
---

# facturavoz-delivery

## Archivos de entrada
- [.github/workflows/ci.yml](../../../.github/workflows/ci.yml)
- [.vercelignore](../../../.vercelignore)
- [backend/vercel.json](../../../backend/vercel.json)
- [tools/scan_publication.py](../../../tools/scan_publication.py)
- [docs/FACTURAVOZ_RETORNO.md](../../../docs/FACTURAVOZ_RETORNO.md)

## Trabajo
Comprueba status/diff y rama, conserva trabajo ajeno. Rama actual de evolución codex/facturavoz-evolucion; descubre estado real antes de actuar. GitHub PFfrank13/FacturaVoz privado. Vercel factura-voz, team portafolio-frank: verificar IDs vía inspect antes de mutar. Usa plugin/CLI oficial con credenciales protegidas. Preview primero; nunca promociones ni merges implícitos por instalar skills. No crear otro Supabase/proyecto. Verifica manifest de despliegue excluye Hub, Flutter build y secretos. Callback de Auth exacto requiere autorización vigente, diff limitado y comprobación; instalar skills no autoriza tocarlo.

## Aceptación
Commit revisable, pruebas pertinentes, push solo autorizado, target preview/commit confirmados. Ready y HTTP no prueban sesión/UI. Registrar rollback compatible sin borrar datos. gh-fix-ci para fallos Actions, revisando sus prerrequisitos y aprobaciones junto con autorización de la sesión.
