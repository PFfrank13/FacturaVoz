// Avisos de Yape/Plin automáticos (Android). El lector nativo (PaymentNoticeListener.kt) deja en una cola local
// solo los pagos RECIBIDOS de Yape y bancos con Plin; aquí se leen, se interpretan con notice_parser y se guardan
// en «Avisos de Yape y Plin» de la empresa. Nunca se registra un cobro sin que alguien lo confirme.
// Investigación: docs/INVESTIGACION_RETAIL.md, fila 1 (73 % de la venta de bodegas de Lima entra por billetera).
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../access.dart';
import '../logic/notice_parser.dart';
import 'repo.dart';
import 'v2_repo.dart';

/// Un pago recibido que llegó por notificación.
class IncomingPayment {
  const IncomingPayment({required this.notice, required this.at, this.saved = false});
  final PaymentNotice notice;
  final DateTime at;
  final bool saved;
}

/// Código de operación que sirve para no duplicar: los «códigos de seguridad» de 3 dígitos de Yape se repiten
/// entre pagos distintos, así que solo se usan códigos de 6 o más caracteres.
String dedupeOperation(String op) => op.trim().length >= 6 ? op.trim() : '';

/// Convierte lo que dejó el lector nativo en avisos interpretados (descarta lo que no es un pago).
List<IncomingPayment> parseQueued(List<Object?> raw) {
  final out = <IncomingPayment>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final text = item['text'];
    final at = item['at'];
    if (text is! String) continue;
    final n = parsePaymentNotice(text);
    if (n == null) continue;
    out.add(IncomingPayment(notice: n, at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : DateTime.now()));
  }
  return out;
}

/// ¿Este aviso paga [total]? Mismo monto (al céntimo) y llegó hace menos de [window].
bool matchesCharge(IncomingPayment p, double total, {DateTime? now, Duration window = const Duration(minutes: 10)}) {
  final age = (now ?? DateTime.now()).difference(p.at);
  return (p.notice.amount - total).abs() < 0.005 && age >= const Duration(minutes: -1) && age <= window;
}

class PaymentListener {
  PaymentListener._();
  static final PaymentListener instance = PaymentListener._();

  static const _methods = MethodChannel('facturavoz/payments');
  static const _events = EventChannel('facturavoz/payments/events');

  /// Últimos pagos recibidos en esta sesión (el más reciente primero), para el cobro y el inicio.
  final ValueNotifier<List<IncomingPayment>> recent = ValueNotifier(const []);
  final ValueNotifier<bool?> enabled = ValueNotifier(null);
  StreamSubscription<dynamic>? _sub;
  bool _draining = false;

  bool get supported => !kIsWeb && Platform.isAndroid;
  bool get _allowed => Access.instance.has('avisos_pago') && Access.instance.can('collect');

  Future<void> start() async {
    if (!supported) return;
    await refreshEnabled();
    _sub ??= _events.receiveBroadcastStream().listen((_) => drain(), onError: (_) {});
    await drain();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<bool> refreshEnabled() async {
    if (!supported) return false;
    try {
      final v = await _methods.invokeMethod<bool>('isEnabled') ?? false;
      enabled.value = v;
      return v;
    } catch (_) {
      enabled.value = false;
      return false;
    }
  }

  Future<void> openSettings() async {
    if (supported) await _methods.invokeMethod<void>('openSettings');
  }

  /// Lee la cola nativa y guarda cada pago como aviso «nuevo» de la empresa activa.
  Future<void> drain() async {
    if (!supported || _draining || Repo.activeOrgId == null || !_allowed) return;
    _draining = true;
    try {
      final raw = await _methods.invokeMethod<List<Object?>>('drain') ?? const [];
      final parsed = parseQueued(raw);
      if (parsed.isEmpty) return;
      final saved = <IncomingPayment>[];
      for (final p in parsed) {
        var ok = true;
        try {
          await V2Repo.addNotice(app: p.notice.app, amount: p.notice.amount, payer: p.notice.payer,
              operation: dedupeOperation(p.notice.operation), raw: p.notice.raw);
        } catch (_) {
          ok = false; // repetido (mismo código de operación) o sin conexión: se ve igual en la pantalla de avisos
        }
        saved.add(IncomingPayment(notice: p.notice, at: p.at, saved: ok));
      }
      final cutoff = DateTime.now().subtract(const Duration(hours: 2));
      recent.value = [...saved.reversed, ...recent.value.where((r) => r.at.isAfter(cutoff))].take(20).toList();
    } catch (_) {
      // Sin canal nativo (pruebas, iOS) o cola dañada: no interrumpe la venta.
    } finally {
      _draining = false;
    }
  }
}
