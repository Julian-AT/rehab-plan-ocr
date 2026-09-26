import importlib.util
import os
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "llvm_references", Path(__file__).resolve().parents[1] / "llvm_references.py"
)
llvm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(llvm)

MODULE = 'source_filename = "test.c"\ntarget triple = "arm64-apple-macosx11.0.0"\n'
FIXTURE_SHA = "9f6b7d748059ea603a1f06d9a1afe1d224273a227c6e14318540d0325ff2c290"
BARRIER_SHA = "d91a1aa8024709c0973763276867c50b886f3196b79a95d1de1ab1851b14a367"


class ParserTests(unittest.TestCase):
    def parse(self, text):
        return llvm.parse_ir(text, Path("/checkout/module.bc"))

    def test_symbols_attributes_and_imported_namespaces_are_not_file_edges(self):
        text = (
            MODULE
            + """
declare void @other()
attributes #0 = { "probe-stack"="inline-asm" }
!llvm.dbg.cu = !{!0}
!0 = distinct !DICompileUnit(file: !1, imports: !2)
!1 = !DIFile(filename: "other.c", directory: "/old/source")
!2 = !{!3}
!3 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !4)
!4 = !DINamespace(name: "other", scope: null)
"""
        )
        self.assertEqual(self.parse(text)["references"], [])

    def test_self_summary_and_combined_index_edges_are_distinct(self):
        value = self.parse(MODULE + '^0 = module: (path: "/checkout/module.bc", hash: (0))')
        self.assertEqual(value["summary_entries"], 1)
        self.assertEqual(value["references"], [])
        value = self.parse(
            'source_filename = "combined.bc"\n^0 = module: (path: "/checkout/other.o", hash: (0))'
        )
        self.assertEqual(
            value["references"], [{"kind": "thinlto_module", "path": "/checkout/other.o"}]
        )

    def test_escaped_path_and_debug_ast_edges(self):
        value = self.parse(
            MODULE
            + r'!0 = distinct !DICompileUnit(splitDebugFilename: "/path/a\20b.pcm", dwoId: 42)'
        )
        self.assertEqual(value["references"][0]["path"], "/path/a b.pcm")

    def test_relative_missing_and_unsupported_metadata_refuse(self):
        for suffix in [
            '^0 = module: (path: "other.o", hash: (0))',
            '!0 = distinct !DICompileUnit(splitDebugFilename: "other.dwo", dwoId: 42)',
            "!0 = distinct !DICompileUnit(dwoId: 42)",
            '!0 = !DIModule(name: "Other", includePath: "/modules")',
            '!llvm.linker.options = !{!0}\n!0 = !{!"other.o"}',
            '!llvm.module.flags = !{!0}\n!0 = !{i32 1, !"Linker Options", !1}',
            '!llvm.module.flags = !{!0}\n!0 = !{i32 1, !"new-unknown", i32 0}',
        ]:
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                self.parse(MODULE + suffix)
        for text in ["", 'source_filename = "empty"\n', MODULE.replace("apple", "linux")]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.parse(text)

    def test_only_exact_empty_memory_barriers_are_allowed(self):
        for prefix in ["call", "tail call"]:
            value = self.parse(
                MODULE + f'  {prefix} void asm sideeffect "", "~{{memory}}"() #1, !dbg !2'
            )
            self.assertEqual(value["empty_memory_barriers"], 1)
        for line in [
            r'module asm ".incbin \22/external.bin\22"',
            r'call void asm sideeffect ".include \22/external.s\22", ""()',
            'call void asm sideeffect "nop", "~{memory}"()',
            'call void asm sideeffect "", "r"(i32 0)',
        ]:
            with self.subTest(line=line), self.assertRaisesRegex(ValueError, "Opaque"):
                self.parse(MODULE + line)

    def test_llvm_hex_escapes_do_not_turn_strings_into_keywords(self):
        self.assertEqual(
            self.parse(MODULE + r'attributes #0 = { "custom"="text \22 asm \22" }')["references"],
            [],
        )
        with self.assertRaises(ValueError):
            self.parse(MODULE + r'^0 = module: (path: "/x\00y", hash: (0))')

    def test_string_payloads_comments_and_held_descriptor_are_lexically_distinct(self):
        self.assertEqual(
            self.parse(MODULE + '\n; asm !DIModule(\n!0 = !{!"!DIModule("}')["references"], []
        )
        value = llvm.parse_ir(
            MODULE + 'define void @f() { ret void }\n^0 = module: (path: "/dev/fd/3", hash: (0))',
            Path("/checkout/module.bc"),
            "/dev/fd/3",
        )
        self.assertEqual(value["references"], [])
        self.assertEqual(value["summary_module_paths"], ["/checkout/module.bc"])
        with self.assertRaises(ValueError):
            llvm.parse_ir(
                'source_filename = "index"\n^0 = module: (path: "/dev/fd/3", hash: (0))',
                Path("/checkout/module.bc"),
                "/dev/fd/3",
            )

    def test_metadata_keys_inside_quoted_strings_are_not_fields(self):
        value = self.parse(
            MODULE + '!0 = distinct !DICompileUnit(producer: "splitDebugFilename: ", '
            'splitDebugFilename: "/actual/external.dwo", dwoId: 42)'
        )
        self.assertEqual(value["references"][0]["path"], "/actual/external.dwo")
        self.assertEqual(
            self.parse(MODULE + '!0 = distinct !DICompileUnit(producer: "dwoId: 42")')[
                "references"
            ],
            [],
        )


@unittest.skipUnless(sys.platform == "darwin", "Darwin process/RSS contract")
class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.scratch = self.root / "scratch"
        self.scratch.mkdir()

    def run_child(self, source):
        return llvm.run_bounded([sys.executable, "-B", "-c", source], self.scratch)

    def test_success_and_parent_environment_are_isolated(self):
        with patch.dict(os.environ, {"DYLD_LIBRARY_PATH": "/untrusted"}):
            result = self.run_child(
                "import os; assert 'DYLD_LIBRARY_PATH' not in os.environ; print('bounded')"
            )
        self.assertEqual(result["stdout"], b"bounded\n")

    def test_timeout_kills_process_even_after_both_output_streams_close(self):
        child_pid = self.root / "pid"
        source = (
            f"import os,time; open({str(child_pid)!r},'w').write(str(os.getpid()));"
            "os.close(1);os.close(2);time.sleep(10)"
        )
        with patch.object(llvm, "TIMEOUT", 1), self.assertRaisesRegex(ValueError, "timeout"):
            self.run_child(source)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(child_pid.read_text()), 0)

    def test_output_and_extra_files_are_refused(self):
        with patch.object(llvm, "MAX_OUTPUT", 1024), self.assertRaisesRegex(ValueError, "output"):
            self.run_child("print('x'*4096)")
        with self.assertRaisesRegex(ValueError, "multiple-module"):
            self.run_child("open('-.0','w').write('extra');print('IR')")

    def test_rss_sampler_failure_and_limit_refuse(self):
        with (
            patch.object(llvm, "resident_bytes", return_value=llvm.MAX_RSS + 1),
            self.assertRaisesRegex(ValueError, "RSS"),
        ):
            self.run_child("import time;time.sleep(2)")
        with (
            patch.object(llvm, "resident_bytes", side_effect=ValueError("RSS unavailable")),
            self.assertRaisesRegex(ValueError, "RSS"),
        ):
            self.run_child("import time;time.sleep(2)")

    def test_process_group_descendant_is_killed_on_failure(self):
        pidfile = self.root / "descendant"
        source = (
            "import os,time;"
            "child=os.fork();"
            f"open({str(pidfile)!r},'w').write(str(child)) if child else None;"
            "time.sleep(10)"
        )
        with patch.object(llvm, "TIMEOUT", 1), self.assertRaisesRegex(ValueError, "timeout"):
            self.run_child(source)
        pid = int(pidfile.read_text())
        for _ in range(20):
            result = subprocess.run(
                ["/bin/ps", "-o", "state=", "-p", str(pid)], capture_output=True, text=True
            )
            if result.returncode == 1 or result.stdout.strip().startswith("Z"):
                break
            time.sleep(0.05)
        else:
            os.kill(pid, signal.SIGKILL)
            self.fail("LLVM subprocess descendant survived")


class BoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def test_missing_setup_never_downloads(self):
        with patch.object(llvm.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                llvm.Reader(self.root)
        run.assert_not_called()

    def test_loader_trace_binds_images_and_known_delayed_messages(self):
        text = (
            "dyld[42]: <A> /reader/llvm-dis\n"
            "dyld[42]: <B> /toolchain/libLLVM.dylib\n"
            "dyld[42]: <C> /System/Library/Frameworks/Foundation\n"
            "dyld[42]: move loaded to delayed: Foundation\n"
        )
        self.assertEqual(llvm.loaded_images(text), {"/reader/llvm-dis", "/toolchain/libLLVM.dylib"})
        for line in ["unrecognized warning", "dyld[42]: move loaded to delayed: unknown"]:
            with self.assertRaises(ValueError):
                llvm.loaded_images(text + line)

    def test_symlink_and_mid_hash_mutation_are_refused(self):
        source = self.root / "object.bc"
        source.write_bytes(b"original")
        link = self.root / "link.bc"
        link.symlink_to(source)
        with self.assertRaisesRegex(ValueError, "Symbolic"):
            llvm.fingerprint(link)

        def mutate(path):
            path.write_bytes(b"changed")
            return "a" * 64

        with (
            patch.object(llvm, "sha", side_effect=mutate),
            self.assertRaisesRegex(ValueError, "changed"),
        ):
            llvm.fingerprint(source)

    def test_reserve_failure_precedes_setup_download(self):
        library = self.root / "libLLVM.dylib"
        library.write_bytes(b"test library")
        with (
            patch.object(llvm, "library_path", return_value=library),
            patch.object(llvm, "fingerprint", return_value={"sha256": llvm.LIBRARY_SHA}),
            patch.object(
                llvm.shutil, "disk_usage", return_value=type("Space", (), {"free": llvm.RESERVE})()
            ),
            patch.object(llvm.subprocess, "run") as run,
            self.assertRaisesRegex(ValueError, "reserve"),
        ):
            llvm.setup(self.root)
        run.assert_not_called()

    def test_oversized_input_is_refused_before_hashing(self):
        source = self.root / "large.bc"
        with source.open("wb") as stream:
            stream.truncate(llvm.MAX_INPUT + 1)
        reader = object.__new__(llvm.Reader)
        reader.root = self.root
        reader.verify = lambda **kwargs: None
        with patch.object(llvm, "fingerprint") as fingerprint:
            with self.assertRaisesRegex(ValueError, "size limit"):
                reader.read(source)
        fingerprint.assert_not_called()


# Real compiler-generated negative fixtures stay in the private evidence archive.
# Explicit test inputs make offline CI skips visible, without auto-installation or
# committing private generated build products. The fixture recipes are recorded
# with that archive; the hash makes a replacement a different test input.
@unittest.skipUnless(
    os.environ.get("LLVM_READER_TEST_ARCHIVE") and os.environ.get("LLVM_READER_TEST_FIXTURES"),
    "Set explicit verified tool and synthetic-fixture archives for live LLVM tests",
)
class RealReaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name).resolve()
        cls.fixture_archive = Path(os.environ["LLVM_READER_TEST_FIXTURES"]).resolve()
        if llvm.sha(cls.fixture_archive) != FIXTURE_SHA:
            raise ValueError("Unexpected synthetic fixture archive")
        llvm.setup(cls.root, Path(os.environ["LLVM_READER_TEST_ARCHIVE"]).resolve())
        cls.reader = llvm.Reader(cls.root)

    def fixture(self, name):
        directory = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / (name + ".bc")
        with tarfile.open(self.fixture_archive, "r:gz") as archive:
            member = archive.getmember(f"fixtures-v5/{name}.bc")
            self.assertTrue(member.isfile())
            self.assertLess(member.size, 16384)
            with archive.extractfile(member) as source, path.open("xb") as destination:
                destination.write(source.read())
        return path

    def test_full_module_and_original_combined_summary(self):
        value = self.reader.read(self.fixture("plain-symbol"))
        self.assertEqual(value["references"], [])
        value = self.reader.read(self.fixture("thinlto-external"))
        self.assertGreater(value["summary_entries"], 0)
        self.assertEqual(value["references"][0]["path"], "/private-fixture/external-input.o")

    def test_dwo_ast_and_non_file_metadata(self):
        for name, suffix in [("split-dwo", ".dwo"), ("external-ast", ".pcm")]:
            value = self.reader.read(self.fixture(name))
            self.assertTrue(value["references"][0]["path"].endswith(suffix))
        for name in ["stack-probe-attribute", "imported-namespace"]:
            self.assertEqual(self.reader.read(self.fixture(name))["references"], [])

    def test_actual_archived_empty_barriers_are_allowed(self):
        archive = self.fixture_archive.parent / "empty-barrier-fixture-v2.tar.gz"
        self.assertEqual(llvm.sha(archive), BARRIER_SHA)
        with tempfile.TemporaryDirectory(dir=self.root) as temporary:
            target = Path(temporary) / "fixture.bc"
            with tarfile.open(archive, "r:gz") as bundle:
                member = bundle.getmember("fixture.bc")
                self.assertTrue(member.isfile())
                self.assertLess(member.size, 16384)
                with bundle.extractfile(member) as source, target.open("xb") as output:
                    output.write(source.read())
            value = self.reader.read(target)
        self.assertEqual(value["empty_memory_barriers"], 2)
        self.assertEqual(value["references"], [])

    def test_real_opaque_assembly_malformed_and_multiple_modules_refuse(self):
        for name in [
            "asm-incbin",
            "function-asm-include",
            "source-module",
            "malformed",
            "multiple-modules",
        ]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.reader.read(self.fixture(name))
        self.assertEqual(list((self.root / ".local/maintenance").iterdir()), [])

    def test_changed_input_during_actual_reader_is_refused(self):
        source = self.fixture("plain-symbol")
        real = llvm.run_bounded

        def mutate(*args, **kwargs):
            value = real(*args, **kwargs)
            source.write_bytes(source.read_bytes() + b"x")
            return value

        with patch.object(llvm, "run_bounded", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "changed"):
                self.reader.read(source)

    def test_tool_mutation_and_binding_change_refuse_before_read(self):
        reader = self.root / llvm.INSTALLATION / "bin/llvm-dis"
        original_mode = reader.stat().st_mode
        try:
            reader.chmod(0o644)
            with self.assertRaises(ValueError):
                self.reader.read(self.fixture("plain-symbol"))
        finally:
            reader.chmod(original_mode)
        # Restoring bytes/mode does not restore ctime; establish a new valid instance.
        self.__class__.reader = llvm.Reader(self.root)
        link = self.root / llvm.INSTALLATION / "lib/libLLVM.dylib"
        original = os.readlink(link)
        try:
            link.unlink()
            link.symlink_to(self.root / "other-library")
            with self.assertRaisesRegex(ValueError, "binding changed"):
                self.reader.read(self.fixture("plain-symbol"))
        finally:
            link.unlink()
            link.symlink_to(original)
        self.__class__.reader = llvm.Reader(self.root)

    def test_setup_replay_is_offline_and_rejects_corrupt_archive(self):
        with patch.object(llvm.subprocess, "run", wraps=llvm.subprocess.run) as run:
            llvm.setup(self.root)
        self.assertTrue(all("curl" not in str(call) for call in run.call_args_list))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            corrupt = root / "archive"
            corrupt.write_bytes(b"not the reviewed archive")
            with self.assertRaisesRegex(ValueError, "checksum"):
                llvm.setup(root, corrupt)
            self.assertFalse((root / llvm.INSTALLATION).exists())


if __name__ == "__main__":
    unittest.main()
