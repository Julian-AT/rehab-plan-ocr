"""Shared installers must never target an unrelated simulator or sign source products."""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.device.simulator import disposable, install  # noqa: E402


class SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
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


if __name__ == "__main__":
    unittest.main()
