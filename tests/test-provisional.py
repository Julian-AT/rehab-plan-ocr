"""Provisional-reference isolation and grouping guards, using invented data."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

prepare = load('prepare-provisional')
benchmark = load('benchmark')
class ProvisionalTests(unittest.TestCase):
    def test_related_photos_keep_separate_unverified_references_without_final_holdout(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            baseline = root / 'baseline'
            entries = []
            for n in range(2):
                image = root / f'{n}.png'
                image.write_bytes(f'invented-image-{n}'.encode())
                digest = hashlib.sha256(image.read_bytes()).hexdigest()
                entry = {'png': {'path': str(image), 'sha256': digest}, 'source_sha256': f'original-{n}'}
                entries.append(entry)
                directory = baseline / f'document-{n:02}'
                directory.mkdir(parents=True)
                (directory / 'run.json').write_text(json.dumps({'document': {'source_hash': digest}, 'sections': [{'date': '2026-09-10'}], 'appointments': [{'id': str(n)}]}))
            conversion = root / 'conversion.json'
            conversion.write_text(json.dumps({'entries': entries}))
            output = root / 'private'
            result = prepare.prepare(baseline, conversion, output)
            self.assertEqual(result, {'images': 2, 'provisional_groups': 1, 'verified_references': 0})
            references = list((output / 'labels/provisional').glob('*.json'))
            self.assertEqual(len(references), 2)
            self.assertTrue(all(json.loads(p.read_text())['verified'] is False for p in references))
            split = json.loads((output / 'split.json').read_text())
            self.assertFalse(split['final_holdout_available'])
            self.assertFalse(split['grouping_verified'])
            self.assertEqual(len(split['days']['development-01']['document_hashes']), 2)
            with self.assertRaises(ValueError):
                prepare.prepare(baseline, conversion, output)
            self.assertTrue(all(Path(e['png']['path']).exists() for e in entries))
            with patch.object(benchmark, 'PRIVATE', output), patch('sys.argv', ['benchmark', '--models', str(root), '--config', str(root / 'unused')]):
                with self.assertRaisesRegex(ValueError, 'relationships'):
                    benchmark.main()
            self.assertFalse((output / 'holdout-used.json').exists())

if __name__ == '__main__': unittest.main()
