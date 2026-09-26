import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "runtime_parity", Path(__file__).resolve().parents[1] / "runtime_parity.py"
)
diagnostic = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diagnostic)


class RuntimeParityTests(unittest.TestCase):
    def test_cpu_variants_disable_all_offloading_and_isolate_batch_geometry(self):
        settings = {"seed": 42, "max_output_tokens": 192}
        for variant in diagnostic.VARIANTS:
            args = diagnostic.command("runtime", "model", "prompt", variant, settings)

            def value(flag):
                return args[args.index(flag) + 1]

            self.assertEqual(value("-f"), "prompt")
            self.assertEqual(value("--temp"), "0")
            self.assertEqual(value("-n"), "192")
            self.assertEqual(value("-c"), "2048")
            self.assertEqual(value("--n-gpu-layers"), "auto" if variant == "desktop-auto" else "0")
            self.assertEqual("--no-kv-offload" in args, variant != "desktop-auto")
            self.assertEqual("--no-op-offload" in args, variant != "desktop-auto")
            self.assertEqual(
                value("--batch-size"), "512" if variant == "cpu-native-batch" else "2048"
            )
            self.assertEqual(
                value("--ubatch-size"), "128" if variant == "cpu-native-batch" else "512"
            )
        with self.assertRaisesRegex(ValueError, "Unknown"):
            diagnostic.command("runtime", "model", "prompt", "typo", settings)

    def test_changed_mutations_and_malformed_answers_remain_failed(self):
        row = {"context": {"visible_references": ["event-1"]}, "expected": {"action": "cancel"}}
        wrong = diagnostic.observations('{"action":"remove","query":{"reference":"event-1"}}', row)
        self.assertTrue(wrong["schema_valid"])
        self.assertTrue(wrong["unsafe_mutation"])
        self.assertFalse(wrong["exact_match"])
        self.assertFalse(diagnostic.observations("not JSON", row)["schema_valid"])
        self.assertTrue(diagnostic.observations('{"action":"cancel"}', row)["exact_match"])


if __name__ == "__main__":
    unittest.main()
