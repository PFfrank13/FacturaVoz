"""Offline, hermetic tests for the Phase 5 Android distribution gate."""
import base64
import json
import tempfile
import unittest
from pathlib import Path

from preflight import check, defines_errors, signing_errors, source_errors


def jwt(role):
    payload = base64.urlsafe_b64encode(json.dumps({"role": role}).encode()).decode().rstrip("=")
    return "eyJhbGciOiJIUzI1NiJ9." + payload + ".signature"


class ReleasePreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "repo/app"
        (self.project / "android/app/src/main").mkdir(parents=True)
        (self.project / "pubspec.yaml").write_text("name: facturavoz\nversion: 3.3.0+8\n", encoding="utf-8")
        (self.project / "android/app/build.gradle.kts").write_text(
            'val hasReleaseSigning = true\napplicationId = "dev.solvexsoftware.facturavoz"\n'
            'signingConfig = signingConfigs.getByName("release")\n',
            encoding="utf-8",
        )
        (self.project / "android/app/src/main/AndroidManifest.xml").write_text(
            '<manifest><application android:allowBackup="false" '
            'android:usesCleartextTraffic="false">'
            '<activity android:exported="true" /></application></manifest>',
            encoding="utf-8",
        )
        self.defines = self.root / "release_public.json"
        self.values = {
            "SUPABASE_URL": "https://real-project.supabase.co",
            "SUPABASE_ANON_KEY": "sb_publishable_" + "X" * 20,
            "API_BASE_URL": "https://facturavoz.example.org",
            "APP_VERSION": "3.3.0",
        }
        self._save()
        self.sign = self.root / "private-signing"
        self.sign.mkdir()
        self.keystore = self.sign / "facturavoz-release.jks"
        self.keystore.write_bytes(b"test-only-not-a-real-keystore")
        self.properties = self.sign / "signing.properties"
        self._set_properties()

    def _save(self):
        self.defines.write_text(json.dumps(self.values), encoding="utf-8")

    def _set_properties(self, alias="facturavoz-release", keystore=None):
        self.properties.write_text(
            f"storeFile={keystore or self.keystore}\n"
            "storePassword=not-real\nkeyPassword=not-real\n"
            f"keyAlias={alias}\n", encoding="utf-8",
        )

    def test_source_policy_is_valid_without_any_private_credentials(self):
        self.assertEqual([], source_errors(self.project))
        self.assertEqual([], check(self.project))

    def test_release_inputs_pass_with_public_config_and_external_keystore(self):
        self.assertEqual([], check(self.project, release=True,
                                   defines=self.defines, signing_dir=self.sign))

    def test_release_refuses_missing_secret_keys_and_debug_alias(self):
        self._set_properties(alias="androiddebugkey")
        self.assertTrue(signing_errors(self.project, self.sign))
        self.properties.write_text("storeFile=/tmp/not-found\nkeyAlias=release\n", encoding="utf-8")
        self.assertTrue(any("incompleta" in s for s in signing_errors(self.project, self.sign)))

    def test_release_never_reads_keystore_from_repo(self):
        inner = self.project / "android/app/secret.jks"
        inner.write_bytes(b"secret")
        self._set_properties(keystore=inner)
        self.assertTrue(any("proyecto" in s for s in signing_errors(self.project, self.sign)))

    def test_private_supabase_key_never_enters_compiled_app(self):
        self.values["SUPABASE_ANON_KEY"] = jwt("service_role")
        self.values["SERVICE_ROLE_KEY"] = "supersecret"
        self._save()
        problems = defines_errors(self.defines, "3.3.0")
        self.assertGreaterEqual(len(problems), 2)
        self.assertFalse(any("supersecret" in p for p in problems))

    def test_anonymous_legacy_key_accepted(self):
        self.values["SUPABASE_ANON_KEY"] = jwt("anon")
        self._save()
        self.assertEqual([], defines_errors(self.defines, "3.3.0"))

    def test_placeholder_or_http_endpoints_fail(self):
        self.values["SUPABASE_URL"] = "http://example.supabase.co"
        self.values["API_BASE_URL"] = "https://example.vercel.app"
        self._save()
        self.assertEqual(2, len(defines_errors(self.defines, "3.3.0")))

    def test_app_version_cannot_differ_from_pubspec(self):
        self.values["APP_VERSION"] = "3.1.0"
        self._save()
        self.assertTrue(any("APP_VERSION" in p for p in defines_errors(self.defines, "3.3.0")))

    def test_debug_signing_or_wrong_app_id_fails_source_gate(self):
        gradle = self.project / "android/app/build.gradle.kts"
        gradle.write_text('applicationId = "com.example.demo"\n'
                          'val hasReleaseSigning = true\n'
                          'signingConfig = signingConfigs.getByName("debug")\n', encoding="utf-8")
        problems = source_errors(self.project)
        self.assertTrue(any("applicationId" in p for p in problems))
        self.assertTrue(any("debug" in p for p in problems))

    def test_android_cleartext_and_backup_never_enabled_in_release(self):
        manifest = self.project / "android/app/src/main/AndroidManifest.xml"
        manifest.write_text('<manifest><application android:allowBackup="true" '
                            'android:usesCleartextTraffic="true"><activity '
                            'android:exported="true"/></application></manifest>',
                            encoding="utf-8")
        self.assertEqual(2, len(source_errors(self.project)))

    def test_release_rejects_absent_defines_and_properties(self):
        self.assertTrue(check(self.project, release=True, signing_dir=self.sign))
        self.properties.unlink()
        self.assertTrue(check(self.project, release=True, defines=self.defines, signing_dir=self.sign))


if __name__ == "__main__":
    unittest.main()
