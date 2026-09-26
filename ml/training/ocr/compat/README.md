# Preserved synthetic training contracts

`synthetic_data_v1.py` and the v2 synthetic generator preserve selected development
dataset receipts exactly. `training_v1/{train,contract,prepare}.py` are byte-identical
snapshots of the original training contract. They are referenced by the original
run identities and are verified against fixed SHA-256 values in `run_identity.py`.
Do not format or edit those snapshots.

Current evaluation, export and registration distinguish historical provenance
from current validation. An original synthetic run may retain its original
identity only when the dataset, settings, environment, registry, package versions,
Python and platform still match. Its historical source hashes must match the
verified archives, including the old reference exporter kept by annotation tools.
That exporter is provenance only; it is never selected for a new real-data export.
Real reference runs have no legacy exception.

On resume, the original `train.py` numerical training implementation and original
contract helpers are actually loaded from these files. The entry point explicitly
replaces lineage verification, dataset validation, live reference review and
completed-checkpoint verification with current guards. Resume checks both the
latest checkpoint and its earlier best checkpoint, including the required baseline
binding and directory/receipt/state epochs. Missing evidence is not a legacy
exception. The local `restore.py` bridge calls the current offline upstream
verifier. A separate, content-addressed `run/compatibility/*.json` receipt records
the original identity and actual current guard hashes. The optimizer/checkpoint
format, original identity, model card and recovery journals stay unchanged.

Use the normal `make resume-ocr` entry point. These snapshots are not standalone
commands and must not be used to bypass current validation. Replaying provenance
or resuming an experiment never grants a dataset approval or model promotion.

Other source revisions have no compatibility exception: replay them only with
their recorded sources and environment, or start a new run. The current export
and registration gates also require a complete, internally consistent selection.
