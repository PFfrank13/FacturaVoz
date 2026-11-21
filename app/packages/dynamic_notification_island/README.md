# Dynamic Notification Island

Adaptación Flutter de [rit3zh/expo-dynamic-notifications](https://github.com/rit3zh/expo-dynamic-notifications/tree/5de059a5cbefbe28c14efbe785166665a7c70bc5), revisión `5de059a5cbefbe28c14efbe785166665a7c70bc5`. La licencia original acompaña al paquete en [LICENSE](LICENSE).

La geometría de crecimiento de la gota, el perfil del cuello elástico y la expansión proceden de `src/core/build-notification-geometry.ts` y `src/logic/neck-profile.ts`. La secuencia de aparición, los tiempos y los umbrales del gesto provienen de `src/hooks/use-notification-timeline.ts` y `src/constants/notification.consts.ts`. Flutter pinta la forma y presenta el contenido en un OverlayPortal dentro de la aplicación.

`notice` contiene el aviso autorizado vigente. Un cambio de `announcement` anuncia el aviso nuevo. Tocar la cápsula permite volver a consultarlo, tocar la tarjeta abre su destino y deslizarla hacia arriba la cierra. Los lectores de pantalla pueden cerrar la tarjeta con un botón y disponen de tiempo ilimitado para leer.
