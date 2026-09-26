"""Training keeps the working reserve before epochs and before checkpoint writes."""

import importlib.util
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from ml.training import storage  # noqa: E402
from ml.training.assistant import train as assistant  # noqa: E402

sys.path.insert(0, str(ROOT / "ml/training/ocr"))
spec = importlib.util.spec_from_file_location(
    "ocr_training_storage", ROOT / "ml/training/ocr/train.py"
)
ocr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ocr)


class StorageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        policy = self.root / "config/storage/retention.json"
        policy.parent.mkdir(parents=True)
        policy.write_text(json.dumps({"reserve_gib": 20}))
        self.policy = policy

    def test_planned_peak_is_additional_to_the_twenty_gib_reserve(self):
        with patch.object(storage.shutil, "disk_usage") as disk:
            disk.return_value.free = 23 * storage.GIB - 1
            with self.assertRaisesRegex(RuntimeError, "20 GiB reserve.*3.00 GiB"):
                storage.require_storage(self.root, self.root, 3)
            disk.return_value.free += 1
            result = storage.require_storage(self.root, self.root, 3)
            self.assertEqual(result["peak_bytes"], 3 * storage.GIB)
            disk.assert_called_with(self.root)

    def test_large_runtime_checkpoint_increases_the_peak_budget(self):
        tensor = types.SimpleNamespace(nbytes=storage.GIB)
        peak = storage.checkpoint_peak({"weight": tensor}, {}, random={})
        self.assertEqual(peak, 10 * storage.GIB + 64 * 1024**2)
        with patch.object(storage.shutil, "disk_usage") as disk:
            disk.return_value.free = 30 * storage.GIB
            with self.assertRaisesRegex(RuntimeError, "checkpoint/temporary peak"):
                storage.require_storage(self.root, self.root, 3, peak)

    def test_tensor_sizes_use_metadata_and_count_already_larger_optimizer(self):
        paddle_tensor = types.SimpleNamespace(shape=(2, 3), element_size=lambda: 4)
        mlx_tensor = types.SimpleNamespace(nbytes=40)
        self.assertEqual(storage.tensor_bytes({"a": paddle_tensor, "b": [mlx_tensor, 1]}), 64)
        peak = storage.checkpoint_peak(
            mlx_tensor, {"moments": types.SimpleNamespace(nbytes=400)}, trainable=paddle_tensor
        )
        self.assertEqual(peak, 2 * (40 + 400) + 64 * 1024**2)
        with self.assertRaisesRegex(ValueError, "Unsupported checkpoint"):
            storage.tensor_bytes(object())

    def test_invalid_reserve_and_peak_cannot_disable_the_guard(self):
        for reserve in [0, 19, True, float("nan"), float("inf")]:
            with self.subTest(reserve=reserve):
                self.policy.write_text(json.dumps({"reserve_gib": reserve}))
                with self.assertRaisesRegex(ValueError, "at least 20"):
                    storage.require_storage(self.root, self.root, 3)
        self.policy.write_text(json.dumps({"reserve_gib": 20}))
        for peak in [-1, float("nan"), float("inf")]:
            with self.subTest(peak=peak), self.assertRaisesRegex(ValueError, "finite"):
                storage.require_storage(self.root, self.root, peak)

    def test_both_trainers_check_before_importing_training_frameworks(self):
        for trainer, planned in [(assistant, 3), (ocr, 4)]:
            with (
                self.subTest(trainer=trainer.__name__),
                patch.object(
                    trainer, "require_storage", side_effect=RuntimeError("low storage")
                ) as guard,
                self.assertRaisesRegex(RuntimeError, "low storage"),
            ):
                trainer.execute(self.root)
            guard.assert_called_once_with(trainer.ROOT, self.root, planned)

    def test_checkpoint_storage_rejection_preserves_the_last_complete_epoch(self):
        saved = self.root / "checkpoints/epoch-0001/saved"
        saved.parent.mkdir(parents=True)
        saved.write_bytes(b"existing complete checkpoint")
        tensor = types.SimpleNamespace(nbytes=24, stop_gradient=False)
        core = types.ModuleType("mlx.core")
        core.random = types.SimpleNamespace(state=[tensor])
        core.save_safetensors = Mock()
        utils = types.ModuleType("mlx.utils")
        utils.tree_flatten = Mock()
        mlx = types.ModuleType("mlx")
        mlx.core = core
        mlx.utils = utils
        paddle = types.ModuleType("paddle")
        paddle.save = Mock()
        model = Mock()
        model.trainable_parameters.return_value = {"weight": tensor}
        model.state_dict.return_value = {"weight": tensor}
        model.parameters.return_value = [tensor]
        optimizer = types.SimpleNamespace(state={"moment": tensor}, state_dict=lambda: {})
        with (
            patch.dict(
                sys.modules, {"mlx": mlx, "mlx.core": core, "mlx.utils": utils, "paddle": paddle}
            ),
            patch.object(
                storage.shutil,
                "disk_usage",
                return_value=types.SimpleNamespace(free=22 * storage.GIB),
            ),
        ):
            for trainer in [assistant, ocr]:
                with self.subTest(trainer=trainer.__name__), self.assertRaises(RuntimeError):
                    if trainer is assistant:
                        trainer.checkpoint(self.root, 2, model, optimizer, {}, {}, {})
                    else:
                        trainer.checkpoint(self.root, 2, model, optimizer, {}, {})
        core.save_safetensors.assert_not_called()
        paddle.save.assert_not_called()
        self.assertEqual(list((self.root / "checkpoints").iterdir()), [saved.parent])
        self.assertEqual(saved.read_bytes(), b"existing complete checkpoint")


if __name__ == "__main__":
    unittest.main()
