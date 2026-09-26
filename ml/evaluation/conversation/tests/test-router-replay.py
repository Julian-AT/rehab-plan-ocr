"""Paired replay must retain unsafe regressions and reject incomplete evidence."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.conversation import router_replay as replay  # noqa: E402
from ml.evaluation.conversation.app_evaluation import prepare  # noqa: E402
from ml.evaluation.conversation.router_replay import VARIANTS, assess  # noqa: E402
from ml.training.assistant.contract import messages  # noqa: E402
from ml.training.assistant.prepare import examples  # noqa: E402


class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dataset = Path(self.temp.name) / "dataset.json"
        self.dataset.write_text(
            json.dumps(
                dict(
                    schema_version=1,
                    kind="invented-development-dialogues",
                    final_holdout=False,
                    samples=[row for index in range(4) for row in examples(index, 20260917)],
                )
            )
        )
        self.fixture, self.rows = prepare(self.dataset, "paired", "custom")
        self.recorded = dict(variants=[dict(id=name, model_identity="pinned") for name in VARIANTS])
        self.result = dict(
            kind="paired-recorded-synthetic-response-replay",
            qualified=False,
            fresh_inference=False,
            full_voice_workflow=False,
            variants=[
                dict(
                    id=name,
                    recorded_responses_admitted=len(self.rows),
                    cases=[
                        dict(
                            id=r["id"],
                            family=r["family"],
                            expected=r["expected"],
                            operation=r["expected"],
                            provider="recorded-response",
                            recorded_response_admitted=True,
                        )
                        for r in self.rows
                    ],
                )
                for name in VARIANTS
            ],
        )

    def audit(self, result=None):
        return assess(result or self.result, self.fixture, self.rows, self.recorded)

    def test_regression_is_reported_separately_from_total_quality(self):
        changed = copy.deepcopy(self.result)
        case = changed["variants"][2]["cases"][0]
        case["operation"] = dict(action="remove", query=dict(reference="termin-1"))
        report = self.audit(changed)
        self.assertEqual(report["new_unsafe_proposed_mutations"], [case["id"]])
        self.assertEqual(report["new_incorrect_cases"], [case["id"]])
        self.assertFalse(report["qualified"])
        self.assertEqual(report["independent_real_dialogues"], 0)
        self.assertEqual(len(report["variants"]["corrected-cli"]["dependency_components"]), 1)

    def test_partial_reordered_and_wrong_scope_evidence_is_rejected(self):
        changes = [
            ("qualified", True),
            ("fresh_inference", True),
            ("full_voice_workflow", True),
            ("variants", self.result["variants"][:-1]),
            ("variants", list(reversed(self.result["variants"]))),
        ]
        for key, value in changes:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.audit(dict(self.result, **{key: value}))
        changed = copy.deepcopy(self.result)
        changed["variants"][1]["cases"].reverse()
        with self.assertRaises(ValueError):
            self.audit(changed)

    def test_provider_admission_must_match_actual_trace_and_count(self):
        for key, value in [("recorded_response_admitted", False), ("provider", "complete-rules")]:
            changed = copy.deepcopy(self.result)
            changed["variants"][2]["cases"][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.audit(changed)
        changed = copy.deepcopy(self.result)
        changed["variants"][2]["recorded_responses_admitted"] -= 1
        with self.assertRaises(ValueError):
            self.audit(changed)

    def test_prepared_replay_rejects_a_changed_complete_rule_source(self):
        app, deployment, native = (
            Path(self.temp.name) / name for name in ["app", "deployment", "native"]
        )
        for directory in [app, deployment, native]:
            directory.mkdir()
        (app / "dataset.json").write_bytes(self.dataset.read_bytes())
        replay.write(app / "input.json", self.fixture)
        prior, original, controls, sources = [], [], [], {}
        for index, row in enumerate(self.rows):
            base = {key: row[key] for key in ["id", "family", "expected"]}
            answer = json.dumps(row["expected"])
            prior.append(dict(base, outputs=dict(assistant=answer)))
            original.append(dict(base, observation=dict(operation=row["expected"])))
            prompt = deployment / f"case-{index:04}.prompt.txt"
            prompt.write_text(
                "<|im_start|>user\n"
                + messages(row, include_answer=False)[1]["content"]
                + "<|im_end|>"
            )
            sources[str(prompt.resolve())] = replay.sha(prompt)
            (native / f"case-{index:04}.desktop-auto.txt").write_text(answer)
            controls.append(
                dict(
                    id=row["id"],
                    variants={"desktop-auto": dict(prompt_tokens_equal=True, answer=answer)},
                )
            )
        replay.write(deployment / "parity.json", dict(cases=prior))
        sources[str((deployment / "parity.json").resolve())] = replay.sha(
            deployment / "parity.json"
        )
        replay.write(native / "report.json", dict(full_corpus_controls=controls, sources=sources))
        replay.write(
            app / "report.json",
            dict(
                cases=original,
                model_identity="pinned",
                dataset_sha256=replay.sha(app / "dataset.json"),
                fixture_sha256=replay.sha(app / "input.json"),
            ),
        )
        private = replay.ROOT / ".local/runs"
        private.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=private) as temporary:
            output = Path(temporary) / "replay"
            replay.prepare_replay(app, deployment, native, output)
            replay.write(output / "router.json", self.result)
            real_sha = replay.sha
            rule = replay.ROOT / "apps/ios/Features/Conversation/ConversationRules.swift"
            with patch.object(
                replay,
                "sha",
                side_effect=lambda path: "changed" if path == rule else real_sha(path),
            ):
                with self.assertRaisesRegex(ValueError, "Replay source changed"):
                    replay.summarize(output)

    def test_new_compiler_response_entries_are_pinned_without_an_evaluator_list_change(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            checks = root / "tooling/checks"
            checks.mkdir(parents=True)
            (checks / "test-custom-assistant-provider.sh").write_text("sh test-calendar-answers.sh")
            (checks / "test-calendar-answers.sh").write_text("swiftc @tooling/checks/sources.rsp")
            source = root / "AddedRule.swift"
            source.write_text("// synthetic compiler input")
            response = checks / "sources.rsp"
            response.write_text("AddedRule.swift\n")
            with patch.object(replay, "ROOT", root):
                self.assertIn(source, replay.source_paths())
                self.assertIn(response, replay.source_paths())
                response.write_text("../outside.swift\n")
                with self.assertRaisesRegex(ValueError, "Invalid Swift compiler source"):
                    replay.source_paths()


if __name__ == "__main__":
    unittest.main()
