import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { access, mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, devices, webkit } from 'playwright';

const bundle = fileURLToPath(new URL('../../build/browser-qa/', import.meta.url));
const captures = fileURLToPath(new URL('../previews/browser/', import.meta.url));
const mime = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png',
  '.webp': 'image/webp', '.ttf': 'font/ttf', '.otf': 'font/otf', '.svg': 'image/svg+xml',
};

async function serveBundle() {
  await access(path.join(bundle, 'main.dart.js')).catch(() => {
    throw new Error('Primero compila tool/browser_qa/main.dart en build/browser-qa.');
  });
  const server = createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      const file = path.resolve(bundle, '.' + (pathname === '/' ? '/index.html' : pathname));
      const relative = path.relative(bundle, file);
      if (relative.startsWith('..') || path.isAbsolute(relative)) {
        response.writeHead(403).end();
        return;
      }
      const bytes = await readFile(file);
      response.writeHead(200, { 'Content-Type': mime[path.extname(file)] ?? 'application/octet-stream' });
      response.end(bytes);
    } catch {
      response.writeHead(404).end();
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return server;
}

const profiles = [
  { device: 'iPhone 13', browser: webkit, name: 'iphone', viewport: { width: 390, height: 844 } },
  { device: 'Pixel 7', browser: chromium, name: 'android', viewport: { width: 412, height: 915 } },
  { device: 'iPad Pro 11 landscape', browser: webkit, name: 'ipad', wide: true, dark: true, reduce: true },
];

async function swipe(page, start, end) {
  const session = await page.context().newCDPSession(page);
  const point = (progress) => [{
    x: start.x + (end.x - start.x) * progress,
    y: start.y + (end.y - start.y) * progress,
    radiusX: 4, radiusY: 4, force: 1, id: 1,
  }];
  await session.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: point(0) });
  for (let step = 1; step <= 14; step++) {
    await session.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: point(step / 14) });
  }
  await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await session.detach();
}

async function scrollHome(page, browser, heading) {
  if (browser === chromium) {
    await swipe(page, { x: 180, y: 580 }, { x: 180, y: 140 });
  } else {
    // Flutter also supports pointing devices. Start in the page margin, inside the scroll view.
    const { x } = await heading.boundingBox();
    await page.mouse.move(x - 10, page.viewportSize().height * 0.72);
    await page.mouse.down();
    await page.mouse.move(x - 10, 125, { steps: 18 });
    await page.mouse.up();
  }
}

async function checkProfile(profile, origin) {
  const browser = await profile.browser.launch();
  try {
    const context = await browser.newContext({
      ...devices[profile.device],
      ...(profile.viewport ? { viewport: profile.viewport } : {}),
      deviceScaleFactor: 1,
      locale: 'es-PE',
      colorScheme: profile.dark ? 'dark' : 'light',
      reducedMotion: profile.reduce ? 'reduce' : 'no-preference',
      serviceWorkers: 'block',
    });
    const external = [];
    await context.route('**/*', async (route) => {
      if (new URL(route.request().url()).origin === origin) return route.continue();
      external.push(route.request().url());
      await route.abort();
    });
    await context.routeWebSocket('**/*', (socket) => {
      external.push(socket.url());
      socket.close({ code: 1000, reason: 'La prueba usa tiempo real en memoria.' });
    });
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('console', (message) => {
      if (/exception caught|another exception was thrown|renderflex overflowed/i.test(message.text())) {
        errors.push(message.text());
      }
    });
    const button = (name) => page.getByRole('button', { name, exact: typeof name === 'string' });
    const heading = (name) => page.getByRole('heading', { name, exact: true });
    const capture = async (name) => {
      // CanvasKit animations are painted frames and do not expose a CSS transition end event.
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(captures, name + '.png') });
    };
    await page.goto(origin);
    const greeting = heading('Hola, Mercado Oliva');
    await greeting.waitFor({ timeout: 45000 });
    const preferences = await page.evaluate(() => ({
      reduce: matchMedia('(prefers-reduced-motion: reduce)').matches,
      dark: matchMedia('(prefers-color-scheme: dark)').matches,
    }));
    assert.equal(preferences.reduce, Boolean(profile.reduce));
    assert.equal(preferences.dark, Boolean(profile.dark));

    const menu = button(profile.wide ? 'Ocultar menú lateral' : 'Abrir menú');
    const bell = button('Notificaciones pendientes');
    const island = button('Vista previa de notificaciones');
    const menuBox = await menu.boundingBox();
    const bellBox = await bell.boundingBox();
    assert.ok(menuBox.x < bellBox.x && Math.abs(menuBox.y - bellBox.y) < 16);
    await island.waitFor();
    const chart = page.getByRole('slider');
    await chart.waitFor();
    const today = await chart.getAttribute('aria-valuetext');
    assert.match(today, /S\/ 55\.00$/);
    await button('Ventas de hoy: S/ 55.00, 1 venta').waitFor();
    await button('Establecer meta del mes').waitFor();
    if (profile.name === 'iphone') await capture('iphone-inicio');
    const sales = button(profile.wide ? /^Venta rápida Pestaña/ : 'Ventas');
    const checkScroll = async () => {
      const salesBox = await sales.boundingBox();
      await scrollHome(page, profile.browser, greeting);
      await page.waitForFunction(() => {
        const title = Array.from(document.querySelectorAll('h2'))
          .find((element) => element.textContent === 'Hola, Mercado Oliva');
        const reachedHistory = document.body.textContent.includes('DEMO-10') ||
          document.querySelector('[aria-label*="DEMO-10"]');
        return reachedHistory && (!title || title.getBoundingClientRect().bottom < 60);
      });
      assert.deepEqual(await sales.boundingBox(), salesBox);
    };
    if (profile.browser === chromium) {
      const box = await chart.boundingBox();
      const y = box.y + box.height * 0.55;
      await swipe(page, { x: box.x + box.width * 0.9, y }, { x: box.x + box.width * 0.2, y });
      await page.waitForFunction((value) => {
        return document.querySelector('[role="slider"]')?.getAttribute('aria-valuetext') !== value;
      }, today);
      await button('Establecer meta del mes').tap();
      await page.getByRole('textbox', { name: 'Meta (con IGV)' }).waitFor();
      await button('Cerrar').tap();
      await button('Abrir menú').waitFor();
    } else {
      await checkScroll();
    }

    await island.tap();
    await page.getByRole('group', { name: /Diferencia en cierre de caja/ }).waitFor();
    if (profile.name === 'android') await capture('android-isla');
    await button('Cerrar').tap();
    if (profile.browser === chromium) await checkScroll();
    await bell.tap();
    await heading('Notificaciones').waitFor();
    await button('Marcar todas como leídas').tap();
    await button('Marcar todas como leídas').waitFor({ state: 'hidden' });
    await button(/^Atrás/).tap();
    await button('Notificaciones').waitFor();

    if (!profile.wide) {
      // The left drawer and bottom tabs both remain usable after scrolling.
      await menu.tap();
      await button(/^Inventario Pestaña/).tap();
      await heading('Inventario').waitFor();
    }
    await sales.tap();
    await heading('Venta rápida').waitFor();
    const drinks = page.getByRole('checkbox', { name: 'Bebidas', exact: true });
    await drinks.tap();
    const add = button('Añadir Agua mineral');
    await add.waitFor();
    await button('Añadir Leche fresca').waitFor({ state: 'hidden' });
    await add.tap();
    const review = button(profile.wide ? 'Revisar y cobrar' : /Ver carrito/);
    await review.waitFor();
    if (profile.wide) {
      await button('Aumentar Agua mineral').tap();
      await button('Reducir Agua mineral').tap();
      await page.getByRole('checkbox', { name: 'Todo', exact: true }).tap();
      await button('Añadir Leche fresca').waitFor();
      await capture('ipad-venta-oscura');
    }
    await review.tap();
    await heading('Carrito de venta').waitFor();
    await button('Agregar uno').tap();
    await button('Continuar al pago').tap();
    await heading('Método de cobro').waitFor();
    assert.match(await page.locator('body').ariaSnapshot(), /S\/ 4\.25/);
    if (profile.name === 'iphone') await capture('metodos-cobro-claro');
    if (profile.name === 'ipad') await capture('metodos-cobro-oscuro');
    for (const method of ['Yape', 'Plin', 'Tarjeta']) {
      await button(new RegExp('^Seleccionar ' + method)).tap();
      await page.getByRole('heading', { name: new RegExp('^Cobro ' + method + '$', 'i') }).waitFor();
      assert.equal(await button('Confirmar pago').isEnabled(), false);
      await button('Cambiar método').tap();
      await heading('Método de cobro').waitFor();
    }
    assert.deepEqual(errors, []);
    assert.deepEqual(external, []);
    console.log('OK', profile.device, profile.browser.name(), page.viewportSize(), preferences);
  } finally {
    await browser.close();
  }
}

await mkdir(captures, { recursive: true });
const server = await serveBundle();
try {
  const origin = 'http://127.0.0.1:' + server.address().port;
  for (const profile of profiles) await checkProfile(profile, origin);
} finally {
  server.close();
}
