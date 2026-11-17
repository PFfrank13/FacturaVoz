# Riesgo auditado y acotado — dependencias del backend
Fecha de análisis: 2026-11-17. Referencia: [issue #14](https://github.com/PFfrank13/FacturaVoz/issues/14).

## Qué se encontró
`npm audit --json` marcaba **11 paquetes HIGH**: @next/eslint-plugin-next,
@typescript-eslint/typescript-estree, eslint-config-next,
eslint-import-resolver-typescript, fast-glob, fdir, micromatch,
picomatch, tinyglobby, vite y vitest.

El informe detallado en el workflow de diagnóstico `44168701339`
demostró que **las once entradas heredan una única alerta raíz**:
[GHSA-fc5q-39xc-vjpf](https://github.com/advisories/GHSA-fc5q-39xc-vjpf),
CVE-2026-112366, ReDoS de `picomatch` a través de extglobs repetidos.
Las entradas afectadas del `package-lock.json` son `dev: true`; sus
rutas provienen de **ESLint y Vitest/Vite**, no de dependencias de
ejecución del servidor.

`npm audit fix --package-lock-only` falló en npm con
`Cannot read properties of null (reading 'edgesOut')`.
La sugerencia de npm era **retroceder** eslint-config-next a 14.2.35
y vitest a 3.1.4 (cambios mayores, no actualizaciones seguras).
No se aplicaron estos cambios ni `npm audit fix --force`.

## Tratamiento temporal (no equivale a corregir picomatch)
Hasta que exista una versión parcheada publicada y compatible,
`scripts/audit-gate.mjs` acepta **solo esta GHSA**:
- Únicamente mientras **todas** las rutas y sus paquetes padres
  en el lockfile sean exclusivamente de desarrollo (`dev: true`).
- Únicamente para `picomatch` y para el advisory exacto; todos los
  demás avisos HIGH/CRITICAL siguen bloqueando CI.
- Solo hasta **2026-12-31**, inclusive. Después, el gate falla de
  forma deliberada si el advisory sigue presente.
- **Producción: cero excepciones.** Antes del análisis completo se
  ejecuta `npm audit --omit=dev --json` y cualquier HIGH/CRITICAL
  en dependencias de ejecución bloquea CI.
- Errores de red, informes incompletos o JSON inválido también
  bloquean CI: no se interpreta ausencia de informe como cero riesgos.
- Se incluyen tests con `node --test scripts/audit-gate.test.mjs`
  que comprueban expiración, nuevos advisories y la inclusión accidental
  de dependencias afectadas en producción.

## Seguimiento
1. Vigilar la GHSA y el mantenedor de picomatch; cuando se publique
   una versión reparada, actualizar versiones y `package-lock.json`,
   volver a ejecutar `npm ci`, lint, TypeScript, tests, build y audit.
2. Eliminar esta excepción después de comprobar que ya no aparece
   en el reporte. **No renovarla automáticamente.**
3. No suministrar patrones de glob procedentes de clientes a las
   herramientas de desarrollo; estos paquetes no deben ejecutarse
   para procesar entradas no confiables en el backend de producción.
4. Si el aviso cambia de alcance o se descubre explotación desde
   producción, eliminar la excepción y bloquear inmediatamente.

**Estado honesto:** este cambio corrige el gate de seguridad para
distinguir una vulnerabilidad de desarrollo temporalmente revisada;
**no afirma que la vulnerabilidad de picomatch haya sido parcheada**.
El issue #14 permanece abierto hasta actualizar picomatch o retirar
su ruta vulnerable del árbol.
