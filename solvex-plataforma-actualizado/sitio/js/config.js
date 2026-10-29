/* Datos que cambias tú. Los vacíos no se muestran.
   Culqi revisa que en la web estén: titular, RUC, dirección, correo, WhatsApp y precios. Completa los que faltan antes de publicar. */
window.SOLVEX = {
  // Dirección pública del Hub (el mismo PUBLIC_URL del servidor). Agrégala también en el CSP de cada página (connect-src).
  HUB_URL: /^(localhost|127\.0\.0\.1)$/.test(location.hostname) ? 'http://localhost:8080' : 'https://hub.solvex.pe',

  // Titular del negocio. Vacíos = no se muestran en ninguna página.
  // Culqi y el Libro de Reclamaciones exigen que el titular y el RUC estén visibles: complétalos antes de pedir la revisión de Culqi
  // (con tu RUC 10 o con el de la empresa cuando la creen).
  NOMBRE_COMERCIAL: 'Solvex',
  RAZON_SOCIAL: '',      // ej. 'Solvex S.A.C.'
  RUC: '',               // ej. '20612345678'

  // FALTA COMPLETAR
  DIRECCION: '',         // dirección fiscal tal como figura en tu ficha RUC (ej. 'Av. Ejemplo 123, Miraflores, Lima')
  WHATSAPP: '',          // con código de país, sin + ni espacios (ej. '51987654321')
  CORREO: '',            // ej. 'hola@solvex.pe' (cuando tengas el dominio) o tu Gmail mientras tanto

  // Precios que se muestran si el Hub todavía no está publicado. Cuando el Hub esté en línea, se usan los del panel.
  // Ejemplo: BARBERIA: [{ nombre: 'Mensual', precio: 99, periodo: 'al mes' }, { nombre: 'Anual', precio: 990, periodo: 'al año' }]
  PRECIOS_INCLUYEN_IGV: true, // los precios de arriba son el total que paga un cliente del Perú (lo exige la ley al mostrarlos)
  PRECIOS: {
    BARBERIA: [],
    RESTAURANTE: [],
  },
};
