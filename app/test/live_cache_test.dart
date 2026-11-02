import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/services/live.dart';
import 'package:facturavoz/services/repo.dart';

void main() {
  tearDown(() {
    LiveCache.clear();
    Repo.activeOrgId = null;
  });

  test('guarda y devuelve por empresa', () {
    Repo.activeOrgId = 'a';
    LiveCache.put('clients.all', [1, 2, 3]);
    expect(LiveCache.get<List<int>>('clients.all'), [1, 2, 3]);
    Repo.activeOrgId = 'b';
    expect(LiveCache.get<List<int>>('clients.all'), isNull); // otra empresa: nada
    Repo.activeOrgId = 'a';
    expect(LiveCache.get<List<int>>('clients.all'), [1, 2, 3]);
  });

  test('tipo distinto o null devuelven null y put(null) borra', () {
    Repo.activeOrgId = 'a';
    LiveCache.put('k', 'texto');
    expect(LiveCache.get<List<int>>('k'), isNull);
    LiveCache.put('k', null);
    expect(LiveCache.get<String>('k'), isNull);
  });

  test('clear borra todo', () {
    Repo.activeOrgId = 'a';
    LiveCache.put('x', 1);
    LiveCache.clear();
    expect(LiveCache.get<int>('x'), isNull);
  });
}
