/* Página de pago de un cobro. Sin scripts en línea (CSP estricta). El monto lo fija el servidor. */
(function () {
  'use strict';
  var app = document.getElementById('app'); if (!app) return;
  var token = app.getAttribute('data-token'), amount = Number(app.getAttribute('data-amount')), pk = app.getAttribute('data-pk');
  var msg = document.getElementById('msg');
  function say(t, err) { msg.textContent = t; msg.className = err ? 'err' : ''; }
  function post(path, body) {
    return fetch('/v1/public/pay/' + encodeURIComponent(token) + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), credentials: 'omit' })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { return { ok: r.ok, j: j }; }); });
  }
  function done(r) {
    if (r.ok) { say('Pago aprobado. Recibo ' + (r.j.receipt || '') + (r.j.period_end ? '. Servicio vigente hasta el ' + r.j.period_end + '.' : '.')); setTimeout(function () { location.reload(); }, 2500); }
    else say(r.j.message || 'No se pudo procesar el pago.', true);
  }

  var payBtn = document.getElementById('pay');
  if (payBtn) payBtn.addEventListener('click', function () {
    var em = document.getElementById('em').value.trim();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(em)) { say('Escribe un correo válido.', true); return; }
    if (pk === 'simulada') { payBtn.disabled = true; say('Procesando…'); post('/card', { token: 'tkn_ok_simulado', email: em }).then(done, function () { say('No se pudo conectar.', true); }).then(function () { payBtn.disabled = false; }); return; }
    if (!window.Culqi) { say('No se pudo cargar la pasarela. Revisa tu conexión.', true); return; }
    window.__em = em;
    window.Culqi.publicKey = pk;
    window.Culqi.settings({ title: app.getAttribute('data-company'), currency: app.getAttribute('data-currency') || 'PEN', amount: amount, description: app.getAttribute('data-number') });
    window.Culqi.options({ lang: 'es', installments: false, paymentMethods: { tarjeta: true, yape: true } });
    window.Culqi.open();
  });
  // Culqi Checkout v4 llama a la función global culqi() con el token o el error.
  window.culqi = function () {
    var C = window.Culqi;
    if (C.token) { if (C.close) C.close(); payBtn.disabled = true; say('Procesando tu pago…'); post('/card', { token: C.token.id, email: window.__em }).then(done, function () { say('No se pudo conectar. No vuelvas a pagar: revisa tu correo o recarga en un minuto.', true); }).then(function () { payBtn.disabled = false; }); }
    else if (C.error) say(C.error.user_message || 'No se pudo procesar el pago.', true);
  };

  var rep = document.getElementById('rep');
  if (rep) rep.addEventListener('submit', function (e) {
    e.preventDefault();
    var b = { method: document.getElementById('rm').value, operation_ref: document.getElementById('ro').value.trim(), amount: document.getElementById('ra').value.trim().replace(',', '.'), paid_on: document.getElementById('rd').value, website: document.getElementById('rw').value };
    if (!b.operation_ref) { say('Escribe el número de operación.', true); return; }
    var btn = rep.querySelector('button'); btn.disabled = true; say('Enviando…');
    post('/report', b).then(function (r) { if (r.ok) { say(r.j.message || 'Recibido.'); rep.reset(); } else say(r.j.message || 'No se pudo enviar.', true); }, function () { say('No se pudo conectar.', true); }).then(function () { btn.disabled = false; });
  });
})();
