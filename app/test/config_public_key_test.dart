import 'package:flutter_test/flutter_test.dart';

import '../lib/config.dart';

void main() {
  group('Supabase public API key configuration', () {
    test('accepts a standalone anon JWT and publishable key', () {
      expect(Config.isPublicKeyFormat(
          'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.signature123'), isTrue);
      expect(Config.isPublicKeyFormat('sb_publishable_1234567890abcdef'), isTrue);
    });

    test('rejects the entire Flutter launch command pasted as a key', () {
      expect(Config.isPublicKeyFormat(
          'flutter run --release --dart-define=SUPABASE_ANON_KEY=eyJ.abc.sig '
          '--dart-define=API_BASE_URL=https://example.com'), isFalse);
    });

    test('rejects whitespace, empty strings and secret key types', () {
      expect(Config.isPublicKeyFormat(''), isFalse);
      expect(Config.isPublicKeyFormat(' eyJ.abc.sig'), isFalse);
      expect(Config.isPublicKeyFormat('sb_secret_1234567890abcdef'), isFalse);
      expect(Config.isPublicKeyFormat('not-a-key'), isFalse);
    });
  });
}
