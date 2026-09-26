"""Only redundant tensor payloads may be removed, with intact resume evidence."""

import ast
import fcntl
import json
import math
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import checkpoints as c  # noqa: E402

import artifacts  # noqa: E402


class CheckpointRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="reha-checkpoints-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.run_name = ".local/runs/synthetic-run"
        self.run = self.root / self.run_name
        self.destination = self.root / c.INDEX / "plan.json"
        self.addCleanup(patch.stopall)
        patch.object(artifacts, "guard").start()
        self.commands = patch.object(artifacts, "command", side_effect=self.command).start()

    def command(self, root, *args):
        if args == ("git", "ls-files", "-z"):
            return ""
        if args == ("git", "rev-parse", "HEAD"):
            return "a" * 40
        if args[:1] == ("ps",):
            return ""
        self.fail(f"Unexpected command: {args}")

    def save(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, sort_keys=True))

    def fixture(self, kind="ocr"):
        producer = c.FORMATS[kind]["producers"][0]
        source = self.root / producer
        source.parent.mkdir(parents=True)
        shutil.copyfile(c.ROOT / producer, source)
        dataset = self.root / ".local/datasets/invented.json"
        self.save(dataset, {"kind": "invented", "rows": []})
        registry = self.root / f"ml/registry/{kind}-base.json"
        self.save(registry, {"model": "invented"})
        environment = self.root / f"ml/training/{kind}/uv.lock"
        environment.write_text("synthetic pinned environment")
        settings = {
            "dataset": str(dataset),
            "max_epochs": 5,
            "patience": 5,
            **({"fine_tune_type": "lora"} if kind == "assistant" else {"mode": "full"}),
        }
        self.save(self.run / "settings.json", settings)
        lineage = {
            "dataset_sha256": artifacts.sha(dataset),
            "registry_sha256": artifacts.sha(registry),
            "environment_sha256": artifacts.sha(environment),
            ("sources_sha256" if kind == "assistant" else "source_sha256"): {
                (producer if kind == "assistant" else "train.py"): artifacts.sha(source)
            },
        }
        self.save(
            self.run / "identity.json",
            {"settings_sha256": artifacts.sha(self.run / "settings.json"), "lineage": lineage},
        )
        self.save(self.run / "baseline.json", {"invented": True})
        (self.run / "training.lock").touch()
        for epoch in range(1, 6):
            directory = self.run / f"checkpoints/epoch-{epoch:04d}"
            directory.mkdir(parents=True)
            for name in c.FORMATS[kind]["payloads"]:
                (directory / name).write_bytes(f"invented {name} epoch {epoch}".encode())
            best_epoch = min(epoch, 2)
            state = {
                "epoch": epoch,
                "best_epoch": best_epoch,
                "steps": epoch * 10,
                "best_score": [1, 0.1, 1] if epoch == 1 else [0, 0.0, 0],
                "stale_epochs": epoch - best_epoch,
                "stopped": False,
            }
            record = {
                "epoch": epoch,
                "state": state,
                "run_identity": artifacts.sha(self.run / "identity.json"),
                "baseline_sha256": artifacts.sha(self.run / "baseline.json"),
            }
            if kind == "ocr":
                record.update(
                    training_sha256=artifacts.sha(directory / "training.pdstate"),
                    metrics={
                        "overall": {
                            "critical_errors": 0 if epoch == 2 else 1,
                            "group_mean_error": 0.0 if epoch == 2 else 0.1,
                            "character_errors": 0 if epoch == 2 else 1,
                        }
                    },
                )
            else:
                self.save(directory / "adapter_config.json", {"rank": 8})
                self.save(directory / "metrics.json", {"epoch": epoch})
                record["files"] = {p.name: artifacts.sha(p) for p in directory.iterdir()}
            self.save(directory / "checkpoint.json", record)
        self.save(self.run / "progress.json", state)
        if kind == "ocr":
            self.save(self.run / "selection.json", {"epoch": 2})
        else:
            self.save(self.run / "result.json", {"selection": state})
        return kind

    def plan(self):
        return c.plan(self.root, [self.run_name], self.destination)

    def actual_resume_reader(self, kind):
        # Execute the actual reader and its validators without importing Paddle/MLX or
        # changing either training implementation's immutable lineage.
        source = c.ROOT / c.FORMATS[kind]["producers"][0]
        sources = {source: {"verify_checkpoint", "latest_checkpoint"}}
        if kind == "ocr":
            sources[source].add("best_checkpoint")
            sources[source.with_name("contract.py")] = {"selection"}
        namespace = {"json": json, "math": math, "sha": artifacts.sha}
        for path, names in sources.items():
            functions = [
                node
                for node in ast.parse(path.read_text()).body
                if isinstance(node, ast.FunctionDef) and node.name in names
            ]
            self.assertEqual({node.name for node in functions}, names)
            exec(compile(ast.Module(body=functions, type_ignores=[]), str(path), "exec"), namespace)
        return namespace["latest_checkpoint"](self.run)

    def test_ocr_pruning_preserves_best_latest_receipts_and_actual_resume_reader(self):
        self.fixture()
        before = {p: p.read_bytes() for p in self.run.rglob("*.json")}
        plan = self.plan()
        self.assertEqual(
            {Path(p).parent.name for p in plan["files"]}, {"epoch-0001", "epoch-0003", "epoch-0004"}
        )
        result = c.apply(self.root, self.destination)
        self.assertEqual(len(result["removed"]), 3)
        self.assertTrue((self.run / "checkpoints/epoch-0002/training.pdstate").is_file())
        self.assertEqual(self.actual_resume_reader("ocr")[1]["epoch"], 5)
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        self.assertEqual(c.inventory(self.root, [self.run_name])["files"], {})

    def test_assistant_keeps_optimizer_random_and_adapter_for_best_and_latest(self):
        self.fixture("assistant")
        self.plan()
        c.apply(self.root, self.destination)
        for epoch in [2, 5]:
            for name in c.FORMATS["assistant"]["files"]:
                self.assertTrue((self.run / f"checkpoints/epoch-{epoch:04d}" / name).is_file())
        self.assertEqual(self.actual_resume_reader("assistant")[1]["epoch"], 5)

    def test_path_hash_and_identity_epoch_references_each_protect_checkpoint(self):
        self.fixture()
        epoch1 = self.run / "checkpoints/epoch-0001/training.pdstate"
        self.save(
            self.root / ".local/runs/evidence/proof.json",
            {
                "source_checkpoint": self.run_name + "/checkpoints/epoch-0003/training.pdstate",
                "source_sha256": artifacts.sha(epoch1),
                "run_identity_sha256": artifacts.sha(self.run / "identity.json"),
                "epoch": 4,
            },
        )
        self.assertEqual(c.inventory(self.root, [self.run_name])["files"], {})

    def test_relative_checkpoint_reference_is_resolved_in_run_context(self):
        self.fixture()
        self.save(
            self.root / ".local/runs/evidence/proof.json",
            {"run": "synthetic-run", "checkpoint": "checkpoints/epoch-0003/training.pdstate"},
        )
        self.assertNotIn(
            self.run_name + "/checkpoints/epoch-0003/training.pdstate",
            c.inventory(self.root, [self.run_name])["files"],
        )

    def test_mixed_run_model_card_does_not_assign_another_runs_epoch(self):
        self.fixture()
        self.save(
            self.root / ".local/runs/evidence/model-card.json",
            {
                "runs": [
                    {
                        "run_identity_sha256": artifacts.sha(self.run / "identity.json"),
                        "selected_epoch": 2,
                    },
                    {"run_identity_sha256": "f" * 64, "selected_epoch": 3},
                ]
            },
        )
        names = c.inventory(self.root, [self.run_name])["files"]
        self.assertIn(self.run_name + "/checkpoints/epoch-0003/training.pdstate", names)

    def test_receipt_inventory_retains_metadata_without_pinning_its_tensor(self):
        self.fixture()
        receipt = self.run / "checkpoints/epoch-0003/checkpoint.json"
        self.save(
            self.root / ".local/runs/evidence/metadata-proof.json",
            {
                "protected_receipt_sha256": {
                    str(receipt.relative_to(self.root)): artifacts.sha(receipt)
                },
                "runs": [{"run": self.run_name, "checkpoint": "epoch-0005"}],
            },
        )
        self.plan()
        c.apply(self.root, self.destination)
        self.assertTrue(receipt.exists())
        self.assertFalse(receipt.with_name("training.pdstate").exists())

    def test_failure_receipt_path_hash_map_keeps_the_complete_checkpoint(self):
        self.fixture()
        receipt = self.run / "checkpoints/epoch-0003/checkpoint.json"
        self.save(
            self.root / ".local/runs/failure/report.json",
            {
                "failed_checkpoint_inputs": {
                    str(receipt.relative_to(self.root)): artifacts.sha(receipt),
                },
            },
        )
        self.assertNotIn(
            str(receipt.with_name("training.pdstate").relative_to(self.root)),
            c.inventory(self.root, [self.run_name])["files"],
        )

    def test_actual_checkpoint_receipt_hash_still_protects_weights(self):
        self.fixture()
        receipt = self.run / "checkpoints/epoch-0003/checkpoint.json"
        self.save(
            self.root / ".local/runs/failure/report.json",
            {
                "source_checkpoint_sha256": artifacts.sha(receipt),
            },
        )
        self.assertNotIn(
            str(receipt.with_name("training.pdstate").relative_to(self.root)),
            c.inventory(self.root, [self.run_name])["files"],
        )

    def test_external_checkpoint_symlink_and_unknown_extra_file_are_refused(self):
        self.fixture()
        extra = self.run / "checkpoints/epoch-0003/unknown.weights"
        extra.write_bytes(b"keep me")
        with self.assertRaisesRegex(ValueError, "Unknown checkpoint contents"):
            c.inventory(self.root, [self.run_name])
        extra.unlink()
        payload = extra.with_name("training.pdstate")
        outside = self.root / "external-original"
        payload.rename(outside)
        payload.symlink_to(outside)
        with self.assertRaises(ValueError):
            c.inventory(self.root, [self.run_name])
        self.assertTrue(outside.exists())

    def test_changed_dataset_provenance_blocks_plan(self):
        self.fixture()
        (self.root / ".local/datasets/invented.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "pin changed"):
            self.plan()

    def test_forged_payload_digest_cannot_override_the_checkpoint_receipt(self):
        self.fixture()
        plan = self.plan()
        name = next(iter(plan["files"]))
        (self.root / name).write_bytes(b"changed since receipt")
        plan["files"][name] = artifacts.fingerprint(self.root / name)
        self.destination.write_text(json.dumps(plan))
        with self.assertRaisesRegex(ValueError, "immutable checkpoint receipt"):
            c.apply(self.root, self.destination)
        self.assertEqual(len(list(self.run.rglob("*.pdstate"))), 5)

    def test_oversized_report_is_streamed_and_preserves_every_named_run_state(self):
        self.fixture()
        report = self.root / ".local/runs/evidence/large.log"
        report.parent.mkdir(parents=True)
        report.write_text("x" * 200 + self.run_name + "y" * 200)
        with patch.object(c, "MAX_REFERENCE_BYTES", 64):
            with patch.object(Path, "read_bytes", wraps=Path.read_bytes) as reads:
                # Catalog must read JSON normally; inspect the reference reader separately.
                text, digest, oversized = c.read_reference(report, {self.run_name})
                reads.assert_not_called()
            self.assertTrue(oversized)
            self.assertEqual(text, self.run_name)
            self.assertEqual(digest, artifacts.sha(report))
            self.assertEqual(c.inventory(self.root, [self.run_name])["files"], {})

    def test_new_error_reference_after_preview_prevents_removal(self):
        self.fixture()
        self.plan()
        self.save(
            self.root / ".local/runs/failure/report.json",
            {"checkpoint": self.run_name + "/checkpoints/epoch-0003/training.pdstate"},
        )
        with self.assertRaisesRegex(ValueError, "protected"):
            c.apply(self.root, self.destination)
        self.assertEqual(len(list(self.run.rglob("*.pdstate"))), 5)

    def test_unknown_files_or_missing_optimizer_fail_closed(self):
        self.fixture("assistant")
        path = self.run / "checkpoints/epoch-0003/optimizer.safetensors"
        path.unlink()
        with self.assertRaisesRegex(ValueError, "Missing checkpoint"):
            c.inventory(self.root, [self.run_name])

    def test_changed_weights_source_pins_and_shared_inode_are_rejected(self):
        self.fixture()
        payload = self.run / "checkpoints/epoch-0003/training.pdstate"
        original = payload.read_bytes()
        payload.write_bytes(b"corrupt optimizer")
        with self.assertRaisesRegex(ValueError, "tensor changed"):
            self.plan()
        payload.write_bytes(original)
        os.link(payload, self.root / "shared-checkpoint")
        with self.assertRaisesRegex(ValueError, "independently owned"):
            c.inventory(self.root, [self.run_name])

    def test_mutation_after_preview_is_rejected_before_any_deletion(self):
        self.fixture()
        self.plan()
        (self.run / "checkpoints/epoch-0003/training.pdstate").write_bytes(b"changed")
        with self.assertRaises(ValueError):
            c.apply(self.root, self.destination)
        self.assertEqual(len(list(self.run.rglob("*.pdstate"))), 5)

    def test_trainer_lock_and_live_model_process_prevent_planning(self):
        self.fixture()
        with (self.run / "training.lock").open("rb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                self.plan()
        original = self.command
        self.commands.side_effect = lambda root, *args: (
            "12345 python ml/evaluation/recognition/operation_parity.py\n"
            if args[:1] == ("ps",)
            else original(root, *args)
        )
        with self.assertRaisesRegex(ValueError, "Active model"):
            self.plan()
        self.assertFalse(self.destination.exists())

    def test_interruption_after_unlink_resumes_and_completed_replay_keeps_later_bytes(self):
        self.fixture()
        plan = self.plan()
        actual = artifacts.append
        triggered = False

        def interrupt(path, record):
            nonlocal triggered
            if record["action"] == "removed" and not triggered:
                triggered = True
                raise RuntimeError("simulated crash after unlink")
            actual(path, record)

        with patch.object(artifacts, "append", side_effect=interrupt):
            with self.assertRaisesRegex(RuntimeError, "simulated crash"):
                c.apply(self.root, self.destination)
        result = c.apply(self.root, self.destination)
        rebuilt = self.root / next(iter(plan["files"]))
        rebuilt.write_bytes(b"later restored data")
        self.assertEqual(c.apply(self.root, self.destination), result)
        self.assertEqual(rebuilt.read_bytes(), b"later restored data")

    def test_forged_plan_cannot_delete_best_or_non_checkpoint_file(self):
        self.fixture()
        plan = self.plan()
        protected = self.run_name + "/checkpoints/epoch-0002/training.pdstate"
        plan["files"][protected] = plan["protected"][protected]
        self.destination.write_text(json.dumps(plan))
        with self.assertRaisesRegex(ValueError, "protected"):
            c.apply(self.root, self.destination)
        self.assertTrue((self.root / protected).is_file())

    def test_unknown_producer_is_not_a_candidate(self):
        self.fixture()
        identity = json.loads((self.run / "identity.json").read_text())
        identity["lineage"]["source_sha256"]["train.py"] = "f" * 64
        self.save(self.run / "identity.json", identity)
        with self.assertRaisesRegex(ValueError, "Unknown checkpoint producer"):
            c.inventory(self.root, [self.run_name])


if __name__ == "__main__":
    unittest.main()
