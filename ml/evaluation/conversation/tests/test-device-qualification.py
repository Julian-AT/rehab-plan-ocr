import copy
import hashlib
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "qualification", Path(__file__).parents[1] / "device_qualification.py"
)
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)


def fixture():
    turns = []
    for i in range(100):
        turns.append(
            dict(
                case_id=str(i),
                repeat=0,
                cycle_index=i,
                speaker_id=f"s{i % 5}",
                dialogue_id=f"d{i // 5}",
                source_sha256=hashlib.sha256(str(i).encode()).hexdigest(),
                partition="holdout",
                task_success=True,
                clarified=False,
                unnecessary_clarification=False,
                raw_model_success=None,
                physical_device=True,
                natural_speech=True,
                human_reviewed=True,
                temperature="cold" if i < 10 else "warm",
                speech_end_ms=1000,
                meaningful_audio_ms=2000,
                microphone_feedback_ms=100,
                explicit_stop_ms=180,
                spoken_interruption_ms=400,
                peak_memory_mb=500,
                energy_mj=50,
                **dict.fromkeys(qualification.COUNTS, 0),
            )
        )
    return dict(
        schema_version=1,
        artifact=dict(
            provider="invented",
            provider_version="fixture",
            runtime_version="fixture",
            hardware="fixture",
            os_version="fixture",
            conversion_settings="fixture",
            system_managed=True,
        ),
        turns=turns,
        scenarios=dict.fromkeys(qualification.SCENARIOS, "passed"),
    )


class DeviceQualificationTests(unittest.TestCase):
    def test_audits_observations_without_promoting_model(self):
        result = qualification.summarize(fixture())
        self.assertTrue(result["observed_gates_passed"])
        self.assertFalse(result["qualified"])
        self.assertEqual(result["speaker_count"], 5)
        self.assertEqual(result["raw_model_count"], 0)
        self.assertIsNone(result["raw_model_success_rate"])

    def test_failed_turns_and_endpoint_waiting_cannot_disappear(self):
        run = fixture()
        for row in run["turns"][-10:]:
            row.update(task_success=False, meaningful_audio_ms=None)
        result = qualification.summarize(run)
        self.assertIn("end_to_audio_latency", result["release_gate_failures"])
        self.assertEqual(result["task_success_rate"], 0.9)
        run = fixture()
        for row in run["turns"]:
            row["meaningful_audio_ms"] = 4500
        self.assertIn("end_to_audio_latency", qualification.summarize(run)["release_gate_failures"])

    def test_simulator_synthetic_unsafe_or_missing_scenarios_fail(self):
        for field in ("physical_device", "natural_speech", "human_reviewed"):
            run = fixture()
            run["turns"][0][field] = False
            self.assertFalse(qualification.summarize(run)["observed_gates_passed"])
        run = fixture()
        run["turns"][0]["wrong_target_writes"] = 1
        self.assertIn(
            "unsafe_or_ungrounded_result", qualification.summarize(run)["release_gate_failures"]
        )
        run = fixture()
        run["scenarios"].pop("quiet_speech")
        self.assertFalse(qualification.summarize(run)["observed_gates_passed"])

    def test_leakage_nonfinite_duplicate_and_unpaired_inputs_rejected(self):
        run = fixture()
        run["turns"][0]["partition"] = "development"
        with self.assertRaisesRegex(ValueError, "crosses"):
            qualification.summarize(run)
        run = fixture()
        run["turns"][0]["peak_memory_mb"] = float("nan")
        with self.assertRaises(ValueError):
            qualification.summarize(run)
        base = fixture()
        candidate = copy.deepcopy(base)
        candidate["turns"][0]["source_sha256"] = "a" * 64
        with self.assertRaisesRegex(ValueError, "Paired"):
            qualification.paired(base, candidate)
        candidate = copy.deepcopy(base)
        candidate["turns"][0]["task_success"] = False
        self.assertEqual(qualification.paired(base, candidate)["task_regressions"], [["0", 0]])


if __name__ == "__main__":
    unittest.main()
