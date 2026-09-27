# Human reference review packet

Create a private, self-contained review packet with:

```sh
make reference-review-packet DATASET=<private-root> RUN=.local/runs/review-NEW
```

Open its `index.html` locally. Assets stay inside the packet and its content
security policy blocks network requests. Review four distinct areas: page/day
coverage; every printed field and provisional row; text polygons against original
pixels; and privacy masks plus actual purpose/consent evidence. Empty masks do not
prove privacy review. Crop previews are not approved training crops.

Downloaded working notes use `human-reference-review-notes` with
`grants_approval: false`. They can be reloaded only against matching source,
reference and snapshot hashes. Keep them privately and confirm successful saving
before closing the page. Missing or changed inputs invalidate the packet.

Notes do not grant approval or import references. After human inspection, apply
reviewed changes through the [reference CLI](reference-cli.md), keeping field,
coverage, geometry, relationship and privacy approvals separate. A packet without
its final manifest is incomplete. Only synthetic fixtures belong in CI or public
screenshots. Follow the [dataset](dataset.md) and
[collection](../product/research/collection-guide.md) contracts.
