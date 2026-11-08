import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../services/retail_purchase.dart';

/// Settles an already received supplier purchase, without touching stock.
/// A pending local operation always takes precedence over a new payment.
class RetailSettlementScreen extends StatefulWidget {
  const RetailSettlementScreen({super.key, this.receipt});
  final Map<String, dynamic>? receipt;

  @override
  State<RetailSettlementScreen> createState() => _RetailSettlementScreenState();
}

class _RetailSettlementScreenState extends State<RetailSettlementScreen> {
  final _reference = TextEditingController();
  PendingRetailSettlement? _pending;
  String _method = 'efectivo';
  bool _confirmed = false;
  bool _busy = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final org = Repo.activeOrgId;
    final user = Supabase.instance.client.auth.currentUser?.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (org == null || user == null) {
        throw const FormatException('Selecciona una empresa e inicia sesión.');
      }
      final p = await RetailSettlementStore.load(user, org);
      if (!mounted || Repo.activeOrgId != org ||
          Supabase.instance.client.auth.currentUser?.id != user) {
        return;
      }
      setState(() => _pending = p);
    } catch (e) {
      if (mounted && Repo.activeOrgId == org &&
          Supabase.instance.client.auth.currentUser?.id == user) {
        setState(() => _error = 'No se puede leer el pago anterior. No se sobrescribirá: $e');
      }
    } finally {
      if (mounted && Repo.activeOrgId == org &&
          Supabase.instance.client.auth.currentUser?.id == user) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pay() async {
    // An uncertain settlement must remain retryable with its original ID,
    // even after a network error. Only block creating a NEW payment while
    // local recovery is broken.
    if (_busy || _loading || (_error != null && _pending == null)) return;
    if (_pending == null && !_confirmed) return;
    final org = Repo.activeOrgId;
    final user = Supabase.instance.client.auth.currentUser?.id;
    if (org == null || user == null) return;
    final p = _pending;
    if (p == null && widget.receipt?['payment_method'] != 'pendiente') return;
    final receiptId = widget.receipt?['id'] as String?;
    if (p == null && (receiptId == null || receiptId.isEmpty)) return;
    setState(() => _busy = true);
    try {
      final checkout = p ?? PendingRetailSettlement(
        orgId: org, userId: user, requestId: Repo.newRequestId(),
        receiptId: receiptId!, method: _method, evidence: _reference.text.trim(),
      );
      if (checkout.orgId != org || checkout.userId != user) {
        throw AppException('El pago pendiente pertenece a otra empresa.');
      }
      if (p == null) {
        // Must be durable before the network call. If the response is lost,
        // replaying the SAME request ID is safe and cannot record another expense.
        await RetailSettlementStore.save(checkout);
      }
      if (!mounted) return;
      setState(() => _pending = checkout);
      final id = await RetailSettlementRepo.settle(checkout);
      await RetailSettlementStore.clear(checkout);
      if (!mounted || Repo.activeOrgId != org ||
          Supabase.instance.client.auth.currentUser?.id != user) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pago registrado sin duplicados · ${id.substring(0, 8)}'),
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Pago no confirmado. Conservamos la misma solicitud para recuperar: ${friendly(e)}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pending;
    final receipt = widget.receipt;
    final amount = ((receipt?['total_cents'] as num?) ?? 0).toDouble() / 100;
    final currency = (receipt?['currency'] ?? 'PEN') as String;
    return Scaffold(
      appBar: AppBar(title: const Text('Pago al proveedor')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && p == null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center),
                TextButton(onPressed: _restore, child: const Text('Reintentar lectura')),
              ]),
            ))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (p != null) ...[
                  const Icon(Icons.sync_lock_rounded, size: 44),
                  const SizedBox(height: 12),
                  const Text('El pago anterior pudo haberse registrado. '
                      'Reenvía la misma solicitud; nunca generes una segunda.'),
                  const SizedBox(height: 12),
                  Text('Compra: ${p.receiptId}'),
                  Text('Método: ${paymentMethods[p.method] ?? p.method}'),
                  if (p.evidence.isNotEmpty) Text('Referencia: ${p.evidence}'),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _pay,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Recuperar pago sin duplicarlo'),
                  ),
                ] else if (receipt != null &&
                    receipt['payment_method'] == 'pendiente') ...[
                  Text(receipt['supplier_name']?.toString() ?? 'Proveedor',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Saldo total: ${money(amount, currency)}',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  const Text('Se registrará un único pago completo. '
                      'La mercadería ya ingresó y no volverá a sumarse al stock.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    items: const [
                      DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                      DropdownMenuItem(value: 'yape', child: Text('Yape')),
                      DropdownMenuItem(value: 'plin', child: Text('Plin')),
                      DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
                      DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                    ],
                    onChanged: _busy ? null : (value) {
                      setState(() {
                        _method = value ?? _method;
                        _confirmed = false;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reference,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Número de operación o referencia (opcional)',
                    ),
                  ),
                  CheckboxListTile(
                    value: _confirmed,
                    onChanged: _busy ? null : (v) =>
                        setState(() => _confirmed = v ?? false),
                    title: const Text('Confirmo que ya pagué al proveedor'),
                    subtitle: Text(_method == 'efectivo'
                        ? 'Se registrará el egreso en caja.'
                        : 'Confirmación manual. No se comprueba con el banco.'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy || !_confirmed ? null : _pay,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Registrar pago'),
                  ),
                ] else ...[
                  const Center(child: Text('No hay pagos pendientes de recuperación.')),
                  TextButton(onPressed: () => Navigator.pop(context),
                    child: const Text('Volver a compras')),
                ],
              ],
            ),
    );
  }
}
