"""Create an offline, private visual review of difficult-region comparisons."""

import argparse
import html
import json
from pathlib import Path


def report(comparisons, baseline):
    cards = []
    for path in sorted(comparisons.glob("document-*/comparison.json")):
        data = json.loads(path.read_text())
        run = json.loads((baseline / path.parent.name / "run.json").read_text())
        target = set(data["source"]["target_ids"])
        values = [
            {
                k: a.get(k)
                for k in [
                    "date",
                    "start",
                    "end",
                    "duration_minutes",
                    "title",
                    "location",
                    "therapist",
                    "metadata",
                ]
            }
            for a in run["appointments"]
            if a["id"] in target
        ]
        readings = [
            "<article><h3>Portable draft</h3><pre>"
            + html.escape(json.dumps(values, ensure_ascii=False, indent=2))
            + "</pre></article>"
        ]
        for reader in data["readers"]:
            readings.append(
                "<article><h3>"
                + html.escape(reader["candidate"])
                + "</h3><p>"
                + html.escape(str(reader["status"]))
                + " · "
                + html.escape(str(reader.get("total_ms", "—")))
                + " ms · "
                + html.escape(str(reader.get("peak_rss_bytes", "—")))
                + " bytes RSS</p><pre>"
                + html.escape(reader.get("text", reader.get("reason", "")))
                + "</pre></article>"
            )
        name = html.escape(path.parent.name)
        cards.append(
            f'<section><h2>{name}</h2><p>Unverified source-linked readings. No values approved or applied.</p><a href="{name}/crop.png"><img src="{name}/crop.png" alt="Original-resolution source region for {name}" loading="lazy"></a><div class="readings">'
            + "".join(readings)
            + f'</div><p><a href="{name}/comparison.json">Hashes, transforms and full measurement record</a></p></section>'
        )
    document = """<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>Private region comparison</title><style>body{font:16px system-ui;margin:24px;color:#18181b;background:#fff;max-width:1600px}section{border-top:1px solid #ddd;margin-top:32px;padding-top:12px}img{max-width:100%;height:auto}.readings{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:14px ui-monospace,monospace}article{min-width:0}@media(max-width:900px){.readings{grid-template-columns:1fr}}</style><h1>Private difficult-region comparison</h1><p>These are previously explored development photographs. References and grouping remain unverified; there is no independent final holdout and no accuracy score. One target region per image is compared. Model output is a reading, never an approval or clinical advice.</p>"""
    (comparisons / "review.html").write_text(document + "".join(cards) + "</html>\n")
    return len(cards)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("comparisons", type=Path)
    parser.add_argument("baseline", type=Path)
    args = parser.parse_args()
    print(json.dumps({"images": report(args.comparisons, args.baseline), "accuracy": None}))
