"""Verify historical training provenance separately from current validation code.

Only the frozen, invented-data training contract has a compatibility route. Its
optimizer/training implementation is executed from the archived source on resume;
current dataset validation still runs before it. Real references never use it.
"""

import importlib.util
import json
from pathlib import Path

from contract import digest, sha, write
from preflight import ROOT

ARCHIVE = Path(__file__).with_name("compat") / "training_v1"
LEGACY_SOURCES = {
    "train.py": "3616fded43de7e8dfe2a034ae262580270cad820dbed1851f61c98050ebb25c5",
    "contract.py": "bb834e4505a70763ef56ceab6c073c0025228d67b98c0245a9bdc58556141b66",
    "prepare.py": "7af15ebe75bc1ff8bdaedb5e82638e5d894054df78319e3f6469d6f5136d7a33",
}
LEGACY_REFERENCE = "f2da2e24b99dd7c440a4865b89608327ec2a61ef748d4f12b39c8f00b545326d"
LEGACY_FACTS = {
    "dataset_sha256",
    "registry_sha256",
    "environment_sha256",
    "packages",
    "python",
    "platform",
}


def archived_sources():
    paths = {name: ARCHIVE / name for name in LEGACY_SOURCES}
    paths["reference-data.py"] = ROOT / "ml/data/annotation/compat/reference-data-v2.py.source"
    expected = {**LEGACY_SOURCES, "reference-data.py": LEGACY_REFERENCE}
    for name, path in paths.items():
        if path.is_symlink() or sha(path) != expected[name]:
            raise ValueError("Archived OCR training source changed")
    return {
        name: {"path": str(path.relative_to(ROOT)), "sha256": sha(path)}
        for name, path in paths.items()
    }


def verify(run):
    """Read-only proof; never substitute an archive hash for a current file hash."""
    from train import lineage

    run = Path(run)
    identity = json.loads((run / "identity.json").read_text())
    config = json.loads((run / "settings.json").read_text())
    path = Path(config["dataset"])
    actual = {"settings_sha256": sha(run / "settings.json"), "lineage": lineage(path)}
    mode, archived = "current", None
    if identity != actual:
        recorded = identity.get("lineage", {})
        dataset = json.loads(path.read_text())
        if (
            set(identity) != {"settings_sha256", "lineage"}
            or identity.get("settings_sha256") != actual["settings_sha256"]
            or set(recorded) != LEGACY_FACTS | {"source_sha256", "reference_tool_sha256"}
            or recorded.get("source_sha256") != LEGACY_SOURCES
            or recorded.get("reference_tool_sha256") != LEGACY_REFERENCE
            or any(recorded.get(key) != actual["lineage"][key] for key in LEGACY_FACTS)
            or dataset.get("kind") not in {"pixel-verified-synthetic-crops", "invented-smoke-text"}
            or dataset.get("final_holdout") is not False
        ):
            raise ValueError("Run lineage changed; preserve the recorded candidate")
        archived = archived_sources()
        mode = "archived-synthetic-v1"
    current = {
        str(p.relative_to(ROOT)): sha(p)
        for p in [
            Path(__file__),
            Path(__file__).with_name("train.py"),
            Path(__file__).with_name("contract.py"),
            Path(__file__).with_name("prepare.py"),
            Path(__file__).with_name("synthetic_data.py"),
            ROOT / "ml/data/annotation/reference-data.py",
            ROOT / "ml/data/annotation/privacy.py",
        ]
    }
    return {
        "schema_version": 1,
        "mode": mode,
        "run_identity_sha256": sha(run / "identity.json"),
        "dataset_sha256": sha(path),
        "archived_training_sources": archived,
        "current_validation_sources": current,
    }


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_inputs(run):
    """Common current gate for export, registration and every prepared-run diagnosis."""
    from contract import validate_dataset
    from train import DICTIONARY, current_review

    proof = verify(run)
    path = Path(json.loads((run / "settings.json").read_text())["dataset"])
    dataset = validate_dataset(path, DICTIONARY.read_text().splitlines())
    current_review(dataset, path)
    if verify(run) != proof:
        raise ValueError("Run inputs changed during validation")
    return dataset, proof


def legacy_engine(run):
    """Load the actual original training kernel, with explicit current input checks."""
    import contract
    import train

    proof = verify(run)
    if proof["mode"] != "archived-synthetic-v1":
        raise ValueError("An original synthetic training identity is required")
    engine = _load("ocr_training_v1", ARCHIVE / "train.py")
    old_contract = _load("ocr_contract_v1", ARCHIVE / "contract.py")
    for name in ["CRITICAL", "advance", "field_name", "sha", "write"]:
        setattr(engine, name, getattr(old_contract, name))
    engine.validate_dataset = contract.validate_dataset
    dataset = Path(json.loads((run / "settings.json").read_text())["dataset"])

    def original_lineage(path):
        if path != dataset or verify(run) != proof:
            raise ValueError("Compatibility inputs changed before training")
        return json.loads((run / "identity.json").read_text())["lineage"]

    engine.lineage = original_lineage

    def guarded_review(data, path):
        train.current_review(data, path)
        original_lineage(path)

    engine.current_review = guarded_review
    return engine, proof


def resume_legacy(run, pause_after_epoch=None):
    engine, proof = legacy_engine(run)
    # A new, content-addressed receipt records this execution's validators without
    # rewriting original identities, model cards, or checkpoint recovery journals.
    proof = proof | {
        "resume_adapter": {
            "source_sha256": sha(Path(__file__)),
            "restore_bridge_sha256": sha(ARCHIVE / "restore.py"),
            "overrides": ["lineage verification", "dataset validation", "live reference review"],
        }
    }
    target = run / "compatibility" / (digest(proof) + ".json")
    target.parent.mkdir(exist_ok=True)
    if target.exists():
        if json.loads(target.read_text()) != proof:
            raise ValueError("Compatibility receipt changed")
    else:
        write(target, proof)
    engine.execute(run, pause_after_epoch)
