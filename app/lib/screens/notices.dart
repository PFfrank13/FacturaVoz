// Avisos de pago de Yape / Plin / banco (Fase 8 · módulo 18). Pegas (o compartes) el texto de la notificación,
// la app lee monto, quién pagó y el código de operación, te sugiere la factura que coincide y registra el cobro.
// Nota honesta: leer las notificaciones del teléfono AUTOMÁTICAMENTE exige un permiso especial de Android con código
// nativo; está en la HOJA_DE_RUTA. Hoy funciona copiando/pegando (2 toques) y no se registra nada sin tu confirmación.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../errors.dart';
import '../logic/notice_parser.dart';
import '../logic/search_score.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../services/live.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'client_profile.dart' show shortDateTime;

class PaymentNoticesScreen extends StatefulWidget {
  const PaymentNoticesScreen({super.key});

  @override
  State<PaymentNoticesScreen> createState() => _PaymentNoticesScreenState();
}

class _PaymentNoticesScreenState extends State<PaymentNoticesScreen> with LiveReload<PaymentNoticesScreen> {
  final _text = TextEditingController();
  List<NoticeRow>? _notices;
  List<InvoiceRecord> _open = const [];
  PaymentNotice? _parsed;
  String? _error;
  bool _busy = false;
  int _shake = 0;

  @override
  List<String> get liveTables => const ['payment_notices', 'invoices', 'payments'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _notices = LiveCache.get<List<NoticeRow>>('notices.list');
    _open = LiveCache.get<List<InvoiceRecord>>('notices.open') ?? const [];
    _load();
    startLive(); // tiempo real
  }

  @override
  void dispose() {
    stopLive();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final n = await V2Repo.notices();
      final o = await ProRepo.listReceivables().catchError((_) => <InvoiceRecord>[]);
      LiveCache.put('notices.list', n);
      LiveCache.put('notices.open', o);
      if (mounted) {
        setState(() {
          _notices = n;
          _open = o;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text ?? '';
    if (t.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Primero copia el texto de la notificación de Yape o Plin.')));
      return;
    }
    _text.text = t;
    _read();
  }

  void _read() {
    final p = parsePaymentNotice(_text.text);
    setState(() {
      _parsed = p;
      if (p == null) _shake++;
    });
  }

  /// Facturas por cobrar con ese saldo exacto (primero las del cliente que se parece al nombre del pagador).
  List<InvoiceRecord> _matches(PaymentNotice p) {
    final list = _open.where((i) => (i.balance - p.amount).abs() < 0.01).toList();
    list.sort((a, b) => matchScore(p.payer, b.clientName).compareTo(matchScore(p.payer, a.clientName)));
    return list;
  }

  Future<void> _save({InvoiceRecord? inv}) async {
    final p = _parsed;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final id = await V2Repo.addNotice(app: p.app, amount: p.amount, payer: p.payer, operation: p.operation, raw: p.raw);
      if (inv != null) {
        await Repo.addPayment(
          invoiceId: inv.id,
          amount: p.amount > inv.balance ? inv.balance : p.amount,
          method: p.app == 'banco' ? 'transferencia' : (p.app == 'otro' ? 'otro' : p.app),
          note: [if (p.payer.isNotEmpty) p.payer, if (p.operation.isNotEmpty) 'op. ${p.operation}'].join(' · '),
        );
        await V2Repo.setNotice(id, status: 'aplicado', invoiceId: inv.id);
        AppState.instance.bump();
      }
      if (!mounted) return;
      Haptics.success();
      showSuccess(context, inv != null ? 'Cobro registrado en ${inv.fiscalNumber ?? inv.number}' : 'Aviso guardado');
      _text.clear();
      setState(() => _parsed = null);
      _load();
    } catch (e) {
      final dup = e.toString().contains('23505');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dup ? 'Ese código de operación ya se registró antes.' : friendly(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = _parsed;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    return Scaffold(
      appBar: AppBar(title: const Text('Avisos de Yape y Plin')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : AbsorbPointer(
              absorbing: _busy,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                Text('Copia la notificación de Yape/Plin (mantén presionado → Copiar) y pégala aquí.', style: t.textTheme.bodySmall),
                const SizedBox(height: 10),
                Shake(
                  trigger: _shake,
                  child: TextField(
                    controller: _text,
                    maxLines: 4,
                    onChanged: (_) => _read(),
                    decoration: const InputDecoration(hintText: '¡Yape! JUAN PEREZ te envió un pago por S/ 25.50…'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: FilledButton.tonalIcon(onPressed: _paste, icon: const Icon(Icons.content_paste_rounded), label: const Text('Pegar'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: _read, icon: const Icon(Icons.search_rounded), label: const Text('Leer'))),
                ]),
                if (_text.text.trim().isNotEmpty && p == null)
                  const Padding(padding: EdgeInsets.only(top: 8), child: Text('No encontré un monto en "S/ …". Revisa el texto.', style: TextStyle(color: Brand.bad))),
                if (p != null) ...[
                  const SizedBox(height: 12),
                  Reveal(
                    child: SoftCard(
                      color: Brand.ok.withValues(alpha: 0.08),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          TagChip(p.app.toUpperCase(), color: Brand.lilac),
                          const Spacer(),
                          Money(money(p.amount, cur), size: 22, weight: FontWeight.w800, color: Brand.ok),
                        ]),
                        const SizedBox(height: 6),
                        Text(p.payer.isEmpty ? 'Pagador no identificado' : 'De: ${p.payer}', style: t.textTheme.titleSmall),
                        if (p.operation.isNotEmpty) Text('Operación / código: ${p.operation}', style: t.textTheme.bodySmall),
                        const Divider(height: 22),
                        Builder(builder: (context) {
                          final m = _matches(p);
                          if (m.isEmpty) {
                            return Text('Ninguna factura por cobrar tiene saldo de ${money(p.amount, cur)}. Puedes guardar el aviso igual.', style: t.textTheme.bodySmall);
                          }
                          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text('¿Es el pago de…?', style: t.textTheme.labelLarge),
                            for (final i in m.take(4))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${i.fiscalNumber ?? i.number} · ${i.clientName}'),
                                subtitle: Text('Saldo ${money(i.balance, i.currency)}'),
                                trailing: FilledButton(onPressed: () => _save(inv: i), child: const Text('Registrar')),
                              ),
                          ]);
                        }),
                        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _save(), child: const Text('Solo guardar el aviso'))),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const SectionTitle('Últimos avisos'),
                if (_notices == null)
                  const SkeletonList(count: 2)
                else if (_notices!.isEmpty)
                  Text('Aún no registraste avisos.', style: t.textTheme.bodySmall)
                else
                  for (final n in _notices!)
                    ListTile(
                      dense: true,
                      leading: Icon(n.status == 'aplicado' ? Icons.check_circle_rounded : Icons.notifications_rounded, color: n.status == 'aplicado' ? Brand.ok : null),
                      title: Text('${n.app.toUpperCase()} · ${money(n.amount, cur)}${n.payer.isNotEmpty ? ' · ${n.payer}' : ''}'),
                      subtitle: Text([if (n.createdAt != null) shortDateTime(n.createdAt!), n.status == 'aplicado' ? 'cobro registrado' : 'sin factura'].join(' · ')),
                      trailing: n.status == 'nuevo'
                          ? IconButton(
                              tooltip: 'Descartar',
                              onPressed: () async {
                                await V2Repo.setNotice(n.id, status: 'descartado').catchError((_) {});
                                _load();
                              },
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                    ),
              ]),
            ),
    );
  }
}
