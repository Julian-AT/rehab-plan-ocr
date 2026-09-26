"""The selected release profile must retain source lines for crash symbolication."""

import json
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import workspace  # noqa: E402


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "Apple DWARF tools")
class ReleaseSymbolsTests(unittest.TestCase):
    def test_release_source_lines_and_matching_dsym_identity(self):
        profile = tomllib.loads((workspace.ROOT / "Cargo.toml").read_text())["profile"]["release"]
        with tempfile.TemporaryDirectory(prefix="reha release symbols ") as folder:
            root = Path(folder)
            (root / "Cargo.toml").write_text(
                '[package]\nname="release-symbol-probe"\nversion="0.0.0"\nedition="2021"\n'
                '[[bin]]\nname="release-symbol-probe"\npath="symbol_source.rs"\n'
                "[profile.release]\n"
                + "".join(f"{key}={json.dumps(value)}\n" for key, value in profile.items())
            )
            (root / "symbol_source.rs").write_text(
                "#[inline(never)]\nfn traced(value: usize) -> usize {\n"
                "    std::hint::black_box(value).wrapping_add(42)\n}\n"
                'fn main() { println!("{}", traced(std::env::args().count())); }\n'
            )
            env = workspace.environment()
            env["CARGO_TARGET_DIR"] = str(root / "output")
            # Profile overrides would bypass the repository contract under test.
            for key in tuple(env):
                if key.startswith("CARGO_PROFILE_RELEASE_") or key in {
                    "RUSTFLAGS",
                    "CARGO_ENCODED_RUSTFLAGS",
                    "CARGO_BUILD_RUSTFLAGS",
                }:
                    env.pop(key)
            compiled = subprocess.run(
                ["cargo", "build", "--release", "--offline"],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
                timeout=90,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            executable = root / "output/release/release-symbol-probe"
            symbols = executable.with_suffix(".dSYM")
            self.assertTrue(symbols.is_dir(), "Release build did not retain a dSYM bundle")

            def dwarf(option, path):
                return subprocess.check_output(
                    ["xcrun", "dwarfdump", option, str(path)], text=True, timeout=30
                )

            def identity(path):
                found = re.findall(r"UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)", dwarf("--uuid", path))
                self.assertTrue(found, "Missing build UUID")
                return found

            self.assertEqual(identity(executable), identity(symbols))
            self.assertIn("symbol_source.rs", dwarf("--debug-line", symbols))


if __name__ == "__main__":
    unittest.main()
