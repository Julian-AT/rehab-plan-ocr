# /// script
# requires-python = ">=3.11"
# dependencies = ["icalendar==6.3.2"]
# ///
"""Independent RFC parser check, exclusively using an invented reviewed fixture."""

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

from icalendar import Calendar

ROOT = Path(__file__).resolve().parents[1]
binary = ROOT / "target/release/reha"
with tempfile.TemporaryDirectory() as temporary:
    folder = Path(temporary)
    run = json.loads((ROOT / "tests/fixtures/sample-run.json").read_text())
    draft = folder / "draft.json"
    draft.write_text(json.dumps(run))
    blocked = subprocess.run(
        [str(binary), "ics", str(draft), str(folder / "blocked.ics")],
        capture_output=True,
        check=False,
    )
    assert blocked.returncode != 0 and not (folder / "blocked.ics").exists(), (
        "Unreviewed export must fail."
    )
    # Explicit synthetic approval: exclude the deliberately incomplete water appointment.
    run["appointments"][5]["included"] = False
    run["appointments"][0]["title"] = "Frühstück, Brot; Äpfel \\ " + (
        "Überprüfung " * 15
    )
    run["appointments"][0]["notes"] = "Zeile eins\nZweite Zeile; Komma, Backslash \\"
    run["appointments"][0]["therapist"] = "Alex Beispiel MSc"
    # Explicit confirmations use the current contract. Legacy approval must no
    # longer be silently upgraded into source-checked room/therapist evidence.
    run["schema_version"] = 3
    run["document"]["schema_version"] = 3
    metadata_fields = [
        "clinic",
        "department",
        "address",
        "contact",
        "treatment_code",
        "preparation",
        "document_reference",
        "appointment_notes",
    ]
    fields = [
        "date",
        "start",
        "end",
        "end_date",
        "duration_minutes",
        "title",
        "location",
        "therapist",
        "notes",
    ]
    for a in run["appointments"]:
        a.setdefault("therapist", "")
        a["metadata"] = {f: a.get("metadata", {}).get(f, "") for f in metadata_fields}
        values = {
            **{f: a.get(f) for f in fields},
            **a["metadata"],
            "included": a["included"],
        }
        a["fields"] = {
            f: {
                "state": "legible" if a[f] else "not_printed",
                "frame": "page",
                "polygon": [],
                "reasons": [],
                "confirmed_at": 1,
                "confirmed_value": a[f],
            }
            for f in ["location", "therapist"]
        }
        a["approval"] = (
            {
                "approved_at": 1,
                "values_hash": hashlib.sha256(
                    json.dumps(
                        values,
                        sort_keys=True,
                        ensure_ascii=False,
                        separators=(",", ":"),
                    ).encode()
                ).hexdigest(),
            }
            if a["included"]
            else None
        )
    run["review_confirmed"] = True
    approved = folder / "approved.json"
    approved.write_text(json.dumps(run))
    output = folder / "approved.ics"
    subprocess.run(
        [str(binary), "ics", str(approved), str(output)],
        check=True,
        capture_output=True,
    )
    content = output.read_bytes()
    assert all(len(line) <= 75 for line in content.split(b"\r\n"))
    assert b"\n" not in content.replace(b"\r\n", b"")
    calendar = Calendar.from_ical(content)
    events = calendar.walk("VEVENT")
    assert len(events) == 7 and len({str(e["UID"]) for e in events}) == 7
    assert sum(str(e["SUMMARY"]) == "Entspannung" for e in events) == 2
    assert str(events[0]["SUMMARY"]) == run["appointments"][0]["title"].strip()
    assert (
        str(events[0]["DESCRIPTION"])
        == "Raum: Speisesaal\nTherapeut: Alex Beispiel MSc\nHinweise: Zeile eins\n  Zweite Zeile; Komma, Backslash \\"
    )
    assert events[0].decoded("DTSTART").isoformat() == "2026-09-10T05:30:00+00:00"
    assert events[0].decoded("DTEND").isoformat() == "2026-09-10T06:00:00+00:00"
    subprocess.run(
        [str(binary), "ics", str(approved), str(output)],
        check=True,
        capture_output=True,
    )
    again = Calendar.from_ical(output.read_bytes()).walk("VEVENT")
    assert [str(e["UID"]) for e in events] == [str(e["UID"]) for e in again]
    print(
        "PASS: review gate, seven events, repeat multiplicity, stable UIDs, UTC instants, UTF-8 folding and escaped text."
    )
