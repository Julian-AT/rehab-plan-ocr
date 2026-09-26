#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
python3 - "$probe" << 'PY'
import sys
import zlib
from pathlib import Path

root = Path(sys.argv[1])
for name, count in [("boundary", 50_000), ("oversized", 100_000)]:
    stream = zlib.compress(b"BT /F1 0.001 Tf 10 400 Td (" + b"A" * count + b") Tj ET")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(stream)).encode() + b" /Filter /FlateDecode >>\nstream\n"
        + stream + b"\nendstream",
    ]
    output = bytearray(b"%PDF-1.4\n")
    offsets = []
    for index, value in enumerate(objects, 1):
        offsets.append(len(output))
        output.extend(f"{index} 0 obj\n".encode() + value + b"\nendobj\n")
    xref = len(output)
    output.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode())
    for offset in offsets:
        output.extend(f"{offset:010} 00000 n \n".encode())
    output.extend(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    )
    (root / f"{name}.pdf").write_bytes(output)
PY
swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path "$probe/modules" \
  packages/apple/AppleServices/Sources/AppleServices/PDFTextEvidence.swift \
  apps/ios/Tests/PDFTextEvidenceProbe.swift -o "$probe/pdf-evidence"
"$probe/pdf-evidence" "$probe"
