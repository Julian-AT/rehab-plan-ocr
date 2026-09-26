"""Pinned, bounded LLVM file-reference reader. Setup is never part of inspection."""

import argparse
import hashlib
import json
import os
import re
import resource
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path, PurePosixPath

VERSION = "22.1.8-rust1.98.1"
INSTALLATION = f".local/tools/llvm-reader/{VERSION}"
ARCHIVE_URL = (
    "https://static.rust-lang.org/dist/2026-09-03/llvm-tools-1.98.1-aarch64-apple-darwin.tar.xz"
)
ARCHIVE_SHA = "9b68ac31be7c6d25a08ce34dbd2c1d026b8006905e74415b6d9576678379ecbc"
ARCHIVE_BYTES = 25_713_200
READER_SHA = "743281628bbd2ebaf67d4cd43061c8f9eaf8c9ad362f96e894bf6f1fc71b249e"
LIBRARY_SHA = "6f65eb3fd2cef5fa962c20b0520ee91a393b15bbe8b19b46d363d791b6bab028"
LICENSE_SHA = "8d85c1057d742e597985c7d4e6320b015a9139385cff4cbae06ffc0ebe89afee"
README_SHA = "d4239cd989d30e8627477c436a1df3a81ebe1d2a3ad2a5541fd016ae097402d8"
PREFIX = "llvm-tools-1.98.1-aarch64-apple-darwin/"
PAYLOAD = PREFIX + "llvm-tools-preview/lib/rustlib/aarch64-apple-darwin/"
MAGICS = (b"BC\xc0\xde", b"\xde\xc0\x17\x0b")
TIMEOUT = 30
MAX_INPUT = 16 * 1024**2
MAX_OUTPUT = 64 * 1024**2
MAX_DIAGNOSTICS = 512 * 1024
MAX_RSS = 256 * 1024**2
RESERVE = 20 * 1024**3
SETUP_BUDGET = 300 * 1024**2
STRING = r'"((?:[^"\\]|\\[0-9A-Fa-f]{2})*)"'
KNOWN_NAMED = {"llvm.dbg.cu", "llvm.module.flags", "llvm.ident", "llvm.errno.tbaa"}
KNOWN_FLAGS = {
    "SDK Version",
    "ProfileSummary",
    "Dwarf Version",
    "Debug Info Version",
    "wchar_size",
    "PIC Level",
    "PIE Level",
    "uwtable",
    "frame-pointer",
    "EnableSplitLTOUnit",
    "ThinLTO",
    "LTOPostLink",
    "Code Model",
    "RtLibUseGOT",
    "SmallDataLimit",
    "branch-target-enforcement",
    "sign-return-address",
    "sign-return-address-all",
    "sign-return-address-with-bkey",
}
EMPTY_BARRIER = re.compile(
    r'^\s*(?:tail )?call void asm sideeffect "", "~\{memory\}"\(\)'
    r"(?: #\d+)?(?:, ![^\n]+)*$"
)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def regular(path):
    """Reject link substitutions, including parent links, before opening anything."""
    if any(p.is_symlink() for p in [path, *path.parents]):
        raise ValueError(f"Symbolic LLVM input/tool path: {path}")
    value = path.lstat()
    if not stat.S_ISREG(value.st_mode):
        raise ValueError(f"Not a regular LLVM input/tool: {path}")
    return value


def identity(path):
    value = regular(path)
    return [
        value.st_dev,
        value.st_ino,
        value.st_size,
        value.st_mtime_ns,
        value.st_ctime_ns,
        value.st_mode,
    ]


def fingerprint(path):
    before = identity(path)
    value = {"identity": before, "sha256": sha(path)}
    if identity(path) != before:
        raise ValueError(f"LLVM file changed while hashing: {path}")
    return value


def library_path():
    return (
        Path(os.environ.get("RUSTUP_HOME", Path.home() / ".rustup"))
        / "toolchains/1.98.1-aarch64-apple-darwin/lib/libLLVM.dylib"
    ).absolute()


def safe_directory(path):
    if any(p.is_symlink() for p in [path, *path.parents]):
        raise ValueError(f"Symbolic LLVM setup/scratch directory: {path}")
    path.mkdir(parents=True, exist_ok=True)
    if not path.is_dir():
        raise ValueError("LLVM setup expected a directory")


def ensure_space(path, budget):
    if shutil.disk_usage(path).free - budget < RESERVE:
        raise ValueError("LLVM reader would consume the 20 GiB reserve")


def child_limits():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_OUTPUT, MAX_OUTPUT))
    resource.setrlimit(resource.RLIMIT_CPU, (TIMEOUT, TIMEOUT))
    # Darwin rejects a finite RLIMIT_RSS here. Enforce the reader RSS bound
    # through active sampling plus the actual per-child wait4 high-water mark.


def resident_bytes(pid):
    result = subprocess.run(
        ["/bin/ps", "-o", "rss=", "-p", str(pid)],
        capture_output=True,
        text=True,
        timeout=1,
    )
    if result.returncode == 1 and not result.stdout.strip() and not result.stderr:
        return 0  # The child exited; wait4 will still check its peak.
    if result.returncode or result.stderr or not result.stdout.strip().isdigit():
        raise ValueError("Cannot establish LLVM reader RSS bound")
    return int(result.stdout) * 1024


def run_bounded(argv, scratch, *, loader_trace=False, pass_fds=()):
    """One process group, finite output/time/RSS, no surviving child or output."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("DYLD_")}
    if loader_trace:
        env["DYLD_PRINT_LIBRARIES"] = "1"
    process = subprocess.Popen(
        argv,
        cwd=scratch,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        preexec_fn=child_limits,
        pass_fds=pass_fds,
    )
    started = time.monotonic()
    checked_rss = started
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    try:
        while selector.get_map():
            now = time.monotonic()
            if now - started > TIMEOUT:
                raise ValueError("LLVM reader timeout")
            if any(scratch.iterdir()):
                raise ValueError("LLVM reader produced extra/multiple-module files")
            if now - checked_rss >= 0.1:
                if resident_bytes(process.pid) > MAX_RSS:
                    raise ValueError("LLVM reader RSS limit")
                checked_rss = time.monotonic()
            for key, _ in selector.select(0.05):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                buffers[key.data].extend(chunk)
                limit = MAX_OUTPUT if key.data == "stdout" else MAX_DIAGNOSTICS
                if len(buffers[key.data]) > limit:
                    raise ValueError("LLVM reader output limit")
        # Pipes may close before the process exits. Do not use unbounded wait4.
        while True:
            pid, status, usage = os.wait4(process.pid, os.WNOHANG)
            if pid:
                process.returncode = os.waitstatus_to_exitcode(status)
                break
            if time.monotonic() - started > TIMEOUT:
                raise ValueError("LLVM reader timeout after output closed")
            if resident_bytes(process.pid) > MAX_RSS:
                raise ValueError("LLVM reader RSS limit")
            time.sleep(0.01)
        if usage.ru_maxrss > MAX_RSS:
            raise ValueError("LLVM reader peak RSS limit")
        if process.returncode or any(scratch.iterdir()):
            raise ValueError("LLVM reader failed or produced multiple-module output")
        return {key: bytes(value) for key, value in buffers.items()}
    finally:
        selector.close()
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if process.returncode is None:
            process.wait(timeout=2)
        process.stdout.close()
        process.stderr.close()


def unescape(value):
    result = bytearray()
    position = 0
    while position < len(value):
        if value[position] == "\\":
            result.append(int(value[position + 1 : position + 3], 16))
            position += 3
        else:
            result.extend(value[position].encode("utf-8"))
            position += 1
    decoded = result.decode("utf-8", errors="strict")
    if "\0" in decoded:
        raise ValueError("NUL in LLVM metadata path")
    return decoded


def field(line, name):
    skeleton = re.sub(STRING, lambda match: " " * len(match[0]), line)
    key = re.search(r"\b" + re.escape(name) + r":", skeleton)
    match = re.match(r"\s*" + STRING, line[key.end() :]) if key else None
    return unescape(match[1]) if match else None


def parse_ir(text, source, descriptor=None):
    """Read the full pinned writer grammar; reject unreviewed reference carriers."""
    references = []
    summaries = []
    flags = set()
    flag_nodes = {}
    source_filename = None
    target = None
    summary_count = 0
    has_code = False
    empty_barriers = 0
    for line in text.splitlines():
        # Mask quoted payloads before interpreting syntax (including comments).
        skeleton = re.sub(STRING, lambda match: " " * len(match[0]), line).split(";", 1)[0]
        if line.startswith("source_filename = "):
            source_filename = unescape(re.search(STRING, line)[1])
        elif line.startswith("target triple = "):
            target = unescape(re.search(STRING, line)[1])
        if line.startswith(("define ", "declare ", "@")):
            has_code = True
        if re.match(r"^\^\d+\s*=", line):
            summary_count += 1
            if "= module:" in skeleton:
                value = field(line, "path")
                if value is None:
                    raise ValueError("Unparsed LLVM summary module path")
                summaries.append(value)
        named = re.match(r"^!([A-Za-z$._][^ =]*)\s*=", line)
        if named:
            if named[1] not in KNOWN_NAMED:
                raise ValueError(f"Unreviewed LLVM named metadata: {named[1]}")
            if named[1] == "llvm.module.flags":
                flags.update(re.findall(r"!(\d+)", line))
        node = re.match(r"^!(\d+)\s*=", line)
        if node and node[1] in flags:
            flag_nodes[node[1]] = line
        if re.match(r"^!\d+\s*=\s*(?:distinct )?!DICompileUnit\(", skeleton):
            filename = field(line, "splitDebugFilename")
            dwo = re.search(r"\bdwoId:\s*([^,)]+)", skeleton)
            if filename:
                references.append({"kind": "external_debug_or_ast", "path": filename})
            elif dwo and int(dwo[1], 0):
                raise ValueError("LLVM DWO identity without an external filename")
        if re.match(r"^!\d+\s*=\s*(?:distinct )?!DIModule\(", skeleton):
            raise ValueError("LLVM source-module/AST lookup needs separate review")
        # Imported namespaces and DIFile source locations are not object inputs.
        if re.search(r"(?<![\w.%@-])asm(?![\w.-])", skeleton):
            if not EMPTY_BARRIER.fullmatch(line):
                raise ValueError("Opaque LLVM assembly may reference external files")
            empty_barriers += 1
    for node in flags:
        found = re.search(r"=\s*!\{i32\s+\d+,\s*!" + STRING, flag_nodes.get(node, ""))
        if not found or unescape(found[1]) not in KNOWN_FLAGS:
            raise ValueError("Unreviewed LLVM module flag")
    if source_filename is None or (target is None and (has_code or not summary_count)):
        raise ValueError("Missing complete LLVM module/index output")
    if target is not None and not re.fullmatch(r"[A-Za-z0-9_]+-apple-[A-Za-z0-9_.-]+", target):
        raise ValueError("LLVM reference inspection supports Apple targets only")
    normalized = []
    for value in summaries:
        if descriptor is not None and value == descriptor and (has_code or target is not None):
            value = str(source)  # Single-module summary identifies its held input.
        normalized.append(value)
        if value != str(source):
            references.append({"kind": "thinlto_module", "path": value})
    for reference in references:
        # Source/debug compilation directories do not prove the linker's cwd.
        # Never guess a relative ThinLTO/DWO/AST file against our current cwd.
        path = Path(reference["path"])
        if not path.is_absolute() or ".." in path.parts or path.is_relative_to("/dev"):
            raise ValueError("Ambiguous relative LLVM external file reference")
    return {
        "references": references,
        "summary_entries": summary_count,
        "summary_module_paths": normalized,
        "empty_memory_barriers": empty_barriers,
        "target": target,
    }


def loaded_images(text):
    images = set()
    delayed = set()
    for line in text.splitlines():
        image = re.fullmatch(r"dyld\[\d+\]: <[^>]+> (/.+)", line)
        moved = re.fullmatch(r"dyld\[\d+\]: move loaded to delayed: (.+)", line)
        if image:
            images.add(image[1])
        elif moved:
            delayed.add(moved[1])
        else:
            raise ValueError("Unexpected LLVM loader diagnostic")
    if not delayed.issubset({Path(path).name for path in images}):
        raise ValueError("Unbound LLVM delayed image diagnostic")
    return {path for path in images if not path.startswith(("/usr/lib/", "/System/Library/"))}


class Reader:
    def __init__(self, root):
        if sys.platform != "darwin":
            raise ValueError("LLVM reader qualification requires Darwin")
        self.root = root
        self.directory = root / INSTALLATION
        self.reader = self.directory / "bin/llvm-dis"
        link = self.directory / "lib/libLLVM.dylib"
        try:
            # Only this one explicit, receipt-bound library link is permitted.
            if any(p.is_symlink() for p in link.parents):
                raise ValueError("Symbolic LLVM library parent")
            if not link.is_symlink():
                raise ValueError("Missing pinned LLVM library binding")
            self.library = Path(os.readlink(link))
            if not self.library.is_absolute():
                raise ValueError("LLVM library binding must be absolute")
            self.link_target = os.readlink(link)
            self.receipt_path = self.directory / "receipt.json"
            self.receipt = fingerprint(self.receipt_path)
            value = json.loads(self.receipt_path.read_text())
            expected = {
                "schema": 1,
                "archive_sha256": ARCHIVE_SHA,
                "reader_sha256": READER_SHA,
                "library_sha256": LIBRARY_SHA,
                "library": str(self.library),
            }
            if value != expected:
                raise ValueError("Invalid LLVM setup receipt")
            self.tools = {
                self.reader: fingerprint(self.reader),
                self.library: fingerprint(self.library),
            }
            if self.tools[self.reader]["sha256"] != READER_SHA:
                raise ValueError("Changed LLVM reader")
            if self.tools[self.library]["sha256"] != LIBRARY_SHA:
                raise ValueError("Changed LLVM library")
            if not os.access(self.reader, os.X_OK):
                raise ValueError("LLVM reader is not executable")
        except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
            raise ValueError("LLVM reader unavailable; run make artifact-reader-setup") from error
        scratch_parent = root / ".local/maintenance"
        safe_directory(scratch_parent)
        ensure_space(scratch_parent, MAX_OUTPUT)
        with tempfile.TemporaryDirectory(prefix="llvm-read-", dir=scratch_parent) as temporary:
            result = run_bounded(
                [str(self.reader), "--version"], Path(temporary), loader_trace=True
            )
        if b"22.1.8-rust-1.98.1-stable" not in result["stdout"]:
            raise ValueError("Unexpected LLVM reader version")
        loaded = loaded_images(result["stderr"].decode("utf-8", errors="strict"))
        if loaded != {str(self.reader), str(self.library)}:
            raise ValueError("LLVM reader loaded an unexpected library closure")
        self.verify()

    def verify(self, *, hashes=True):
        if os.readlink(self.directory / "lib/libLLVM.dylib") != self.link_target:
            raise ValueError("LLVM library binding changed during inspection")
        if fingerprint(self.receipt_path) != self.receipt:
            raise ValueError("LLVM receipt changed during inspection")
        for path, expected in self.tools.items():
            actual = fingerprint(path) if hashes else {"identity": identity(path)}
            if any(expected[key] != value for key, value in actual.items()):
                raise ValueError("LLVM reader/library changed during inspection")

    def qualification(self):
        return {
            "version": VERSION,
            "reader_sha256": READER_SHA,
            "library_sha256": LIBRARY_SHA,
            "library": str(self.library),
            "implementation_sha256": sha(Path(__file__)),
        }

    def read(self, path):
        self.verify(hashes=False)
        if not path.is_relative_to(self.root) or ".." in path.parts:
            raise ValueError("LLVM input is outside the reviewed checkout")
        if regular(path).st_size > MAX_INPUT:
            raise ValueError("LLVM input size limit")
        before = fingerprint(path)
        if before["identity"][2] > MAX_INPUT:
            raise ValueError("LLVM input size limit")
        parent = self.root / ".local/maintenance"
        safe_directory(parent)
        ensure_space(parent, MAX_OUTPUT)
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as stream:
            opened = os.fstat(stream.fileno())
            held = [
                opened.st_dev,
                opened.st_ino,
                opened.st_size,
                opened.st_mtime_ns,
                opened.st_ctime_ns,
                opened.st_mode,
            ]
            if held != before["identity"]:
                raise ValueError("LLVM input replaced before opening")
            if not stream.read(4).startswith(MAGICS):
                raise ValueError("Unsupported LLVM header")
            stream.seek(0)
            if hashlib.file_digest(stream, "sha256").hexdigest() != before["sha256"]:
                raise ValueError("LLVM input changed before reading")
            stream.seek(0)
            descriptor = f"/dev/fd/{stream.fileno()}"
            with tempfile.TemporaryDirectory(prefix="llvm-read-", dir=parent) as temporary:
                result = run_bounded(
                    [str(self.reader), "-o", "-", descriptor],
                    Path(temporary),
                    pass_fds=(stream.fileno(),),
                )
            stream.seek(0)
            if hashlib.file_digest(stream, "sha256").hexdigest() != before["sha256"]:
                raise ValueError("LLVM held input changed during inspection")
        if result["stderr"] or not result["stdout"]:
            raise ValueError("LLVM reader diagnostic or empty module output")
        after = fingerprint(path)
        self.verify(hashes=False)
        if before != after:
            raise ValueError("LLVM input changed during inspection")
        parsed = parse_ir(result["stdout"].decode("utf-8", errors="strict"), path, descriptor)
        # Raw IR embeds the descriptor number; it is deliberately not a plan key.
        # Exact input bytes plus the qualified reader/library bind replay instead.
        parsed["input"] = before
        return parsed


def setup(root, archive=None):
    """Explicit installation; a pinned Rust 1.98.1 library is a prerequisite."""
    library = library_path()
    if not library.exists():
        raise ValueError(f"Setup requires Rust 1.98.1 at {library}")
    if fingerprint(library)["sha256"] != LIBRARY_SHA:
        raise ValueError("Setup requires the pinned Rust 1.98.1 libLLVM.dylib")
    directory = root / INSTALLATION
    safe_directory(directory.parent)
    if directory.exists():
        reader = Reader(root)
        return reader.qualification()  # No silent repair/replacement of evidence.
    ensure_space(root, SETUP_BUDGET)
    cache = root / ".local/tools/cache"
    safe_directory(cache)
    if archive is None:
        archive = cache / ARCHIVE_SHA
        if not archive.exists():
            with tempfile.NamedTemporaryFile(dir=cache, prefix="llvm-download-") as download:
                result = subprocess.run(
                    [
                        "/usr/bin/curl",
                        "--fail",
                        "--location",
                        "--silent",
                        "--show-error",
                        "--max-time",
                        "90",
                        "--max-filesize",
                        str(ARCHIVE_BYTES),
                        ARCHIVE_URL,
                    ],
                    stdout=download,
                    stderr=subprocess.PIPE,
                    timeout=95,
                )
                download.flush()
                temporary = Path(download.name)
                if result.returncode or temporary.stat().st_size != ARCHIVE_BYTES:
                    raise ValueError("LLVM archive download failed")
                if sha(temporary) != ARCHIVE_SHA:
                    raise ValueError("LLVM archive checksum mismatch")
                os.link(temporary, archive)
    archive = archive.absolute()
    before = fingerprint(archive)
    if before["sha256"] != ARCHIVE_SHA or before["identity"][2] != ARCHIVE_BYTES:
        raise ValueError("LLVM archive checksum/size mismatch")
    with tempfile.TemporaryDirectory(prefix="llvm-setup-", dir=directory.parent) as temporary:
        stage = Path(temporary)
        (stage / "bin").mkdir()
        (stage / "lib").mkdir()
        selected = {
            PAYLOAD + "bin/llvm-dis": ("bin/llvm-dis", READER_SHA),
            PREFIX + "LICENSE.TXT": ("LICENSE.TXT", LICENSE_SHA),
            PREFIX + "README.txt": ("README.txt", README_SHA),
        }
        with tarfile.open(archive, "r:xz") as bundle:
            members = bundle.getmembers()
            names = [member.name for member in members]
            if len(names) != len(set(names)):
                raise ValueError("Duplicate LLVM archive paths")
            for member in members:
                path = PurePosixPath(member.name)
                if path.is_absolute() or ".." in path.parts or "\\" in member.name:
                    raise ValueError("Unsafe LLVM archive path")
            for name, (destination, expected) in selected.items():
                member = bundle.getmember(name)
                if not member.isfile() or member.size > 1024**2:
                    raise ValueError("Unexpected LLVM archive member")
                target = stage / destination
                with bundle.extractfile(member) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)
                if sha(target) != expected:
                    raise ValueError("LLVM extracted member checksum mismatch")
            member = bundle.getmember(PAYLOAD + "lib/libLLVM.dylib")
            if not member.isfile() or member.size != regular(library).st_size:
                raise ValueError("Unexpected LLVM archive library")
            with bundle.extractfile(member) as source:
                if hashlib.file_digest(source, "sha256").hexdigest() != LIBRARY_SHA:
                    raise ValueError("LLVM archive library differs from the installed toolchain")
        if fingerprint(archive) != before or fingerprint(library)["sha256"] != LIBRARY_SHA:
            raise ValueError("LLVM setup input changed")
        (stage / "bin/llvm-dis").chmod(0o755)
        (stage / "lib/libLLVM.dylib").symlink_to(library)
        value = {
            "schema": 1,
            "archive_sha256": ARCHIVE_SHA,
            "reader_sha256": READER_SHA,
            "library_sha256": LIBRARY_SHA,
            "library": str(library),
        }
        (stage / "receipt.json").write_text(json.dumps(value, indent=2) + "\n")
        # mkdir publishes an exclusive destination; no existing installation is replaced.
        directory.mkdir()
        for child in stage.iterdir():
            child.rename(directory / child.name)
    return Reader(root).qualification()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["setup"])
    parser.add_argument("--archive", type=Path, help="Existing hash-pinned archive; no download")
    args = parser.parse_args()
    try:
        print(json.dumps(setup(Path(__file__).resolve().parents[2], args.archive), indent=2))
    except (OSError, ValueError, subprocess.SubprocessError, tarfile.TarError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
