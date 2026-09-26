"""Shared installers must never target an unrelated simulator or sign source products."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.device.simulator import disposable, install, signed_copy  # noqa: E402


class SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        patcher = patch("ml.evaluation.device.simulator.clone")
        self.clone = patcher.start()
        self.addCleanup(patcher.stop)
        self.device = dict(udid="disposable", name="Termine-Native-Test-fixture")

    def fake_run(self, command, **kwargs):
        self.calls.append(command)
        if command[2:4] == ["list", "devices"]:
            return json.dumps({"devices": {"test": [self.device]}})
        if command[2] == "get_app_container":
            return "/synthetic/container"
        return ""

    def test_other_or_missing_simulators_stop_before_any_mutation(self):
        for identifier, name in [
            ("different", "Termine-Native-Test-fixture"),
            ("disposable", "Personal"),
        ]:
            self.device["name"] = name
            self.calls = []
            with self.assertRaises(ValueError):
                disposable(identifier, self.fake_run)
            self.assertEqual(len(self.calls), 1)

    def test_signing_uses_disposable_copy_and_keeps_all_app_group_entitlements(self):
        self.assertEqual(disposable("disposable", self.fake_run)["runtime_identifier"], "test")
        app = Path("/synthetic/built/Laßnitzhöhe.app")
        self.assertEqual(install(app, "disposable", self.fake_run), Path("/synthetic/container"))
        signs = [call for call in self.calls if call[0] == "codesign"]
        self.assertEqual(len(signs), 4)
        self.assertTrue(all("reha-evaluation-" in call[-1] for call in signs))
        self.assertTrue(all("--entitlements" in call for call in signs))
        self.assertFalse(any(call[-1].startswith(str(app)) for call in signs))

    def test_retained_copy_uses_same_signatures_without_installing(self):
        source = Path("/synthetic/built/Example.app")
        destination = Path("/synthetic/retained/Example.app")
        signed_copy(source, destination, self.fake_run)
        self.clone.assert_called_once_with(source, destination, expected_files=None)
        self.assertEqual(self.calls[0], ["xattr", "-cr", str(destination)])
        self.assertEqual(len([c for c in self.calls if c[0] == "codesign"]), 4)
        self.assertFalse(any(c[0] == "xcrun" for c in self.calls))

    def test_existing_or_nested_staging_fails_before_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "Example.app"
            source.mkdir()
            for destination in [source, source / "nested.app", Path(temporary)]:
                with self.subTest(destination=destination), self.assertRaises(ValueError):
                    signed_copy(source, destination, self.fake_run)
        self.assertEqual(self.calls, [])

    def test_install_cleans_only_its_temporary_copy_after_sign_failure(self):
        staged = None

        def copy(source, destination, **kwargs):
            nonlocal staged
            staged = destination
            staged.mkdir()

        self.clone.side_effect = copy

        def failing(command, **kwargs):
            if command[0] == "codesign":
                raise RuntimeError("synthetic signing failure")
            return self.fake_run(command, **kwargs)

        with self.assertRaisesRegex(RuntimeError, "synthetic signing"):
            install(Path("/synthetic/source.app"), "disposable", failing)
        self.assertIsNotNone(staged)
        self.assertFalse(staged.parent.exists())
        self.assertFalse(any(c[:3] == ["xcrun", "simctl", "install"] for c in self.calls))


if __name__ == "__main__":
    unittest.main()
