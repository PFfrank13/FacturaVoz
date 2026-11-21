# Pruebas de FacturaVoz con Playwright

Este recorrido abre el `MainShell` de Flutter con la tienda ficticia Mercado Oliva. El servidor escucha en un puerto temporal de `127.0.0.1`. Los servicios de ventas, alertas y tiempo real responden en memoria. Chromium y WebKit solo pueden solicitar archivos de ese servidor.

Con Flutter y Node.js 22 instalados, ejecuta desde `app/`:

```sh
flutter pub get
flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn --output=build/browser-qa --target=tool/browser_qa/main.dart
cd tool/browser_qa
npm ci
npx --no-install playwright install chromium webkit
npm test
```

En Linux, usa `npx --no-install playwright install --with-deps chromium webkit` para instalar también las bibliotecas del sistema.

La prueba recorre Inicio, gráfica de ventas, meta mensual, isla dinámica, notificaciones, catálogo, revisión del carrito y selección y verificación manual de Yape, Plin y Tarjeta. Comprueba el total con IGV y el bloqueo del botón de confirmación antes de verificar el pago. Los perfiles son iPhone en WebKit, Android en Chromium e iPad horizontal en WebKit con tema oscuro y movimiento reducido. Chromium envía gestos táctiles horizontales a la gráfica y verticales a Inicio. WebKit usa toques en los botones y arrastre de puntero para el desplazamiento. Las capturas se guardan en `tool/previews/browser/` dentro de `app/`.
