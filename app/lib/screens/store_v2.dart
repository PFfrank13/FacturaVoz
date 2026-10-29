// Tienda al extremo (Fase 4) + carta QR (módulo 12) + reservas y citas (módulo 14): opciones de la página pública.
// Se guardan en org_store (RLS: solo administradores escriben; el público solo ve lo publicado vía el servidor).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'branding.dart' show brandColors;
import 'team.dart' show dbMessage;

class StoreOptionsScreen extends StatefulWidget {
  const StoreOptionsScreen({super.key});

  @override
  State<StoreOptionsScreen> createState() => _StoreOptionsScreenState();
}

class _StoreOptionsScreenState extends State<StoreOptionsScreen> {
  Map<String, dynamic>? _row;
  final _about = TextEditingController();
  final _deliveryNote = TextEditingController();
  final _minOrder = TextEditingController();
  final _services = TextEditingController();
  final _hours = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _cols = 'theme_color, mode, about, pickup, delivery, delivery_note, min_order, show_stock, booking, booking_services, booking_hours';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_about, _deliveryNote, _minOrder, _services, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client.from('org_store').select(_cols).eq('org_id', Repo.activeOrgId!).maybeSingle();
      if (!mounted) return;
      if (r == null) {
        setState(() => _error = 'Primero activa tu tienda (pantalla anterior) y guarda su enlace.');
        return;
      }
      final m = Map<String, dynamic>.from(r);
      _about.text = (m['about'] ?? '') as String;
      _deliveryNote.text = (m['delivery_note'] ?? '') as String;
      _minOrder.text = m['min_order'] == null ? '' : qtyText((m['min_order'] as num).toDouble());
      _services.text = ((m['booking_services'] ?? const []) as List).join(', ');
      _hours.text = (m['booking_hours'] ?? '') as String;
      setState(() => _row = m);
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _save(Map<String, dynamic> fields, {bool quiet = false}) async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.from('org_store').update(fields).eq('org_id', Repo.activeOrgId!);
      if (!mounted) return;
      setState(() => _row = {...?_row, ...fields});
      if (!quiet) showSuccess(context, 'Guardado');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is AppException ? e.message : dbMessage(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveTexts() => _save({
        'about': _about.text.trim().isEmpty ? null : _about.text.trim(),
        'delivery_note': _deliveryNote.text.trim().isEmpty ? null : _deliveryNote.text.trim(),
        'min_order': parseDecimal(_minOrder.text),
        'booking_services': _services.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).take(30).toList(),
        'booking_hours': _hours.text.trim().isEmpty ? null : _hours.text.trim(),
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = _row;
    final admin = Access.instance.can('settings');
    return Scaffold(
      appBar: AppBar(title: const Text('Opciones de la tienda')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : r == null
              ? const SkeletonList(count: 3)
              : AbsorbPointer(
                  absorbing: _busy || !admin,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                    const SectionTitle('¿Qué es tu página?'),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'tienda', label: Text('Tienda'), icon: Icon(Icons.storefront_rounded)),
                        ButtonSegment(value: 'carta', label: Text('Carta (restaurante)'), icon: Icon(Icons.restaurant_menu_rounded)),
                      ],
                      selected: {(r['mode'] ?? 'tienda') as String},
                      onSelectionChanged: (s) => _save({'mode': s.first}),
                    ),
                    const SizedBox(height: 6),
                    Text('En modo Carta, los pedidos llevan número de mesa (QR por mesa) y llegan a Comandas.', style: t.textTheme.bodySmall),
                    const SizedBox(height: 16),
                    const SectionTitle('Color'),
                    Wrap(spacing: 10, children: [
                      for (final c in brandColors)
                        Pressable(
                          onTap: () => _save({'theme_color': c}),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Color(int.parse('FF${c.substring(1)}', radix: 16)),
                              shape: BoxShape.circle,
                              border: Border.all(color: (r['theme_color'] ?? '').toString().toUpperCase() == c ? t.colorScheme.onSurface : Colors.transparent, width: 3),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    const SectionTitle('Entrega'),
                    SwitchListTile(contentPadding: EdgeInsets.zero, value: r['pickup'] != false, onChanged: (v) => _save({'pickup': v}), title: const Text('Recojo en tienda')),
                    SwitchListTile(contentPadding: EdgeInsets.zero, value: r['delivery'] == true, onChanged: (v) => _save({'delivery': v}), title: const Text('Delivery')),
                    if (r['delivery'] == true) TextField(controller: _deliveryNote, maxLength: 200, decoration: const InputDecoration(labelText: 'Nota de delivery (zonas, costo)')),
                    TextField(controller: _minOrder, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Pedido mínimo (opcional)')),
                    SwitchListTile(contentPadding: EdgeInsets.zero, value: r['show_stock'] == true, onChanged: (v) => _save({'show_stock': v}), title: const Text('Mostrar "quedan pocos" según stock')),
                    const SizedBox(height: 10),
                    TextField(controller: _about, maxLines: 3, maxLength: 400, decoration: const InputDecoration(labelText: 'Sobre tu negocio (aparece arriba)')),
                    const SizedBox(height: 16),
                    const SectionTitle('Reservas y citas en línea'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: r['booking'] == true,
                      onChanged: Access.instance.has('agenda') ? (v) => _save({'booking': v}) : null,
                      title: const Text('Permitir reservar desde tu página'),
                      subtitle: Text(Access.instance.has('agenda') ? 'Las reservas llegan a tu Agenda y te avisamos.' : 'Disponible en planes con Agenda.'),
                    ),
                    if (r['booking'] == true) ...[
                      TextField(controller: _services, decoration: const InputDecoration(labelText: 'Servicios que se pueden reservar (separados por coma)', hintText: 'Corte, Tinte, Manicure')),
                      const SizedBox(height: 10),
                      TextField(controller: _hours, maxLength: 120, decoration: const InputDecoration(labelText: 'Horario de atención', hintText: 'Lun a sáb 9 am – 7 pm')),
                    ],
                    const SizedBox(height: 16),
                    GradientButton(label: 'Guardar textos', icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _saveTexts),
                    if (!admin) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Solo el dueño o un administrador puede cambiar esto.', style: t.textTheme.bodySmall)),
                    const SizedBox(height: 10),
                    Text('Tip: cada producto puede tener foto, categoría, descripción y precio por mayor (en Productos).', style: t.textTheme.bodySmall?.copyWith(color: Brand.indigo)),
                  ]),
                ),
    );
  }
}
