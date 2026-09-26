"""The app's native decoder and model evaluation share compact-schema examples."""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from ml.evaluation.conversation.intent import InvalidIntent, parse  # noqa: E402


class NativeContractTests(unittest.TestCase):
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
