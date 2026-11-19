import 'dart:io';
import 'proposal.dart';

void main() {
  final out = StringBuffer('''# FacturaVoz — nuevos planes, propuesta v1

Generado desde `app/tool/plans/proposal.dart`, única fuente de esta propuesta.
Regenerar desde app: `dart run tool/plans/document.dart`.
No reemplaza el contrato vigente del Hub ni la matriz histórica de compatibilidad.
No contiene precios. Ningún límite se ha publicado.

## Matriz comercial de desarrollo

''');
  for (final p in TrialPlan.values) {
    final v = proposals[p]!;
    out.writeln('- **${v.label} — ${v.experience}:** ${v.users} usuarios, ${v.branches} sucursales. Incluye lo propuesto en planes inferiores.');
  }
  out.writeln('\n“Existente” significa evidencia en código, no certificación E2E ni disponibilidad automática. Las filas parciales requieren completar/validar su recorrido. Un destino listado en una fila pendiente es una dependencia existente, no la función completa.\n');
  out.writeln('| Función | Clave propuesta | Desde | Archivo / destino | Estado | Límite | Rol/permiso | Integración |');
  out.writeln('|---|---|---|---|---|---|---|---|');
  for (final f in proposedFeatures) {
    out.writeln('| ${f.name} | `${f.key}` | ${proposals[f.minimum]!.label} | ${f.file == '-' ? 'Sin pantalla operativa' : 'app/lib/screens/${f.file} — ${f.destination}'} | ${f.status} | ${f.limit} | ${f.permission} | ${f.integration} |');
  }
  out.write('''
`@base` es un marcador de la propuesta para capacidades no comercializadas como feature independiente; no se enviará al Hub. Seguridad personal permanece disponible, incluso con licencia restringida. `branches` es un permiso propuesto pendiente de contrato servidor; no habilita ningún permiso real.

## Claves nuevas y diferencias de autorización

Propuestas pendientes de aprobación y de implementación en todos los consumidores: `presentaciones`, `devoluciones`, `reposicion_inteligente`, `reportes_avanzados`, `rentabilidad`, `lectura_documentos`, `importacion_inteligente`, `whatsapp_automatizaciones`, `inventario_sucursales`, `consolidacion`, `cajas_avanzadas`, `reportes_empresariales`.

- `stock` actualmente habilita inventario y reposición. Separar reposición premium exige una clave nueva y comprobaciones de servidor, sin quitar el derecho existente a clientes actuales.
- `reportes` actualmente cubre reportes y rentabilidad. La división comercial no puede implementarse cambiando solo el menú.
- ScanScreen utiliza el permiso finance; ImportScreen utiliza import. Antes de cobrar estas capacidades por plan se necesitan guardias compatibles del backend y migración explícita.
- `multisucursal`, `max_users` y `max_branches` existen en el vocabulario histórico. OrgsScreen cambia organizaciones y no demuestra inventario ni consolidación por sucursal.
- PIN/biometría no depende de antifraude; auditoría avanzada sí. No bloquear la seguridad personal al reducir un plan.
- Roles propuestos del laboratorio: propietario y administrador tienen permisos de prueba; cajero solo sell, collect, clients y self. En producción manda my_access. No se modificaron roles reales.

## Diferencias frente al Hub observado

En la sesión autenticada revisada en Android Studio se observó Básico, Propietario, prueba activa y hasta 2 usuarios. Mostraba facturación, clientes, cobros, voz, cotizaciones, reportes, caja y avisos de pago. No mostraba fiados, stock, tienda o copiloto como incluidos.

La propuesta agrega inventario esencial, fiados, compras y proveedores a Básico; propone 1 usuario en vez de los 2 observados. Esa reducción NO debe aplicarse automáticamente a una licencia activa. Cotizaciones y avisos actualmente concedidos tampoco pueden perderse por no aparecer como objetivo explícito en el nuevo listado.

No se leyó una exportación completa de todas las licencias de Hub. Pro/Empresa vigentes y complementos de otros clientes siguen pendientes de inventario autorizado. El archivo histórico docs/facturavoz-planes.json es una propuesta anterior, no prueba del estado actual del Hub.

## Laboratorio seguro

Entrada exclusiva `app/tool/plans/main.dart`; no importada por lib/main.dart. Ejecutar desde app: `flutter run --debug -t tool/plans/main.dart`. No pasar dart-define ni credenciales.

No importa Access, Supabase, repositorios, clientes HTTP ni pantallas operativas. No modifica el singleton de permisos. El selector cambia solo PlanProposal/TrialRole locales. La entrada rechaza release y profile mediante kDebugMode; no depende de assert. El target normal de release no alcanza el laboratorio en su grafo de imports.

Inicio propuesto filtra funciones por plan y rol; no muestra candados de planes superiores. Menú permite descubrir capacidades superiores y abre Actualiza tu plan → Ver planes → comparación derivada de la misma matriz. Rol denegado muestra permiso requerido, nunca una compra. El estado pendiente tiene etiqueta explícita. Los límites alcanzados simulan incorporación de usuarios/locales, no suspenden las operaciones existentes.

Las fichas incluidas muestran el contrato y el destino real del código. Deliberadamente no ejecutan ese destino con permisos simulados: hacerlo contra los servicios actuales podría iniciar peticiones reales. La navegación operativa se mantiene en la app normal, con autorización real. Este laboratorio acredita decisiones comerciales/UI, no venta, emisión, correo ni integración cloud. No es el nuevo Inicio final; esa construcción corresponde a Fase 1A.

## Pruebas y evidencia

`app/test/plan_proposal_test.dart`: matriz progresiva; voz Básico; Copiloto bloqueado Básico; Empresa sin salto de roles; límites 1/5/20 y 1/1/5; estados pendientes; menú, modal y comparación; aislamiento de Access y cierre del grafo de imports del laboratorio; main productivo no alcanza el selector.

Resultados de ejecución y capturas auténticas: consultar `docs/FACTURAVOZ_PLANES_EVIDENCIA.md`. Las capturas de laboratorio estarán rotuladas como simulación; nunca acreditan concesiones del Hub.

## Migración futura de licencias activas (NO ejecutada)

1. Respaldar y exportar contratos/versiones, concesiones, límites, add-ons y uso actual; verificar restauración sin modificar Hub/AWS en esta fase.
2. Aprobar nombres, alcance, claves, precios y reglas de transición por separado. Versionar la oferta como propuesta v1, sin editar la matriz histórica en sitio.
3. Implementar nuevas claves y permisos en endpoints, RPC/RLS y clientes con compatibilidad hacia atrás. No derivar autorización del nombre del plan. Ensayar sobre restauración aislada.
4. Calcular un diff por licencia: derechos actuales, propuesta y excepciones. Conservar la unión de derechos contratados y add-ons durante la transición; una sustitución por clave conserva su equivalente.
5. Mantener límites contratados o excepciones explícitas: jamás bajar de 2 a 1 usuario ni de ilimitado a 20 automáticamente. No eliminar miembros, sucursales o datos para cumplir el nuevo límite. Aprobar límites al renovar según contrato.
6. Simular cambios con cohortes de prueba, comprobar claims, permisos, caché, eventos, webhooks y sincronización Hub. Cualquier eliminación o pérdida de derecho requiere revisión específica.
7. Solo con aprobación: aplicar gradualmente, con monitoreo y rollback a la versión previa más excepciones conservadas. Mantener IDs de organización, usuarios, paquetes, endpoints, secretos e históricos.

No se ha actualizado Solvex Hub, Supabase, backend productivo ni web. No publicar esta propuesta ni una APK release. Detenerse para revisión de la matriz antes de Fase 1A.
''');
  File('../docs/FACTURAVOZ_NUEVOS_PLANES.md').writeAsStringSync(out.toString());
}
