"""Resolve canonical tool/build storage and preserve explicitly mapped legacy consumers."""

import argparse
import importlib.util
import json
import os
import shlex
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = "config/storage/workspace.json"


def mappings(root=ROOT):
    value = json.loads((root / POLICY).read_text())
    if value.get("version") != 1 or set(value["paths"]) != {"tools", "python", "cargo", "ios"}:
        raise ValueError("Unexpected workspace path policy")
    result = value["paths"]
    for item in result.values():
        for key in ["canonical", "legacy"]:
            relative = Path(item[key])
            if relative.is_absolute() or ".." in relative.parts or str(relative) in {"", "."}:
                raise ValueError("Workspace paths must stay inside the checkout")
        if not item["canonical"].startswith(".local/"):
            raise ValueError("Canonical working storage must be below .local")
    return result


def location(name, root=ROOT):
    """Existing checkouts remain usable until their explicit, verified migration."""
    mapping = mappings(root)[name]
    canonical, legacy = (root / mapping[key] for key in ["canonical", "legacy"])
    if canonical.is_symlink():
        raise ValueError(f"Canonical storage must not be a symlink: {canonical}")
    for path in [canonical, legacy]:
        if not path.parent.resolve().is_relative_to(root.resolve()):
            raise ValueError("Workspace storage ancestor escapes the checkout")
        if path.exists() and not path.is_dir():
            raise ValueError(f"Workspace storage is not a directory: {path}")
    if legacy.is_symlink():
        if legacy.resolve() != canonical.resolve() or not canonical.is_dir():
            raise ValueError(f"Compatibility link has an unexpected destination: {legacy}")
        return canonical
    if legacy.exists():
        if canonical.exists():
            raise ValueError(
                f"Both old and canonical storage exist; preserve and reconcile: {name}"
            )
        return legacy
    return canonical


def cargo_directory(root=ROOT, env=None):
    """Cargo's environment override must be shared by every binary consumer."""
    value = (os.environ if env is None else env).get("CARGO_TARGET_DIR")
    if not value:
        return location("cargo", root)
    path = Path(value).expanduser()
    return path if path.is_absolute() else root / path


def environment(root=ROOT, source=None):
    env = dict(os.environ if source is None else source)
    env["PATH"] = os.pathsep.join(
        [str(location("tools", root) / "bin"), str(Path.home() / ".cargo/bin"), env.get("PATH", "")]
    )
    versions = json.loads((root / "config/toolchains/versions.json").read_text())["versions"]
    env["RUSTUP_TOOLCHAIN"] = versions["rust"]
    env["CARGO_TARGET_DIR"] = str(cargo_directory(root, env))
    env.setdefault("UV_PROJECT_ENVIRONMENT", str(location("python", root)))
    env["REHA_IOS_BUILD_DIR"] = str(location("ios", root))
    return env


def prepare(root=ROOT):
    """New checkouts use .local; existing bytes are moved only by explicit migration."""
    for name, mapping in mappings(root).items():
        path = location(name, root)
        if path == root / mapping["canonical"]:
            path.mkdir(parents=True, exist_ok=True)
            legacy = root / mapping["legacy"]
            legacy.parent.mkdir(parents=True, exist_ok=True)
            if not legacy.is_symlink():
                legacy.symlink_to(os.path.relpath(path, legacy.parent), target_is_directory=True)


def migrate(action, manifest, root=ROOT):
    """Reuse the hashed, resumable private mover without modifying its historical contract."""
    import artifacts

    spec = importlib.util.spec_from_file_location(
        "private_migration", Path(__file__).with_name("migrate-private.py")
    )
    mover = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mover)
    mover.MOVES = {entry["legacy"]: entry["canonical"] for entry in mappings(root).values()}
    manifest = manifest.absolute()
    if not manifest.is_relative_to(root / ".local/migrations"):
        raise ValueError("Migration evidence must stay in .local/migrations")
    artifacts.local_path(root, str(manifest.relative_to(root)))
    with artifacts.locked(root):
        # guard() considers symbolic consumers live references. Before migration,
        # these still need the compatibility paths that the mover preserves.
        artifacts.guard(root, list(mover.MOVES))
        (mover.plan if action == "plan" else mover.apply)(root, manifest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action", choices=["path", "shell", "check", "prepare", "plan", "apply", "toolchain"]
    )
    parser.add_argument("name", nargs="?", choices=["tools", "python", "cargo", "ios"])
    parser.add_argument("--canonical", action="store_true")
    parser.add_argument("--manifest", type=Path, default=ROOT / ".local/migrations/workspace.json")
    args = parser.parse_args()
    if args.action == "path":
        if not args.name:
            parser.error("path requires a storage name")
        print(cargo_directory() if args.name == "cargo" else location(args.name))
    elif args.action == "toolchain":
        print(
            json.loads((ROOT / "config/toolchains/versions.json").read_text())["versions"]["rust"]
        )
    elif args.action == "shell":
        env = environment()
        for key in [
            "PATH",
            "RUSTUP_TOOLCHAIN",
            "CARGO_TARGET_DIR",
            "UV_PROJECT_ENVIRONMENT",
            "REHA_IOS_BUILD_DIR",
        ]:
            print(f"export {key}={shlex.quote(env[key])}")
    elif args.action == "prepare":
        prepare()
    elif args.action in {"plan", "apply"}:
        migrate(args.action, args.manifest)
    else:
        result = {}
        for name, mapping in mappings().items():
            actual = location(name)
            canonical = actual == ROOT / mapping["canonical"]
            if args.canonical and not (
                canonical and actual.is_dir() and (ROOT / mapping["legacy"]).is_symlink()
            ):
                raise ValueError(f"Storage still needs verified migration: {name}")
            result[name] = {"path": str(actual.relative_to(ROOT)), "canonical": canonical}
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
