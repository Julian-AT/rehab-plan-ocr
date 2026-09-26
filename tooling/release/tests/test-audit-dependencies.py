"""Synthetic audit inputs only; no network, compilers or machine-wide installations."""

import io
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/release"))
import audit_dependencies as audit  # noqa: E402
import runtime_inventory  # noqa: E402


class AuditTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve() / "repository"
        for name in [audit.POLICY, "config/storage/workspace.json"]:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        (self.root / "Cargo.lock").write_text("# Synthetic dependency lock\n")
        self.pin = audit.policy(self.root)
        self.binary = b'#!/bin/sh\nprintf "cargo-audit 0.22.2\\n"\n'
        self.archive = self.root / "fixture.tar.gz"
        self.make_archive()
        self.host = patch.object(audit, "host_supported")
        self.host.start()
        self.addCleanup(self.host.stop)
        self.inventory = patch.object(
            runtime_inventory, "verify", return_value={"inventory_sha256": "synthetic"}
        )
        self.inventory.start()
        self.addCleanup(self.inventory.stop)

    def save_pin(self):
        (self.root / audit.POLICY).write_text(json.dumps(self.pin))

    def make_archive(self, duplicate=False, link=False, extra=False):
        with tarfile.open(self.archive, "w:gz") as bundle:
            member = tarfile.TarInfo(self.pin["archive"]["binary_member"])
            member.size = len(self.binary)
            if link:
                member.type = tarfile.SYMTYPE
                member.linkname = "../../outside"
                member.size = 0
            bundle.addfile(member, None if link else io.BytesIO(self.binary))
            if duplicate:
                bundle.addfile(member, io.BytesIO(self.binary))
            if extra:
                unrelated = tarfile.TarInfo("../../unexpected")
                unrelated.size = 7
                bundle.addfile(unrelated, io.BytesIO(b"ignored"))
        self.pin["binary_bytes"] = len(self.binary)
        self.pin["binary_sha256"] = audit.sha(self.binary)
        self.pin["archive"]["bytes"] = self.archive.stat().st_size
        self.pin["archive"]["sha256"] = audit.sha(self.archive.read_bytes())
        self.save_pin()

    def database(self):
        db = self.root / ".local/advisories"
        db.mkdir(parents=True)
        self.git(db, "init", "--quiet")
        self.git(db, "remote", "add", "origin", self.pin["database_url"])
        file = db / "crates/synthetic/RUSTSEC-2000-0000.md"
        file.parent.mkdir(parents=True)
        file.write_text("Synthetic advisory bytes\n")
        self.git(db, "add", ".")
        self.git(
            db,
            "-c",
            "user.name=Synthetic",
            "-c",
            "user.email=synthetic@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "core.hooksPath=/dev/null",
            "commit",
            "--quiet",
            "-m",
            "Synthetic snapshot",
        )
        return db, audit.git(db, "rev-parse", "HEAD").decode().strip(), file

    def git(self, db, *args):
        subprocess.run(["git", "-C", str(db), *args], check=True, capture_output=True)

    def report(self, count=0):
        return {
            "settings": {
                "ignore": [],
                "target_arch": [],
                "target_os": [],
                "severity": None,
                "informational_warnings": ["notice", "unmaintained", "unsound"],
            },
            "vulnerabilities": {"found": bool(count), "count": count, "list": [{}] * count},
            "warnings": {"unmaintained": [{}]},
        }

    def execute(self, db, commit, output, report=None, status=0, mutate=None):
        report = self.report() if report is None else report
        original = subprocess.run

        def invoke(command, **kwargs):
            if command[0] == "git":
                return original(command, **kwargs)
            self.assertEqual(command[0], str(self.root / ".local/tools/bin/cargo-audit"))
            self.assertEqual(
                command[1:],
                [
                    "audit",
                    "--no-fetch",
                    "--no-yanked",
                    "--db",
                    str(db),
                    "--file",
                    str(self.root / "Cargo.lock"),
                    "--json",
                ],
            )
            if mutate:
                mutate()
            return subprocess.CompletedProcess(command, status, json.dumps(report).encode(), b"")

        with patch.object(audit.subprocess, "run", side_effect=invoke):
            return audit.run(self.root, db, commit, output)

    def test_setup_installs_only_exact_member_and_is_repeatable(self):
        self.make_archive(extra=True)
        result = audit.setup(self.root, self.archive)
        binary = self.root / result["binary"]
        before = binary.stat().st_mtime_ns
        self.assertEqual(binary.read_bytes(), self.binary)
        self.assertFalse((self.root.parent / "unexpected").exists())
        self.assertEqual(result, audit.setup(self.root, self.archive))
        self.assertEqual(binary.stat().st_mtime_ns, before)

    def test_setup_rejects_archive_tampering_without_installing(self):
        self.archive.write_bytes(self.archive.read_bytes() + b"changed")
        with self.assertRaisesRegex(ValueError, "bottle checksum"):
            audit.setup(self.root, self.archive)
        self.assertFalse((self.root / ".local/tools/bin/cargo-audit").exists())

    def test_setup_rejects_ambiguous_linked_or_wrong_binary(self):
        for options in [{"duplicate": True}, {"link": True}, {}]:
            self.make_archive(**options)
            if not options:
                self.pin["binary_sha256"] = "0" * 64
                self.save_pin()
            with self.subTest(options=options), self.assertRaises(ValueError):
                audit.setup(self.root, self.archive)
        self.assertFalse((self.root / ".local/tools/bin/cargo-audit").exists())

    def test_setup_never_replaces_changed_tool_or_uses_path_fallback(self):
        with self.assertRaisesRegex(ValueError, "absent or changed"):
            audit.tool(self.root, self.pin)
        result = audit.setup(self.root, self.archive)
        binary = self.root / result["binary"]
        binary.write_bytes(b"different tool")
        with self.assertRaisesRegex(ValueError, "absent or changed"):
            audit.setup(self.root, self.archive)
        self.assertEqual(binary.read_bytes(), b"different tool")

    def test_download_is_explicit_verified_and_reuses_valid_cache(self):
        def fetch(command, **kwargs):
            self.assertEqual(command[0], "curl")
            self.assertIn("Authorization: Bearer QQ==", command)
            self.assertEqual(command[-1], self.pin["archive"]["url"])
            shutil.copyfile(self.archive, command[command.index("--output") + 1])

        with patch.object(audit.subprocess, "run", side_effect=fetch) as network:
            target = audit.download(self.root)
            self.assertEqual(audit.download(self.root), target)
            self.assertEqual(network.call_count, 1)
        self.assertEqual(target.read_bytes(), self.archive.read_bytes())

    def test_corrupt_download_does_not_publish_cache(self):
        def fetch(command, **kwargs):
            Path(command[command.index("--output") + 1]).write_bytes(b"broken")

        with patch.object(audit.subprocess, "run", side_effect=fetch):
            with self.assertRaisesRegex(ValueError, "bottle checksum"):
                audit.download(self.root)
        self.assertFalse(audit.default_archive(self.root, self.pin).exists())

    def test_identity_rejects_wrong_origin_commit_or_dirty_snapshot(self):
        db, commit, file = self.database()
        identity = audit.database_identity(db, commit, self.pin)
        self.assertEqual(
            identity["files_sha256"][str(file.relative_to(db))], audit.sha(file.read_bytes())
        )
        with self.assertRaisesRegex(ValueError, "commit differs"):
            audit.database_identity(db, "0" * 40, self.pin)
        self.git(db, "remote", "set-url", "origin", "https://example.invalid")
        with self.assertRaisesRegex(ValueError, "origin differs"):
            audit.database_identity(db, commit, self.pin)
        self.git(db, "remote", "set-url", "origin", self.pin["database_url"])
        (db / "untracked").write_text("extra")
        with self.assertRaisesRegex(ValueError, "local changes"):
            audit.database_identity(db, commit, self.pin)

    def test_identity_rehashes_content_hidden_from_git_status(self):
        db, commit, file = self.database()
        self.git(db, "update-index", "--assume-unchanged", str(file.relative_to(db)))
        file.write_text("Silently modified advisory\n")
        self.assertFalse(audit.git(db, "status", "--porcelain"))
        with self.assertRaisesRegex(ValueError, "bytes differ"):
            audit.database_identity(db, commit, self.pin)

    def test_outputs_reject_outside_and_escaping_symlink(self):
        with self.assertRaises(ValueError):
            audit.local_path(self.root, Path("../outside"))
        (self.root / ".local").mkdir()
        (self.root / ".local/escape").symlink_to(self.root.parent, target_is_directory=True)
        with self.assertRaises(ValueError):
            audit.local_path(self.root, Path(".local/escape/output"))

    def test_explicit_update_creates_identity_and_preserves_existing_snapshot(self):
        source, commit, _ = self.database()
        destination = self.root / ".local/new-advisories"
        original = subprocess.run

        def clone(command, **kwargs):
            if command[:2] == ["git", "clone"]:
                self.assertEqual(command[2:5], ["--depth", "1", self.pin["database_url"]])
                shutil.copytree(source, command[5])
                return subprocess.CompletedProcess(command, 0)
            return original(command, **kwargs)

        with patch.object(audit.subprocess, "run", side_effect=clone):
            result = audit.update(self.root, destination)
            self.assertEqual(result["commit"], commit)
            receipt = self.root / result["receipt"]
            before = receipt.read_bytes()
            with self.assertRaisesRegex(ValueError, "new database destination"):
                audit.update(self.root, destination)
            self.assertEqual(receipt.read_bytes(), before)

    def test_offline_result_binds_inputs_without_release_approval_or_overwrite(self):
        audit.setup(self.root, self.archive)
        db, commit, _ = self.database()
        output = self.root / ".local/result"
        status, summary = self.execute(db, commit, output)
        self.assertEqual(status, 0)
        self.assertEqual(summary["warnings"], {"unmaintained": 1})
        receipt = json.loads((output / "receipt.json").read_text())
        self.assertFalse(receipt["release_approved"])
        self.assertEqual(receipt["database"]["commit"], commit)
        self.assertEqual(receipt["tool_sha256"], self.pin["binary_sha256"])
        self.assertEqual(
            receipt["cargo_lock_sha256"], audit.sha((self.root / "Cargo.lock").read_bytes())
        )
        before = (output / "receipt.json").read_bytes()
        with self.assertRaises(FileExistsError):
            self.execute(db, commit, output)
        self.assertEqual((output / "receipt.json").read_bytes(), before)

    def test_vulnerability_failure_keeps_completed_evidence(self):
        audit.setup(self.root, self.archive)
        db, commit, _ = self.database()
        output = self.root / ".local/result"
        status, summary = self.execute(db, commit, output, self.report(1), status=1)
        self.assertEqual((status, summary["vulnerabilities"]), (1, 1))
        self.assertTrue((output / "receipt.json").exists())

    def test_filtered_inconsistent_or_failed_review_has_no_receipt(self):
        audit.setup(self.root, self.archive)
        db, commit, _ = self.database()
        cases = []
        for key, value in [
            ("ignore", ["RUSTSEC-synthetic"]),
            ("target_os", ["macos"]),
            ("informational_warnings", []),
        ]:
            report = self.report()
            report["settings"][key] = value
            cases.append((report, 0))
        cases.extend([(self.report(1), 0), (self.report(), 2)])
        for index, (report, status) in enumerate(cases):
            output = self.root / f".local/result-{index}"
            with self.subTest(index=index), self.assertRaises(ValueError):
                self.execute(db, commit, output, report, status)
            self.assertTrue((output / "cargo-audit.json").exists())
            self.assertFalse((output / "receipt.json").exists())

    def test_concurrent_input_change_has_no_receipt(self):
        audit.setup(self.root, self.archive)
        db, commit, _ = self.database()
        output = self.root / ".local/result"
        with self.assertRaisesRegex(ValueError, "inputs changed"):
            self.execute(
                db, commit, output, mutate=lambda: (self.root / "Cargo.lock").write_text("changed")
            )
        self.assertFalse((output / "receipt.json").exists())


if __name__ == "__main__":
    unittest.main()
