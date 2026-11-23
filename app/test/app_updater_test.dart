import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:facturavoz/services/app_updater.dart';
import 'package:facturavoz/ui/update_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final good = {
    'versionCode': 1042,
    'versionName': '3.4.0',
    'apkUrl': 'https://github.com/PFfrank13/FacturaVoz/releases/download/android-v1042/facturavoz.apk',
    'sha256': 'A' * 64,
    'notes': 'Comprobantes en la web',
  };

  final updater = AppUpdater.instance;
  setUp(updater.resetForTest);

  test('accepts a GitHub HTTPS release with a valid SHA-256', () {
    final r = AppRelease.parse(good)!;
    expect(r.versionCode, 1042);
    expect(r.sha256, 'a' * 64);
    expect(r.mandatory, isFalse);
  });

  test('rejects other hosts, plain HTTP and malformed digests', () {
    expect(AppRelease.parse({...good, 'apkUrl': 'https://evil.example/app.apk'}), isNull);
    expect(AppRelease.parse({...good, 'apkUrl': 'http://github.com/x.apk'}), isNull);
    expect(AppRelease.parse({...good, 'sha256': 'abc'}), isNull);
    expect(AppRelease.parse({...good, 'versionCode': '1042'}), isNull);
    expect(AppRelease.parse({...good, 'versionCode': 0}), isNull);
    expect(AppRelease.parse('not json'), isNull);
  });

  test('updates are unsupported on non-Android test hosts', () {
    expect(updater.supported, isFalse);
  });

  group('download', () {
    late Directory dir;
    final bytes = List<int>.generate(40000, (i) => i % 251);
    MockClient serving(List<int> body, {int status = 200}) => MockClient.streaming((request, _) async {
          final chunks = <List<int>>[for (var i = 0; i < body.length; i += 8192) body.sublist(i, (i + 8192).clamp(0, body.length))];
          return http.StreamedResponse(Stream.fromIterable(chunks), status, contentLength: body.length);
        });

    setUp(() => dir = Directory.systemTemp.createTempSync('fv-updates-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps the APK only when its SHA-256 matches, reporting progress', () async {
      final release = AppRelease.parse({...good, 'sha256': sha256.convert(bytes).toString()})!;
      final seen = <double>[];
      void listen() { final v = updater.progress.value; if (v != null) seen.add(v); }
      updater.progress.addListener(listen);
      final ok = await updater.download(release, client: serving(bytes), into: dir);
      updater.progress.removeListener(listen);

      expect(ok, isTrue);
      expect(updater.downloaded!.readAsBytesSync(), bytes);
      expect(seen.last, 1.0);
      expect(updater.progress.value, isNull);

      // Same version again: reused, no second download.
      var calls = 0;
      final counting = MockClient((_) async { calls++; return http.Response('', 500); });
      expect(await updater.download(release, client: counting, into: dir), isTrue);
      expect(calls, 0);
    });

    test('deletes a tampered APK and refuses it', () async {
      final release = AppRelease.parse({...good, 'sha256': 'b' * 64})!;
      expect(await updater.download(release, client: serving(bytes), into: dir), isFalse);
      expect(updater.downloaded, isNull);
      expect(dir.listSync(), isEmpty);
    });

    test('fails cleanly on HTTP errors', () async {
      final release = AppRelease.parse({...good, 'sha256': sha256.convert(bytes).toString()})!;
      expect(await updater.download(release, client: serving(const [], status: 404), into: dir), isFalse);
      expect(updater.downloaded, isNull);
    });

    test('install without a verified file does nothing', () async {
      expect(await updater.install(), InstallStart.failed);
    });
  });

  group('banner', () {
    Widget host() => const MaterialApp(home: Scaffold(body: UpdateBanner()));

    testWidgets('stays hidden until a newer release is available', (tester) async {
      await tester.pumpWidget(host());
      expect(find.byKey(const ValueKey('app-update-banner')), findsNothing);

      updater.available.value = AppRelease.parse(good);
      await tester.pump();
      expect(find.text('Nueva versión 3.4.0 lista'), findsOneWidget);
      expect(find.text('Comprobantes en la web'), findsOneWidget);
      expect(find.text('Actualizar'), findsOneWidget);
    });

    testWidgets('«Más tarde» hides optional updates but not mandatory ones', (tester) async {
      updater.available.value = AppRelease.parse(good);
      await tester.pumpWidget(host());
      await tester.tap(find.byTooltip('Más tarde'));
      await tester.pump();
      expect(find.byKey(const ValueKey('app-update-banner')), findsNothing);

      updater.available.value = AppRelease.parse({...good, 'mandatory': true});
      await tester.pump();
      expect(find.byKey(const ValueKey('app-update-banner')), findsOneWidget);
      expect(find.byTooltip('Más tarde'), findsNothing);
    });

    testWidgets('shows download progress', (tester) async {
      updater.available.value = AppRelease.parse(good);
      await tester.pumpWidget(host());
      updater.progress.value = 0.42;
      await tester.pump();
      expect(find.text('Descargando 42 %'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
