import 'package:flutter/material.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';
import 'settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<InvoiceRecord>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Repo.listInvoices();
      if (mounted) {
        setState(() {
          _items = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  Future<void> _newInvoice() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewInvoiceScreen()));
    if (!mounted) return;
    await _load();
    if (id != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id)));
      if (mounted) _load();
    }
  }

  Future<void> _open(InvoiceRecord inv) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: inv.id)));
    if (mounted) _load();
  }

  /// Total del mes en la moneda del negocio. Excluye comprobantes rechazados por SUNAT.
  ({double total, int count}) _month(String currency) {
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    var total = 0.0;
    var count = 0;
    for (final i in _items ?? const <InvoiceRecord>[]) {
      if (!i.issueDate.startsWith(prefix) || i.currency != currency || i.fiscalStatus == 'rejected') continue;
      total += i.totals.total;
      count++;
    }
    return (total: round2(total), count: count);
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppState.instance.profile;
    final currency = profile?.currency ?? 'PEN';
    final m = _month(currency);
    final t = Theme.of(context);
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: DictateButton(size: 66, onPressed: _newInvoice),
      body: RefreshIndicator(
        onRefresh: _load,
        edgeOffset: 120,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _Header(name: profile?.businessName ?? '', currency: currency, total: m.total, count: m.count, loaded: _items != null)),
            if (_error != null && _items == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    FilledButton(onPressed: _load, child: const Text('Reintentar')),
                  ]),
                ),
              )
            else if (_items == null)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())))
            else if (_items!.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  title: 'Tu primera factura está a una frase',
                  body: 'Toca el micrófono y di el cliente, el servicio y el importe. La revisas antes de guardarla.',
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                sliver: SliverToBoxAdapter(child: Text('Comprobantes', style: t.textTheme.titleMedium)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 150),
                sliver: DecoratedSliver(
                  decoration: BoxDecoration(
                    color: t.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: t.colorScheme.outline),
                  ),
                  sliver: SliverList.separated(
                    itemCount: _items!.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 18, endIndent: 18),
                    itemBuilder: (context, i) => _Row(inv: _items![i], onTap: () => _open(_items![i])),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.currency, required this.total, required this.count, required this.loaded});
  final String name;
  final String currency;
  final double total;
  final int count;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final sym = currencySymbols[currency] ?? currency;
    final amount = total.toStringAsFixed(2);
    final parts = amount.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, top + 12, 24, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.indigo, Brand.indigoDeep]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              name.isEmpty ? 'FacturaVoz' : name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ]),
        const SizedBox(height: 18),
        Text('Facturado este mes',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.72), fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        if (!loaded)
          const SizedBox(height: 56)
        else
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(sym, style: const TextStyle(fontFamily: 'Inter', color: Brand.gold, fontSize: 26, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: whole, style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w700, letterSpacing: -1.6)),
                    TextSpan(text: '.${parts[1]}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7))),
                  ]),
                  style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ]),
        const SizedBox(height: 4),
        Text(
          !loaded ? '' : (count == 0 ? 'Aún sin comprobantes este mes' : (count == 1 ? '1 comprobante' : '$count comprobantes')),
          style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.72), fontSize: 13.5),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.inv, required this.onTap});
  final InvoiceRecord inv;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fiscal = inv.fiscalStatus;
    final label = fiscal == null ? statusLabel(inv.status) : fiscalStatusLabel(fiscal);
    final tone = fiscal == null ? (inv.status == 'paid' ? PillTone.ok : PillTone.neutral) : StatusPill.toneForFiscal(fiscal);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inv.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
              const SizedBox(height: 3),
              Text('${inv.fiscalNumber ?? inv.number}  ·  ${displayDate(inv.issueDate)}', style: t.textTheme.bodySmall),
              const SizedBox(height: 8),
              StatusPill(label, tone: tone),
            ]),
          ),
          const SizedBox(width: 12),
          Money(money(inv.totals.total, inv.currency), size: 16, weight: FontWeight.w700),
        ]),
      ),
    );
  }
}
