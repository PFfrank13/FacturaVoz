import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A published Android build, as described by `android-update.json`.
@immutable
class AppRelease {
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    this.notes = '',
    this.mandatory = false,
  });

  final int versionCode;
  final String versionName;
  final Uri apkUrl;
  final String sha256;
  final String notes;
  final bool mandatory;

  /// Only HTTPS downloads from the project's GitHub releases are accepted,
  /// with a well-formed SHA-256 to verify the file before installing it.
  static AppRelease? parse(Object? json) {
    if (json is! Map) return null;
    final code = json['versionCode'];
    final url = Uri.tryParse('${json['apkUrl'] ?? ''}');
    final digest = '${json['sha256'] ?? ''}'.toLowerCase();
    if (code is! int || code <= 0 || url == null) return null;
    if (url.scheme != 'https' || !_trustedHosts.contains(url.host)) return null;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return null;
    return AppRelease(
      versionCode: code,
      versionName: '${json['versionName'] ?? ''}',
      apkUrl: url,
      sha256: digest,
      notes: '${json['notes'] ?? ''}',
      mandatory: json['mandatory'] == true,
    );
  }

  static const _trustedHosts = {'github.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com'};
}

enum InstallStart { started, needsPermission, failed }

/// Self-update for the Android app, without app stores or a cable.
///
/// GitHub Actions publishes a signed APK and its manifest on every merge to
/// `main`; the app compares versions, downloads, verifies the SHA-256 and hands
/// the file to Android's installer, which always asks the user to confirm.
class AppUpdater {
  AppUpdater._();
  static final instance = AppUpdater._();

  static const manifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://github.com/PFfrank13/FacturaVoz/releases/latest/download/android-update.json',
  );
  static const _channel = MethodChannel('facturavoz/updater');

  final available = ValueNotifier<AppRelease?>(null);
  final progress = ValueNotifier<double?>(null);
  DateTime? _lastCheck;
  File? _downloaded;
  int? _downloadedCode;

  /// The verified APK ready for the installer, if any.
  File? get downloaded => _downloaded;

  @visibleForTesting
  void resetForTest() {
    _downloaded = null;
    _downloadedCode = null;
    _lastCheck = null;
    available.value = null;
    progress.value = null;
  }

  bool get supported => !kIsWeb && Platform.isAndroid;

  /// Checks at most every [every]; failures are silent (offline is normal).
  Future<void> check({Duration every = const Duration(hours: 3), http.Client? client}) async {
    if (!supported) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < every) return;
    _lastCheck = now;
    final c = client ?? http.Client();
    try {
      final response = await c.get(Uri.parse(manifestUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final release = AppRelease.parse(jsonDecode(response.body));
      final current = await _channel.invokeMethod<int>('versionCode') ?? 0;
      available.value = release != null && release.versionCode > current ? release : null;
    } catch (_) {
      // No network or no published release yet.
    } finally {
      if (client == null) c.close();
    }
  }

  /// Downloads the APK with progress and verifies its SHA-256.
  ///
  /// A file already verified for the same version is reused, so tapping
  /// «Actualizar» again after granting the install permission is instant.
  /// [into] overrides the cache folder (tests); the native installer only
  /// accepts files inside `<cache>/updates`.
  Future<bool> download(AppRelease release, {http.Client? client, Directory? into}) async {
    final previous = _downloaded;
    if (previous != null && _downloadedCode == release.versionCode && await previous.exists()) return true;
    final dir = into ?? Directory('${(await getTemporaryDirectory()).path}/updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}/facturavoz-${release.versionCode}.apk');
    final c = client ?? http.Client();
    progress.value = 0;
    try {
      final response = await c.send(http.Request('GET', release.apkUrl)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return false;
      final total = response.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      final hashOut = _DigestSink();
      final hasher = sha256.startChunkedConversion(hashOut);
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (total > 0) progress.value = received / total;
        }
      } finally {
        // Closed before any delete: a cut connection must not leave the file locked.
        await sink.close();
      }
      hasher.close();
      if (hashOut.value.toString() != release.sha256) {
        await file.delete();
        return false;
      }
      _downloaded = file;
      _downloadedCode = release.versionCode;
      return true;
    } catch (_) {
      if (await file.exists()) await file.delete();
      return false;
    } finally {
      progress.value = null;
      if (client == null) c.close();
    }
  }

  Future<InstallStart> install() async {
    final file = _downloaded;
    if (file == null) return InstallStart.failed;
    try {
      final allowed = await _channel.invokeMethod<bool>('canInstall') ?? false;
      if (!allowed) {
        await _channel.invokeMethod('openInstallSettings');
        return InstallStart.needsPermission;
      }
      await _channel.invokeMethod('install', {'path': file.path});
      return InstallStart.started;
    } catch (_) {
      return InstallStart.failed;
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
