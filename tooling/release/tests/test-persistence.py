"""Offline release comparison preserves original backups and detects data loss."""

import json
import plistlib
import shutil
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import persistence  # noqa: E402


def fixture(root):
    for name in (
        "App/Documents",
        "AgendaGroup",
        "IntakeGroup",
        persistence.SUPPORT,
        persistence.PREFERENCES.parent,
    ):
        (root / name).mkdir(parents=True, exist_ok=True)
    (root / persistence.PREFERENCES).write_bytes(
        plistlib.dumps({"existing": "preserve", "enabled": True})
    )
    (root / "App/Documents/source.pdf").write_bytes(b"invented PDF fixture")
    (root / "AgendaGroup/pending.json").write_text('{"operation":"invented-pending"}')
    (root / "IntakeGroup/source.bin").write_bytes(b"invented source")
    database = root / persistence.SUPPORT / "ledger.sqlite"
    with sqlite3.connect(database) as connection:
        for table in sorted(persistence.NATIVE_TABLES):
            connection.execute(f'CREATE TABLE "{table}" (id TEXT PRIMARY KEY, value TEXT)')
            connection.execute(f'INSERT INTO "{table}" VALUES (?,?)', ("one", "invented-value"))
        connection.execute("PRAGMA user_version=8")
    return database


class PersistenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.before = self.root / "before"
        self.db = fixture(self.before)
        self.baseline = persistence.snapshot(self.before)
        self.after = self.root / "after"
        shutil.copytree(self.before, self.after)

    def test_identical_copies_preserve_all_tables_sources_and_journals(self):
        original = persistence.inventory(self.before)
        result = persistence.compare(self.before, self.baseline, self.after)
        self.assertTrue(result["existing_data_preserved"])
        self.assertFalse(result["review_required"])
        self.assertEqual(len(result["original_table_projections_unchanged"]), 15)
        self.assertEqual(result["original_source_files"], 2)
        self.assertFalse(result["device_update_authorized"])
        self.assertEqual(persistence.inventory(self.before), original)

    def test_changed_original_backup_is_rejected(self):
        (self.before / "App/Documents/source.pdf").write_bytes(b"different")
        with self.assertRaisesRegex(ValueError, "Original backup"):
            persistence.compare(self.before, self.baseline, self.after)

    def test_changed_ownership_pending_operation_source_and_preference_are_detected(self):
        for table in (
            "owned_events",
            "operations",
            "event_mutations",
            "plan_acceptances",
            "settings",
        ):
            path = self.after / persistence.SUPPORT / "ledger.sqlite"
            shutil.copyfile(self.db, path)
            with sqlite3.connect(path) as connection:
                connection.execute(f'UPDATE "{table}" SET value=?', ("unexpected",))
            result = persistence.compare(self.before, self.baseline, self.after)
            self.assertFalse(result["existing_data_preserved"], table)
            self.assertFalse(result["original_table_projections_unchanged"][table])
        shutil.copyfile(self.db, path)
        (self.after / "App/Documents/source.pdf").unlink()
        (self.after / persistence.PREFERENCES).write_bytes(
            plistlib.dumps({"existing": "changed", "enabled": True})
        )
        result = persistence.compare(self.before, self.baseline, self.after)
        self.assertFalse(result["existing_data_preserved"])
        self.assertEqual(result["changed_preference_keys"], ["existing"])
        self.assertEqual(result["durable_files"]["App/Documents/source.pdf"], "missing")

    def test_additive_schema_preserves_old_columns_but_requires_migration_review(self):
        with sqlite3.connect(self.after / persistence.SUPPORT / "ledger.sqlite") as connection:
            connection.execute("ALTER TABLE scans ADD COLUMN run_summary TEXT")
            connection.execute("UPDATE scans SET run_summary='invented-summary'")
            connection.execute("CREATE TABLE source_deletions (id TEXT PRIMARY KEY)")
            connection.execute("PRAGMA user_version=10")
        result = persistence.compare(self.before, self.baseline, self.after)
        self.assertTrue(result["existing_data_preserved"])
        self.assertTrue(result["review_required"])
        self.assertFalse(result["schema_unchanged"])
        self.assertEqual(result["added_tables"], ["source_deletions"])

    def test_row_associations_are_not_lost_in_column_hashes(self):
        with sqlite3.connect(self.db) as connection:
            connection.execute("INSERT INTO owned_events VALUES('two','another-value')")
        self.baseline = persistence.snapshot(self.before)
        shutil.copyfile(self.db, self.after / persistence.SUPPORT / "ledger.sqlite")
        with sqlite3.connect(self.after / persistence.SUPPORT / "ledger.sqlite") as connection:
            connection.execute(
                "UPDATE owned_events SET value=CASE id WHEN 'one' THEN 'another-value' ELSE 'invented-value' END"
            )
        result = persistence.compare(self.before, self.baseline, self.after)
        self.assertFalse(result["original_table_projections_unchanged"]["owned_events"])

    def test_wal_rows_are_read_from_a_copy_without_mutating_original_sidecars(self):
        connection = sqlite3.connect(self.db)
        self.addCleanup(connection.close)
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("INSERT INTO settings VALUES('wal-only','retained')")
        connection.commit()
        self.assertTrue(Path(str(self.db) + "-wal").exists())
        original = persistence.inventory(self.before)
        snap = persistence.snapshot(self.before)
        self.assertEqual(snap["database"]["tables"]["settings"]["rows"], 2)
        self.assertEqual(persistence.inventory(self.before), original)

    def test_json_formatting_can_change_but_boolean_and_numeric_values_cannot(self):
        path = self.after / "AgendaGroup/pending.json"
        path.write_text(json.dumps({"operation": "invented-pending"}, indent=4))
        result = persistence.compare(self.before, self.baseline, self.after)
        self.assertTrue(result["existing_data_preserved"])
        self.assertEqual(result["durable_files"]["AgendaGroup/pending.json"], "same_content")
        self.assertNotEqual(
            persistence.content_hash({"value": True}), persistence.content_hash({"value": 1})
        )
        self.assertNotEqual(persistence.content_hash(1), persistence.content_hash(1.0))

    def test_missing_container_symlink_or_unrecognized_database_fails(self):
        shutil.rmtree(self.after / "IntakeGroup")
        with self.assertRaises(ValueError):
            persistence.snapshot(self.after)
        (self.after / "IntakeGroup").mkdir()
        (self.after / "IntakeGroup/escape").symlink_to(self.before / "App/Documents/source.pdf")
        with self.assertRaises(ValueError):
            persistence.snapshot(self.after)
        (self.after / "IntakeGroup/escape").unlink()
        with sqlite3.connect(self.after / persistence.SUPPORT / "ledger.sqlite") as connection:
            connection.execute("DROP TABLE owned_events")
        with self.assertRaises(ValueError):
            persistence.snapshot(self.after)

    def test_added_preferences_and_durable_files_require_explicit_review(self):
        (self.after / persistence.PREFERENCES).write_bytes(
            plistlib.dumps({"existing": "preserve", "enabled": True, "new": "value"})
        )
        (self.after / "IntakeGroup/new.json").write_text("{}")
        result = persistence.compare(self.before, self.baseline, self.after)
        self.assertTrue(result["existing_data_preserved"])
        self.assertTrue(result["review_required"])
        self.assertEqual(result["added_preference_keys"], ["new"])
        self.assertEqual(result["added_durable_files"], ["IntakeGroup/new.json"])

    def test_evidence_stays_private_and_never_overwrites(self):
        with patch.object(persistence, "ROOT", self.root):
            destination = self.root / ".local/runs/snapshot.json"
            persistence.save(destination, self.baseline)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                persistence.save(destination, self.baseline)
            with self.assertRaises(ValueError):
                persistence.save(self.root / "tracked.json", self.baseline)


if __name__ == "__main__":
    unittest.main()
