import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/cutoff.dart';

void main() {
  lastNoticeTests();
  test('sin aviso no se puede cortar', () {
    expect(noticeAge({}, '2026-10-30'), isNull);
    expect(canCut({}, '2026-10-30'), isFalse);
    expect(noticeLabel({}, '2026-10-30'), 'Sin aviso previo');
  });

  test('aviso de hoy aún no habilita el corte; desde el día siguiente sí', () {
    final e = {'aviso_corte_fecha': '2026-10-30'};
    expect(canCut(e, '2026-10-30'), isFalse);
    expect(noticeLabel(e, '2026-10-30'), 'Avisado hoy');
    expect(canCut(e, '2026-10-31'), isTrue);
    expect(noticeLabel(e, '2026-11-01'), 'Avisado hace 2 días');
  });

  test('fecha mal formada se ignora', () {
    expect(noticeDate({'aviso_corte_fecha': 5}), isNull);
    expect(noticeDate({'aviso_corte_fecha': '2026'}), isNull);
    expect(noticeDate({'aviso_corte_fecha': '2026-10-30T10:00:00'}), '2026-10-30');
  });
}

void lastNoticeTests() {
  test('lastNoticeText', () {
    expect(lastNoticeText({}, pensionNoticeKey, '2026-10-31'), '');
    expect(lastNoticeText({pensionNoticeKey: '2026-10-31'}, pensionNoticeKey, '2026-10-31'), 'Avisado hoy');
    expect(lastNoticeText({pensionNoticeKey: '2026-10-30'}, pensionNoticeKey, '2026-10-31'), 'Avisado hace 1 día');
    expect(lastNoticeText({pensionNoticeKey: '2026-10-20'}, pensionNoticeKey, '2026-10-31'), 'Avisado hace 11 días');
  });
}
