"""A matching team/profile name cannot replace signing-certificate authorization."""

import datetime
import hashlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from signing import verify_signer  # noqa: E402


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 9, 20, 12, 0, tzinfo=datetime.timezone.utc)
        self.profile = {"DeveloperCertificates": [b"another authorized certificate", b"leaf"]}
        self.calls = []
        self.chain = [b"leaf", b"intermediate", b"root"]
        self.files = []

    def invoke(self, *args):
        self.calls.append(args)
        if args[0] == "codesign":
            self.assertEqual(args[1], "--display")
            self.assertTrue(args[2].startswith("--extract-certificates="))
            for index, content in enumerate(self.chain):
                path = Path(args[2].split("=", 1)[1] + str(index))
                path.write_bytes(content)
                self.files.append(path)
        return b""

    def check(self, runner=None, profile=None):
        return verify_signer(
            Path("copied app.app"),
            self.profile if profile is None else profile,
            runner or self.invoke,
            now=self.now,
        )

    def test_authorized_leaf_is_checked_at_current_time_without_network_or_added_trust(self):
        report = self.check()
        self.assertEqual(report["certificate_sha256"], hashlib.sha256(b"leaf").hexdigest())
        self.assertEqual(len(report["chain_sha256"]), 3)
        self.assertTrue(report["authorized_by_profile"])
        self.assertFalse(report["fresh_revocation_status_verified"])
        self.assertFalse(report["target_platform_acceptance_verified"])
        command = self.calls[1]
        self.assertEqual(
            command[:11],
            (
                "security",
                "verify-cert",
                "-p",
                "codeSign",
                "-L",
                "-R",
                "offline",
                "-N",
                "-d",
                "2026-09-20-12:00:00",
                "-c",
            ),
        )
        self.assertEqual(
            [command[index + 1] for index, arg in enumerate(command) if arg == "-c"],
            [str(path) for path in self.files],
        )
        self.assertNotIn("-r", command)
        self.assertTrue(all(not path.exists() for path in self.files))

    def test_same_profile_but_different_leaf_is_rejected_before_trust_evaluation(self):
        self.chain[0] = b"different leaf"
        with self.assertRaisesRegex(ValueError, "not authorized"):
            self.check()
        self.assertEqual(len(self.calls), 1)
        self.assertTrue(all(not path.exists() for path in self.files))

    def test_missing_or_malformed_profile_certificate_lists_fail_closed(self):
        for allowed in [None, [], b"leaf", ["leaf"], [b""]]:
            with self.subTest(allowed=allowed), self.assertRaisesRegex(ValueError, "authorized"):
                self.check(profile={"DeveloperCertificates": allowed})
        self.assertEqual(self.calls, [])

    def test_ad_hoc_signature_without_certificates_cannot_pass(self):
        self.chain = []
        with self.assertRaisesRegex(ValueError, "certificate chain"):
            self.check()
        self.assertEqual(len(self.calls), 1)

    def test_expired_not_yet_valid_or_untrusted_chain_error_is_preserved(self):
        for failure in ["expired", "not yet valid", "untrusted"]:

            def rejected(*args):
                if args[0] == "security":
                    raise RuntimeError(failure)
                return self.invoke(*args)

            with self.subTest(failure=failure), self.assertRaisesRegex(RuntimeError, failure):
                self.check(runner=rejected)
            self.assertTrue(all(not path.exists() for path in self.files))

    def test_certificate_extraction_error_and_incomplete_chain_fail_closed(self):
        def rejected(*_):
            raise RuntimeError("codesign failed")

        with self.assertRaisesRegex(RuntimeError, "codesign failed"):
            self.check(runner=rejected)

        def gap(*args):
            if args[0] == "codesign":
                Path(args[2].split("=", 1)[1] + "1").write_bytes(b"intermediate without leaf")
            return b""

        with self.assertRaisesRegex(ValueError, "certificate chain"):
            self.check(runner=gap)


if __name__ == "__main__":
    unittest.main()
