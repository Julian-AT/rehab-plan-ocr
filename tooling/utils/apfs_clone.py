"""Exclusive APFS clones for writable evaluation copies; no full-copy fallback.

Darwin COPYFILE_CLONE_FORCE cannot clone directories recursively. Each regular
file uses this strict operation, with a positive WAS_CLONED receipt. Directory
and symlink metadata are copied without COPYFILE_DATA. Failed fresh destinations
remain unqualified; callers may remove only their own temporary containers.
"""

import ctypes
import errno
import hashlib
import os
import stat
import sys
from pathlib import Path

# Darwin SDK copyfile.h. CLONE_FORCE also implies EXCL, STAT, XATTR and DATA.
CLONE_FORCE = 1 << 25
ACL = 1
METADATA = 7
NOFOLLOW = (1 << 18) | (1 << 19)
WAS_CLONED = 10


class StatFS(ctypes.Structure):
    """Darwin statfs64 layout from sys/mount.h; use the explicit 64-bit symbol."""

    _fields_ = [
        ("bsize", ctypes.c_uint32),
        ("iosize", ctypes.c_int32),
        ("blocks", ctypes.c_uint64),
        ("bfree", ctypes.c_uint64),
        ("bavail", ctypes.c_uint64),
        ("files", ctypes.c_uint64),
        ("ffree", ctypes.c_uint64),
        ("fsid", ctypes.c_int32 * 2),
        ("owner", ctypes.c_uint32),
        ("type", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("subtype", ctypes.c_uint32),
        ("fstypename", ctypes.c_char * 16),
        ("mntonname", ctypes.c_char * 1024),
        ("mntfromname", ctypes.c_char * 1024),
        ("flags_ext", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32 * 7),
    ]


def library():
    if sys.platform != "darwin":
        raise ValueError("Evaluation copies require Darwin APFS; no copying fallback")
    lib = ctypes.CDLL(None, use_errno=True)
    for name, args, result in [
        ("statfs64", [ctypes.c_char_p, ctypes.POINTER(StatFS)], ctypes.c_int),
        (
            "copyfile",
            [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_uint32],
            ctypes.c_int,
        ),
        ("copyfile_state_alloc", [], ctypes.c_void_p),
        ("copyfile_state_free", [ctypes.c_void_p], ctypes.c_int),
        ("copyfile_state_get", [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p], ctypes.c_int),
        ("acl_get_link_np", [ctypes.c_char_p, ctypes.c_int], ctypes.c_void_p),
        ("acl_to_text", [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ssize_t)], ctypes.c_void_p),
        ("acl_free", [ctypes.c_void_p], ctypes.c_int),
        (
            "listxattr",
            [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int],
            ctypes.c_ssize_t,
        ),
        (
            "getxattr",
            [
                ctypes.c_char_p,
                ctypes.c_char_p,
                ctypes.c_void_p,
                ctypes.c_size_t,
                ctypes.c_uint32,
                ctypes.c_int,
            ],
            ctypes.c_ssize_t,
        ),
    ]:
        function = getattr(lib, name)
        function.argtypes, function.restype = args, result
    return lib


def checked(result, path):
    if result:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(path))


def filesystem(lib, path):
    value = StatFS()
    checked(lib.statfs64(os.fsencode(path), ctypes.byref(value)), path)
    return bytes(value.fstypename).decode("ascii")


def acl_text(lib, path):
    acl = lib.acl_get_link_np(os.fsencode(path), 0x100)
    if not acl:
        if ctypes.get_errno() == errno.ENOENT:
            # Darwin also uses ENOENT for an existing inode without an extended ACL.
            # The surrounding entry() checks lstat identity before/after retrieval.
            path.lstat()
            return None
        checked(-1, path)
    try:
        size = ctypes.c_ssize_t()
        text = lib.acl_to_text(acl, ctypes.byref(size))
        if not text:
            checked(-1, path)
        try:
            return ctypes.string_at(text, size.value).decode()
        finally:
            lib.acl_free(text)
    finally:
        lib.acl_free(acl)


def xattrs(lib, path):
    # Darwin xattr.h XATTR_NOFOLLOW; Python's os xattr APIs are Linux-only.
    encoded = os.fsencode(path)
    size = lib.listxattr(encoded, None, 0, 1)
    if size < 0:
        checked(-1, path)
    if size > 16 * 1024 * 1024:
        raise ValueError("Unexpectedly large xattr names")
    buffer = ctypes.create_string_buffer(size)
    count = lib.listxattr(encoded, buffer, size, 1)
    if count != size:
        raise ValueError("Source xattr names changed")
    result = {}
    for name in buffer.raw.rstrip(b"\0").split(b"\0") if size else []:
        size = lib.getxattr(encoded, name, None, 0, 0, 1)
        if size < 0:
            checked(-1, path)
        if size > 16 * 1024 * 1024:
            raise ValueError("Unexpectedly large xattr value")
        buffer = ctypes.create_string_buffer(size)
        if lib.getxattr(encoded, name, buffer, size, 0, 1) != size:
            raise ValueError("Source xattr value changed")
        result[os.fsdecode(name)] = buffer.raw
    return result


def identity(info):
    # Reads may alter atime; ctime plus inode catches restored size/mtime mutations.
    return (
        info.st_dev,
        info.st_ino,
        info.st_mode,
        info.st_uid,
        info.st_gid,
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
        info.st_flags,
        info.st_nlink,
    )


def entry(lib, path):
    before = path.lstat()
    kind = stat.S_IFMT(before.st_mode)
    if kind not in (stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK):
        raise ValueError(f"Unsupported special file: {path}")
    # Never create shared inodes. Ambiguous source hardlink ownership is rejected too.
    if kind != stat.S_IFDIR and before.st_nlink != 1:
        raise ValueError(f"Source must not be hardlinked: {path}")
    value = {
        "identity": identity(before),
        "kind": kind,
        "mode": stat.S_IMODE(before.st_mode),
        "uid": before.st_uid,
        "gid": before.st_gid,
        "flags": before.st_flags,
        "mtime_ns": before.st_mtime_ns,
        "xattrs": xattrs(lib, path),
        "acl": acl_text(lib, path),
    }
    if kind == stat.S_IFREG:
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as stream:
            if identity(os.fstat(stream.fileno())) != identity(before):
                raise ValueError(f"Source changed before reading: {path}")
            value["sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
            value["bytes"] = before.st_size
            if identity(os.fstat(stream.fileno())) != identity(before):
                raise ValueError(f"Source changed while reading: {path}")
    elif kind == stat.S_IFLNK:
        value["target"] = os.readlink(path)
    if identity(path.lstat()) != identity(before):
        raise ValueError(f"Source changed while checking: {path}")
    return value


def snapshot(lib, source, allow_symlinks):
    result = {}

    def visit(path):
        if path != source and not path.parent.resolve(strict=True).is_relative_to(source):
            raise ValueError("Resource ancestor escapes source")
        value = entry(lib, path)
        if value["identity"][0] != source.lstat().st_dev:
            raise ValueError("Cross-volume resource trees are unsupported")
        if value["kind"] == stat.S_IFLNK:
            target = value["target"]
            if not allow_symlinks or os.path.isabs(target):
                raise ValueError(f"Resource symlink violates contract: {path}")
            try:
                resolved = path.resolve(strict=True)
            except (OSError, RuntimeError) as error:
                raise ValueError(f"Resource symlink is dangling or cyclic: {path}") from error
            if not resolved.is_relative_to(source):
                raise ValueError(f"Resource symlink escapes source: {path}")
        result[str(path.relative_to(source))] = value
        if value["kind"] == stat.S_IFDIR:
            for child in sorted(path.iterdir()):
                visit(child)

    visit(source)
    return result


def copy_metadata(lib, source, destination):
    checked(
        lib.copyfile(os.fsencode(source), os.fsencode(destination), None, METADATA | NOFOLLOW),
        destination,
    )


def strict_file(lib, source, destination):
    state = lib.copyfile_state_alloc()
    if not state:
        raise MemoryError("Cannot allocate strict APFS clone state")
    try:
        checked(
            lib.copyfile(
                os.fsencode(source), os.fsencode(destination), state, CLONE_FORCE | ACL | NOFOLLOW
            ),
            destination,
        )
        cloned = ctypes.c_bool()
        checked(lib.copyfile_state_get(state, WAS_CLONED, ctypes.byref(cloned)), destination)
        if not cloned.value:
            raise ValueError("Kernel did not attest an APFS clone; no copying fallback")
    finally:
        lib.copyfile_state_free(state)


def clone(
    source,
    destination,
    *,
    expected_sha256=None,
    expected_bytes=None,
    expected_files=None,
    allow_symlinks=True,
):
    """Clone a file/tree into a fresh name, checking both bytes and source metadata.

    App copies preserve ACLs, xattrs and writable modes. Their caller may then
    clear/sign the copy. This deliberately does not use model_objects' read-only,
    xattr-free immutable-object publication policy or its hardlink publication.
    """
    lib = library()
    source, destination = Path(source).absolute(), Path(destination).absolute()
    if source.is_symlink():
        raise ValueError("Clone root must not be a symlink")
    source = source.resolve(strict=True)
    parent = destination.parent.resolve(strict=True)
    destination = parent / destination.name
    if destination.exists() or destination.is_symlink() or destination.is_relative_to(source):
        raise ValueError("Clone destination must be new and outside the source")
    if filesystem(lib, source) != "apfs" or filesystem(lib, parent) != "apfs":
        raise ValueError("Evaluation copies require exact APFS; no copying fallback")
    if source.stat().st_dev != parent.stat().st_dev:
        raise ValueError("APFS clones require source and destination on the same volume")
    original = snapshot(lib, source, allow_symlinks)
    top = original["."]
    if expected_sha256 is not None and top.get("sha256") != expected_sha256:
        raise ValueError("Clone source differs from the pinned artifact hash")
    if expected_bytes is not None and top.get("bytes") != expected_bytes:
        raise ValueError("Clone source differs from the pinned artifact size")
    for name, digest in (expected_files or {}).items():
        if original.get(name, {}).get("sha256") != digest:
            raise ValueError(f"Clone source differs from the pinned resource: {name}")
    directories = []
    for name, value in original.items():
        src, dst = source / name, destination / name
        if src != source and not src.parent.resolve(strict=True).is_relative_to(source):
            raise ValueError("Source ancestor changed before cloning")
        if identity(src.lstat()) != value["identity"]:
            raise ValueError(f"Source changed before cloning: {src}")
        if value["kind"] == stat.S_IFDIR:
            dst.mkdir(mode=0o700)  # Exclusive; no overwrite or adoption of another tree.
            directories.append((src, dst))
        elif value["kind"] == stat.S_IFLNK:
            os.symlink(value["target"], dst)
            copy_metadata(lib, src, dst)
        else:
            strict_file(lib, src, dst)
    for src, dst in reversed(directories):
        copy_metadata(lib, src, dst)
    if snapshot(lib, source, allow_symlinks) != original:
        raise ValueError("Source changed during clone; destination is unqualified")
    copied = snapshot(lib, destination, allow_symlinks)
    if copied.keys() != original.keys():
        raise ValueError("Cloned resource inventory differs")
    for name, value in original.items():
        actual = copied[name]
        if actual["identity"][:2] == value["identity"][:2]:
            raise ValueError("Clone unexpectedly shares its source inode")
        # Directory allocation size/ctime/inode are necessarily different.
        if {k: v for k, v in actual.items() if k != "identity"} != {
            k: v for k, v in value.items() if k != "identity"
        }:
            raise ValueError(f"Clone metadata or bytes differ: {name}")
    return {
        "method": "darwin-copyfile-clone-force",
        "files": sum(v["kind"] == stat.S_IFREG for v in original.values()),
    }


if __name__ == "__main__":
    import argparse
    import json

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    print(json.dumps(clone(args.source, args.destination), sort_keys=True))
