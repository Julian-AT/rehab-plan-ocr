"""No simulator/model: invented observations audit the integrated trial's fail-closed grader."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.conversation import voice_trial as trial  # noqa: E402

RUN = "00000000-0000-0000-0000-000000000001"
MODEL = "assistant-development-002/invented-model/invented-native"


def state(**changes):
    return dict(
        response="",
        proposal=None,
        running=False,
        busy=False,
        audio_speaking=False,
        confirmation_count=0,
        read_count=3,
        **changes,
    )


def fixture(scenario):
    query = (
        trial.CREATE
        if scenario == "minimal-create"
        else trial.ROOM
        if scenario == "live-confirm"
        else trial.QUERY
    )
    admission = dict(
        text=query,
        model_identity=MODEL,
        status="returned",
        delivery_returned=True,
        typed_result={"action": "calendar"},
        phase=0,
    )
    result = dict(
        schema_version=1,
        run_id=RUN,
        case_id=scenario,
        provider="custom-qwen-trial",
        model_identity=MODEL,
        expected_model_identity=MODEL,
        today="2031-05-15",
        timezone="Europe/Vienna",
        transcript_source="scripted-recognizer-output",
        calendar_mode="owned-live-fixture" if scenario == "live-confirm" else "fake",
        qualified=False,
        full_voice_workflow=False,
        real_asr=False,
        human_listening=False,
        failure=None,
        status="cancelled",
        admissions=[admission],
        previews=[],
        confirmations=[],
        events=[{"kind": "transcript-chunk", "text": query}],
        state=state(),
        turns=[],
        audio=[
            dict(
                response_id="invented",
                prepared_text="Raum 3.42.",
                prepared_speech="Raum 3.42.",
                spoken_text="Raum 3.42.",
                playing_frames=10,
                peak_level=0.2,
                phase="idle",
            )
        ],
    )
    if scenario == "calendar-audio":
        result["turns"] = [
            dict(text=query, state=state()),
            dict(text="Und der Raum dazu?", state=dict(response="Raum 3.42.")),
        ]
    if scenario == "late-cancel":
        result.update(
            status="late-drained", cancelled_snapshot=state(), late_snapshot=state(), audio=[]
        )
    if scenario == "minimal-create":
        result.update(
            redundant_title_prompt=False,
            late_yes_delivered=True,
            late_yes_snapshot=dict(confirmation_count=0, proposal="new", last_user="Ja, speichern"),
            turns=[
                dict(
                    text=query,
                    state=dict(
                        title="Gymnastik", new_date="2031-05-17", new_time=480, question="duration"
                    ),
                )
            ],
            previews=[
                dict(
                    token="new",
                    kind="create",
                    patch=dict(
                        title="Gymnastik",
                        start_utc="2031-05-17T06:00:00Z",
                        end_utc="2031-05-17T06:30:00Z",
                        timezone="Europe/Vienna",
                    ),
                )
            ],
            confirmations=[dict(token="new", phase=0, confirmation="button")],
        )
    if scenario in {"rename-confirm", "live-confirm"}:
        before = dict(
            id="event",
            values=dict(
                title="Physiotherapie",
                start_utc="2031-05-16T08:00:00Z",
                end_utc="2031-05-16T08:30:00Z",
                location="Raum 2.14",
            ),
        )
        result.update(
            cancelled_snapshot=state(),
            admissions=[admission, dict(admission, phase=1)],
            previews=[
                dict(
                    token=token,
                    before=copy.deepcopy(before),
                    kind="update",
                    patch={"title": "Gymnastik"},
                )
                for token in ("cancelled", "confirmed")
            ],
            confirmations=[dict(token="confirmed", phase=1, confirmation="button")],
        )
        if scenario == "live-confirm":
            for item in result["admissions"]:
                item["typed_result"] = {"action": "calendar", "query": {"detail": "room"}}
            result["turns"] = [
                dict(
                    text=trial.ROOM,
                    phase=phase,
                    state={"response": "Für diesen Termin ist mir kein Raum bekannt."},
                )
                for phase in (0, 1)
            ]
        after = copy.deepcopy(before)
        after["values"]["title"] = "Gymnastik"
        result["live_snapshots"] = [
            dict(label=label, events=[copy.deepcopy(event)])
            for label, event in [
                ("before-preview", before),
                ("after-cancel", before),
                ("after-confirm", after),
            ]
        ]
    if scenario != "late-cancel":
        sequences = {
            "calendar-audio": [(0, trial.QUERY), (0, "Und der Raum dazu?")],
            "minimal-create": [(0, trial.CREATE), (0, "30 Minuten")],
            "rename-confirm": [
                (phase, text) for phase in (0, 1) for text in (trial.QUERY, trial.RENAME)
            ],
            "live-confirm": [
                (phase, text)
                for phase in (0, 1)
                for text in ("Nächster Termin", trial.ROOM, trial.RENAME)
            ],
        }
        prior = {(turn.get("phase", 0), turn["text"]): turn["state"] for turn in result["turns"]}
        result["turns"] = [
            dict(phase=phase, text=text, state=prior.get((phase, text), {}))
            for phase, text in sequences[scenario]
        ]
        required = [turn["state"] for turn in result["turns"]]
        if scenario == "minimal-create":
            required.append(result["late_yes_snapshot"])
        if scenario in {"minimal-create", "rename-confirm", "live-confirm"}:
            result["confirmation_audio"] = {"response": "Der Termin ist gespeichert."}
            required.append(result["confirmation_audio"])
        result["audio"] = []
        for index, item in enumerate(required):
            item["response_id"] = f"invented-response-{index}"
            if not item.get("response"):
                item["response"] = f"Erfundene Antwort {index}."
            result["audio"].append(
                dict(
                    response_id=item["response_id"],
                    prepared_text=item["response"],
                    prepared_speech=item["response"],
                    spoken_text=item["response"],
                    phase="idle",
                    completed=True,
                    playing_frames=10,
                    peak_level=0.2,
                )
            )
            result["events"].append(dict(kind="audio-completed", response_id=item["response_id"]))
    return result


class VoiceTrialTests(unittest.TestCase):
    def test_all_five_invented_controls_pass_but_cannot_qualify(self):
        reports = {case: fixture(case) for case in trial.CASES}
        value = trial.grade(
            reports,
            dict(passed=True, complete_run_passed=True, executed_tests=trial.TESTS),
            RUN,
            MODEL,
        )
        self.assertTrue(value["passed"], value)
        for key in ("qualified", "full_voice_workflow", "real_asr", "human_listening"):
            self.assertIs(value[key], False)
        self.assertTrue(all(c["native_generation_calls"] is None for c in value["cases"]))

    def assert_bad(self, scenario, mutate, check):
        value = fixture(scenario)
        mutate(value)
        result = trial.grade_case(value, scenario, RUN, MODEL)
        self.assertFalse(result["passed"])
        self.assertFalse(result["checks"][check])

    def test_title_loss_remains_failure_even_after_recovery_and_button(self):
        self.assert_bad(
            "minimal-create",
            lambda r: r.update(redundant_title_prompt=True),
            "retained_fields_and_justified_clarification",
        )
        self.assert_bad(
            "minimal-create",
            lambda r: r["turns"][0]["state"].update(title=None, question="title"),
            "retained_fields_and_justified_clarification",
        )

    def test_provider_bypass_wrong_model_and_errors_fail(self):
        self.assert_bad(
            "calendar-audio", lambda r: r.update(admissions=[]), "real_provider_admitted"
        )
        self.assert_bad(
            "calendar-audio",
            lambda r: r["admissions"][0].update(model_identity="other"),
            "real_provider_admitted",
        )
        self.assert_bad(
            "calendar-audio",
            lambda r: r["admissions"][0].update(status="error"),
            "real_provider_admitted",
        )
        self.assert_bad("calendar-audio", lambda r: r.update(run_id="stale"), "current_observation")

    def test_preconfirmation_spoken_yes_or_extra_button_fails(self):
        self.assert_bad(
            "minimal-create",
            lambda r: r["late_yes_snapshot"].update(confirmation_count=1),
            "spoken_yes_cannot_confirm",
        )
        self.assert_bad(
            "minimal-create",
            lambda r: r["confirmations"].append(r["confirmations"][0]),
            "one_visible_button_confirmation",
        )
        self.assert_bad(
            "rename-confirm",
            lambda r: r["confirmations"][0].update(confirmation="voice"),
            "one_visible_button_confirmation",
        )

    def test_rename_target_time_or_additional_field_changes_fail(self):
        self.assert_bad(
            "rename-confirm",
            lambda r: r["previews"][1]["patch"].update(location="elsewhere"),
            "title_only_same_target",
        )
        self.assert_bad(
            "rename-confirm",
            lambda r: r["previews"][1]["before"].update(id="different"),
            "title_only_same_target",
        )
        self.assert_bad(
            "rename-confirm",
            lambda r: r["cancelled_snapshot"].update(confirmation_count=1),
            "cancel_before_write",
        )

    def test_live_write_on_cancel_and_other_field_change_fail(self):
        self.assert_bad(
            "live-confirm",
            lambda r: r["live_snapshots"][1]["events"][0]["values"].update(title="Gymnastik"),
            "owned_live_only_confirmed_title_changes",
        )
        self.assert_bad(
            "live-confirm",
            lambda r: r["live_snapshots"][2]["events"][0]["values"].update(location="elsewhere"),
            "owned_live_only_confirmed_title_changes",
        )
        self.assert_bad(
            "live-confirm",
            lambda r: r["turns"][1]["state"].update(response="Der Raum ist 105."),
            "missing_room_is_reported_without_invention",
        )

    def test_late_native_delivery_cannot_change_ui_or_write(self):
        self.assert_bad(
            "late-cancel",
            lambda r: r["late_snapshot"].update(response="late answer"),
            "late_delivery_stays_cancelled",
        )
        self.assert_bad(
            "late-cancel",
            lambda r: r["late_snapshot"].update(running=True),
            "late_delivery_stays_cancelled",
        )
        self.assert_bad(
            "late-cancel",
            lambda r: r["admissions"][0].update(delivery_returned=False),
            "real_provider_admitted",
        )

    def test_silent_mismatched_or_truncated_audio_cannot_pass(self):
        for change in [
            dict(peak_level=0),
            dict(playing_frames=0),
            dict(spoken_text="unrelated"),
            dict(spoken_text="Raum"),
            dict(phase="failed"),
        ]:
            with self.subTest(change=change):
                self.assert_bad(
                    "calendar-audio",
                    lambda r: r["audio"][0].update(change),
                    "real_audio_matches_prepared_words",
                )

    def test_earlier_complete_audio_cannot_cover_missing_or_truncated_room_reply(self):
        self.assert_bad(
            "calendar-audio", lambda r: r["audio"].pop(), "real_audio_matches_prepared_words"
        )
        self.assert_bad(
            "calendar-audio",
            lambda r: r["audio"][-1].update(spoken_text="Raum"),
            "real_audio_matches_prepared_words",
        )
        self.assert_bad(
            "calendar-audio",
            lambda r: r["turns"][-1]["state"].update(
                response_id=r["turns"][0]["state"]["response_id"]
            ),
            "real_audio_matches_prepared_words",
        )

    def test_complete_proposal_audio_cannot_cover_missing_or_prefix_only_saved_reply(self):
        for scenario in ["minimal-create", "rename-confirm", "live-confirm"]:
            with self.subTest(scenario=scenario):
                self.assert_bad(
                    scenario, lambda r: r["audio"].pop(), "real_audio_matches_prepared_words"
                )
                self.assert_bad(
                    scenario,
                    lambda r: r["audio"][-1].update(spoken_text="Der Termin ist"),
                    "real_audio_matches_prepared_words",
                )
                self.assert_bad(
                    scenario,
                    lambda r: r["audio"][-1].update(completed=False),
                    "real_audio_matches_prepared_words",
                )

    def test_required_audio_needs_its_actual_completion_event(self):
        self.assert_bad(
            "calendar-audio", lambda r: r["events"].pop(), "each_required_audio_completed_naturally"
        )
        self.assert_bad(
            "rename-confirm", lambda r: r.update(confirmation_audio=None), "saved_answer_is_bound"
        )

    def test_zero_partial_duplicate_or_extra_tests_cannot_pass(self):
        reports = {case: fixture(case) for case in trial.CASES}
        for tests in [
            [],
            trial.TESTS[:-1],
            trial.TESTS + [trial.TESTS[0]],
            trial.TESTS + ["unrelated"],
        ]:
            self.assertFalse(
                trial.grade(
                    reports,
                    dict(passed=True, complete_run_passed=True, executed_tests=tests),
                    RUN,
                    MODEL,
                )["passed"]
            )
        del reports["minimal-create"]
        self.assertFalse(
            trial.grade(
                reports,
                dict(passed=True, complete_run_passed=True, executed_tests=trial.TESTS),
                RUN,
                MODEL,
            )["passed"]
        )

    def test_xctestrun_patch_preserves_source_and_accepts_both_known_shapes(self):
        target = {
            "TestBundlePath": "__TESTROOT__/Runner.app/PlugIns/AssistantVoiceTrialUITests.xctest",
            "UITargetAppPath": "__TESTROOT__/Laßnitzhöhe.app",
            "DependentProductPaths": ["__TESTROOT__/Laßnitzhöhe.app", "__TESTROOT__/Runner.app"],
            "EnvironmentVariables": {"existing": "retained"},
        }
        for source in [
            {"AssistantVoiceTrialUITests": target},
            {"TestConfigurations": [{"TestTargets": [target]}]},
        ]:
            original = copy.deepcopy(source)
            value = trial.patch_xctestrun(
                source, Path("/products"), Path("/owned/Laßnitzhöhe.app"), RUN, MODEL
            )
            self.assertEqual(source, original)
            patched = (
                value.get("AssistantVoiceTrialUITests")
                or value["TestConfigurations"][0]["TestTargets"][0]
            )
            self.assertEqual(patched["UITargetAppPath"], "/owned/Laßnitzhöhe.app")
            self.assertEqual(patched["EnvironmentVariables"]["REHA_ASSISTANT_VOICE_MODEL"], MODEL)
            self.assertEqual(patched["EnvironmentVariables"]["existing"], "retained")
        for invalid in [
            {},
            {"a": target, "b": target},
            {"a": dict(target, TestBundlePath="other.xctest")},
        ]:
            with self.assertRaises(ValueError):
                trial.patch_xctestrun(
                    invalid, Path("/products"), Path("/owned/App.app"), RUN, MODEL
                )

    def test_bounded_app_evidence_read(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "report.json"
            path.write_text(json.dumps({"test": "ok"}))
            self.assertEqual(trial.load_report(path), {"test": "ok"})
            with patch.object(trial, "MAX_REPORT_BYTES", 3), self.assertRaises(ValueError):
                trial.load_report(path)

    def test_signed_runner_relocation_preserves_testhost_relative_paths(self):
        source = {
            "tests": {
                "TestHostPath": "__TESTROOT__/AssistantVoiceTrialUITests-Runner.app",
                "TestBundlePath": "__TESTHOST__/PlugIns/AssistantVoiceTrialUITests.xctest",
                "DependentProductPaths": [
                    "__TESTROOT__/AssistantVoiceTrialUITests-Runner.app/PlugIns/AssistantVoiceTrialUITests.xctest"
                ],
            }
        }
        value = trial.patch_xctestrun(
            source,
            Path("/products"),
            Path("/owned/App.app"),
            RUN,
            MODEL,
            Path("/owned/AssistantVoiceTrialUITests-Runner.app"),
        )["tests"]
        self.assertEqual(value["TestHostPath"], "/owned/AssistantVoiceTrialUITests-Runner.app")
        self.assertEqual(value["TestBundlePath"], source["tests"]["TestBundlePath"])
        self.assertEqual(
            value["DependentProductPaths"],
            [
                "/owned/AssistantVoiceTrialUITests-Runner.app/PlugIns/AssistantVoiceTrialUITests.xctest"
            ],
        )

    def test_collect_keeps_exact_app_bytes_including_malformed_partial_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            container, target = root / "app", root / "observations"
            (container / "Documents").mkdir(parents=True)
            target.mkdir()
            original = b'{ "status" : "failed" }\n\n'
            malformed = b"{partial"
            for case, data in [("calendar-audio", original), ("minimal-create", malformed)]:
                (container / f"Documents/assistant-voice-{RUN}-{case}.json").write_bytes(data)
            observations, missing, digests = trial.collect_observations(container, target, RUN)
            self.assertEqual(observations, {"calendar-audio": {"status": "failed"}})
            self.assertEqual((target / "calendar-audio.json").read_bytes(), original)
            self.assertEqual((target / "minimal-create.json").read_bytes(), malformed)
            self.assertEqual(len(missing), 4)
            self.assertEqual(set(digests), {"calendar-audio", "minimal-create"})

    def test_build_identity_binds_model_sources_and_test_products(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            registry = root / "ml/registry/assistant-development-002.json"
            app = root / "App.app"
            (app / "assistant-trial").mkdir(parents=True)
            registry.parent.mkdir(parents=True)
            (app / "Termine.debug.dylib").write_bytes(b"invented app")
            model = app / "assistant-trial/assistant.gguf"
            model.write_bytes(b"invented model")
            registry.write_text(
                json.dumps(
                    dict(
                        id="assistant-development-002",
                        qualified=False,
                        artifact=dict(bytes=model.stat().st_size, sha256=trial.sha(model)),
                    )
                )
            )
            source = root / "source.swift"
            source.write_text("invented source")
            run = root / "tests.xctestrun"
            run.write_bytes(b"invented tests")
            runner = root / "runner.app"
            runner.mkdir()
            (runner / "code").write_bytes(b"invented code")
            manifest = dict(
                model_id="assistant-development-002",
                registry_sha256=trial.sha(registry),
                model_sha256=trial.sha(model),
                model_bytes=model.stat().st_size,
                native_identity="invented-native",
            )
            (app / "assistant-trial/manifest.json").write_text(json.dumps(manifest))
            receipt = dict(
                qualified=False,
                trial_manifest=manifest,
                app="App.app",
                app_binary_sha256=trial.sha(app / "Termine.debug.dylib"),
                sources={"source.swift": trial.sha(source)},
                voice_ui_tests=dict(
                    scheme="AssistantVoiceTrial",
                    xctestrun="tests.xctestrun",
                    xctestrun_sha256=trial.sha(run),
                    runner="runner.app",
                    runner_inventory=trial.product_generation.inventory(runner),
                ),
            )
            self.assertEqual(trial.verify_build(receipt, root)[0], app)
            for path in [model, source, run, runner / "code", app / "Termine.debug.dylib"]:
                original = path.read_bytes()
                path.write_bytes(b"changed")
                with self.subTest(path=path), self.assertRaises(ValueError):
                    trial.verify_build(receipt, root)
                path.write_bytes(original)

    def test_timeout_stops_only_owned_process_group_before_return(self):
        with tempfile.TemporaryDirectory() as temporary:
            with (
                patch.object(trial.subprocess, "Popen") as launch,
                patch.object(trial.os, "killpg") as stop,
            ):
                process = launch.return_value
                process.pid = 1234
                process.wait.side_effect = [trial.subprocess.TimeoutExpired("synthetic", 1800), 143]
                with self.assertRaises(trial.subprocess.TimeoutExpired):
                    trial.execute_tests(["invented"], Path(temporary) / "log", 42)
                self.assertTrue(launch.call_args.kwargs["start_new_session"])
                self.assertEqual(launch.call_args.kwargs["pass_fds"], (42,))
                stop.assert_called_once_with(1234, trial.signal.SIGTERM)


if __name__ == "__main__":
    unittest.main()
