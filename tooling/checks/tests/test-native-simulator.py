import copy
import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "simulator", Path(__file__).resolve().parents[1] / "native-simulator.py"
)
simulator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(simulator)


class SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.profile = {"runtime": "ios-pinned", "version": "26.4", "build": "23E244"}
        self.inventory = {
            "runtimes": [
                {
                    "identifier": "ios-newer",
                    "version": "26.5",
                    "buildversion": "23F77",
                    "isAvailable": True,
                },
                {
                    "identifier": "ios-pinned",
                    "version": "26.4",
                    "buildversion": "23E244",
                    "isAvailable": True,
                },
            ],
            "devices": {
                "ios-pinned": [
                    {
                        "udid": "owned",
                        "name": "Termine-Native-Test-example",
                        "isAvailable": True,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                    }
                ]
            },
        }

    def test_newer_installed_runtime_does_not_replace_requested_identity(self):
        before = copy.deepcopy(self.inventory)
        result = simulator.select(self.profile, self.inventory)
        self.assertEqual(result["runtime"]["identifier"], "ios-pinned")
        self.assertIsNone(result["reused_device"])
        self.assertEqual(self.inventory, before)

    def test_missing_unavailable_or_changed_build_fails_without_fallback(self):
        for change in [None, {"isAvailable": False}, {"buildversion": "different"}]:
            inventory = copy.deepcopy(self.inventory)
            if change is None:
                inventory["runtimes"].pop()
            else:
                inventory["runtimes"][-1].update(change)
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, "no newer"):
                simulator.select(self.profile, inventory)

    def test_reuse_requires_owned_available_device_and_exact_runtime(self):
        self.assertEqual(
            simulator.select(self.profile, self.inventory, "owned")["reused_device"]["udid"],
            "owned",
        )
        for change in [
            {"name": "Personal phone"},
            {"isAvailable": False},
            {"deviceTypeIdentifier": "different-phone"},
        ]:
            inventory = copy.deepcopy(self.inventory)
            inventory["devices"]["ios-pinned"][0].update(change)
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, "owned iPhone"):
                simulator.select(self.profile, inventory, "owned")
        self.inventory["devices"]["ios-newer"] = self.inventory["devices"].pop("ios-pinned")
        with self.assertRaisesRegex(ValueError, "pinned runtime"):
            simulator.select(self.profile, self.inventory, "owned")


if __name__ == "__main__":
    unittest.main()
