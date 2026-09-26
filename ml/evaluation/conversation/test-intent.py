import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from ml.data.synthesis.assistant_smoke import examples
from ml.evaluation.conversation.intent import InvalidIntent, canonical_time, parse, validate


class IntentTests(unittest.TestCase):
    def test_invented_references_match_contract_and_families_do_not_overlap(self):
        families = {}
        for row in examples():
            with self.subTest(row=row["id"]):
                references = [row["context"].get("selected")]
                self.assertEqual(validate(row["expected"], references=references), row["expected"])
                self.assertEqual(row["human_review"], "pending")
                self.assertNotIn(row["family"], families)
                families[row["family"]] = row["partition"]

    def test_calendar_facts_and_confirmation_flags_are_rejected(self):
        for extra in [{"room": "123"}, {"answer": "Um neun"}, {"confirmed": True}]:
            with self.subTest(extra=extra), self.assertRaises(InvalidIntent):
                validate(
                    {
                        "action": "calendar",
                        "query": {"detail": "next", "date": "2030-09-17"},
                        **extra,
                    }
                )
        with self.assertRaises(InvalidIntent):
            parse('{"next":{"therapist":"Dr. Müller"}}')

    def test_changes_require_known_targets_and_explicit_fields(self):
        for reference in ["unknown", "", {"id": "e1"}]:
            with self.subTest(reference=reference), self.assertRaises(InvalidIntent):
                validate({"action": "remove", "query": {"reference": reference}}, references=["e1"])
        value = {"action": "update", "query": {"reference": "e1"}, "change": {"duration": 20}}
        self.assertEqual(validate(value, references=["e1"]), value)
        self.assertEqual(set(value["change"]), {"duration"})
        with self.assertRaises(InvalidIntent):
            validate(
                {"action": "update", "query": {"reference": "e1"}, "change": {}}, references=["e1"]
            )

    def test_cancellation_cannot_carry_an_old_mutation(self):
        self.assertEqual(parse('{"action":"cancel"} [end of text]'), {"action": "cancel"})
        with self.assertRaises(InvalidIntent):
            validate({"action": "cancel", "change": {"title": "old proposal"}})

    def test_invalid_dates_times_and_durations_are_rejected(self):
        for patch in [
            {"date": "2030-02-31"},
            {"date": "2030-2-1"},
            {"time": "24:00"},
            {"duration": True},
            {"duration": 0},
            {"duration": 2.5},
            {"duration": 1441},
        ]:
            with self.subTest(patch=patch), self.assertRaises(InvalidIntent):
                validate(
                    {
                        "action": "create",
                        "change": {
                            "title": "Pause",
                            "date": "2030-09-17",
                            "time": "09:00",
                            **patch,
                        },
                    }
                )

    def test_unscoped_and_contradictory_queries_are_rejected(self):
        for query in [
            {"detail": "next"},
            {"detail": "list", "date": "2030-09-17", "after": "12:00", "before": "09:00"},
        ]:
            with self.subTest(query=query), self.assertRaises(InvalidIntent):
                validate({"action": "calendar", "query": query})

    def test_every_canonical_minute_is_accepted(self):
        for hour in range(24):
            for minute in range(60):
                canonical_time(f"{hour:02}:{minute:02}")

    def test_ambiguous_or_non_json_outputs_are_rejected(self):
        for text in [
            '{"action":"remove","action":"cancel"}',
            '{"action":"cancel"} trailing',
            '```json\n{"action":"cancel"}\n```',
            '{"action":',
            "[]",
            '"cancel"',
            '{"action":[]}',
            "[" * 2000 + "]" * 2000,
            " " * 4097,
        ]:
            with self.subTest(text=text[:60]), self.assertRaises(InvalidIntent):
                parse(text)

    def test_only_registered_help_topics_are_accepted(self):
        self.assertEqual(
            parse(json.dumps({"action": "help", "topic": "capture"}))["topic"], "capture"
        )
        with self.assertRaises(InvalidIntent):
            validate({"action": "help", "topic": "invented instructions"})


if __name__ == "__main__":
    unittest.main()
