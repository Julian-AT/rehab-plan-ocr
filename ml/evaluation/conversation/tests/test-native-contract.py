"""The app's native decoder and model evaluation share compact-schema examples."""

import ast
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.conversation.intent import InvalidIntent, parse  # noqa: E402


class NativeContractTests(unittest.TestCase):
    def test_app_prompt_matches_pinned_training_template(self):
        root = Path(__file__).resolve().parents[4]
        module = ast.parse((root / "ml/training/assistant/contract.py").read_text())
        system = next(
            ast.literal_eval(node.value)
            for node in module.body
            if isinstance(node, ast.Assign)
            and any(isinstance(t, ast.Name) and t.id == "SYSTEM" for t in node.targets)
        )
        self.assertEqual(
            (root / "apps/ios/Features/Conversation/Resources/assistant-system-v1.txt").read_text(),
            system,
        )
        fixture = json.loads((Path(__file__).parents[1] / "fixtures/prompt-v1.json").read_text())
        expected = (
            "<|im_start|>system\n"
            + system
            + "<|im_end|>\n<|im_start|>user\n"
            + json.dumps(fixture["model_context"], ensure_ascii=False, sort_keys=True)
            + "\n"
            + fixture["utterance"]
            + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        )
        self.assertEqual(fixture["expected_prompt"], expected)

    def test_same_acceptance_contract_as_native_decoder(self):
        cases = json.loads(
            (Path(__file__).parents[1] / "fixtures/native-contract.json").read_text()
        )
        for case in cases:
            with self.subTest(case=case["id"]):
                try:
                    parse(case["json"], references=case["references"])
                    accepted = True
                except InvalidIntent:
                    accepted = False
                self.assertEqual(accepted, case["valid"])


if __name__ == "__main__":
    unittest.main()
