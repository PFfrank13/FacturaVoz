// Precios y promociones (Fase 8 · módulo 10) + Puntos, cupones y cumpleaños (módulo 11).
// Las promociones se aplican al vender (Venta rápida y factura) eligiendo el MEJOR precio vigente; nunca negativo.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../logic/pricing.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'client_profile.dart';
import 'team.dart' show dbMessage;

const promoKinds = {'porcentaje': '% de descuento', 'monto': 'Monto fijo menos', 'volumen': 'Llevando N o más (% menos)'};

class PromosScreen extends StatefulWidget {
  const PromosScreen({super.key});

  @override
  State<PromosScreen> createState() => _PromosScreenState();
}

class _PromosScreenState extends State<PromosScreen> {
  List<Promo>? _promos;
  List<Coupon> _coupons = const [];
  List<Product> _products = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await V2Repo.promotions();
      final c = await V2Repo.coupons();
      final prods = await Repo.listProducts(activeOnly: true).catchError((_) => <Product>[]);
      if (mounted) {
        setState(() {
          _promos = p;
          _coupons = c;
          _products = prods;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _editPromo([Promo? p]) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PromoForm(promo: p, products: _products),
    );
    if (ok == true) _load();
  }

  Future<void> _newCoupon() async {
    final code = TextEditingController(), value = TextEditingController(), uses = TextEditingController();
    var kind = 'porcentaje';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nuevo cupón'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Código (ej.: BIENVENIDO10)')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'porcentaje', label: Text('%')), ButtonSegment(value: 'monto', label: Text('Monto'))],
              selected: {kind},
              onSelectionChanged: (s) => set(() => kind = s.first),
            ),
            TextField(controller: value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: kind == 'porcentaje' ? 'Porcentaje' : 'Monto')),
            TextField(controller: uses, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Usos máximos (vacío = sin límite)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
          ],
        ),
      ),
    );
    final c = code.text.trim(), v = parseDecimal(value.text) ?? 0, u = int.tryParse(uses.text.trim());
    disposeAfterClose([code, value, uses]);
    if (ok != true || c.length < 3 || v <= 0) return;
    try {
      await V2Repo.saveCoupon(code: c, kind: kind, value: v, maxUses: u);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dbMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final today = todayIso();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Precios y promociones'), bottom: const TabBar(tabs: [Tab(text: 'Promociones'), Tab(text: 'Cupones')])),
        body: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
            : _promos == null
                ? const SkeletonList()
                : TabBarView(children: [
                    ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
                      Text('El precio por mayor se define en cada producto. Aquí van las ofertas por tiempo o cantidad.', style: t.textTheme.bodySmall),
                      const SizedBox(height: 10),
                      if (_promos!.isEmpty) const EmptyState(title: 'Sin promociones', body: 'Crea una: "10 % en gaseosas este fin de semana" o "llevando 6, 15 % menos".'),
                      for (final p in _promos!)
                        Card(
                          child: ListTile(
                            leading: Icon(Icons.local_offer_rounded, color: p.liveOn(today) ? Brand.ok : t.colorScheme.onSurfaceVariant),
                            title: Text(p.name),
                            subtitle: Text([
                              p.kind == 'monto' ? '${money(p.value, 'PEN')} menos' : '${p.value.toStringAsFixed(0)} % menos',
                              if (p.minQty != null) 'desde ${qtyText(p.minQty!)} unid.',
                              p.productIds.isEmpty ? 'todos los productos' : '${p.productIds.length} productos',
                              if (p.endsOn != null) 'hasta ${displayDate(p.endsOn!)}',
                              if (!p.liveOn(today)) 'no vigente',
                            ].join(' · ')),
                            onTap: () => _editPromo(p),
                          ),
                        ),
                      const SizedBox(height: 8),
                      FilledButton.icon(onPressed: () => _editPromo(), icon: const Icon(Icons.add_rounded), label: const Text('Nueva promoción')),
                    ]),
                    ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
                      if (_coupons.isEmpty) const EmptyState(title: 'Sin cupones', body: 'Crea códigos para tus clientes (redes, WhatsApp) y úsalos al vender.'),
                      for (final c in _coupons)
                        Card(
                          child: SwitchListTile(
                            value: c.active,
                            onChanged: (v) async {
                              await V2Repo.setCouponActive(c.id, v).catchError((_) {});
                              _load();
                            },
                            title: Text(c.code, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: 1)),
                            subtitle: Text([
                              c.kind == 'monto' ? '${money(c.value, 'PEN')} menos' : '${c.value.toStringAsFixed(0)} % menos',
                              '${c.uses}${c.maxUses != null ? '/${c.maxUses}' : ''} usos',
                              if (c.expiresOn != null) 'vence ${displayDate(c.expiresOn!)}',
                            ].join(' · ')),
                          ),
                        ),
                      const SizedBox(height: 8),
                      FilledButton.icon(onPressed: _newCoupon, icon: const Icon(Icons.add_rounded), label: const Text('Nuevo cupón')),
                    ]),
                  ]),
      ),
    );
  }
}

class _PromoForm extends StatefulWidget {
  const _PromoForm({this.promo, required this.products});
  final Promo? promo;
  final List<Product> products;

  @override
  State<_PromoForm> createState() => _PromoFormState();
}

class _PromoFormState extends State<_PromoForm> {
  late final _name = TextEditingController(text: widget.promo?.name ?? '');
  late final _value = TextEditingController(text: widget.promo?.value.toString() ?? '');
  late final _min = TextEditingController(text: widget.promo?.minQty?.toString() ?? '');
  late String _kind = widget.promo?.kind ?? 'porcentaje';
  late final Set<String> _ids = {...?widget.promo?.productIds};
  late String? _ends = widget.promo?.endsOn;
  late bool _active = widget.promo?.active ?? true;
  bool _busy = false;
  String _msg = '';

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseDecimal(_value.text) ?? 0;
    if (_name.text.trim().isEmpty || v <= 0 || (_kind != 'monto' && v > 90)) {
      setState(() => _msg = 'Pon un nombre y un valor válido (máximo 90 %).');
      return;
    }
    setState(() => _busy = true);
    try {
      await V2Repo.savePromo(
        id: widget.promo?.id,
        name: _name.text,
        kind: _kind,
        value: v,
        productIds: _ids.toList(),
        minQty: _kind == 'volumen' ? (parseDecimal(_min.text) ?? 2) : parseDecimal(_min.text),
        startsOn: widget.promo?.startsOn ?? todayIso(),
        endsOn: _ends,
        active: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _msg = dbMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(shrinkWrap: true, children: [
        Text(widget.promo == null ? 'Nueva promoción' : 'Editar promoción', style: t.textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre (lo verá el cliente)')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Tipo'),
          items: [for (final e in promoKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _kind = v ?? 'porcentaje'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _kind == 'monto' ? 'Monto menos' : '% menos'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _min, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Desde cantidad'))),
        ]),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: Text(_ends == null ? 'Sin fecha de fin' : 'Hasta ${displayDate(_ends!)}'),
          onTap: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
            if (d != null) setState(() => _ends = todayIso(d));
          },
          trailing: _ends == null ? null : IconButton(onPressed: () => setState(() => _ends = null), icon: const Icon(Icons.close_rounded)),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Activa')),
        Text('Productos (ninguno marcado = todos)', style: t.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in widget.products.take(80))
            FilterChip(
              label: Text(p.name),
              selected: _ids.contains(p.id),
              onSelected: (v) => setState(() => v ? _ids.add(p.id) : _ids.remove(p.id)),
            ),
        ]),
        if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg, style: const TextStyle(color: Brand.bad))),
        const SizedBox(height: 14),
        GradientButton(label: 'Guardar', icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _save),
        if (widget.promo != null)
          TextButton(
            onPressed: () async {
              await V2Repo.deletePromo(widget.promo!.id).catchError((_) {});
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Eliminar', style: TextStyle(color: Brand.bad)),
          ),
      ]),
    );
  }
}

// ═════════════════════════ Puntos y fidelización ═════════════════════════
class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  List<LoyaltyBalance>? _list;
  OrgSettings? _s;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await V2Repo.settings(refresh: true);
      final l = await V2Repo.loyalty();
      if (mounted) {
        setState(() {
          _s = s;
          _list = l..sort((a, b) => b.points.compareTo(a.points));
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _rate() async {
    final s = _s;
    if (s == null) return;
    final c = TextEditingController(text: s.loyaltyRate == 0 ? '' : s.loyaltyRate.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Puntos por compra'),
        content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Puntos por cada sol cobrado (ej.: 1)', helperText: '0 = programa de puntos apagado')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    final v = parseDecimal(c.text) ?? 0;
    disposeAfterClose([c]);
    if (ok != true) return;
    s.loyaltyRate = v.clamp(0, 100).toDouble();
    try {
      await V2Repo.saveSettings(s);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dbMessage(e))));
    }
  }

  Future<void> _redeem(LoyaltyBalance b) async {
    final pts = TextEditingController(), why = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Canjear puntos de ${b.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Tiene ${b.points} puntos.'),
          TextField(controller: pts, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puntos a canjear')),
          TextField(controller: why, decoration: const InputDecoration(labelText: 'Premio (ej.: gaseosa gratis)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Canjear')),
        ],
      ),
    );
    final p = int.tryParse(pts.text.trim()) ?? 0;
    final w = why.text;
    disposeAfterClose([pts, why]);
    if (ok != true || p <= 0 || p > b.points) return;
    try {
      await V2Repo.redeemPoints(b.clientId, p, w);
      if (mounted) showSuccess(context, 'Canje registrado 🎁');
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dbMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Puntos y fidelización')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _list == null || s == null
              ? const SkeletonList()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                  SoftCard(
                    child: Column(children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.loyalty_rounded, color: Brand.goldDeep),
                        title: Text(s.loyaltyRate > 0 ? '${s.loyaltyRate} punto(s) por cada sol cobrado' : 'Programa de puntos apagado'),
                        subtitle: const Text('Los puntos se suman solos al registrar cada cobro.'),
                        trailing: TextButton(onPressed: _rate, child: const Text('Cambiar')),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: s.birthdayGreetings,
                        onChanged: (v) async {
                          s.birthdayGreetings = v;
                          await V2Repo.saveSettings(s).catchError((_) {});
                          setState(() {});
                        },
                        title: const Text('Recordarme los cumpleaños'),
                        subtitle: const Text('Aparecen en "Para hoy" con un saludo listo para WhatsApp.'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  if (_list!.isEmpty)
                    const EmptyState(title: 'Aún sin puntos', body: 'Cuando actives los puntos, tus clientes los irán sumando con cada compra.')
                  else
                    for (final b in _list!)
                      ListTile(
                        leading: CircleAvatar(child: Text(b.name.isEmpty ? '?' : b.name.characters.first.toUpperCase())),
                        title: Text(b.name),
                        subtitle: Text('${b.points} puntos', style: t.textTheme.bodySmall),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (b.phone.isNotEmpty)
                            IconButton(
                              tooltip: 'Avisarle',
                              onPressed: () => openWhatsApp(context, b.phone, 'Hola ${b.name.split(' ').first}, tienes ${b.points} puntos en ${AppState.instance.activeOrg?.name ?? 'nuestro negocio'}. ¡Úsalos en tu próxima compra!'),
                              icon: const Icon(Icons.chat_rounded),
                            ),
                          TextButton(onPressed: b.points > 0 ? () => _redeem(b) : null, child: const Text('Canjear')),
                        ]),
                      ),
                ]),
    );
  }
}
