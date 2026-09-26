"""Historical provenance stays immutable while current validation remains mandatory."""

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import contract
import run_identity
import train


class RunIdentityTests(unittest.TestCase):
    def setUp(self):
        packages = patch.object(train.importlib.metadata, "version", return_value="test-version")
        packages.start()
        self.addCleanup(packages.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run = self.root / "run"
        self.run.mkdir()
        self.dataset = self.root / "dataset.json"
        contract.write(
            self.dataset, {"kind": "pixel-verified-synthetic-crops", "final_holdout": False}
        )
        contract.write(self.run / "settings.json", {"dataset": str(self.dataset)})
        self.current()

    def current(self):
        contract.write(
            self.run / "identity.json",
            {
                "settings_sha256": contract.sha(self.run / "settings.json"),
                "lineage": train.lineage(self.dataset),
            },
        )

    def legacy(self):
        self.current()
        identity = json.loads((self.run / "identity.json").read_text())
        identity["lineage"] = {
            key: value
            for key, value in identity["lineage"].items()
            if key in run_identity.LEGACY_FACTS
        } | {
            "source_sha256": run_identity.LEGACY_SOURCES,
            "reference_tool_sha256": run_identity.LEGACY_REFERENCE,
        }
        contract.write(self.run / "identity.json", identity)
        return identity

    def test_current_and_historical_identities_are_distinct_without_rewriting(self):
        self.assertEqual(run_identity.verify(self.run)["mode"], "current")
        self.legacy()
        before = (self.run / "identity.json").read_bytes()
        proof = run_identity.verify(self.run)
        self.assertEqual(proof["mode"], "archived-synthetic-v1")
        self.assertEqual(before, (self.run / "identity.json").read_bytes())
        for name, recorded in proof["archived_training_sources"].items():
            self.assertEqual(recorded["sha256"], contract.sha(run_identity.ROOT / recorded["path"]))
        for name, value in proof["current_validation_sources"].items():
            self.assertEqual(value, contract.sha(run_identity.ROOT / name))

    def test_real_references_have_no_legacy_exception(self):
        contract.write(self.dataset, {"kind": "approved-reference-crops", "final_holdout": False})
        self.legacy()
        with self.assertRaisesRegex(ValueError, "Run lineage changed"):
            run_identity.verify(self.run)

    def test_changed_dataset_settings_environment_or_unknown_sources_fail(self):
        for field in [
            "dataset_sha256",
            "environment_sha256",
            "source_sha256",
            "reference_tool_sha256",
        ]:
            identity = self.legacy()
            identity["lineage"][field] = "changed"
            contract.write(self.run / "identity.json", identity)
            with self.subTest(field=field), self.assertRaises(ValueError):
                run_identity.verify(self.run)
        self.legacy()
        with (self.run / "settings.json").open("a") as stream:
            stream.write("\n")
        with self.assertRaises(ValueError):
            run_identity.verify(self.run)

    def test_archives_are_verified_and_actual_original_training_code_is_loaded(self):
        self.legacy()
        engine, proof = run_identity.legacy_engine(self.run)
        self.assertEqual(
            Path(engine.execute.__code__.co_filename), run_identity.ARCHIVE / "train.py"
        )
        self.assertEqual(
            Path(engine.advance.__code__.co_filename), run_identity.ARCHIVE / "contract.py"
        )
        self.assertIs(engine.validate_dataset, contract.validate_dataset)
        with patch.object(train, "current_review") as review:
            engine.current_review({}, self.dataset)
            review.assert_called_once_with({}, self.dataset)
        self.assertEqual(
            engine.lineage(self.dataset),
            json.loads((self.run / "identity.json").read_text())["lineage"],
        )
        self.assertEqual(run_identity.verify(self.run), proof)
        other = self.root / "archive"
        shutil.copytree(run_identity.ARCHIVE, other)
        with (other / "train.py").open("a") as stream:
            stream.write("\n")
        with (
            patch.object(run_identity, "ARCHIVE", other),
            self.assertRaisesRegex(ValueError, "Archived"),
        ):
            run_identity.legacy_engine(self.run)

    def test_resume_records_current_guards_and_keeps_historical_receipts(self):
        self.legacy()
        engine, proof = run_identity.legacy_engine(self.run)
        identity = (self.run / "identity.json").read_bytes()
        with (
            patch.object(engine, "execute") as execute,
            patch.object(run_identity, "legacy_engine", return_value=(engine, proof)),
        ):
            run_identity.resume_legacy(self.run, 3)
            execute.assert_called_once_with(self.run, 3)
        receipts = list((self.run / "compatibility").glob("*.json"))
        self.assertEqual(len(receipts), 1)
        self.assertIn("resume_adapter", json.loads(receipts[0].read_text()))
        self.assertEqual(identity, (self.run / "identity.json").read_bytes())
        # Writing the separate receipt must not mutate the input proof captured by the engine.
        self.assertEqual(engine.lineage(self.dataset), json.loads(identity)["lineage"])

    def test_shared_input_gate_propagates_live_review_revocation(self):
        dictionary = self.root / "dictionary.txt"
        dictionary.write_text("a\nb\n")
        data = {"kind": "approved-reference-crops", "samples": []}
        with (
            patch.object(train, "DICTIONARY", dictionary),
            patch.object(contract, "validate_dataset", return_value=data) as validate,
            patch.object(train, "current_review", side_effect=ValueError("revoked")) as review,
            self.assertRaisesRegex(ValueError, "revoked"),
        ):
            run_identity.validate_inputs(self.run)
        validate.assert_called_once_with(self.dataset, ["a", "b"])
        review.assert_called_once_with(data, self.dataset)

    def test_dataset_change_during_validation_cannot_reuse_identity(self):
        dictionary = self.root / "dictionary.txt"
        dictionary.write_text("a\n")

        def changed(path, chars):
            contract.write(path, {"kind": "invented-smoke-text", "final_holdout": False})
            return {"kind": "invented-smoke-text"}

        with (
            patch.object(train, "DICTIONARY", dictionary),
            patch.object(contract, "validate_dataset", side_effect=changed),
            self.assertRaises(ValueError),
        ):
            run_identity.validate_inputs(self.run)


if __name__ == "__main__":
    unittest.main()
