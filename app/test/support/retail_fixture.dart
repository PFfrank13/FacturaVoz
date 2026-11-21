import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/browser_qa/offline_retail.dart';
export '../../tool/browser_qa/offline_retail.dart'
    show emptyRetailCatalog, fixtureAlertRead, stopRetailFixture;

Future<void> startRetailFixture({DateTime? salesDate}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (call) async => call.method == 'getAll' ? <String, Object>{} : true,
  );
  for (final channel in [
    'plugins.flutter.io/quick_actions',
    'com.llfbandit.record/messages',
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers.global/events',
  ]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(channel),
      (_) async => null,
    );
  }
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (call) async {
      if (call.method == 'create') {
        final id = call.arguments['playerId'];
        messenger.setMockMethodCallHandler(
          MethodChannel('xyz.luan/audioplayers/events/$id'),
          (_) async => null,
        );
      }
      return null;
    },
  );
  await startOfflineRetailBackend(salesDate: salesDate);
}
