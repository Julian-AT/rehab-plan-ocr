"""Pinned downloads stop before an oversized server response consumes local reserve."""

import hashlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "restore.py"
spec = importlib.util.spec_from_file_location("ocr_restore", SOURCE)
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class CheckpointDownloadTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.target = Path(temporary.name) / "checkpoint.pdparams"
        self.target.write_bytes(b"previous checkpoint")
        self.content = b"pinned synthetic checkpoint"
        self.pin = {
            "checkpoint_bytes": len(self.content),
            "checkpoint_sha256": hashlib.sha256(self.content).hexdigest(),
        }

    def test_exact_response_publishes_only_after_size_and_hash_match(self):
        restore.download_checkpoint(io.BytesIO(self.content), self.target, self.pin)
        self.assertEqual(self.target.read_bytes(), self.content)
        self.assertFalse(self.target.with_suffix(".pdparams.part").exists())

    def test_short_corrupt_and_oversized_responses_preserve_installed_checkpoint(self):
        for response in [self.content[:-1], b"x" * len(self.content), self.content + b"extra"]:
            with self.subTest(response=response), self.assertRaisesRegex(ValueError, "mismatch"):
                restore.download_checkpoint(io.BytesIO(response), self.target, self.pin)
            self.assertEqual(self.target.read_bytes(), b"previous checkpoint")

    def test_unending_response_is_bounded_without_waiting_for_eof(self):
        class Endless:
            read_bytes = 0

            def read(stream, limit):
                self.assertGreater(limit, 0)
                self.assertLessEqual(stream.read_bytes + limit, self.pin["checkpoint_bytes"] + 1)
                stream.read_bytes += limit
                return b"x" * limit

        response = Endless()
        with self.assertRaisesRegex(ValueError, "mismatch"):
            restore.download_checkpoint(response, self.target, self.pin)
        self.assertEqual(response.read_bytes, self.pin["checkpoint_bytes"] + 1)
        self.assertEqual(self.target.read_bytes(), b"previous checkpoint")

    def test_network_error_preserves_installed_checkpoint(self):
        class Interrupted:
            def read(self, _limit):
                raise OSError("synthetic disconnect")

        with self.assertRaises(OSError):
            restore.download_checkpoint(Interrupted(), self.target, self.pin)
        self.assertEqual(self.target.read_bytes(), b"previous checkpoint")

    def test_bad_pin_cannot_start_a_download(self):
        for value in [0, -1, True, 1.5]:
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "positive"):
                restore.download_checkpoint(
                    None, self.target, self.pin | {"checkpoint_bytes": value}
                )
        self.assertEqual(self.target.read_bytes(), b"previous checkpoint")


if __name__ == "__main__":
    unittest.main()
