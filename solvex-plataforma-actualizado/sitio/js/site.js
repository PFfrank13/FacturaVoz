/* Solvex · sitio público. Sin datos sensibles en el navegador: los formularios van al Hub por HTTPS. */
(function () {
  'use strict';
  var CFG = window.SOLVEX || {}, TAU = Math.PI * 2;
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };

  /* engranaje de cristal */
  (function () {
    var g = $('gear'); if (!g) return;
    var teeth = 10, cx = 50, cy = 50, Ro = 46, Ri = 37, pts = [], k;
    for (k = 0; k < teeth; k++) { var a = k * TAU / teeth; [[-0.17, Ri], [-0.09, Ro], [0.09, Ro], [0.17, Ri]].forEach(function (t) { pts.push([cx + Math.cos(a + t[0]) * t[1], cy + Math.sin(a + t[0]) * t[1]]); }); }
    var d = pts.map(function (p, i) { return (i ? 'L' : 'M') + p[0].toFixed(2) + ' ' + p[1].toFixed(2); }).join('') + 'Z';
    d += 'M' + (cx + 15) + ' ' + cy + 'A15 15 0 1 0 ' + (cx - 15) + ' ' + cy + 'A15 15 0 1 0 ' + (cx + 15) + ' ' + cy + 'Z';
    g.setAttribute('d', d); $('gear-hl').setAttribute('d', 'M30 24a28 28 0 0 1 30-8 40 40 0 0 0-26 18z');
  })();

  /* insignias con laurel */
  (function () {
    var box = $('badges'); if (!box) return;
    function badge(lines) {
      var s = '<svg viewBox="0 0 120 112" role="img" aria-label="' + esc(lines.join(' ')) + '">';
      for (var side = -1; side <= 1; side += 2) for (var k = 0; k < 10; k++) {
        var ph = 0.3 + k * 0.2, x = 60 + side * 47 * Math.sin(ph), y = 56 + 47 * Math.cos(ph), rot = Math.atan2(side * Math.cos(ph), Math.sin(ph)) * 180 / Math.PI;
        s += '<ellipse cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" rx="3.3" ry="7.5" fill="#0B1A2C" transform="rotate(' + rot.toFixed(0) + ' ' + x.toFixed(1) + ' ' + y.toFixed(1) + ')"/>';
      }
      lines.forEach(function (t, i) { s += '<text x="60" y="' + (50 + i * 14) + '" text-anchor="middle" font-family="Hanken Grotesk, system-ui, sans-serif" font-size="' + (i === 1 ? 11 : 9.5) + '" font-weight="600" fill="#0B1A2C">' + esc(t) + '</text>'; });
      return s + '</svg>';
    }
    box.innerHTML = badge(['Prueba', 'gratuita', '30 días']) + badge(['Sin datos', 'de tarjeta', 'guardados']);
  })();

  /* datos de contacto y pie legal */
  (function () {
    var ul = $('channels'), h = '';
    if (ul) {
      if (CFG.WHATSAPP) h += '<li>WhatsApp: <a href="https://wa.me/' + esc(String(CFG.WHATSAPP).replace(/\D/g, '')) + '" rel="noopener noreferrer" target="_blank">+' + esc(CFG.WHATSAPP) + '</a></li>';
      if (CFG.CORREO) h += '<li>Correo: <a href="mailto:' + esc(CFG.CORREO) + '">' + esc(CFG.CORREO) + '</a></li>';
      ul.innerHTML = h;
    }
    var lg = $('legal');
    if (lg) {
      var nc = CFG.NOMBRE_COMERCIAL || 'Solvex', rs = CFG.RAZON_SOCIAL || '';
      var parts = ['© ' + new Date().getFullYear() + ' ' + nc + (rs && rs !== nc ? ', nombre comercial de ' + rs : '')];
      if (CFG.RUC) parts.push('RUC ' + CFG.RUC);
      if (CFG.DIRECCION) parts.push(CFG.DIRECCION);
      if (CFG.CORREO) parts.push(CFG.CORREO);
      if (CFG.WHATSAPP) parts.push('WhatsApp +' + String(CFG.WHATSAPP).replace(/\D/g, ''));
      lg.textContent = parts.join(' · ');
    }
  })();

  /* menú del celular */
  (function () {
    var b = $('burger'), m = $('menu'); if (!b || !m) return;
    var set = function (open) { m.classList.toggle('open', open); b.setAttribute('aria-expanded', open ? 'true' : 'false'); b.setAttribute('aria-label', open ? 'Cerrar menú' : 'Abrir menú'); };
    b.addEventListener('click', function () { set(!m.classList.contains('open')); });
    m.addEventListener('click', function (e) { if (e.target.closest('a')) set(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') set(false); });
  })();

  /* llamada al Hub con tiempo límite */
  function hub(path, body, method) {
    if (!CFG.HUB_URL) return Promise.reject(new Error('sin hub'));
    var ctl = 'AbortController' in window ? new AbortController() : null;
    var t = ctl && setTimeout(function () { ctl.abort(); }, 12000);
    return fetch(CFG.HUB_URL.replace(/\/+$/, '') + path, { method: method || 'POST', headers: body ? { 'Content-Type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined, credentials: 'omit', mode: 'cors', signal: ctl && ctl.signal })
      .then(function (r) { if (t) clearTimeout(t); return r.json().catch(function () { return {}; }).then(function (j) { if (!r.ok) { var e = new Error(j.message || 'Error'); e.status = r.status; throw e; } return j; }); });
  }

  /* precios desde el catálogo del Hub (si está publicado) */
  (function () {
    var boxes = document.querySelectorAll('.prices[data-product]'); if (!boxes.length) return;
    var money = function (n) { return 'S/ ' + Number(n).toLocaleString('es-PE', { minimumFractionDigits: 0, maximumFractionDigits: 2 }); };
    /* precios escritos en config.js: se muestran de inmediato y el Hub los reemplaza si responde */
    var fixed = CFG.PRECIOS || {};
    boxes.forEach(function (box) {
      var list = fixed[box.getAttribute('data-product')];
      if (!list || !list.length) return;
      box.innerHTML = list.slice(0, 3).map(function (p) { return '<div class="price-row"><span>' + esc(p.nombre) + '</span><span><b>' + money(p.precio) + '</b> ' + esc(p.periodo || '') + '</span></div>'; }).join('') +
        '<p class="price-note">Precios en soles' + (CFG.PRECIOS_INCLUYEN_IGV === false ? ' + IGV' : ', incluyen IGV') + '. Ver <a href="terminos.html">términos</a>.</p>';
    });
    var unit = function (p) { if (p.interval_unit === 'none') return 'pago único'; if (p.interval_unit === 'month') return p.interval_count === 1 ? 'al mes' : 'cada ' + p.interval_count + ' meses'; if (p.interval_unit === 'year') return p.interval_count === 1 ? 'al año' : 'cada ' + p.interval_count + ' años'; return 'cada ' + p.interval_count + ' días'; };
    hub('/v1/public/catalog', null, 'GET').then(function (cat) {
      (cat.products || []).forEach(function (prod) {
        var box = document.querySelector('.prices[data-product="' + prod.code + '"]'); if (!box || !prod.plans.length) return;
        // Precio final para un cliente del Perú: si el plan es "+ IGV", se muestra con el IGV sumado (la ley pide mostrar el precio total).
        var igv = Number(cat.igv_rate_bp) || 0;
        var final = function (p) { return p.tax_mode === 'mas_impuesto' ? Math.round(p.price_cents * (10000 + igv) / 10000) : p.price_cents; };
        box.innerHTML = prod.plans.slice(0, 3).map(function (p) { return '<div class="price-row"><span>' + esc(p.name) + '</span><span><b>' + money(final(p) / 100) + '</b> ' + esc(unit(p)) + '</span></div>'; }).join('') +
          '<p class="price-note">' + (igv ? 'Precios en soles, incluyen IGV.' : 'Precios en soles.') + (prod.plans.some(function (p) { return p.trial_days; }) ? ' Incluye prueba gratuita.' : '') + '</p>';
      });
    }).catch(function () { /* sin catálogo: se queda el texto por defecto */ });
  })();

  /* botones de producto: llevan el rubro al formulario */
  document.querySelectorAll('[data-sector]').forEach(function (a) { a.addEventListener('click', function () { var s = $('f-rubro'); if (s) s.value = a.getAttribute('data-sector'); }); });

  /* formulario de contacto */
  (function () {
    var form = $('brief'); if (!form) return;
    var t0 = Date.now(), sent = $('sent'), btn = $('send'), result = $('result'), copyBtn = $('copy');
    var val = function (id) { return $(id).value.trim(); };
    form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      sent.classList.add('on'); result.classList.remove('on'); copyBtn.hidden = true;
      var contact = val('f-contacto');
      $('f-contacto').classList.remove('invalid');
      if (!contact || (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(contact) && !/^\+?[\d\s-]{9,15}$/.test(contact))) { sent.textContent = 'Escribe un celular o correo válido para poder responderte.'; $('f-contacto').classList.add('invalid'); $('f-contacto').focus(); return; }
      if (!$('f-ok').checked) { sent.textContent = 'Marca la autorización para que podamos contactarte.'; $('f-ok').focus(); return; }
      var body = { name: val('f-nombre'), business: val('f-negocio'), sector: val('f-rubro'), branches: val('f-sedes'), contact: contact, message: val('f-msg'), consent: true, website: $('f-web').value, elapsed_ms: Date.now() - t0 };
      btn.disabled = true; sent.textContent = 'Enviando…';
      hub('/v1/public/leads', body).then(function () { sent.textContent = '¡Listo! Recibimos tu solicitud y te escribiremos pronto al contacto que indicaste.'; form.reset(); }, function (e) {
        var txt = 'Consultoría de diseño con Solvex\nNombre: ' + (body.name || '—') + '\nNegocio: ' + (body.business || '—') + '\nRubro: ' + body.sector + '\nSedes: ' + body.branches + '\nQué quiero resolver: ' + (body.message || '—') + '\nContacto: ' + contact;
        sent.textContent = e && e.status === 429 ? e.message : 'No pudimos enviarla desde aquí. Copia el resumen y envíanoslo' + (CFG.WHATSAPP ? ' por WhatsApp.' : '.');
        result.textContent = txt; result.classList.add('on'); copyBtn.hidden = false;
        copyBtn.onclick = function () { (navigator.clipboard ? navigator.clipboard.writeText(txt) : Promise.reject()).then(function () { copyBtn.textContent = 'Copiado ✓'; if (CFG.WHATSAPP) window.open('https://wa.me/' + String(CFG.WHATSAPP).replace(/\D/g, '') + '?text=' + encodeURIComponent(txt), '_blank', 'noopener'); }, function () { copyBtn.textContent = 'Selecciona el texto y cópialo'; }); };
      }).then(function () { btn.disabled = false; });
    });
  })();

  /* zona de clientes: pedir enlace de pago */
  (function () {
    var form = $('paylink'); if (!form) return;
    var msg = $('pl-msg');
    form.addEventListener('submit', function (ev) {
      ev.preventDefault(); msg.className = 'formmsg';
      var code = $('pl-code').value.trim().toUpperCase().replace(/\s/g, ''), doc = $('pl-doc').value.replace(/\D/g, '');
      if (/^\d{1,6}$/.test(code)) code = 'LIC-' + code.padStart(5, '0');
      if (!/^LIC-\d{5,}$/.test(code)) { msg.textContent = 'El código tiene la forma LIC-00012. Está en tu contrato y en los correos de cobro.'; msg.className = 'formmsg err'; return; }
      if (!/^(\d{8}|\d{11})$/.test(doc)) { msg.textContent = 'Escribe un DNI (8 dígitos) o RUC (11 dígitos).'; msg.className = 'formmsg err'; return; }
      var b = form.querySelector('button'); b.disabled = true; msg.textContent = 'Enviando…';
      hub('/v1/public/pay-link', { license_code: code, doc_number: doc, website: $('pl-web').value }).then(function (r) { msg.textContent = r.message; form.reset(); }, function (e) { msg.textContent = e.status === 429 ? 'Demasiados intentos. Espera unos minutos.' : 'No pudimos conectar. Intenta en un momento.'; msg.className = 'formmsg err'; }).then(function () { b.disabled = false; });
    });
  })();

  /* aparición suave, menú activo, volver arriba */
  (function () {
    var secs = [].slice.call(document.querySelectorAll('.block')), links = [].slice.call(document.querySelectorAll('.links a'));
    var top = document.createElement('button'); top.className = 'totop'; top.type = 'button'; top.setAttribute('aria-label', 'Volver arriba'); top.textContent = '↑';
    top.addEventListener('click', function () { window.scrollTo({ top: 0, behavior: 'smooth' }); }); document.body.appendChild(top);
    window.addEventListener('scroll', function () { top.classList.toggle('on', window.scrollY > 900); }, { passive: true });
    if (!('IntersectionObserver' in window)) return;
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!reduce) secs.forEach(function (s) { s.classList.add('rv'); });
    var io = new IntersectionObserver(function (es) { es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }); }, { threshold: 0.06 });
    secs.forEach(function (s) { io.observe(s); });
    setTimeout(function () { secs.forEach(function (s) { s.classList.add('in'); }); }, 5000);
    var so = new IntersectionObserver(function (es) { es.forEach(function (e) { if (e.isIntersecting) links.forEach(function (a) { a.setAttribute('aria-current', a.getAttribute('href') === '#' + e.target.id ? 'true' : 'false'); }); }); }, { rootMargin: '-40% 0px -55% 0px' });
    document.querySelectorAll('section[id]').forEach(function (s) { so.observe(s); });
  })();
})();
