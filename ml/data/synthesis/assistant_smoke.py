"""Invented German examples for pipeline checks, awaiting human language review.

These few examples are not a benchmark or the production training corpus.
Their scenario families are disjoint across the two smoke partitions.
"""

import json

SYSTEM = """Wandle die deutsche Äußerung in eine JSON-Kalenderabsicht um.
Aktionen: calendar, create, update, remove, cancel, help, clarify.
Kalenderfragen: query mit detail (next, room, therapist, duration, list), date
(yyyy-MM-dd), reference (nur eine ID aus dem Kontext), after oder before (HH:mm).
Änderungen: change enthält ausschließlich ausdrücklich genannte neue Werte:
title, date, time, duration. Vorhandene Werte nicht ergänzen. Ungültige Daten:
clarify mit problem=invalid_date. Abbruch oder verneinte Änderung: cancel.
Keine Kalenderfakten erfinden. Nichts ausführen oder als gespeichert behaupten.
Antworte ausschließlich mit einem JSON-Objekt, ohne Erläuterung."""


def examples():
    rows = [
        (
            "train",
            "next",
            "Was ist heute mein nächster Termin?",
            {},
            {"action": "calendar", "query": {"detail": "next", "date": "2030-09-17"}},
        ),
        (
            "train",
            "room",
            "In welchem Raum ist dieser Termin?",
            {"selected": "e1"},
            {"action": "calendar", "query": {"detail": "room", "reference": "e1"}},
        ),
        (
            "train",
            "create",
            "Trage morgen um 9 Uhr Gymnastik für 30 Minuten ein.",
            {},
            {
                "action": "create",
                "change": {
                    "title": "Gymnastik",
                    "date": "2030-09-18",
                    "time": "09:00",
                    "duration": 30,
                },
            },
        ),
        (
            "train",
            "rename",
            "Nenne diesen Termin bitte Bewegung.",
            {"selected": "e1"},
            {"action": "update", "query": {"reference": "e1"}, "change": {"title": "Bewegung"}},
        ),
        (
            "train",
            "duration_change",
            "Dieser Termin soll nur 20 Minuten dauern.",
            {"selected": "e1"},
            {"action": "update", "query": {"reference": "e1"}, "change": {"duration": 20}},
        ),
        (
            "train",
            "invalid_date",
            "Trage am 31. Februar einen Spaziergang ein.",
            {},
            {"action": "clarify", "problem": "invalid_date"},
        ),
        (
            "train",
            "cancellation",
            "Abbrechen, ich möchte doch nichts ändern.",
            {"pending": "update"},
            {"action": "cancel"},
        ),
        (
            "train",
            "help",
            "Wie fotografiere ich einen Plan?",
            {},
            {"action": "help", "topic": "capture"},
        ),
        (
            "valid",
            "therapist",
            "Wer leitet diesen Termin?",
            {"selected": "e2"},
            {"action": "calendar", "query": {"detail": "therapist", "reference": "e2"}},
        ),
        (
            "valid",
            "duration_query",
            "Wie lange dauert dieser Termin?",
            {"selected": "e2"},
            {"action": "calendar", "query": {"detail": "duration", "reference": "e2"}},
        ),
        (
            "valid",
            "negated_removal",
            "Nein, diesen Termin nicht löschen.",
            {"selected": "e2", "pending": "remove"},
            {"action": "cancel"},
        ),
        (
            "valid",
            "time_constraint",
            "Welche Termine habe ich morgen vor 12 Uhr?",
            {},
            {
                "action": "calendar",
                "query": {"detail": "list", "date": "2030-09-18", "before": "12:00"},
            },
        ),
    ]
    return [
        {
            "id": family,
            "family": family,
            "partition": partition,
            "provenance": "agent-authored-invented-smoke",
            "human_review": "pending",
            "context": {"today": "2030-09-17", **context},
            "utterance": text,
            "expected": expected,
        }
        for partition, family, text, context, expected in rows
    ]


def messages(row, *, include_answer=True):
    result = [
        {"role": "system", "content": SYSTEM},
        {
            "role": "user",
            "content": json.dumps(row["context"], ensure_ascii=False) + "\n" + row["utterance"],
        },
    ]
    if include_answer:
        result.append(
            {
                "role": "assistant",
                "content": json.dumps(row["expected"], ensure_ascii=False, separators=(",", ":")),
            }
        )
    return result
