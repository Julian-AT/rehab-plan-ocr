# Local reference review

The Rust CLI manages a private directory with `inventory.json`, `raw/` and
`labels/provisional/`. A saved draft is not an approved reference. From the root:

```sh
cargo run --locked -p reha-cli -- lab list <dataset>
cargo run --locked -p reha-cli -- lab get <dataset> <source-sha256>
cargo run --locked -p reha-cli -- lab image <dataset> <source-sha256> <original.png>
cargo run --locked -p reha-cli -- lab save <dataset> <edited-reference.json>
cargo run --locked -p reha-cli -- lab confirm-row <dataset> <source-sha256> <row-id>
cargo run --locked -p reha-cli -- lab confirm-coverage <dataset> <source-sha256>
cargo run --locked -p reha-cli -- lab approve <dataset> <source-sha256>
```

Confirm rows only after inspecting original pixels. Changed values, image lineage,
coverage or geometry invalidate the relevant approval. Field accuracy, complete
row coverage, crop geometry, source relationships and privacy are separate review
obligations. Do not infer consent or fabricate approval. See the
[dataset contract](dataset.md) and [human review packet](reference-review-packet.md).
