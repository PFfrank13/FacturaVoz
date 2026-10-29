/* Páginas legales: completa datos de la empresa y envía el Libro de Reclamaciones al Hub. */
(function () {
  'use strict';
  var CFG = window.SOLVEX || {};
  document.querySelectorAll('[data-if]').forEach(function (el) { if (!CFG[el.getAttribute('data-if')]) el.remove(); });
  document.querySelectorAll('[data-k]').forEach(function (el) {
    var v = CFG[el.getAttribute('data-k')]; if (!v) return;
    if (el.getAttribute('data-mail')) { el.textContent = v; el.setAttribute('href', 'mailto:' + v); return; }
    el.textContent = (el.getAttribute('data-prefix') || '') + v;
  });
  var f = document.getElementById('lr'); if (!f) return;
  var $ = function (id) { return document.getElementById(id); }, msg = $('lr-msg');
  f.addEventListener('submit', function (e) {
    e.preventDefault(); msg.className = 'formmsg';
    var radio = function (n) { var r = f.querySelector('input[name="' + n + '"]:checked'); return r ? r.value : ''; };
    var b = { kind: radio('kind'), name: $('c-name').value.trim(), doc_type: $('c-dt').value, doc_number: $('c-dn').value.trim(), email: $('c-em').value.trim(), phone: $('c-ph').value.trim() || undefined, address: $('c-ad').value.trim(), minor_guardian: $('c-gu').value.trim() || undefined,
      good_type: radio('gt'), good_description: $('c-gd').value.trim(), amount: $('c-am').value.trim().replace(',', '.') || undefined, description: $('c-de').value.trim(), request: $('c-rq').value.trim(), accept: $('c-ok').checked, website: $('c-web').value };
    if (!b.name || !b.doc_number || !b.email || !b.address || !b.good_description || b.description.length < 10 || !b.request) { msg.textContent = 'Completa los campos obligatorios (el detalle debe tener al menos 10 caracteres).'; msg.className = 'formmsg err'; return; }
    if (!b.accept) { msg.textContent = 'Marca la declaración para enviar.'; msg.className = 'formmsg err'; return; }
    var btn = f.querySelector('button'); btn.disabled = true; msg.textContent = 'Enviando…';
    fetch((CFG.HUB_URL || '').replace(/\/+$/, '') + '/v1/public/complaints', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b), credentials: 'omit' })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error(j.message || 'No se pudo enviar.'); return j; }); })
      .then(function (j) { f.hidden = true; var ok = $('lr-ok'); ok.textContent = 'Registramos tu ' + b.kind + ' con el número ' + j.number + '. Te enviamos la constancia a ' + b.email + '. Responderemos a más tardar el ' + new Date(j.due_on + 'T12:00:00Z').toLocaleDateString('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }) + '.'; ok.classList.add('on'); window.scrollTo({ top: 0, behavior: 'smooth' }); },
        function (err) { msg.textContent = err.message + ' Si el problema persiste, escríbenos' + (CFG.CORREO ? ' a ' + CFG.CORREO : '') + '.'; msg.className = 'formmsg err'; })
      .then(function () { btn.disabled = false; });
  });
})();
