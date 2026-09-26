"""Expand known German development failures; never create a human approval or holdout."""

import argparse
import copy
import datetime as dt
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.training.assistant.contract import sha, validate_dataset, write  # noqa: E402

VERSION = 2
TITLES = [
    "Wassergymnastik",
    "Entspannung",
    "Gehtraining",
    "Rückenschule",
    "Einzeltherapie",
    "Bewegungsbad",
    "Koordination",
    "Ruhepause",
]


def additional_examples(index, seed):
    """Each family varies values, not its claimed number of independent dialogues."""
    today = dt.date(2028, 1, 1) + dt.timedelta(days=(seed + index * 53) % 1461)
    tomorrow = today + dt.timedelta(days=1)
    later = today + dt.timedelta(days=2)
    title = TITLES[index % len(TITLES)]
    hour, minute = 7 + index % 10, [0, 15, 30, 45][index % 4]
    clock = f"{hour:02}:{minute:02}"
    duration = [10, 15, 25, 35, 40, 50, 60, 90][index % 8]
    reference = f"entwicklung-{index + 1}"
    context = {
        "today": today.isoformat(),
        "timezone": "Europe/Vienna",
        "visible_references": [reference],
        "selected": reference,
    }

    def query(detail, **scope):
        return {"action": "calendar", "query": {"detail": detail, **scope}}

    def change(**fields):
        return {"action": "update", "query": {"reference": reference}, "change": fields}

    def create(date):
        return {"action": "create", "change": {"title": title, "date": date, "time": clock}}

    cases = [
        (
            "room-short",
            ["Welcher Raum gehört dazu?", "Wo ist der ausgewählte Termin?"],
            query("room", reference=reference),
        ),
        (
            "room-no-change",
            [
                "Nichts ändern, ich möchte nur den Raum wissen.",
                "Bitte nur sagen, in welchem Raum dieser Termin ist.",
            ],
            query("room", reference=reference),
        ),
        (
            "next-short",
            ["Welcher Termin folgt darauf?", "Was steht anschließend an?"],
            query("next", reference=reference),
        ),
        (
            "list-corrected-day",
            [
                "Welche Termine sind morgen? Ich meine übermorgen.",
                "Zeige die Termine übermorgen, nicht morgen.",
            ],
            query("list", date=later.isoformat()),
        ),
        (
            "next-after-time",
            [
                f"Welcher Termin ist morgen der nächste nach {clock} Uhr?",
                f"Nächster Termin morgen, aber erst nach {clock} Uhr.",
            ],
            query("next", date=tomorrow.isoformat(), after=clock),
        ),
        (
            "list-before-time",
            [f"Zeige morgen nur Termine vor {clock} Uhr.", f"Was steht morgen vor {clock} Uhr an?"],
            query("list", date=tomorrow.isoformat(), before=clock),
        ),
        (
            "bounded-window",
            [
                f"Welche Termine sind heute nach {clock} Uhr und vor 18 Uhr?",
                f"Zeige heute Termine vor 18 Uhr, aber nach {clock} Uhr.",
            ],
            query("list", date=today.isoformat(), after=clock, before="18:00"),
        ),
        (
            "create-dotted-date",
            [
                f"Am {later:%d.%m.%Y} um {clock} Uhr bitte {title} eintragen.",
                f"Trage {title} für den {later:%d.%m.%Y}, {clock} Uhr, ein.",
            ],
            create(later.isoformat()),
        ),
        (
            "create-iso-date",
            [
                f"Erstelle {title} am {later.isoformat()} um {clock} Uhr.",
                f"Neuer Termin: {title}, {later.isoformat()}, {clock} Uhr.",
            ],
            create(later.isoformat()),
        ),
        (
            "create-relative-minimal",
            [
                f"Lege für morgen um {clock} Uhr {title} an.",
                f"Bitte morgen {title} um {clock} Uhr vormerken.",
            ],
            create(tomorrow.isoformat()),
        ),
        (
            "rename-not-remove",
            [
                f"Behalte diesen Termin. Er soll jetzt {title} heißen.",
                f"Lösche ihn nicht, benenne diesen Termin in {title} um.",
            ],
            change(title=title),
        ),
        (
            "duration-not-remove",
            [
                f"Den Termin behalten, nur die Dauer auf {duration} Minuten ändern.",
                f"Nicht absagen. Dieser Termin soll {duration} Minuten dauern.",
            ],
            change(duration=duration),
        ),
        (
            "duration-pauses",
            [
                f"Für diesen Termin, äh, bitte {duration} Minuten als Dauer.",
                f"Ändere die Dauer dieses Termins ... auf {duration} Minuten.",
            ],
            change(duration=duration),
        ),
        (
            "time-only-explicit",
            [
                f"Nur die Uhrzeit dieses Termins auf {clock} Uhr setzen.",
                f"Alles andere bleibt: diesen Termin um {clock} Uhr beginnen lassen.",
            ],
            change(time=clock),
        ),
        (
            "date-only-explicit",
            [
                "Nur das Datum dieses Termins ändern: übermorgen.",
                "Uhrzeit und Dauer behalten, den Termin auf übermorgen legen.",
            ],
            change(date=later.isoformat()),
        ),
        (
            "cancel-keep-values",
            [
                "Keine Änderung mehr. Bitte den Vorschlag verwerfen.",
                "Halt, ich breche ab. Den Termin so lassen.",
            ],
            {"action": "cancel"},
        ),
        (
            "invalid-short-month",
            [
                f"Trage {title} am 31. Juni {today.year} um {clock} Uhr ein.",
                f"Erstelle {title} für 31. November {today.year}, {clock} Uhr.",
            ],
            {"action": "clarify", "problem": "invalid_date"},
        ),
        (
            "invalid-iso-date",
            [
                f"Lege {title} am {today.year}-02-30 um {clock} Uhr an.",
                f"Erstelle {title} am {today.year}-06-31 um {clock} Uhr.",
            ],
            {"action": "clarify", "problem": "invalid_date"},
        ),
        (
            "missing-new-time",
            [
                f"Erstelle für übermorgen den Termin {title}.",
                f"Am {later:%d.%m.%Y} bitte {title} eintragen.",
            ],
            {"action": "clarify", "problem": "missing_time"},
        ),
        (
            "help-not-remove",
            [
                "Wo erklärt die App, wie ich gespeicherte Daten entferne?",
                "Wie kann ich meine Daten in den Einstellungen löschen?",
            ],
            {"action": "help", "topic": "privacy"},
        ),
    ]
    return [
        {
            "id": f"v2-{family}-{index:04d}",
            "family": f"v2-{family}",
            "partition": "train",
            "scenario_group": f"v2-{family}",
            "paraphrase_group": f"v2-{family}",
            # Same invented writer, not invented independent human speakers.
            "speaker_group": "invented-text-train",
            "provenance": "agent-authored-invented-development",
            "human_review": "pending",
            "context": dict(context),
            "utterance": texts[index % len(texts)],
            "expected": expected,
        }
        for family, texts, expected in cases
    ]


def prepare(source, output, per_family=8, seed=20260921):
    if not 2 <= per_family <= 1000:
        raise ValueError("Use 2–1000 examples per added training family")
    previous = validate_dataset(source)
    if previous["kind"] != "invented-development-dialogues":
        raise ValueError("This development expansion does not mix participant or reviewed data")
    if previous.get("generator_version", 1) != 1:
        raise ValueError("Expand a version-one dataset once; do not duplicate a prior expansion")
    data = copy.deepcopy(previous)
    data.update(
        generator_version=VERSION,
        generator_sha256=sha(Path(__file__)),
        contract_sha256=sha(Path(__file__).with_name("contract.py")),
        source_dataset_sha256=sha(source),
        additional_seed=seed,
        validation_use="previously-examined-development-only",
        independent_real_dialogues=0,
        human_review="pending",
        qualified=False,
    )
    data["samples"] += [
        row for index in range(per_family) for row in additional_examples(index, seed)
    ]
    output.mkdir(parents=True, exist_ok=False)
    write(output / "dataset.json", data)
    validate_dataset(output / "dataset.json")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--per-family", type=int, default=8)
    args = parser.parse_args()
    source, output = args.source.resolve(strict=True), args.output.resolve()
    if not source.is_relative_to(ROOT / ".local") or not output.is_relative_to(ROOT / ".local"):
        parser.error("Source and generated datasets belong in private .local storage")
    data = prepare(source, output, args.per_family)
    counts = {p: sum(r["partition"] == p for r in data["samples"]) for p in ["train", "validation"]}
    print(
        f"Prepared {counts}; existing validation is reused development data, human review pending."
    )


if __name__ == "__main__":
    main()
