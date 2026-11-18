import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/jobs.dart';

void main() {
  test('Kanban conserva columnas táctiles en móvil y ventanas estrechas', () {
    for (final width in [320.0, 390.0, 600.0, 699.0, 768.0, 899.0]) {
      expect(jobBoardColumnWidth(width, 3), 270, reason: '$width dp');
    }
    expect(jobBoardColumnWidth(double.infinity, 3), 270);
    expect(jobBoardColumnWidth(1200, 0), 270);
  });

  test('Kanban aprovecha tablet/desktop sin desbordar ni comprimir cards', () {
    expect(jobBoardColumnWidth(960, 3), inInclusiveRange(270.0, 380.0));
    expect(jobBoardColumnWidth(1280, 3), 380);
    expect(jobBoardColumnWidth(1440, 4), inInclusiveRange(270.0, 380.0));
    expect(jobBoardColumnWidth(1024, 8), 270);
    expect(jobBoardColumnWidth(3440, 5), 380);
  });
}
