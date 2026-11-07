import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/models_v2.dart';

void main() {
  test('commercial offer round trips without changing historical license context', () {
    final settings = OrgSettings.fromJson({
      'business_type': 'taller',
      'labels': {'job': 'Orden', 'custom': 'Conservar'},
      'modules': {'stock': true},
    });
    settings.labels['commercial_offer'] = 'both';
    settings.onboardingDone = true;
    final restored = OrgSettings.fromJson(settings.toRow());
    expect(restored.businessType, 'taller');
    expect(restored.labels, {'job': 'Orden', 'custom': 'Conservar', 'commercial_offer': 'both'});
    expect(restored.modules['stock'], isTrue);
    expect(restored.onboardingDone, isTrue);
  });
}
