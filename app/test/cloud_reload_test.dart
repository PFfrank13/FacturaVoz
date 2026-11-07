import 'dart:async';
import 'package:facturavoz/app_state.dart';
import 'package:facturavoz/services/live.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class QueryScreen extends StatefulWidget {
  const QueryScreen(this.query, {super.key});
  final Future<void> Function() query;
  @override
  State<QueryScreen> createState() => _QueryScreenState();
}
class _QueryScreenState extends State<QueryScreen> with LiveReload<QueryScreen> {
  @override
  List<String> get liveTables => ['products'];
  @override
  Future<void> reloadLive() => widget.query();
  @override
  void initState() { super.initState(); startLive(); }
  @override
  void dispose() { stopLive(); super.dispose(); }
  @override
  Widget build(BuildContext context) => const SizedBox();
}
void main() {
  testWidgets('reconsulta al reactivar y no consulta en segundo plano', (tester) async {
    var calls = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(QueryScreen(() async { calls++; }));
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
  });
  testWidgets('agrupa avisos durante una consulta y libera el estado tras error', (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(QueryScreen(() async {
      calls++;
      if (calls == 1) await pending.future;
      if (calls == 2) throw StateError('consulta interrumpida');
    }));
    AppState.instance.bump(); AppState.instance.bump(); AppState.instance.bump();
    expect(calls, 1);
    pending.complete(); await tester.pump();
    expect(calls, 2);
    AppState.instance.bump(); await tester.pump();
    expect(calls, 3);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
