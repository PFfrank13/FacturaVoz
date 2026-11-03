# FacturaVoz · Fase 38: simplicidad por rubro, sin eliminar funciones

**Base utilizada:** Fase 37, con licencias de Solvex Hub, comandas persistentes, fotografías y migraciones previas.

## Alcance real de la fase

Se reorganiza la **presentación** de los nueve rubros sin cambiar el modelo de datos, el registro de ventas, la facturación SUNAT, las políticas RLS ni la matriz de licencias. No se eliminaron archivos ni herramientas del catálogo. Las funciones habilitadas siguen dependiendo del **rubro**, del **rol** y del **plan vigente**.

- **Inicio:** el banner describe una tarea real del rubro y los accesos rápidos usan nombres entendibles. Se muestran hasta tres accesos del sector, más «Nueva venta» cuando el rol puede vender y «Ver todas». La «Venta rápida» duplicada se evita cuando ya hay acceso a «Nueva venta»; sigue accesible por la pestaña Vender, caja rápida o Menú.
- **Menú:** buscador arriba; hasta tres tareas frecuentes; «¿Primera vez? Empieza aquí» con tres pasos propios; categorías desplegables («Cobros y caja», «Reportes y administración», «Configuración»); apartado «Más herramientas» para cualquier función permitida que no aparezca en la agrupación principal.
- **Venta por voz:** ejemplos contextualizados por rubro en lugar de repetir una frase propia de un salón para cualquier empresa.
- **Historial vacío:** habla de *comprobantes* en vez de sugerir «primera venta» a negocios que empiezan por citas, trabajos o pedidos.

## Flujo que debe entender un nuevo usuario

| Rubro | Primera tarea | Segunda tarea | Tercera tarea |
|---|---|---|---|
| Bodega | Añadir productos, precio y stock | Vender | Revisar fiados y caja |
| Restaurante | Preparar carta y mesas | Tomar pedido y enviar comanda | Cobrar y entregar comprobante |
| Servicios técnicos | Registrar cliente/equipo o instalación | Crear trabajo y actualizar estado | Cobrar o registrar mensualidad |
| Salón | Configurar servicios | Agendar citas | Cobrar servicio |
| Consultorio | Registrar paciente y cita | Atender | Registrar pago y resguardar datos |
| Taller | Buscar o añadir placa | Crear orden y diagnóstico | Finalizar y cobrar |
| Mayorista | Preparar catálogo y precios | Crear cotización o pedido | Registrar pagos pendientes |
| Educación | Registrar alumnos y cursos | Organizar horarios/cuotas | Revisar y registrar cobros |
| Construcción | Crear obra y trabajos | Registrar gastos y materiales | Revisar facturación y saldo |

## Pruebas manuales obligatorias (en Android release)

1. Crear o utilizar una empresa de cada rubro, siempre con su propia cuenta de pruebas y su licencia válida. Confirmar que su Inicio, primera tarea y la guía dicen lo correcto.
2. Abrir el Menú con pantalla pequeña (360 dp), texto aumentado 1,3×, modo claro y modo oscuro. Expandir todas las secciones; comprobar que no hay botones cortados, desbordes ni campos inaccesibles.
3. Usar el buscador del Menú para encontrar una función común y una función propia. Confirmar que una función exclusiva de otro rubro no aparece.
4. Abrir la herramienta principal de cada rubro y regresar. No debe perderse estado ni datos.
5. Entrar con un rol limitado y un plan Básico. Las funciones no autorizadas por el rol no deben mostrarse; las del plan superior deben aparecer con candado cuando corresponda.
6. Verificar que al abrir «Más herramientas» aparezcan funciones permitidas que no estaban en categorías principales.
7. Realizar una operación de principio a fin, **en una base de staging**: venta y cobro, comanda, fiado, cita, orden o mensualidad según el rubro.
8. Repetir con el rol del propietario y empleado y comprobar que los datos de una empresa no aparecen en otra.

## Limitaciones de validación

En el entorno de preparación no se cuenta con `flutter` ni `dart` instalados, ni conexión a tu Supabase/Hub; por tanto, **no es correcto afirmar que la app compiló o que nueve clientes no técnicos ya validaron estos flujos**. Se verificó la integridad del ZIP, cobertura estática de guías y preservación del backend y migraciones. La experiencia de uso requiere prueba presencial o remota con usuarios reales.

## Comandos en tu Windows

Desde la carpeta `app`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run --release --dart-define=SUPABASE_URL=TU_SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=TU_ANON_KEY --dart-define=API_BASE_URL=TU_API_BASE_URL
```

**No hay migraciones SQL nuevas para esta fase visual.** Mantén las de Fase 37 que correspondan, pero pruébalas antes en staging; la activación de licencias puede bloquear negocios sin clave asignada.
