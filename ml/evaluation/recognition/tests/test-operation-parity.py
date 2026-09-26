"""Intermediate diagnostics preserve the original graph and never renumber its operations."""

import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from operation_parity import first_differences, instrument_pir


def value(index):
    return {"%": index, "TT": {"#": "0.t_dtensor", "D": [{"#": "0.t_f32"}, [1, 3, 48, -1]]}}


def graph():
    operations = [
        {"#": "p", "A": [0, 1, 1, "weight"], "O": value(1)},
        {"#": "1.data", "O": [value(2)]},
        {"#": "1.conv2d", "I": [{"%": 2}, {"%": 1}], "O": [value(3)]},
        {"#": "1.conv2d", "I": [{"%": 3}, {"%": 1}], "O": [value(4)]},
        {
            "#": "1.fetch",
            "I": [{"%": 4}],
            "O": [value(5)],
            "A": [
                {"N": "name", "AT": {"#": "0.a_str", "D": "fetch_name_0"}},
                {"N": "col", "AT": {"#": "0.a_i32", "D": 0}},
            ],
        },
    ]
    return {
        "base_code": {"magic": "pir", "trainable": True, "version": 4},
        "program": {"regions": [{"blocks": [{"ops": operations}]}]},
    }


class OperationParityTests(unittest.TestCase):
    def test_fetches_are_appended_without_changing_source_or_original_operators(self):
        source = graph()
        before = copy.deepcopy(source)
        copied, aligned, missing = instrument_pir(
            source, {"p2o.pd_op.conv2d.0.0", "p2o.pd_op.conv2d.1.0"}
        )
        self.assertEqual(source, before)
        ops = copied["program"]["regions"][0]["blocks"][0]["ops"]
        self.assertEqual(ops[:5], source["program"]["regions"][0]["blocks"][0]["ops"])
        self.assertEqual([r["value_id"] for r in aligned], [3, 4])
        self.assertEqual([op["O"][0]["%"] for op in ops[5:]], [6, 7])
        self.assertEqual([op["I"][0]["%"] for op in ops[5:]], [3, 4])
        self.assertEqual([op["A"][1]["AT"]["D"] for op in ops[5:]], [1, 2])
        self.assertEqual(missing, [])

    def test_batched_output_keeps_original_exporter_ordinal(self):
        _, aligned, missing = instrument_pir(graph(), {"p2o.pd_op.conv2d.1.0"})
        self.assertEqual(len(aligned), 1)
        self.assertEqual(aligned[0]["value_id"], 4)
        self.assertEqual(aligned[0]["input_ids"], [3, 1])
        self.assertEqual(missing, [{"program_index": 2, "name": "p2o.pd_op.conv2d.0.0"}])

    def test_unknown_serialization_or_control_flow_fails_closed(self):
        for changed in ["version", "region", "fetch"]:
            source = graph()
            if changed == "version":
                source["base_code"]["version"] = 5
            elif changed == "region":
                source["program"]["regions"].append({"blocks": []})
            else:
                source["program"]["regions"][0]["blocks"][0]["ops"].pop()
            with self.assertRaises(ValueError):
                instrument_pir(source, {"p2o.pd_op.conv2d.0.0"})
        with self.assertRaises(ValueError):
            instrument_pir(graph(), set())

    def test_first_rounding_difference_is_distinct_from_tolerance_failure(self):
        rows = [
            {"name": "exact", "bitwise_equal": True, "allclose": True},
            {"name": "rounded", "bitwise_equal": False, "allclose": True},
            {"name": "failed", "bitwise_equal": False, "allclose": False},
        ]
        found = first_differences(rows)
        self.assertEqual(found["first_bit_difference"]["name"], "rounded")
        self.assertEqual(found["first_outside_tolerance"]["name"], "failed")
        self.assertEqual(
            first_differences(rows[:1]),
            {"first_bit_difference": None, "first_outside_tolerance": None},
        )


if __name__ == "__main__":
    unittest.main()
