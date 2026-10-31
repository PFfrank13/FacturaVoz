// "¿Cuánto me queda?" + estimador SUNAT (Fase 8 · módulo 4). Todo REFERENCIAL: se muestra siempre
// "confírmalo con tu contador". Usa las mismas reglas que el servidor (logic/taxes.dart ↔ backend/src/lib/taxes.ts).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../access.dart';
import '../app_state.dart';
import '../logic/taxes.dart';
import '../models.dart';
import '../models_pro.dart';
import '../services/pro_repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'assistant.dart';

class TaxesScreen extends StatefulWidget {
  const TaxesScreen({super.key});

  @override
  State<TaxesScreen> createState() => _TaxesScreenState();
}

class _TaxesScreenState extends State<TaxesScreen> {
  String? _regime;
  double _base = 0, _tax = 0, _expBase = 0, _expTax = 0, _yearBase = 0;
  bool _loading = true;
  String? _error;

  String get _cur => AppState.instance.profile?.currency.isNotEmpty == true ? AppState.instance.profile!.currency : 'PEN';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final from = todayIso(DateTime(now.year, now.month, 1));
      final to = todayIso(DateTime(now.year, now.month + 1, 1));
      final yearFrom = todayIso(DateTime(now.year, 1, 1));
      final s = await V2Repo.settings();
      final month = await V2Repo.salesSummary(from, to, 'PEN');
      final year = await V2Repo.salesSummary(yearFrom, to, 'PEN');
      var expenses = const <Expense>[];
      try {
        expenses = await ProRepo.listExpenses(from, to);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _regime = s.taxRegime;
        _base = ((month?['sales_base'] as num?) ?? 0).toDouble();
        _tax = ((month?['sales_tax'] as num?) ?? 0).toDouble();
        _yearBase = ((year?['sales_base'] as num?) ?? 0).toDouble();
        final pen = expenses.where((e) => e.currency == 'PEN');
        _expBase = pen.fold(0.0, (a, e) => a + e.base);
        _expTax = pen.fold(0.0, (a, e) => a + e.tax);
        _loading = false;
        _error = month == null ? 'Ejecuta las migraciones v2.0 en Supabase para ver tus cifras reales.' : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = V2Repo.missingHint(e);
        });
      }
    }
  }

  Future<void> _setRegime(String r) async {
    setState(() => _regime = r);
    if (!Access.instance.can('settings')) return; // se calcula igual, pero solo el administrador lo guarda
    try {
      await V2Repo.saveSettingsFields({'tax_regime': r});
      if (mounted) showSuccess(context, 'Régimen guardado');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final est = estimateTaxes(regime: _regime, monthSalesBase: _base, monthSalesTax: _tax, monthPurchasesTax: _expTax, yearSalesBase: _yearBase);
    final real = RealProfit(sales: _base, costOfSales: 0, expenses: _expBase, taxes: est.renta);
    final now = DateTime.now();
    final daysLeft = math.max(1, DateTime(now.year, now.month + 1, 0).day - now.day + 1);
    final perDay = est.total / daysLeft;
    return Scaffold(
      appBar: AppBar(title: const Text('¿Cuánto me queda?')),
      body: _loading
          ? const SkeletonList(count: 4)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: SoftCard(color: Brand.warn.withValues(alpha: 0.1), child: Text(_error!))),
                Reveal(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(Radii.xl)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Este mes te queda (estimado)', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85))),
                      CountUp(value: real.net, builder: (_, v) => Text(money(v, _cur), style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800))),
                      const SizedBox(height: 6),
                      Text('Ventas sin IGV ${money(_base, _cur)} − gastos ${money(_expBase, _cur)} − renta ${money(est.renta, _cur)}',
                          style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Reveal(
                  index: 1,
                  child: SoftCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.savings_rounded, color: Brand.warn),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Guarda para SUNAT: ${money(est.total, _cur)}', style: t.textTheme.titleMedium)),
                      ]),
                      const SizedBox(height: 4),
                      Text('Eso es unos ${money(perDay, _cur)} por día hasta fin de mes. Se paga el mes siguiente según tu cronograma (último dígito del RUC).',
                          style: t.textTheme.bodySmall),
                      const Divider(height: 22),
                      _row('IGV por pagar (ventas − compras)', est.igv),
                      _row(est.rentaRate == null ? (_regime == 'nrus' ? 'Cuota Nuevo RUS' : 'Renta') : 'Renta (${(est.rentaRate! * 100).toStringAsFixed(1)} % de tus ventas)', est.renta),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Reveal(
                  index: 2,
                  child: SoftCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Tu régimen tributario', style: t.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final e in regimes.entries) ChoiceChip(label: Text(e.value), selected: _regime == e.key, onSelected: (_) => _setRegime(e.key)),
                      ]),
                      const SizedBox(height: 6),
                      Text('¿No sabes cuál es? Está en tu Ficha RUC (SUNAT) o pregúntale a tu contador.', style: t.textTheme.bodySmall),
                    ]),
                  ),
                ),
                for (final w in est.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SoftCard(
                      color: Brand.bad.withValues(alpha: 0.08),
                      child: Row(children: [const Icon(Icons.warning_amber_rounded, color: Brand.bad), const SizedBox(width: 8), Expanded(child: Text(w))]),
                    ),
                  ),
                for (final n in est.notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.info_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(n, style: t.textTheme.bodySmall)),
                    ]),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => openCopilot(context, ask: 'Explícame en palabras simples cuánto debo pagar a SUNAT este mes y cuánto me queda.'),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Pregúntale al copiloto'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Estimado referencial con tus ventas emitidas (sin borradores ni rechazadas) y tus gastos registrados. No incluye costo de mercadería, planillas ni detracciones. Confírmalo con tu contador.',
                  style: t.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
    );
  }

  Widget _row(String label, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Expanded(child: Text(label)), Money(money(v, _cur), weight: FontWeight.w700)]),
      );
}
