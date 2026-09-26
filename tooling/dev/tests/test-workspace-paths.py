"""Moving generated storage must preserve consumers and respect Cargo overrides."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import workspace  # noqa: E402


class WorkspacePathTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="reha workspace ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        for name in [workspace.POLICY, "config/toolchains/versions.json"]:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(workspace.ROOT / name, target)

    def test_new_checkout_creates_canonical_paths_and_checked_compatibility_links(self):
        workspace.prepare(self.root)
        workspace.prepare(self.root)
        for name, entry in workspace.mappings(self.root).items():
            expected = self.root / entry["canonical"]
            self.assertEqual(workspace.location(name, self.root), expected)
            self.assertTrue(expected.is_dir())
            self.assertEqual((self.root / entry["legacy"]).resolve(), expected)

    def test_existing_storage_waits_for_explicit_migration(self):
        old = self.root / "target"
        old.mkdir()
        (old / "retained").write_bytes(b"previous failure evidence")
        workspace.prepare(self.root)
        self.assertEqual(workspace.location("cargo", self.root), old)
        self.assertEqual((old / "retained").read_bytes(), b"previous failure evidence")
        self.assertFalse((self.root / ".local/builds/rust").exists())

    def test_generated_directories_and_compatibility_links_stay_ignored(self):
        shutil.copyfile(workspace.ROOT / ".gitignore", self.root / ".gitignore")
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        paths = [item["legacy"] for item in workspace.mappings(self.root).values()]
        for path in paths:
            (self.root / path).mkdir(parents=True)

        def ignored():
            result = subprocess.run(
                ["git", "check-ignore", "--", *paths],
                cwd=self.root,
                text=True,
                capture_output=True,
                check=True,
            )
            self.assertEqual(set(result.stdout.splitlines()), set(paths))

        ignored()
        for path in paths:
            (self.root / path).rmdir()
        workspace.prepare(self.root)
        ignored()

    def test_conflicting_or_external_aliases_fail_closed(self):
        old = self.root / "target"
        old.mkdir()
        new = self.root / ".local/builds/rust"
        new.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "Both old and canonical"):
            workspace.location("cargo", self.root)
        old.rmdir()
        old.symlink_to(self.root.parent, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Compatibility link"):
            workspace.location("cargo", self.root)

    def test_cargo_override_and_explicit_training_environment_are_retained(self):
        env = workspace.environment(
            self.root,
            {"CARGO_TARGET_DIR": "alternate output", "UV_PROJECT_ENVIRONMENT": "training-env"},
        )
        self.assertEqual(env["CARGO_TARGET_DIR"], str(self.root / "alternate output"))
        self.assertEqual(env["UV_PROJECT_ENVIRONMENT"], "training-env")
        self.assertEqual(workspace.cargo_directory(self.root, env), self.root / "alternate output")
        self.assertEqual(
            env["RUSTUP_TOOLCHAIN"],
            json.loads((self.root / "config/toolchains/versions.json").read_text())["versions"][
                "rust"
            ],
        )

    def test_resolver_agrees_with_actual_cargo_metadata_for_alternate_output(self):
        (self.root / "Cargo.toml").write_text(
            '[package]\nname="workspace-path-probe"\nversion="0.0.0"\nedition="2021"\n'
            '[lib]\npath="lib.rs"\n'
        )
        (self.root / "lib.rs").write_text("pub fn probe() {}\n")
        env = workspace.environment(
            self.root, dict(os.environ, CARGO_TARGET_DIR="alternate output")
        )
        result = subprocess.run(
            ["cargo", "metadata", "--offline", "--no-deps", "--format-version", "1"],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(
            workspace.cargo_directory(self.root, env),
            Path(json.loads(result.stdout)["target_directory"]),
        )

    def test_native_generator_uses_alternate_cargo_outputs_not_stale_default(self):
        for name in ["tooling/dev/workspace.py", "tooling/build/build-native.sh"]:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(workspace.ROOT / name, target)
        tools = self.root / ".local/tools/bin"
        tools.mkdir(parents=True)
        (tools / "cargo").write_text("#!/bin/sh\nexit 0\n")
        (tools / "cargo").chmod(0o755)
        (tools / "python3").symlink_to(sys.executable)
        # The bootstrap Python must also be on the incoming path before the resolver runs.
        alternative = self.root / "alternate cargo/debug"
        alternative.mkdir(parents=True)
        stale = self.root / "target/debug"
        stale.mkdir(parents=True)
        (stale / "reha-bindgen").write_text("#!/bin/sh\nexit 99\n")
        (stale / "reha-bindgen").chmod(0o755)
        generated = {
            "RehaCore.swift": "binding fixture\n",
            "RehaCoreFFI.h": "header fixture\n",
            "RehaCoreFFI.modulemap": "module fixture\n",
        }
        script = alternative / "reha-bindgen"
        script.write_text(
            f"#!{sys.executable}\nimport os,sys\nfrom pathlib import Path\n"
            "assert Path(sys.argv[2]) == Path(os.environ['CARGO_TARGET_DIR']) / 'debug/libreha_ffi.dylib'\n"
            f"for name, value in {generated!r}.items():\n"
            "    (Path(sys.argv[-1]) / name).write_text(value)\n"
        )
        script.chmod(0o755)
        for name, content in generated.items():
            relative = (
                "Sources/RehaCore/RehaCore.swift"
                if name.endswith(".swift")
                else "Headers/module.modulemap"
                if name.endswith(".modulemap")
                else "Headers/RehaCoreFFI.h"
            )
            target = self.root / "packages/apple/RehaCore" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        completed = subprocess.run(
            ["/bin/sh", "tooling/build/build-native.sh", "check-bindings"],
            cwd=self.root,
            env=dict(
                os.environ,
                PATH=f"{tools}:/usr/bin:/bin",
                CARGO_TARGET_DIR=str(alternative.parent),
            ),
            text=True,
            capture_output=True,
            timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()
