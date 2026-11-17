"""Contract tests of release signer continuity without private credentials."""
import unittest
from verify_certificate import fingerprint, parse_apk_signers, parse_aab_signers, verify

A = "ab" * 32
B = "cd" * 32


def apk_log(value):
    return f"Verifies\nSigner #1 certificate SHA-256 digest: {value}\n"


def aab_log(value):
    separated = ":".join(value[i:i + 2] for i in range(0, 64, 2)).upper()
    return "Owner: CN=Test\nCertificate fingerprints:\n SHA1: XX\n SHA256: " + separated + "\n"


class SignerContinuityTests(unittest.TestCase):
    def test_sha256_forms_match_exactly(self):
        self.assertEqual(A.upper(), fingerprint(A))
        self.assertEqual(A.upper(), fingerprint(":".join(A[i:i + 2] for i in range(0, 64, 2))))

    def test_matching_apk_aab_and_expected_pass(self):
        self.assertEqual(A.upper(), verify(A, apk_log(A), aab_log(A)))

    def test_second_signer_or_missing_signer_blocks(self):
        with self.assertRaises(ValueError):
            verify(A, apk_log(A) + apk_log(B).replace("#1", "#2"), aab_log(A))
        with self.assertRaises(ValueError):
            verify(A, apk_log(A), "")
        with self.assertRaises(ValueError):
            verify(A, "", aab_log(A))

    def test_different_apk_aab_signers_block(self):
        with self.assertRaises(ValueError):
            verify(A, apk_log(B), aab_log(A))
        with self.assertRaises(ValueError):
            verify(A, apk_log(A), aab_log(B))

    def test_no_authorized_fingerprint_blocks(self):
        for invalid in ["", "debug", "aa:bb:cc", "x" * 64, "a" * 63, "a" * 65]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                verify(invalid, apk_log(A), aab_log(A))

    def test_spoofed_hash_in_unrelated_log_line_does_not_count(self):
        fake = f"ERROR: Something SHA256: {A}\n"
        self.assertFalse(parse_apk_signers(fake))
        self.assertFalse(parse_aab_signers(fake))
        with self.assertRaises(ValueError):
            verify(A, fake, fake)

    def test_malformed_certificate_digest_rejected(self):
        self.assertFalse(parse_apk_signers(apk_log("00" * 31)))
        self.assertFalse(parse_aab_signers(aab_log("00" * 31)))

    def test_duplicate_of_same_signer_is_a_single_identity(self):
        self.assertEqual(A.upper(), verify(A, apk_log(A) * 2, aab_log(A)))

if __name__ == "__main__":
    unittest.main()
