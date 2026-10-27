import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../errors.dart';
import '../growth.dart';
import '../models.dart';
import '../services/growth_repo.dart';
import '../services/pro_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Fija la meta de ventas del mes. Muestra al instante la proyección de cierre y cuánto vender por día.
/// Devuelve la meta guardada (o null si se cerró sin cambios).
Future<double?> showGoalSheet(BuildContext context, {double? current, double salesSoFar = 0}) async {
  final cur = AppState.instance.profile?.currency ?? 'PEN';
  final ctrl = TextEditingController(text: current == null || current <= 0 ? '' : qtyText(current));
  var err = '';
  var saving = false;
  double? saved;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final t = Theme.of(ctx);
      final goal = parseDecimal(ctrl.text) ?? 0;
      final g = goalProgress(goal: goal, sales: salesSoFar, today: todayIso());
      final suggestions = <double>{
        if (g.projected > 0) ((g.projected * 1.1) / 100).ceil() * 100.0,
        if (g.projected > 0) ((g.projected * 1.25) / 100).ceil() * 100.0,
        if (current != null && current > 0) current,
      }.toList()
        ..sort();
      Future<void> save() async {
        final v = parseDecimal(ctrl.text);
        if (v != null && (v < 0 || v > 1000000000)) {
          setS(() => err = 'Escribe un monto válido');
          return;
        }
        setS(() {
          saving = true;
          err = '';
        });
        try {
          await GrowthRepo.setMonthlyGoal(v == null || v == 0 ? null : v);
          saved = v ?? 0;
          if (ctx.mounted) Navigator.pop(ctx);
        } catch (e) {
          setS(() {
            saving = false;
            err = ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261102_revolucion.sql.' : friendly(e);
          });
        }
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Tu meta de ventas del mes', style: t.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Una meta clara vende más: te digo cada día si vas bien y cuánto te falta.', style: t.textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            onChanged: (_) => setS(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: const TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w700),
            decoration: InputDecoration(labelText: 'Meta (con IGV)', prefixText: '${currencySymbols[cur] ?? cur} '),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in suggestions)
                ActionChip(
                  label: Text(money(s, cur)),
                  onPressed: () {
                    Haptics.select();
                    ctrl.text = qtyText(s);
                    setS(() {});
                  },
                ),
            ]),
          ],
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: goal <= 0
                ? Text('Al ritmo actual cerrarías el mes en ${money(g.projected, cur)}.', key: const ValueKey('none'), style: t.textTheme.bodyMedium)
                : Container(
                    key: const ValueKey('goal'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: (g.onTrack ? Brand.ok : Brand.warn).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
                    child: Text(
                      g.reached
                          ? '¡Ya superaste esta meta! Ponte una más alta.'
                          : g.onTrack
                              ? 'Vas bien: al ritmo actual cierras en ${money(g.projected, cur)}.'
                              : 'Necesitas vender ${money(g.neededPerDay, cur)} por día los próximos ${g.daysLeft} días (hoy vas a ${money(g.projected, cur)} al cierre).',
                      style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
          if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: const TextStyle(color: Brand.bad))),
          const SizedBox(height: 16),
          GradientButton(label: saving ? 'Guardando…' : 'Guardar meta', icon: Icons.flag_rounded, busy: saving, onPressed: saving ? null : save),
        ]),
      );
    }),
  );
  disposeAfterClose([ctrl]);
  return saved;
}
