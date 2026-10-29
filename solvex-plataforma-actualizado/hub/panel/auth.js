/* Pantallas de acceso: inicio de sesión, cambio de contraseña, activación de 2FA, código. */
import { html, raw, $, S, api, icon, copy } from './core.js';

const shell = (inner) => String(html`<div class="auth"><div class="auth-card"><div class="auth-brand">${raw(LOGO)}<div><b>SOLVEX</b><span>Hub · licencias y cobros</span></div></div>${inner}</div>
  <p class="auth-foot">${icon('shield')} Conexión cifrada · doble factor obligatorio · cada acceso queda registrado</p></div>`);
export const LOGO = '<svg viewBox="0 0 100 100" class="logo-mark" aria-hidden="true"><rect width="100" height="100" rx="24" fill="#0D8460"/><g fill="#fff" transform="translate(13 13) scale(.74)"><polygon points="97.5,4.3 77.2,4.3 80.2,10.3 52.1,39.0 52.1,40.8 74.2,40.8 92.8,21.6 97.5,25.2"/><polygon points="67.0,16.8 44.3,16.8 24.0,37.7 23.4,62.3 25.8,62.3 67.0,18.6"/><polygon points="48.9,43.7 37.7,55.3 49.0,68.2 60.5,55.7"/><polygon points="74.2,49.1 31.2,95.1 53.9,95.1 74.8,73.0"/><polygon points="46.1,71.8 22.8,71.8 1.9,95.1 24.6,95.1"/></g></svg>';

export function renderAuth(root, stage, onDone) {
  const err = (t) => { const e = $('#aerr'); if (e) e.textContent = t || ''; };
  const busy = (b) => { const x = $('#ago'); if (x) { x.disabled = b; x.classList.toggle('busy', b); } };
  const wire = (fn) => $('#aform').addEventListener('submit', async (e) => { e.preventDefault(); err(''); busy(true); try { await fn(); } catch (x) { err(x.message); } finally { busy(false); } });

  if (stage === 'login') {
    root.innerHTML = shell(html`<form id="aform" novalidate><h1>Acceso al panel</h1><p class="sub">Solo para el equipo de Solvex.</p>
      <div class="fld"><label for="ae">Correo</label><input id="ae" type="email" autocomplete="username" autocapitalize="off" spellcheck="false" maxlength="254" required></div>
      <div class="fld"><label for="ap">Contraseña</label><input id="ap" type="password" autocomplete="current-password" maxlength="200" required></div>
      <p id="aerr" class="ferr general" role="alert"></p><button class="btn pri block" id="ago" type="submit">Continuar</button></form>`);
    $('#ae').focus();
    wire(async () => {
      const r = await api('POST', '/auth/login', { email: $('#ae').value.trim(), password: $('#ap').value });
      $('#ap').value = ''; S.me = r.user; renderAuth(root, r.stage, onDone);
    });
    return;
  }
  if (stage === 'codigo') {
    root.innerHTML = shell(html`<form id="aform" novalidate><h1>Verificación en dos pasos</h1><p class="sub">Escribe el código de 6 dígitos de tu app autenticadora.</p>
      <div class="fld"><label for="ac">Código</label><input id="ac" class="code-in" inputmode="numeric" autocomplete="one-time-code" maxlength="11" required></div>
      <p class="help">¿Perdiste tu celular? Usa uno de tus códigos de respaldo (formato XXXXX-XXXXX).</p>
      <p id="aerr" class="ferr general" role="alert"></p><button class="btn pri block" id="ago" type="submit">Entrar</button>
      <button type="button" class="btn ghost block" id="aback">Usar otra cuenta</button></form>`);
    $('#ac').focus();
    $('#aback').onclick = async () => { try { await api('POST', '/auth/logout'); } catch (_) { /* nada */ } renderAuth(root, 'login', onDone); };
    wire(async () => { const r = await api('POST', '/auth/totp', { code: $('#ac').value.trim() }); S.me = r.user; onDone(r); });
    return;
  }
  if (stage === 'cambiar_contrasena') {
    root.innerHTML = shell(html`<form id="aform" novalidate><h1>Crea tu contraseña</h1><p class="sub">Tu contraseña es temporal. Elige una nueva: 12 caracteres o más. Una frase de 3 o 4 palabras es fácil de recordar y difícil de adivinar.</p>
      <div class="fld"><label for="a1">Contraseña temporal</label><input id="a1" type="password" autocomplete="current-password" required></div>
      <div class="fld"><label for="a2">Nueva contraseña</label><input id="a2" type="password" autocomplete="new-password" minlength="12" required></div>
      <div class="fld"><label for="a3">Repite la nueva contraseña</label><input id="a3" type="password" autocomplete="new-password" required></div>
      <p id="aerr" class="ferr general" role="alert"></p><button class="btn pri block" id="ago" type="submit">Guardar y continuar</button></form>`);
    $('#a1').focus();
    wire(async () => {
      if ($('#a2').value !== $('#a3').value) throw new Error('Las contraseñas nuevas no coinciden.');
      const r = await api('POST', '/auth/password', { current: $('#a1').value, next: $('#a2').value }); S.me = r.user; renderAuth(root, r.stage, onDone);
    });
    return;
  }
  if (stage === 'activar_2fa') {
    root.innerHTML = shell(html`<div id="enroll"><h1>Activa el doble factor</h1><p class="sub">Es obligatorio. Aunque alguien conozca tu contraseña, no podrá entrar sin tu celular.</p><p class="sub">Cargando…</p></div>`);
    api('POST', '/auth/enroll/start').then((r) => {
      $('#enroll').innerHTML = String(html`<h1>Activa el doble factor</h1>
        <ol class="steps-list"><li>Instala <b>Google Authenticator</b>, <b>Microsoft Authenticator</b> o <b>1Password</b> en tu celular.</li><li>Escanea este código QR con la app.</li><li>Escribe el código de 6 dígitos que aparece.</li></ol>
        <div class="qr">${raw(r.qrSvg)}</div>
        <details class="manual"><summary>No puedo escanear</summary><p>Escribe esta clave en la app (tipo: basada en tiempo):</p><code>${r.secret}</code> <button type="button" class="btn sm" id="cpk">${icon('copy')} Copiar</button></details>
        <form id="aform" novalidate><div class="fld"><label for="ac">Código de 6 dígitos</label><input id="ac" class="code-in" inputmode="numeric" autocomplete="one-time-code" maxlength="6" required></div>
        <p id="aerr" class="ferr general" role="alert"></p><button class="btn pri block" id="ago" type="submit">Activar</button></form>`);
      $('#cpk').onclick = () => copy(r.secret.replace(/\s/g, ''));
      $('#ac').focus();
      wire(async () => {
        const x = await api('POST', '/auth/enroll/finish', { code: $('#ac').value.trim() });
        S.me = x.user;
        root.innerHTML = shell(html`<h1>Guarda tus códigos de respaldo</h1><p class="sub">Si pierdes tu celular, cada código sirve UNA vez para entrar. Guárdalos en tu gestor de contraseñas o imprímelos. No se volverán a mostrar.</p>
          <div class="codes">${x.recoveryCodes.map((c) => html`<code>${c}</code>`)}</div>
          <button class="btn block" id="cpc">${icon('copy')} Copiar códigos</button><button class="btn pri block" id="ago">Ya los guardé, entrar al panel</button>`);
        $('#cpc').onclick = () => copy(x.recoveryCodes.join('\n'));
        $('#ago').onclick = () => onDone(x);
      });
    }).catch((e) => { $('#enroll').innerHTML = String(html`<p class="ferr general">${e.message}</p>`); });
  }
}
