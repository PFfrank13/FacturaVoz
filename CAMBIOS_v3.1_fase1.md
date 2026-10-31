# FacturaVoz v3.1 — Fase 1
- Rubro fijo: el cliente lo elige una vez (con aviso); luego solo tú lo cambias con `private.admin_set_rubro` (SQL 20261117). La base lo impone aunque alguien use la API.
- Cada rubro ve solo sus funciones + las comunes (Gastos, Caja, Cobranza, Ajustes…). Se quitó "Otras funciones" y "Cambiar de rubro".
- Tienda: imágenes no cargaban por la política de seguridad (CSP); ahora permite imágenes de Supabase.
- Fiados: botón grande "Anotar fiado" visible en la pantalla.
- Overflow ("Bottom overflowed"): cuadrículas con alto fijo según tamaño de letra (Inicio, POS, Rentabilidad, elegir rubro) y fila de acciones del Inicio.
- Colores distintos por función.
SQL a ejecutar: 20261113, 20261114, 20261115, 20261116, 20261117 (en orden).
Verificado: tsc OK, 112 pruebas del servidor OK, SQL probado en Postgres 16 (bloquea al cliente, permite a la plataforma, se puede correr dos veces), sintaxis Dart OK. No verificado: compilar/ejecutar Flutter (no hay SDK aquí) y la imagen real de la tienda en Vercel.
