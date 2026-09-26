"""Token diagnosis must compare one identical context and preserve EOS evidence."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from token_parity import (
    cli_token_ids,
    first_difference,
    forced_request,
    historical_file_command,
    restore_mlx,
    reusable_worker_source,
    sha,
    validate_requests,
)


class TokenParityTests(unittest.TestCase):
    def test_resume_requires_identical_models_requests_and_complete_worker_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            previous = root / ".local/runs/previous"
            (previous / "mlx").mkdir(parents=True)
            current = root / "token_parity.py"
            names = ["sha", "save", "validate_requests", "rankings", "mlx_worker"]
            worker = "\n".join(f"def {name}():\n    return 1\n" for name in names)
            current.write_text(worker + "\ndef diagnose():\n    return 2\n")
            (previous / "token_parity.py").write_text(worker)
            model = root / "weights"
            model.write_bytes(b"unchanged synthetic fixture")
            sources = {str(current): sha(previous / "token_parity.py"), str(model): sha(model)}
            (previous / "sources.json").write_text(json.dumps({"sources": sources}))
            requests = [{"id": "0000", "prompt": "fixture", "max_tokens": 3}]
            (previous / "requests.json").write_text(json.dumps(requests))
            (previous / "mlx/report.json").write_text(json.dumps({"cases": [{"id": "0000"}]}))
            identities = {str(current): sha(current), str(model): sha(model)}
            with (
                mock.patch("token_parity.ROOT", root),
                mock.patch("token_parity.__file__", str(current)),
            ):
                output = root / "valid"
                output.mkdir()
                accepted = dict(identities)
                result = restore_mlx(previous, output, accepted, requests)
                self.assertEqual(result["reused_from"], str(previous / "mlx/report.json"))
                self.assertIn(str(previous / "mlx/report.json"), accepted)
                self.assertTrue((output / "mlx/report.json").is_file())
                for changed, selected in [
                    ({**identities, str(model): "changed"}, requests),
                    (identities, [{**requests[0], "max_tokens": 4}]),
                ]:
                    with self.assertRaises(ValueError):
                        restore_mlx(previous, root / "rejected", dict(changed), selected)
                (previous / "mlx/report.json").write_text(json.dumps({"cases": []}))
                with self.assertRaisesRegex(ValueError, "did not finish"):
                    restore_mlx(previous, root / "incomplete", dict(identities), requests)

    def test_reuse_rejects_changed_worker_or_helpers_but_allows_orchestration_changes(self):
        names = ["sha", "save", "validate_requests", "rankings", "mlx_worker"]
        source = "\n".join(f"def {name}():\n    return 1\n" for name in names)
        reusable_worker_source(source, source + "\ndef diagnose():\n    return 2\n")
        for changed in [
            source.replace("return 1", "return 2", 1),
            source.replace("def rankings", "def other"),
        ]:
            with self.assertRaises(ValueError):
                reusable_worker_source(source, changed)

    def test_request_envelope_bounds_cases_tokens_and_private_file_identifiers(self):
        case = {"id": "0011", "prompt": "retained.prompt", "max_tokens": 192}
        validate_requests([case])
        for invalid in [
            [],
            [{**case, "id": str(i)} for i in range(41)],
            [case, case],
            [{**case, "id": "../old"}],
            [{**case, "max_tokens": 257}],
        ]:
            with self.assertRaises(ValueError):
                validate_requests(invalid)

    def test_cli_input_checks_token_identity_not_only_equal_count(self):
        full = "main: number of tokens in prompt = 3\n 151668 -> '</think>'\n 271 -> '\n\n'\n 9 -> 'x'\n"
        self.assertEqual(cli_token_ids(full), [151668, 271, 9])
        self.assertNotEqual(cli_token_ids(full), cli_token_ids(full.replace("271", "198")))
        for invalid in ["", full.replace(" = 3", " = 4"), full + "1 -> 'extra'\n"]:
            with self.assertRaises(ValueError):
                cli_token_ids(invalid)

    def test_pinned_info_timestamps_do_not_hide_actual_token_ids(self):
        recorded = (
            "0.00.484.224 I llama_completion: number of tokens in prompt = 3\n"
            "0.00.484.224 I 151668 -> '</think>'\n"
            "0.00.484.225 I    271 -> '\n\n'\n"
            "0.00.484.226 I      9 -> 'x'\n"
        )
        self.assertEqual(cli_token_ids(recorded), [151668, 271, 9])
        self.assertEqual(cli_token_ids(recorded.replace("0.00.484.224 ", "")), [151668, 271, 9])
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            cli_token_ids(recorded.replace("271 ->", "lost ->"))

    def test_historical_counterfactual_cannot_mutate_the_corrected_command(self):
        original = ["cli", "--binary-file", "file", "--no-escape", "--temp", "0"]
        self.assertEqual(historical_file_command(original), ["cli", "-f", "file", "--temp", "0"])
        self.assertEqual(original[1:4], ["--binary-file", "file", "--no-escape"])

    def test_forced_request_stops_exactly_at_the_compared_token(self):
        case = {"id": "0011", "prompt": "retained.prompt", "max_tokens": 3, "prefix": [7, 8]}
        validate_requests([case])
        for invalid in [
            {**case, "max_tokens": 4},
            {**case, "prefix": [7, -1]},
            {**case, "prefix": [7, True]},
        ]:
            with self.assertRaises(ValueError):
                validate_requests([invalid])

    def test_first_token_difference_is_not_a_later_text_edit(self):
        self.assertEqual(first_difference([1, 2, 3, 4], [1, 7, 3, 9]), 1)
        self.assertEqual(first_difference([1], [1, 2]), 1)
        self.assertIsNone(first_difference([1, 2], [1, 2]))

    def test_forcing_keeps_only_the_shared_prefix_without_mutating_sources(self):
        request = {"id": "0011", "prompt": "retained.prompt", "max_tokens": 192}
        left = {"input_tokens": [10, 11], "tokens": [1, 2, 3, 99]}
        right = {"input_tokens": [10, 11], "tokens": [1, 2, 7, 99]}
        before = copy.deepcopy((request, left, right))
        self.assertEqual(
            forced_request(request, left, right),
            {"id": "0011", "prompt": "retained.prompt", "prefix": [1, 2], "max_tokens": 3},
        )
        self.assertEqual((request, left, right), before)

    def test_changed_prompt_or_missing_stop_token_cannot_be_hidden_by_forcing(self):
        request = {"id": "0001", "prompt": "a", "max_tokens": 192}
        left = {"input_tokens": [10], "tokens": [1, 2]}
        for right in [
            {"input_tokens": [11], "tokens": [1, 3]},
            {"input_tokens": [10], "tokens": [1, 2]},
            {"input_tokens": [10], "tokens": [1, 2, 3]},
        ]:
            with self.assertRaises(ValueError):
                forced_request(request, left, right)

    def test_first_token_disagreement_has_an_empty_generated_prefix(self):
        result = forced_request(
            {"id": "0001", "max_tokens": 192},
            {"input_tokens": [10], "tokens": [99]},
            {"input_tokens": [10], "tokens": [7, 99]},
        )
        self.assertEqual(result["prefix"], [])
        self.assertEqual(result["max_tokens"], 1)


if __name__ == "__main__":
    unittest.main()
