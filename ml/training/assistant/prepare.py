"""Prepare reproducible invented German intent families, pending human review."""

import argparse
import datetime as dt
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.training.assistant.contract import sha, validate_dataset, write  # noqa: E402


def examples(index, seed):
    today = dt.date(2028, 1, 1) + dt.timedelta(days=(seed + index * 37) % 1461)
    tomorrow = today + dt.timedelta(days=1)
    later = today + dt.timedelta(days=2)
    title = ["Gymnastik", "Ergotherapie", "Spaziergang", "Atemübung", "Training"][index % 5]
    hour = 8 + index % 8
    duration = [15, 20, 30, 45, 60][index % 5]
    reference = f"termin-{index + 1}"
    context = {
        "today": today.isoformat(),
        "timezone": "Europe/Vienna",
        "visible_references": [reference],
        "selected": reference,
    }

    def query(detail, **scope):
        return {"action": "calendar", "query": {"detail": detail, **scope}}

    def update(**change):
        return {"action": "update", "query": {"reference": reference}, "change": change}

    def clarify(problem):
        return {"action": "clarify", "problem": problem}

    cases = [
        (
            "train",
            "next-today",
            "Was ist heute mein nächster Termin?",
            query("next", date=today.isoformat()),
        ),
        (
            "train",
            "list-tomorrow",
            "Welche Termine habe ich morgen?",
            query("list", date=tomorrow.isoformat()),
        ),
        (
            "train",
            "room-selected",
            "In welchem Raum ist dieser Termin?",
            query("room", reference=reference),
        ),
        (
            "train",
            "therapist-selected",
            "Wer leitet diesen Termin?",
            query("therapist", reference=reference),
        ),
        (
            "train",
            "duration-selected",
            "Wie lange dauert dieser Termin?",
            query("duration", reference=reference),
        ),
        (
            "train",
            "start-selected",
            "Wann beginnt dieser Termin?",
            query("start", reference=reference),
        ),
        (
            "train",
            "end-selected",
            "Wann ist dieser Termin zu Ende?",
            query("end", reference=reference),
        ),
        (
            "train",
            "count-today",
            "Wie viele Termine habe ich heute?",
            query("count", date=today.isoformat()),
        ),
        (
            "train",
            "morning-list",
            "Welche Termine habe ich morgen vormittags?",
            query("list", date=tomorrow.isoformat(), before="12:00"),
        ),
        (
            "train",
            "afternoon-list",
            "Welche Termine sind heute nachmittags?",
            query("list", date=today.isoformat(), after="12:00", before="18:00"),
        ),
        (
            "train",
            "after-selected",
            "Was kommt nach diesem Termin?",
            query("next", reference=reference),
        ),
        (
            "train",
            "create-complete",
            f"Trage morgen um {hour} Uhr {title} für {duration} Minuten ein.",
            {
                "action": "create",
                "change": {
                    "title": title,
                    "date": tomorrow.isoformat(),
                    "time": f"{hour:02}:00",
                    "duration": duration,
                },
            },
        ),
        ("train", "rename-only", f"Nenne diesen Termin bitte {title}.", update(title=title)),
        (
            "train",
            "duration-only",
            f"Dieser Termin soll nur {duration} Minuten dauern.",
            update(duration=duration),
        ),
        (
            "train",
            "move-time-only",
            f"Verschiebe diesen Termin auf {hour} Uhr.",
            update(time=f"{hour:02}:00"),
        ),
        (
            "train",
            "move-date-only",
            "Verschiebe diesen Termin auf morgen.",
            update(date=tomorrow.isoformat()),
        ),
        (
            "train",
            "remove-selected",
            "Lösche bitte diesen Termin.",
            {"action": "remove", "query": {"reference": reference}},
        ),
        ("train", "cancel-pending", "Abbrechen, ich möchte nichts ändern.", {"action": "cancel"}),
        ("train", "negative-remove", "Diesen Termin bitte nicht löschen.", {"action": "cancel"}),
        (
            "train",
            "invalid-february",
            f"Trage am 31. Februar {today.year} um {hour} Uhr {title} ein.",
            clarify("invalid_date"),
        ),
        ("train", "missing-create-time", f"Trage morgen {title} ein.", clarify("missing_time")),
        (
            "train",
            "missing-create-date",
            f"Trage {title} um {hour} Uhr ein.",
            clarify("missing_date"),
        ),
        (
            "train",
            "correct-hour",
            f"Verschiebe diesen Termin auf {hour} Uhr, nein, auf {hour + 1} Uhr.",
            update(time=f"{hour + 1:02}:00"),
        ),
        (
            "train",
            "app-capture",
            "Wie fotografiere ich einen Plan?",
            {"action": "help", "topic": "capture"},
        ),
        (
            "train",
            "app-privacy",
            "Wie lösche ich meine Daten in der App?",
            {"action": "help", "topic": "privacy"},
        ),
        (
            "train",
            "app-calendar",
            "Wie wähle ich sichtbare Kalender aus?",
            {"action": "help", "topic": "calendars"},
        ),
        (
            "train",
            "app-archive",
            "Wo finde ich meine alten eingescannten Pläne?",
            {"action": "help", "topic": "archive"},
        ),
        (
            "train",
            "app-voice",
            "Wie starte ich das Gespräch mit der App?",
            {"action": "help", "topic": "voice"},
        ),
        (
            "validation",
            "correct-date",
            "Nicht morgen, sondern übermorgen: Welche Termine habe ich da?",
            query("list", date=later.isoformat()),
        ),
        ("validation", "room-follow-up", "Und der Raum dazu?", query("room", reference=reference)),
        ("validation", "after-follow-up", "Und danach?", query("next", reference=reference)),
        (
            "validation",
            "paused-duration",
            f"Die Dauer von diesem Termin ... bitte ... auf {duration} Minuten ändern.",
            update(duration=duration),
        ),
        (
            "validation",
            "negation-plus-change",
            f"Nicht löschen. Ändere nur den Namen dieses Termins in {title}.",
            update(title=title),
        ),
        (
            "validation",
            "cancel-interruption",
            "Stopp, vergiss die Änderung, lass alles wie es ist.",
            {"action": "cancel"},
        ),
        (
            "validation",
            "invalid-april",
            f"Plane {title} am 31. April {today.year} um {hour} Uhr.",
            clarify("invalid_date"),
        ),
        (
            "validation",
            "bounded-next",
            f"Was habe ich morgen als Nächstes nach {hour} Uhr?",
            query("next", date=tomorrow.isoformat(), after=f"{hour:02}:00"),
        ),
        (
            "validation",
            "minimal-create",
            f"Bitte {title} am {later.strftime('%d.%m.%Y')} um {hour} Uhr eintragen.",
            {
                "action": "create",
                "change": {"title": title, "date": later.isoformat(), "time": f"{hour:02}:00"},
            },
        ),
        ("validation", "missing-target", "Lösche den anderen Termin.", clarify("ambiguous")),
    ]
    return [
        {
            "id": f"{family}-{index:04}",
            "family": family,
            "partition": partition,
            "scenario_group": family,
            "paraphrase_group": family,
            "speaker_group": f"invented-text-{partition}",
            "provenance": "agent-authored-invented-development",
            "human_review": "pending",
            "context": dict(context),
            "utterance": utterance,
            "expected": expected,
        }
        for partition, family, utterance, expected in cases
    ]


def prepare(output, per_family, seed):
    if per_family < 1 or per_family > 1000:
        raise ValueError("Use 1–1000 examples per scenario family")
    output.mkdir(parents=True, exist_ok=False)
    data = {
        "schema_version": 1,
        "kind": "invented-development-dialogues",
        "final_holdout": False,
        "seed": seed,
        "generator_sha256": sha(Path(__file__)),
        "contract_sha256": sha(Path(__file__).with_name("contract.py")),
        "independent_real_dialogues": 0,
        "human_review": "pending",
        "samples": [row for index in range(per_family) for row in examples(index, seed)],
    }
    write(output / "dataset.json", data)
    validate_dataset(output / "dataset.json")
    print(
        f"Prepared {len(data['samples'])} invented examples in 38 disjoint families; human review pending."
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--per-family", type=int, default=16)
    parser.add_argument("--seed", type=int, default=20260917)
    args = parser.parse_args()
    destination = args.output.resolve()
    if not destination.is_relative_to(ROOT / ".local"):
        raise ValueError("Prepared datasets belong in ignored .local storage")
    prepare(destination, args.per_family, args.seed)


if __name__ == "__main__":
    main()
