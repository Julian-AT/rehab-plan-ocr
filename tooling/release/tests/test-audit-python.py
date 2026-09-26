"""Synthetic OSV snapshots prove complete retrieval, privacy and offline replay integrity."""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "audit_python", Path(__file__).parents[1] / "audit_python.py"
)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)
MODIFIED = "2026-09-21T10:00:00Z"


def stub(key):
    return {"id": key, "modified": MODIFIED}


def advisory(key, *, withdrawn=False):
    result = {
        "id": key,
        "modified": MODIFIED,
        "schema_version": "1.7.3",
        "aliases": ["CVE-2026-0001"],
        "details": "Invented full advisory content",
        "affected": [
            {"package": {"ecosystem": "PyPI", "name": name}, "versions": [version]}
            for name, version in [("alpha-pkg", "1.0"), ("beta", "2.0")]
        ],
    }
    if withdrawn:
        result.update(withdrawn=MODIFIED, aliases=["CVE-2026-0002"], affected=[])
    return result


class AuditPython(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        for i, name in enumerate(audit.LOCKFILES):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                'version = 1\nrevision = 3\nrequires-python = ">=3.12"\n'
                "resolution-markers = [\"sys_platform == 'darwin'\"]\n"
                '[[package]]\nname = "Alpha_Pkg"\nversion = "1.0"\n'
                'source = { registry = "https://pypi.org/simple" }\n'
                'dependencies = [{ name = "beta", marker = "python_version < \'3.13\'" }]\n'
                '[[package]]\nname = "private-secret-project"\nversion = "0.1"\nsource = { virtual = "." }\n'
                + (
                    '[[package]]\nname = "beta"\nversion = "2.0"\nsource = { registry = "https://pypi.org/simple" }\n'
                    if i == 4
                    else ""
                )
            )
        self.snapshot = self.root / ".local/audits/snapshot"
        self.output = self.root / ".local/audits/offline"
        self.calls = []
        self.override = None

    def response(self, method, endpoint, body):
        if method == "GET":
            key = endpoint.rsplit("/", 1)[1]
            return advisory(key, withdrawn=key == "OSV-WITHDRAWN")
        queries = json.loads(body)["queries"]
        if len(queries) == 2:
            return {
                "results": [
                    {"vulns": [stub("GHSA-AAAA")], "next_page_token": "alpha-page-2"},
                    {"vulns": [stub("PYSEC-AAAA")]},
                ]
            }
        self.assertEqual(
            queries,
            [
                {
                    "package": {"ecosystem": "PyPI", "name": "alpha-pkg"},
                    "version": "1.0",
                    "page_token": "alpha-page-2",
                }
            ],
        )
        return {"results": [{"vulns": [stub("OSV-WITHDRAWN")]}]}

    def transport(self, method, endpoint, body, destination, bound):
        self.calls.append((method, endpoint, body))
        value = (
            self.override(method, endpoint, body)
            if self.override
            else self.response(method, endpoint, body)
        )
        audit.write(destination, audit.encoded(value))

    def download(self):
        return audit.download(self.snapshot, self.root, self.transport)

    def receipt_hash(self):
        return audit.sha((self.snapshot / "receipt.json").read_bytes())

    def replay(self, output=None):
        with patch.object(
            audit.http.client,
            "HTTPSConnection",
            side_effect=AssertionError("offline opened network"),
        ):
            return audit.offline(
                self.snapshot, self.receipt_hash(), output or self.output, self.root
            )

    def resign(self):
        """Even a caller explicitly accepting a changed receipt cannot bypass semantic replay."""
        path = self.snapshot / "receipt.json"
        value = json.loads(path.read_text())
        value["files"] = audit.file_manifest(self.snapshot)
        path.write_bytes(audit.encoded(value))

    def test_all_five_locks_deduplicate_pypi_but_keep_markers_and_virtual_exclusions(self):
        index = audit.inventory(audit.inputs_now(self.root))
        self.assertEqual(
            [(p["name"], p["version"]) for p in index["packages"]],
            [("alpha-pkg", "1.0"), ("beta", "2.0")],
        )
        self.assertEqual(len(index["packages"][0]["occurrences"]), 5)
        self.assertEqual(len(index["excluded_virtual"]), 5)
        self.assertIn("resolution-markers", index["lock_context"][audit.LOCKFILES[1]])
        self.assertIn(
            "marker", index["packages"][0]["occurrences"][0]["context"]["dependencies"][0]
        )

    def test_complete_pages_full_advisories_alias_groups_and_private_payload_boundary(self):
        receipt = self.download()
        self.assertTrue(receipt["completed"])
        self.assertEqual(len(self.calls), 5)
        for method, endpoint, body in self.calls:
            if method == "POST":
                for query in json.loads(body)["queries"]:
                    self.assertLessEqual(set(query), {"package", "version", "page_token"})
                    self.assertEqual(set(query["package"]), {"name", "ecosystem"})
                self.assertNotIn(b"private-secret", body)
                self.assertNotIn(str(self.root).encode(), body)
                self.assertNotIn(b"uv.lock", body)
        report = self.replay()
        self.assertTrue(report["complete"])
        self.assertFalse(report["passed"])
        self.assertFalse(report["qualified"])
        self.assertEqual(report["status"], "complete-with-findings")
        self.assertEqual(report["counts"]["active_vulnerability_groups"], 1)
        self.assertEqual(report["counts"]["active_affected_package_versions"], 2)
        self.assertEqual(report["counts"]["advisory_records"], 3)
        self.assertEqual(report["counts"]["withdrawn_records"], 1)
        self.assertEqual(report["counts"]["withdrawn_only_groups"], 1)
        self.assertEqual(report["advisories"]["OSV-WITHDRAWN"]["withdrawn"], MODIFIED)
        self.assertEqual(report["advisory_sha256"], receipt["advisory_sha256"])
        again = self.replay(self.root / ".local/audits/offline-again")
        self.assertEqual(report, again)

    def test_empty_results_are_complete_not_fabricated_findings(self):
        self.override = lambda method, endpoint, body: {
            "results": [{} for _ in json.loads(body)["queries"]]
        }
        self.download()
        result = self.replay()
        self.assertTrue(result["passed"])
        self.assertEqual(result["advisories"], {})
        self.assertEqual(result["status"], "complete-no-active-findings")
        self.assertFalse(result["qualified"])

    def test_withdrawn_only_records_remain_visible_without_active_findings(self):
        self.override = lambda method, endpoint, body: (
            advisory("OSV-WITHDRAWN", withdrawn=True)
            if method == "GET"
            else {
                "results": [{"vulns": [stub("OSV-WITHDRAWN")]} for _ in json.loads(body)["queries"]]
            }
        )
        self.download()
        result = self.replay()
        self.assertTrue(result["passed"])
        self.assertEqual(result["counts"]["withdrawn_records"], 1)
        self.assertEqual(result["counts"]["affected_package_versions"], 2)
        self.assertEqual(result["counts"]["active_affected_package_versions"], 0)

    def test_duplicate_json_keys_and_nonfinite_numbers_are_rejected(self):
        for raw in [b'{"results":[],"results":[]}', b'{"value":NaN}', b'{"value":Infinity}']:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                audit.parsed(raw)

    def test_unknown_sources_fail_before_any_network_and_keep_failed_receipt(self):
        lock = self.root / audit.LOCKFILES[0]
        lock.write_text(
            lock.read_text().replace(
                'registry = "https://pypi.org/simple"',
                'registry = "https://private.invalid/simple"',
            )
        )
        with self.assertRaisesRegex(ValueError, "source"):
            self.download()
        self.assertFalse(self.calls)
        self.assertFalse(json.loads((self.snapshot / "receipt.json").read_text())["completed"])
        with self.assertRaisesRegex(ValueError, "incomplete"):
            self.replay()
        self.assertEqual(json.loads((self.output / "report.json").read_text())["status"], "failed")

    def test_missing_lock_and_unknown_source_variants_cannot_be_silently_skipped(self):
        inputs = audit.inputs_now(self.root)
        with self.assertRaises(ValueError):
            audit.inventory({k: v for k, v in inputs.items() if k != audit.LOCKFILES[-1]})
        for source in [
            '{ git = "https://example.invalid/repo" }',
            '{ editable = "." }',
            "{}",
            '{ virtual = "../foreign" }',
        ]:
            changed = dict(inputs)
            changed[audit.LOCKFILES[0]] = changed[audit.LOCKFILES[0]].replace(
                b'{ registry = "https://pypi.org/simple" }', source.encode()
            )
            with self.subTest(source=source), self.assertRaises(ValueError):
                audit.inventory(changed)

    def test_wrong_batch_length_and_unknown_result_keys_are_incomplete(self):
        self.override = lambda *args: {"results": [{}]}
        with self.assertRaisesRegex(ValueError, "length/schema"):
            self.download()
        self.assertFalse(json.loads((self.snapshot / "receipt.json").read_text())["completed"])
        self.snapshot = self.root / ".local/audits/unknown-field"
        self.override = lambda *args: {"results": [{"new_error_field": "unavailable"}, {}]}
        with self.assertRaisesRegex(ValueError, "Unknown"):
            self.download()

    def test_repeating_and_excessive_page_tokens_fail_with_preserved_responses(self):
        self.override = lambda method, endpoint, body: {
            "results": [{"next_page_token": "loop"} for _ in json.loads(body)["queries"]]
        }
        with self.assertRaisesRegex(ValueError, "pagination"):
            self.download()
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(len(list((self.snapshot / "responses").glob("*.json"))), 2)
        self.snapshot = self.root / ".local/audits/page-limit"
        self.calls.clear()
        self.override = lambda method, endpoint, body: {
            "results": [
                {"next_page_token": str(len(self.calls))} for _ in json.loads(body)["queries"]
            ]
        }
        with (
            patch.dict(audit.LIMITS, pages_per_query=2),
            self.assertRaisesRegex(ValueError, "pagination"),
        ):
            self.download()
        self.assertEqual(len(self.calls), 2)

    def test_incorrect_full_id_modified_or_package_order_cannot_pass(self):
        for field in ["id", "modified", "affected", "unknown"]:
            self.snapshot = self.root / (".local/audits/bad-" + field)

            def response(method, endpoint, body):
                value = self.response(method, endpoint, body)
                if method == "GET":
                    value[field] = {
                        "id": "WRONG",
                        "modified": "2026-09-22T10:00:00Z",
                        "affected": [{"package": {"ecosystem": "PyPI", "name": "other"}}],
                        "unknown": True,
                    }[field]
                return value

            self.override = response
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.download()
            self.assertFalse(json.loads((self.snapshot / "receipt.json").read_text())["completed"])

    def test_partial_failure_retains_request_response_and_incomplete_status(self):
        def failed(method, endpoint, body, path, bound):
            audit.write(path, b'{"results":')
            raise TimeoutError("invented socket deadline")

        with self.assertRaises(TimeoutError):
            audit.download(self.snapshot, self.root, failed)
        receipt = json.loads((self.snapshot / "receipt.json").read_text())
        self.assertIn("TimeoutError", receipt["error"])
        self.assertFalse(receipt["completed"])
        self.assertEqual((self.snapshot / "responses/0000.json").read_bytes(), b'{"results":')

    def test_original_snapshot_hash_and_each_response_are_verified_offline(self):
        self.download()
        with self.assertRaisesRegex(ValueError, "expected hash"):
            audit.offline(self.snapshot, "0" * 64, self.output, self.root)
        path = self.snapshot / "responses/0000.json"
        path.write_bytes(path.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "files changed"):
            self.replay(self.root / ".local/audits/tampered")

    def test_special_file_cannot_be_ignored_by_snapshot_closure(self):
        self.download()
        os.mkfifo(self.snapshot / "unexpected-pipe")
        with self.assertRaisesRegex(ValueError, "non-regular"):
            self.replay()

    def test_source_binding_and_changes_during_offline_classification_fail_closed(self):
        self.download()
        original_read = audit.read

        def changed_source(path, *args):
            value = original_read(path, *args)
            return value + b"\n# changed" if path == Path(audit.__file__) else value

        with (
            patch.object(audit, "read", side_effect=changed_source),
            self.assertRaisesRegex(ValueError, "identity"),
        ):
            self.replay()
        original_findings = audit.findings

        def mutate(*args):
            value = original_findings(*args)
            path = self.snapshot / "responses/0000.json"
            path.write_bytes(path.read_bytes() + b" ")
            return value

        with (
            patch.object(audit, "findings", side_effect=mutate),
            self.assertRaisesRegex(ValueError, "changed during"),
        ):
            self.replay(self.root / ".local/audits/changed-during")
        report = json.loads((self.root / ".local/audits/changed-during/report.json").read_text())
        self.assertFalse(report["complete"])
        self.assertFalse(report["passed"])

    def test_total_response_bound_preserves_incomplete_evidence(self):
        with (
            patch.dict(audit.LIMITS, total_response_bytes=1),
            self.assertRaisesRegex(ValueError, "byte limit"),
        ):
            self.download()
        receipt = json.loads((self.snapshot / "receipt.json").read_text())
        self.assertFalse(receipt["completed"])
        self.assertIn("responses/0000.json", receipt["files"])

    def test_resigned_wrong_query_order_and_extra_file_are_rejected(self):
        self.download()
        path = self.snapshot / "requests/0000.json"
        value = json.loads(path.read_text())
        value["body"]["queries"].reverse()
        path.write_bytes(audit.encoded(value))
        self.resign()
        with self.assertRaisesRegex(ValueError, "ordering"):
            self.replay()
        path.write_bytes(
            audit.encoded(
                {
                    "method": "POST",
                    "endpoint": "/v1/querybatch",
                    "body": {
                        "queries": [
                            {
                                "package": {"ecosystem": "PyPI", "name": "alpha-pkg"},
                                "version": "1.0",
                            },
                            {"package": {"ecosystem": "PyPI", "name": "beta"}, "version": "2.0"},
                        ]
                    },
                }
            )
        )
        audit.write(self.snapshot / "extra/receipt.json", b"{}")
        self.resign()
        with self.assertRaisesRegex(ValueError, "closure"):
            self.replay(self.root / ".local/audits/extra-file")

    def test_live_lock_change_during_download_or_before_replay_is_rejected(self):
        changed = self.root / audit.LOCKFILES[0]

        def mutate(method, endpoint, body):
            value = self.response(method, endpoint, body)
            if method == "GET":
                changed.write_text(changed.read_text() + "\n# changed\n")
            return value

        self.override = mutate
        with self.assertRaisesRegex(ValueError, "changed"):
            self.download()
        self.snapshot = self.root / ".local/audits/completed"
        self.override = None
        self.download()
        changed.write_text(changed.read_text() + "\n# later\n")
        with self.assertRaisesRegex(ValueError, "identity"):
            self.replay()

    def test_output_reuse_symlinks_and_outside_paths_preserve_old_bytes(self):
        self.download()
        before = (self.snapshot / "receipt.json").read_bytes()
        with self.assertRaises(FileExistsError):
            self.download()
        with self.assertRaisesRegex(ValueError, "inside an existing"):
            audit.download(self.snapshot / "nested", self.root, self.transport)
        self.assertFalse((self.snapshot / "nested").exists())
        alias = self.root / ".local/audits/alias"
        alias.symlink_to(self.snapshot, target_is_directory=True)
        with self.assertRaises(ValueError):
            audit.download(alias, self.root, self.transport)
        with self.assertRaises(ValueError):
            audit.download(self.root / "outside", self.root, self.transport)
        self.assertEqual((self.snapshot / "receipt.json").read_bytes(), before)

    def test_offline_cli_exit_codes_separate_findings_from_failure(self):
        self.download()
        base = [
            sys.executable,
            str(Path(audit.__file__)),
            "--root",
            str(self.root),
            "offline",
            "--snapshot",
            str(self.snapshot),
        ]
        found = subprocess.run(
            [*base, "--snapshot-sha256", self.receipt_hash(), "--output", str(self.output)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(found.returncode, 1, found.stderr)
        self.assertTrue(json.loads(found.stdout)["complete"])
        failed = subprocess.run(
            [
                *base,
                "--snapshot-sha256",
                "0" * 64,
                "--output",
                str(self.output.with_name("failed")),
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(failed.returncode, 2)
        self.assertIn("incomplete", failed.stderr)


class NetworkBounds(unittest.TestCase):
    def exercise(
        self, raw, *, status=200, limit=100, expected_length=None, times=None, incomplete=False
    ):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        destination = Path(temporary.name) / "response.json"

        class Socket:
            def settimeout(self, value):
                self.timeout = value

        class Response:
            def __init__(self):
                self.offset = 0
                self.status = status

            def getheader(self, name):
                return expected_length

            def isclosed(self):
                return self.offset == len(raw)

            def read1(self, length):
                chunk = raw[self.offset : self.offset + length]
                self.offset += len(chunk)
                if incomplete:
                    raise audit.http.client.IncompleteRead(chunk, 100)
                return chunk

        class Connection:
            sock = Socket()
            closed = False

            def connect(self):
                pass

            def request(self, *args, **kwargs):
                self.requested = (args, kwargs)

            def getresponse(self):
                return Response()

            def close(self):
                self.closed = True

        connection = Connection()
        with patch.object(audit.http.client, "HTTPSConnection", return_value=connection) as connect:
            timer = (
                patch.object(audit.time, "monotonic", side_effect=times)
                if times
                else patch.object(audit.time, "monotonic", return_value=0)
            )
            with timer:
                try:
                    audit.http_request(
                        "POST", "/v1/querybatch", b'{"queries": []}', destination, limit
                    )
                finally:
                    self.assertTrue(connection.closed)
                    connect.assert_called_once_with("api.osv.dev", timeout=30)
                    if incomplete:
                        self.assertEqual(destination.read_bytes(), raw)
        return destination, connection

    def test_exact_response_boundary_and_no_credentials(self):
        path, connection = self.exercise(b"{}", limit=2, expected_length="2")
        self.assertEqual(path.read_bytes(), b"{}")
        self.assertNotIn("Authorization", connection.requested[1]["headers"])

    def test_oversized_response_http_error_and_truncation_are_not_success(self):
        for options in [
            {"raw": b"123", "limit": 2},
            {"raw": b"{}", "status": 429},
            {"raw": b"{}", "expected_length": "3"},
        ]:
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.exercise(**options)

    def test_deadline_expiry_stops_before_request_and_closes_connection(self):
        with self.assertRaises(TimeoutError):
            self.exercise(b"{}", times=[0, 31])

    def test_incomplete_http_body_retains_exception_partial_bytes(self):
        with self.assertRaises(audit.http.client.IncompleteRead):
            self.exercise(b'{"results":', incomplete=True)

    def test_blocking_transport_worker_is_reaped_and_partial_bytes_survive(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            worker = path / "fake-http.py"
            worker.write_text(
                "import os, sys, time\n"
                "from pathlib import Path\n"
                "target = Path(sys.argv[4])\n"
                "target.write_bytes(b'partial')\n"
                "target.with_suffix('.pid').write_text(str(os.getpid()))\n"
                "time.sleep(30)\n"
            )
            output = path / "response.json"
            with (
                patch.object(audit, "__file__", str(worker)),
                patch.dict(audit.LIMITS, request_seconds=0.5),
                self.assertRaises(TimeoutError),
            ):
                audit.network("POST", "/v1/querybatch", b"{}", output, 100)
            self.assertEqual(output.read_bytes(), b"partial")
            pid = int(output.with_suffix(".pid").read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)

    def test_transport_worker_failure_propagates_without_erasing_response(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            worker = path / "fake-http.py"
            worker.write_text(
                "import sys\n"
                "from pathlib import Path\n"
                "Path(sys.argv[4]).write_bytes(b'partial')\n"
                "print('controlled failure', file=sys.stderr)\n"
                "raise SystemExit(7)\n"
            )
            output = path / "response.json"
            with (
                patch.object(audit, "__file__", str(worker)),
                self.assertRaisesRegex(ValueError, "controlled failure"),
            ):
                audit.network("POST", "/v1/querybatch", b"{}", output, 100)
            self.assertEqual(output.read_bytes(), b"partial")


if __name__ == "__main__":
    unittest.main()
