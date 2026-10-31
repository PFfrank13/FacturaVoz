// Bienvenida animada del empleado la primera vez que entra a la empresa (Fase 2): su nombre, la empresa, su rol y
// qué puede hacer. Se marca como vista en la base de datos (mark_welcomed) para no repetirla.
import 'package:flutter/material.dart';

import '../access.dart';
import '../app_state.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class EmployeeWelcomeScreen extends StatefulWidget {
  const EmployeeWelcomeScreen({super.key});

  @override
  State<EmployeeWelcomeScreen> createState() => _EmployeeWelcomeScreenState();
}

class _EmployeeWelcomeScreenState extends State<EmployeeWelcomeScreen> {
  bool _busy = false;

  static List<(IconData, String)> abilities(String role) => switch (role) {
        'tecnico' => const [
            (Icons.assignment_rounded, 'Ver y actualizar TUS trabajos asignados'),
            (Icons.photo_camera_rounded, 'Subir fotos de antes y después'),
            (Icons.inventory_2_rounded, 'Anotar los materiales que usas'),
            (Icons.chat_rounded, 'Avisar al cliente por WhatsApp que vas en camino'),
          ],
        'cajero' => const [
            (Icons.point_of_sale_rounded, 'Vender y emitir boletas y facturas'),
            (Icons.payments_rounded, 'Registrar cobros (Yape, Plin, efectivo)'),
            (Icons.menu_book_rounded, 'Anotar fiados y abonos'),
            (Icons.lock_clock_rounded, 'Cerrar la caja del día'),
          ],
        'vendedor' => const [
            (Icons.request_quote_rounded, 'Cotizar y vender'),
            (Icons.people_alt_rounded, 'Atender a tus clientes y agendar visitas'),
            (Icons.emoji_events_rounded, 'Ver tus ventas y comisiones'),
          ],
        'finanzas' => const [
            (Icons.insights_rounded, 'Ver ventas, gastos y ganancia'),
            (Icons.account_balance_rounded, 'Conciliar el banco y revisar impuestos'),
            (Icons.receipt_long_rounded, 'Emitir y anular comprobantes'),
          ],
        _ => const [
            (Icons.dashboard_customize_rounded, 'Usar todas las funciones de la empresa'),
            (Icons.group_add_rounded, 'Invitar a tu equipo y darles permisos'),
          ],
      };

  Future<void> _start() async {
    setState(() => _busy = true);
    Haptics.success();
    await Access.instance.markWelcomed();
  }

  @override
  Widget build(BuildContext context) {
    final a = Access.instance;
    final org = AppState.instance.activeOrg?.name ?? 'tu empresa';
    final name = a.displayName.isNotEmpty ? a.displayName.split(' ').first : '';
    final list = abilities(a.role);
    return Scaffold(
      body: Aurora(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Reveal(child: BrandMark(size: 56)),
                  const SizedBox(height: 22),
                  Reveal(
                    index: 1,
                    child: Text(name.isEmpty ? '¡Bienvenido!' : '¡Hola, $name!',
                        style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                  ),
                  const SizedBox(height: 8),
                  Reveal(
                    index: 2,
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Ya eres parte de '),
                        TextSpan(text: org, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const TextSpan(text: ' como '),
                        TextSpan(text: a.roleLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const TextSpan(text: '.'),
                      ]),
                      style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.92), fontSize: 17, height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Reveal(index: 3, child: Text('Esto es lo que puedes hacer:', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600))),
                  const SizedBox(height: 12),
                  for (final (i, (icon, text)) in list.indexed)
                    Reveal(
                      index: 4 + i,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(Radii.lg)),
                        child: Row(children: [
                          Icon(icon, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(child: Text(text, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600))),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Reveal(
                    index: 4 + list.length,
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.indigoDeep, minimumSize: const Size.fromHeight(54)),
                        onPressed: _busy ? null : _start,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Empezar'),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
