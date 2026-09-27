"""Submission round trips, provenance and hostile archive rejection."""

import copy
import hashlib
import json
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import source_tree as source
import source_zip


class SourceZipTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="source archive test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "checkout"
        self.root.mkdir()
        self.git("init", "-q")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Fixture")
        for name, data in {
            "README.md": b"# Example\n",
            ".gitignore": b"/.local/\n",
            "AGENTS.md": b"Local instructions",
            "tooling/run.sh": b"#!/bin/sh\nexit 0\n",
        }.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        (self.root / "tooling/run.sh").chmod(0o755)
        self.commit()
        self.archive, _ = source_zip.create(self.root)

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.PIPE)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")

    def mutate(self, change):
        output = Path(self.temporary.name) / "mutated.zip"
        with zipfile.ZipFile(self.archive) as archive:
            entries = [(info, archive.read(info)) for info in archive.infolist()]
        entries = change(entries)
        with zipfile.ZipFile(output, "w") as archive:
            for info, data in entries:
                archive.writestr(info, data)
        return output

    def test_reproducible_and_complete_round_trip_without_git(self):
        duplicate = Path(self.temporary.name) / "repeat.zip"
        _, digest = source_zip.create(self.root, duplicate)
        self.assertEqual(self.archive.read_bytes(), duplicate.read_bytes())
        self.assertEqual(digest, hashlib.sha256(self.archive.read_bytes()).hexdigest())
        output = Path(self.temporary.name) / "extracted with spaces"
        # Python's extractall deliberately ignores executable modes; simulate unzip.
        with zipfile.ZipFile(self.archive) as archive:
            archive.extractall(output)
            for info in archive.infolist():
                (output / info.filename).chmod(stat.S_IMODE(info.external_attr >> 16))
        root = output / "rehab-plan-ocr"
        self.assertFalse((root / "AGENTS.md").exists())
        self.assertFalse((root / ".git").exists())
        self.assertEqual(
            source.identity(root)["commit"], self.git("rev-parse", "HEAD").decode().strip()
        )
        self.assertEqual(source.names(root), [".gitignore", "README.md", "tooling/run.sh"])
        (root / "tooling/run.sh").chmod(0o644)
        with self.assertRaisesRegex(ValueError, "permission"):
            source.verify_directory(root)
        (root / "tooling/run.sh").chmod(0o755)
        (root / "README.md").write_text("modified")
        with self.assertRaisesRegex(ValueError, "content"):
            source.identity(root)

    def test_missing_modified_duplicate_and_symlink_entries_fail(self):
        def symlink(entries):
            entries[0][0].external_attr = (stat.S_IFLNK | 0o777) << 16
            return entries

        def permission(entries):
            for info, _ in entries:
                if info.filename.endswith("run.sh"):
                    info.external_attr = (stat.S_IFREG | 0o644) << 16
            return entries

        for change in [
            lambda e: e[1:],
            lambda e: e + [e[0]],
            symlink,
            permission,
            lambda e: [
                (info, b"changed" if info.filename.endswith("README.md") else data)
                for info, data in e
            ],
        ]:
            with self.subTest(change=change):
                with self.assertRaises((ValueError, KeyError)):
                    source_zip.verify(self.mutate(change))

    def test_unsafe_and_prohibited_paths_fail(self):
        for name in [
            "../escape",
            "/absolute",
            "rehab-plan-ocr/a/../README.md",
            "rehab-plan-ocr/.local/secret",
            "rehab-plan-ocr/apps/model.onnx",
            "rehab-plan-ocr/AGENTS.md",
            "rehab-plan-ocr/apps/.env.production",
            "rehab-plan-ocr/apps/evil\\path",
            "other/README.md",
        ]:
            with self.subTest(name=name):

                def change(entries):
                    info = copy.copy(entries[0][0])
                    info.filename = name
                    return sorted([*entries, (info, b"bad")], key=lambda e: e[0].filename)

                with self.assertRaises(ValueError):
                    source_zip.verify(self.mutate(change))

    def test_forged_hashes_cannot_hide_modified_source_or_commit(self):
        for forge in ["hash", "commit", "tree", "remove"]:

            def change(entries):
                result = []
                for info, data in entries:
                    if info.filename.endswith(source.MANIFEST):
                        manifest = json.loads(data)
                        if forge == "commit":
                            manifest["commit"] = "0" * 40
                        elif forge == "tree":
                            manifest["git_tree"][0]["oid"] = "0" * 40
                        elif forge == "remove":
                            manifest["files"] = manifest["files"][1:]
                        else:
                            manifest["files"][1]["sha256"] = hashlib.sha256(b"changed").hexdigest()
                            manifest["files"][1]["bytes"] = len(b"changed")
                        data = json.dumps(manifest).encode()
                    elif forge == "hash" and info.filename.endswith("README.md"):
                        data = b"changed"
                    result.append((info, data))
                return result

            with self.subTest(forge=forge), self.assertRaises(ValueError):
                source_zip.verify(self.mutate(change))

    def test_dirty_and_hidden_working_tree_changes_fail(self):
        self.git("update-index", "--assume-unchanged", "README.md")
        (self.root / "README.md").write_text("hidden change")
        with self.assertRaisesRegex(ValueError, "differs"):
            source_zip.create(self.root)
        self.git("update-index", "--no-assume-unchanged", "README.md")
        with self.assertRaisesRegex(ValueError, "clean"):
            source_zip.create(self.root)

    def test_tracked_symlinks_and_prohibited_artifacts_fail(self):
        for name, link in [("apps/secret.onnx", False), ("apps/link", True)]:
            path = self.root / name
            path.parent.mkdir(exist_ok=True)
            if link:
                path.symlink_to("../README.md")
            else:
                path.write_text("private weights")
            self.commit()
            with self.assertRaises(ValueError):
                source_zip.create(self.root)
            path.unlink()
            self.commit()

    def test_existing_output_is_never_overwritten(self):
        self.archive.write_bytes(b"preserve")
        with self.assertRaisesRegex(ValueError, "Existing submission"):
            source_zip.create(self.root)
        self.assertEqual(self.archive.read_bytes(), b"preserve")


if __name__ == "__main__":
    unittest.main()
