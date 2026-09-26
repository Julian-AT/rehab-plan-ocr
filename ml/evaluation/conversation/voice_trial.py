"""Five predeclared app/VoiceModel integrations with the actual development-002 provider.

Recognition is scripted. Real provider, dialog, proposal buttons, owned EventKit
fixtures and system audio are observed separately. This cannot qualify a model,
prove microphone recognition, or substitute for human listening. No build occurs.
"""

import argparse
import copy
import json
import os
import plistlib
import re
import signal
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from ml.evaluation.conversation.native import run, sha, write  # noqa: E402
from ml.evaluation.device.simulator import BUNDLE, disposable, signed_copy  # noqa: E402
from tooling.build import product_generation  # noqa: E402
from tooling.utils.apfs_clone import clone  # noqa: E402

QUERY = "Zeige mir die Termine für übermorgen."
ROOM = "In welchem Raum ist dieser Termin?"
CREATE = "Bitte Gymnastik am 17.05.2031 um 8 Uhr eintragen."
RENAME = "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik."
CASES = {
    "calendar-audio": "testNativeProviderCalendarFollowupsAndAudio",
    "minimal-create": "testMinimalCreatePreservesSpokenFieldsAndRequiresButton",
    "rename-confirm": "testNativeAnswerThenTitleOnlyChangeCancelAndButton",
    "late-cancel": "testLateNativeReplyAfterCancelCannotReachViewOrCalendar",
    "live-confirm": "testLiveFixtureWriteAppearsOnlyAfterVisibleButton",
}
TESTS = [f"AssistantVoiceTrialUITests/AssistantVoiceTrialTests/{name}" for name in CASES.values()]
MAX_REPORT_BYTES = 4 * 1024 * 1024


def report_bytes(path):
    with path.open("rb") as stream:
        data = stream.read(MAX_REPORT_BYTES + 1)
    if len(data) > MAX_REPORT_BYTES:
        raise ValueError("App observation exceeds its bounded evidence contract")
    return data


def load_report(path):
    result = json.loads(report_bytes(path))
    if not isinstance(result, dict):
        raise ValueError("App observation must be an object")
    return result


def collect_observations(container, destination, identifier):
    observations, missing, digests = {}, {}, {}
    for scenario in CASES:
        try:
            data = report_bytes(
                container / f"Documents/assistant-voice-{identifier}-{scenario}.json"
            )
            target = destination / (scenario + ".json")
            with target.open("xb") as stream:
                stream.write(data)
            digests[scenario] = sha(target)
            observations[scenario] = load_report(target)
        except (OSError, ValueError) as error:
            missing[scenario] = str(error)
    return observations, missing, digests


def words(text):
    # Audio word marks omit punctuation. Model answers are never modified here.
    return re.findall(r"\w+", text.casefold()) if isinstance(text, str) else []


def audio_contract(rows, required):
    if not rows or not required or len({row.get("response_id") for row in rows}) != len(rows):
        return False
    if len({state.get("response_id") for state in required}) != len(required):
        return False
    by_id = {row["response_id"]: row for row in rows}
    for state in required:
        row = by_id.get(state.get("response_id"), {})
        spoken = words(row.get("spoken_text"))
        forms = [words(row.get(key)) for key in ("prepared_text", "prepared_speech")]
        if not (
            state.get("response")
            and row.get("prepared_text") == state["response"]
            and spoken
            and spoken in forms
            and row.get("phase") == "idle"
            and row.get("completed") is True
            and row.get("playing_frames", 0) > 0
            and row.get("peak_level", 0) > 0
        ):
            return False
    return True


def values_by_id(snapshot):
    events = snapshot.get("events", [])
    if not events or len({e.get("id") for e in events}) != len(events):
        raise ValueError("Live fixture snapshot is missing events or repeats IDs")
    return {e["id"]: e["values"] for e in events}


def live_change(report):
    snapshots = report["live_snapshots"]
    before = values_by_id(next(s for s in snapshots if s["label"] == "before-preview"))
    cancelled = values_by_id(next(s for s in snapshots if s["label"] == "after-cancel"))
    after = values_by_id(next(s for s in snapshots if s["label"] == "after-confirm"))
    wanted = copy.deepcopy(before)
    target = report["previews"][-1]["before"]["id"]
    if target not in wanted or wanted[target]["title"] == "Gymnastik":
        return False
    wanted[target]["title"] = "Gymnastik"
    return before == cancelled and after == wanted


def grade_case(report, scenario, identifier, identity):
    checks = {}
    checks["current_observation"] = all(
        report.get(key) == expected
        for key, expected in {
            "schema_version": 1,
            "run_id": identifier,
            "case_id": scenario,
            "provider": "custom-qwen-trial",
            "model_identity": identity,
            "expected_model_identity": identity,
            "today": "2031-05-15",
            "timezone": "Europe/Vienna",
            "transcript_source": "scripted-recognizer-output",
            "calendar_mode": "owned-live-fixture" if scenario == "live-confirm" else "fake",
        }.items()
    ) and all(
        report.get(key) is False
        for key in ("qualified", "full_voice_workflow", "real_asr", "human_listening")
    )
    checks["no_observation_failure"] = (
        report.get("failure") is None and report.get("status") != "failed"
    )
    admissions = report.get("admissions", [])
    checks["real_provider_admitted"] = bool(admissions) and all(
        a.get("model_identity") == identity
        and a.get("status") == "returned"
        and a.get("delivery_returned") is True
        and isinstance(a.get("typed_result"), dict)
        for a in admissions
    )
    turns = report.get("turns", [])
    previews = report.get("previews", [])
    confirmations = report.get("confirmations", [])
    state = report.get("state", {})
    sequences = {
        "calendar-audio": [(0, QUERY), (0, "Und der Raum dazu?")],
        "minimal-create": [
            (0, CREATE),
            *([(0, "Gymnastik")] if report.get("redundant_title_prompt") is True else []),
            (0, "30 Minuten"),
        ],
        "rename-confirm": [(phase, text) for phase in (0, 1) for text in (QUERY, RENAME)],
        "live-confirm": [
            (phase, text) for phase in (0, 1) for text in ("Nächster Termin", ROOM, RENAME)
        ],
        "late-cancel": [],
    }
    checks["fixed_turn_sequence"] = [
        (turn.get("phase"), turn.get("text")) for turn in turns
    ] == sequences[scenario]
    checks["scripted_multichunk_input"] = any(
        e.get("kind") == "transcript-chunk"
        and e.get("text")
        == (
            CREATE
            if scenario == "minimal-create"
            else ROOM
            if scenario == "live-confirm"
            else QUERY
        )
        for e in report.get("events", [])
    )
    if scenario == "late-cancel":
        checks["held_actual_query_return"] = (
            len(admissions) == 1 and admissions[0].get("text") == QUERY
        )
        checks["no_write_or_preview"] = not previews and not confirmations
        checks["late_delivery_stays_cancelled"] = (
            all(
                isinstance(s, dict)
                and s.get("response") == ""
                and s.get("proposal") is None
                and s.get("running") is False
                and s.get("busy") is False
                and s.get("audio_speaking") is False
                and s.get("confirmation_count") == 0
                for s in (report.get("cancelled_snapshot"), report.get("late_snapshot"))
            )
            and report.get("status") == "late-drained"
        )
    else:
        required = [turn.get("state", {}) for turn in turns]
        if scenario == "minimal-create":
            required.append(report.get("late_yes_snapshot") or {})
        if scenario in {"minimal-create", "rename-confirm", "live-confirm"}:
            required.append(report.get("confirmation_audio") or {})
            checks["saved_answer_is_bound"] = (
                (report.get("confirmation_audio") or {})
                .get("response", "")
                .startswith("Der Termin ist gespeichert.")
            )
        checks["real_audio_matches_prepared_words"] = audio_contract(
            report.get("audio", []), required
        )
        completed = {
            e.get("response_id")
            for e in report.get("events", [])
            if e.get("kind") == "audio-completed"
        }
        checks["each_required_audio_completed_naturally"] = bool(required) and all(
            s.get("response_id") in completed for s in required
        )
    if scenario == "calendar-audio":
        checks["fixed_query_admitted"] = any(a.get("text") == QUERY for a in admissions)
        checks["live_followup_refresh"] = (
            len(turns) == 2
            and turns[-1].get("text") == "Und der Raum dazu?"
            and "3.42" in turns[-1]["state"].get("response", "")
            and "2.14" not in turns[-1]["state"].get("response", "")
            and state.get("read_count", 0) >= 2
        )
        checks["no_write_or_preview"] = not previews and not confirmations
    if scenario == "minimal-create":
        initial = turns[0].get("state", {}) if turns else {}
        checks["retained_fields_and_justified_clarification"] = (
            initial.get("title") == "Gymnastik"
            and initial.get("new_date") == "2031-05-17"
            and initial.get("new_time") == 480
            and initial.get("question") == "duration"
            and report.get("redundant_title_prompt") is False
        )
        checks["fixed_create_admitted"] = any(a.get("text") == CREATE for a in admissions)
        patch = previews[0].get("patch", {}) if len(previews) == 1 else {}
        checks["correct_complete_proposal"] = (
            len(previews) == 1
            and previews[0].get("kind") == "create"
            and all(
                patch.get(k) == v
                for k, v in {
                    "title": "Gymnastik",
                    "start_utc": "2031-05-17T06:00:00Z",
                    "end_utc": "2031-05-17T06:30:00Z",
                    "timezone": "Europe/Vienna",
                }.items()
            )
        )
        late = report.get("late_yes_snapshot") or {}
        checks["spoken_yes_cannot_confirm"] = (
            report.get("late_yes_delivered") is True
            and late.get("confirmation_count") == 0
            and late.get("last_user") == "Ja, speichern"
            and bool(late.get("proposal"))
        )
    if scenario in {"rename-confirm", "live-confirm"}:
        checks["cancel_then_new_proposal"] = len(previews) == 2 and previews[0].get(
            "token"
        ) != previews[1].get("token")
        checks["title_only_same_target"] = (
            len(previews) == 2
            and all(
                p.get("kind") == "update"
                and p.get("patch") == {"title": "Gymnastik"}
                and isinstance(p.get("before"), dict)
                for p in previews
            )
            and previews[0]["before"] == previews[1]["before"]
        )
        cancelled = report.get("cancelled_snapshot") or {}
        checks["cancel_before_write"] = (
            cancelled.get("confirmation_count") == 0
            and cancelled.get("proposal") is None
            and cancelled.get("running") is False
        )
        wanted_query = ROOM if scenario == "live-confirm" else QUERY
        checks["native_admission_both_phases"] = all(
            any(a.get("text") == wanted_query and a.get("phase") == phase for a in admissions)
            for phase in (0, 1)
        )
        if scenario == "live-confirm":
            room_turns = [turn for turn in turns if turn.get("text") == ROOM]
            checks["missing_room_is_reported_without_invention"] = (
                len(room_turns) == 2
                and {turn.get("phase") for turn in room_turns} == {0, 1}
                and all(
                    turn.get("state", {})
                    .get("response", "")
                    .endswith("Für diesen Termin ist mir kein Raum bekannt.")
                    for turn in room_turns
                )
                and all(
                    a.get("typed_result", {}).get("action") == "calendar"
                    and a.get("typed_result", {}).get("query", {}).get("detail") == "room"
                    for a in admissions
                    if a.get("text") == ROOM
                )
            )
            try:
                checks["owned_live_only_confirmed_title_changes"] = live_change(report)
            except (ValueError, KeyError, StopIteration, TypeError):
                checks["owned_live_only_confirmed_title_changes"] = False
    if scenario in {"minimal-create", "rename-confirm", "live-confirm"}:
        checks["one_visible_button_confirmation"] = (
            len(confirmations) == 1
            and confirmations[0].get("confirmation") == "button"
            and confirmations[0].get("phase") == (0 if scenario == "minimal-create" else 1)
            and bool(previews)
            and confirmations[0].get("token") == previews[-1].get("token")
        )
    return {
        "case_id": scenario,
        "passed": all(checks.values()),
        "checks": checks,
        "provider_admissions": len(admissions),
        "native_generation_calls": None,
        "raw_model_answer_observed": False,
        "fake_confirmations": len(confirmations) if scenario != "live-confirm" else 0,
        "owned_live_confirmations": len(confirmations) if scenario == "live-confirm" else 0,
    }


def grade(reports, verification, identifier, identity):
    coverage = (
        verification.get("passed") is True
        and verification.get("complete_run_passed") is True
        and sorted(verification.get("executed_tests", [])) == sorted(TESTS)
    )
    cases = []
    for scenario in CASES:
        try:
            cases.append(grade_case(reports[scenario], scenario, identifier, identity))
        except (KeyError, ValueError, TypeError, IndexError, AttributeError) as error:
            cases.append({"case_id": scenario, "passed": False, "error": str(error)})
    return {
        "passed": coverage and all(c["passed"] for c in cases),
        "exact_ui_coverage": coverage,
        "cases": cases,
        "qualified": False,
        "full_voice_workflow": False,
        "real_asr": False,
        "human_listening": False,
        "independent_real_dialogues": 0,
        "known_development_scenarios": 5,
        "development_dependency_groups": 1,
        "raw_generation_strings_observed": False,
        "integration_boundary": "real native provider, unchanged VoiceModel, proposal buttons and system audio; scripted recognizer outputs",
        "late_reply_boundary": "actual native completion held before provider return; no claim of kernel preemption",
    }


def patch_xctestrun(value, products, app, identifier, identity, runner=None):
    def absolute(item):
        if isinstance(item, str):
            return item.replace("__TESTROOT__", str(products))
        if isinstance(item, list):
            return [absolute(v) for v in item]
        if isinstance(item, dict):
            return {k: absolute(v) for k, v in item.items()}
        return item

    result = absolute(value)
    targets = []

    def visit(item):
        if isinstance(item, list):
            for value in item:
                visit(value)
        if isinstance(item, dict):
            if "TestBundlePath" in item:
                targets.append(item)
            else:
                for value in item.values():
                    visit(value)

    visit(result)
    if (
        len(targets) != 1
        or Path(targets[0]["TestBundlePath"]).name != "AssistantVoiceTrialUITests.xctest"
    ):
        raise ValueError("The isolated voice scheme must contain exactly its own test target")
    target = targets[0]
    if runner is not None:
        # The signed test-host copy owns the existing app-group entitlement.
        # Keep all its embedded frameworks/test paths within that retained copy.
        previous = Path(target["TestHostPath"])
        if previous.name != "AssistantVoiceTrialUITests-Runner.app":
            raise ValueError("Unexpected isolated test host")

        def relocate(item):
            if isinstance(item, str) and (
                item == str(previous) or item.startswith(str(previous) + "/")
            ):
                return str(runner) + item[len(str(previous)) :]
            if isinstance(item, list):
                return [relocate(v) for v in item]
            if isinstance(item, dict):
                return {k: relocate(v) for k, v in item.items()}
            return item

        relocated = relocate(target)
        target.clear()
        target.update(relocated)
    target["UITargetAppPath"] = str(app)
    target["DependentProductPaths"] = [
        str(app) if Path(p).name == app.name else p for p in target.get("DependentProductPaths", [])
    ]
    target["EnvironmentVariables"] = {
        **target.get("EnvironmentVariables", {}),
        "REHA_ASSISTANT_VOICE_RUN_ID": identifier,
        "REHA_ASSISTANT_VOICE_MODEL": identity,
    }
    return result


def verify_build(receipt, root=ROOT):
    manifest = receipt["trial_manifest"]
    registry_path = root / "ml/registry/assistant-development-002.json"
    registry = json.loads(registry_path.read_text())
    artifact = registry["artifact"]
    app = root / receipt["app"]
    if (
        receipt.get("qualified") is not False
        or registry.get("qualified") is not False
        or registry["id"] != "assistant-development-002"
        or manifest["model_id"] != registry["id"]
        or manifest["registry_sha256"] != sha(registry_path)
        or manifest["model_sha256"] != artifact["sha256"]
        or manifest["model_bytes"] != artifact["bytes"]
        or sha(app / "Termine.debug.dylib") != receipt["app_binary_sha256"]
    ):
        raise ValueError("Build receipt does not bind the exact unqualified development-002 app")
    if (
        json.loads((app / "assistant-trial/manifest.json").read_text()) != manifest
        or sha(app / "assistant-trial/assistant.gguf") != artifact["sha256"]
        or (app / "assistant-trial/assistant.gguf").stat().st_size != artifact["bytes"]
    ):
        raise ValueError("Bundled model differs from the registered artifact")
    for name, digest in {
        **receipt["sources"],
        **{"ml/registry/assistant-development-002.json": manifest["registry_sha256"]},
    }.items():
        if sha(root / name) != digest:
            raise ValueError(f"Compiled app source changed: {name}")
    tests = receipt["voice_ui_tests"]
    if (
        tests["scheme"] != "AssistantVoiceTrial"
        or sha(root / tests["xctestrun"]) != tests["xctestrun_sha256"]
        or product_generation.inventory(root / tests["runner"]) != tests["runner_inventory"]
    ):
        raise ValueError("Isolated UI test product changed")
    return app, f"{registry['id']}/{artifact['sha256']}/{manifest['native_identity']}"


def execute_tests(command, log, descriptor):
    environment = dict(os.environ, **{product_generation.LEASE_DESCRIPTOR: str(descriptor)})
    with log.open("x") as stream:
        process = subprocess.Popen(
            command,
            cwd=ROOT,
            env=environment,
            pass_fds=(descriptor,),
            stdout=stream,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            return process.wait(timeout=1800)
        except BaseException:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--source-commit", required=True)
    args = parser.parse_args()
    os.umask(0o077)
    destination = args.run.resolve()
    if not destination.is_relative_to(ROOT / ".local/runs") or destination.exists():
        raise ValueError("Use a new private directory below .local/runs")
    if run(["git", "rev-parse", "HEAD"]) != args.source_commit or run(
        ["git", "status", "--porcelain"]
    ):
        raise ValueError("Select the exact clean final source commit before execution")
    with product_generation.leased(ROOT) as (_, descriptor):
        capacity = product_generation.artifacts.space(ROOT, 24)
        selected = disposable(args.simulator, run)
        receipt_path = ROOT / ".local/builds/assistant-app-trial/verification.json"
        receipt = load_report(receipt_path)
        app, identity = verify_build(receipt)
        if receipt["source_revision"] != args.source_commit:
            raise ValueError("Build the selected final commit first")
        names = run(
            [
                "git",
                "ls-files",
                "--",
                "ml/evaluation/conversation",
                "ml/evaluation/device",
                "tooling/build",
                "tooling/dev",
                "tooling/checks/ui-test-result.py",
                "tooling/utils/xcresult.py",
                "tooling/utils/apfs_clone.py",
                "config/storage",
                "pyproject.toml",
                "uv.lock",
                "ml/registry/assistant-development-002.json",
            ]
        ).splitlines()
        sources = {**receipt["sources"], **{name: sha(ROOT / name) for name in names}}
        identifier = str(uuid.uuid4())
        destination.mkdir(parents=True, exist_ok=False)
        write(destination / "build-receipt.json", receipt)
        report = {
            "stage": "prepared",
            "run_id": identifier,
            "model_identity": identity,
            "qualified": False,
            "full_voice_workflow": False,
            "source_commit": args.source_commit,
            "sources": sources,
            "space": capacity,
            "simulator": selected,
            "build_receipt_sha256": sha(receipt_path),
            "predeclared_cases": CASES,
            "predeclared_utterances": [QUERY, ROOM, CREATE, RENAME],
            "executed": False,
            "python": {"executable": sys.executable, "version": sys.version},
        }
        write(destination / "report.json", report)
        try:
            staged = destination / app.name
            signed_copy(
                app,
                staged,
                run,
                expected_files={
                    "Termine.debug.dylib": receipt["app_binary_sha256"],
                    "assistant-trial/assistant.gguf": receipt["trial_manifest"]["model_sha256"],
                },
            )
            tests = receipt["voice_ui_tests"]
            runner_source = ROOT / tests["runner"]
            runner = destination / runner_source.name
            clone(runner_source, runner)
            if product_generation.inventory(runner) != tests["runner_inventory"]:
                raise ValueError("Cloned runner differs from the verified build receipt")
            run(["xattr", "-cr", str(runner)])
            run(
                [
                    "codesign",
                    "--force",
                    "--sign",
                    "-",
                    "--entitlements",
                    str(ROOT / "apps/ios/App/Termine.entitlements"),
                    str(runner),
                ]
            )
            run(["xcrun", "simctl", "install", args.simulator, str(staged)], timeout=120)
            run(["xcrun", "simctl", "privacy", args.simulator, "grant", "calendar", BUNDLE])
            container = Path(
                run(["xcrun", "simctl", "get_app_container", args.simulator, BUNDLE, "data"])
            )
            original = ROOT / tests["xctestrun"]
            patched = patch_xctestrun(
                plistlib.loads(original.read_bytes()),
                original.parent,
                staged,
                identifier,
                identity,
                runner,
            )
            xctestrun = destination / "AssistantVoiceTrial.xctestrun"
            xctestrun.write_bytes(plistlib.dumps(patched))
            command = [
                sys.executable,
                "tooling/checks/ui-test-result.py",
                "run",
                "-xctestrun",
                str(xctestrun),
                "-destination",
                f"platform=iOS Simulator,id={args.simulator}",
                "-parallel-testing-enabled",
                "NO",
                "-resultBundlePath",
                str(destination / "result.xcresult"),
                *["-only-testing:" + name for name in TESTS],
            ]
            report.update(
                stage="executing",
                executed=True,
                command=command,
                patched_xctestrun_sha256=sha(xctestrun),
            )
            write(destination / "report.json", report)
            try:
                report["exit_code"] = execute_tests(command, destination / "xctest.log", descriptor)
            finally:
                try:
                    run(["xcrun", "simctl", "terminate", args.simulator, BUNDLE], timeout=30)
                except (OSError, subprocess.SubprocessError) as error:
                    write(destination / "cleanup-warning.json", {"error": str(error)})
                observations, missing, digests = collect_observations(
                    container, destination, identifier
                )
                report.update(missing_observations=missing, observation_sha256=digests)
            verification_path = destination / "result.xcresult.verification/verification.json"
            verification = load_report(verification_path) if verification_path.exists() else {}
            report.update(grade(observations, verification, identifier, identity))
            report["passed"] &= report["exit_code"] == 0
            report.update(
                stage="development_evaluated",
            )
            if (
                any(sha(ROOT / name) != digest for name, digest in sources.items())
                or sha(receipt_path) != report["build_receipt_sha256"]
            ):
                raise ValueError("Source/build identity changed during the trial")
            report["sources_unchanged"] = True
        except BaseException as error:
            report.update(stage="failed", passed=False, error=f"{type(error).__name__}: {error}")
            raise
        finally:
            write(destination / "report.json", report)
            try:
                run(["xcrun", "simctl", "terminate", args.simulator, BUNDLE], timeout=30)
            except (OSError, subprocess.SubprocessError) as error:
                write(destination / "cleanup-warning.json", {"error": str(error)})
        if not report["passed"]:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
