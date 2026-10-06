"""Synthetic fixtures only: these tests are not experimental measurements."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('extended_results', Path(__file__).parents[1] / 'extended_results.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class ExtendedResultsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fingerprint = 'sha256:' + 'a'*64
        self.chunks = 'stream_id,chunk_index,chunk_size,is_final\nfile,0,1,0\nfile,1,2,0\nfile,2,2048,0\nfile,3,2049,1\n'
        self.timings = 'repetition,elapsed_seconds,processed_bytes\n0,1,4100\n1,2,4100\n2,4,4100\n3,8,4100\n'
        self.manifest = dict(schema_version=1, chunk_population='all-emitted', timing_measure='cpu-task-clock',
                             datasets={'RAND': dict(dataset_size=4100, dataset_fingerprint=self.fingerprint,
                                                    provenance='SYNTHETIC UNIT TEST ONLY', stream_sizes={'file': 4100, 'empty': 0})},
                             runs=[dict(algorithm='mii', dataset='RAND', target_chunk_size=512, run_id='fixture',
                                        dataset_fingerprint=self.fingerprint, chunk_population='all-emitted',
                                        environment_id='test', source_revision='fixture-only', command='synthetic fixture',
                                        parameters={'p': 6}, chunk_count=4, timing_repetitions=4,
                                        chunks_csv='chunks.csv', timings_csv='timings.csv')])

    def save(self):
        (self.root / 'chunks.csv').write_text(self.chunks)
        (self.root / 'timings.csv').write_text(self.timings)
        path = self.root / 'manifest.json'
        path.write_text(json.dumps(self.manifest))
        return path

    def analyze(self):
        return m.analyze(self.save(), allow_missing=True)

    def test_known_quartiles_strict_tail_and_sample_sd(self):
        summary = self.analyze()[1][0]
        self.assertEqual([summary[f] for f in ('q1_chunk_size', 'median_chunk_size', 'q3_chunk_size', 'p99_chunk_size', 'p999_chunk_size', 'max_chunk_size')], [1, 2, 2048, 2049, 2049, 2049])
        self.assertEqual(summary['chunk_count'], 4)
        self.assertEqual(summary['mean_chunk_size'], 1025)
        self.assertAlmostEqual(summary['sd_chunk_size'], (4190210/3)**0.5)
        self.assertAlmostEqual(summary['byte_fraction_above_4target'], 2049/4100)
        self.assertEqual(summary['target_chunk_size'], 512)  # MII remains configured target.
        scale = 4100/2**20
        self.assertEqual(summary['median_throughput_mib_s'], scale*3/8)
        self.assertEqual(summary['q1_throughput_mib_s'], scale*7/32)
        self.assertEqual(summary['q3_throughput_mib_s'], scale*5/8)
        self.assertEqual(summary['iqr_throughput_mib_s'], scale*13/32)

    def test_exact_extreme_quantile_rank(self):
        values = list(range(1, 10001))
        self.assertEqual(m.quantile(values, 99), 9900)
        self.assertEqual(m.quantile(values, 999, 1000), 9990)

    def test_one_chunk_sd_is_undefined(self):
        s = m.chunk_statistics(b'stream_id,chunk_index,chunk_size,is_final\na,0,1,1\n', {'a': 1}, 512)
        self.assertIsNone(s['sd_chunk_size'])

    def test_missing_grid_errors_by_default(self):
        with self.assertRaisesRegex(ValueError, '199 of 200'):
            m.analyze(self.save())

    def test_explicit_empty_review_export(self):
        self.manifest['runs'] = []
        p = m.export(self.save(), self.root / 'export', True)
        self.assertEqual(len(p['missing_settings']), 200)
        self.assertIn('AUTHOR INPUT REQUIRED', p['status'])
        self.assertIn('Pending', (self.root / 'export/extended-db-rand.tex').read_text())

    def test_export_preserves_raw_repetitions_and_provenance(self):
        p = m.export(self.save(), self.root / 'export', True)
        self.assertEqual((self.root / 'export/raw/fixture.timings.csv').read_text(), self.timings)
        self.assertEqual((self.root / 'chunks.csv').read_text(), self.chunks)
        self.assertEqual(p['raw_files']['fixture.chunks.csv']['sha256'], m.file_sha256(self.root / 'chunks.csv'))
        self.assertEqual(p['summary'][0]['chunk_population'], 'all-emitted')
        self.assertEqual(len(p['raw_files']), 2)
        with self.assertRaisesRegex(ValueError, 'must be empty'):
            m.export(self.save(), self.root / 'export', True)

    def test_population_mismatch_rejected(self):
        for mutate in (lambda r: r.update(chunk_population='nonfinal'),
                       lambda r: r.update(chunk_count=5),
                       lambda r: r.update(dataset_fingerprint='sha256:'+'b'*64)):
            with self.subTest(mutate=mutate):
                before = copy.deepcopy(self.manifest)
                mutate(self.manifest['runs'][0])
                with self.assertRaises(ValueError):
                    self.analyze()
                self.manifest = before

    def test_missing_final_chunk_rejected(self):
        self.chunks = self.chunks.replace('file,3,2049,1\n', '')
        with self.assertRaisesRegex(ValueError, 'coverage mismatch'):
            self.analyze()

    def test_duplicate_or_wrong_final_chunks_rejected(self):
        for replacement in ('file,2,2049,1', 'file,3,2049,0'):
            with self.subTest(replacement=replacement):
                old = self.chunks
                self.chunks = old.replace('file,3,2049,1', replacement)
                with self.assertRaises(ValueError):
                    self.analyze()
                self.chunks = old

    def test_duplicate_grid_and_run_id_rejected(self):
        self.manifest['runs'].append(copy.deepcopy(self.manifest['runs'][0]))
        with self.assertRaisesRegex(ValueError, 'duplicate grid'):
            self.analyze()
        self.manifest['runs'][1]['target_chunk_size'] = 1024
        with self.assertRaisesRegex(ValueError, 'duplicate run_id'):
            self.analyze()

    def test_invalid_timings_rejected(self):
        original = self.timings
        for invalid in ('nan', 'inf', '0', '-1'):
            self.timings = original.replace('0,1,4100', f'0,{invalid},4100')
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                self.analyze()
        for invalid in ('0,1,4099', '1,1,4100'):
            self.timings = original.replace('0,1,4100', invalid)
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                self.analyze()

    def test_header_only_and_malformed_cells_rejected(self):
        for raw in ('stream_id,chunk_index,chunk_size,is_final\n',
                    'stream_id,chunk_index,chunk_size,is_final\nfile,0,4100,1,extra\n',
                    'stream_id,chunk_index,chunk_size,is_final\nfile,0,,1\n'):
            self.chunks = raw
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                self.analyze()

    def test_duplicate_json_key_rejected(self):
        with self.assertRaisesRegex(ValueError, 'duplicate JSON key'):
            json.loads('{"runs":[],"runs":[]}', object_pairs_hook=m.unique_object)

    def test_db_rand_comparison_and_provenance(self):
        self.manifest['runs'][0]['target_chunk_size'] = 2048
        self.manifest['datasets']['DB'] = copy.deepcopy(self.manifest['datasets']['RAND'])
        db = copy.deepcopy(self.manifest['runs'][0])
        db.update(dataset='DB', run_id='db-fixture')
        self.manifest['runs'].append(db)
        self.assertEqual(self.analyze()[4][0]['db_vs_rand_percent_change'], 0)
        db['parameters'] = {'p': 7}
        with self.assertRaisesRegex(ValueError, 'incompatible provenance'):
            self.analyze()
        db['parameters'] = {'p': 6}
        db['environment_id'] = 'different'
        with self.assertRaisesRegex(ValueError, 'incompatible provenance'):
            self.analyze()

    def test_histogram_tracks_mass_and_stream_grouping(self):
        raw = b'stream_id,chunk_index,chunk_size,is_final\na,0,2,0\na,1,2,1\nb,0,8,1\n'
        result = m.chunk_statistics(raw, {'a': 4, 'b': 8}, 1)
        self.assertEqual(result['median_chunk_size'], 2)
        self.assertAlmostEqual(result['byte_fraction_above_4target'], 2/3)
        revisited = b'stream_id,chunk_index,chunk_size,is_final\na,0,2,1\nb,0,8,1\na,0,2,1\n'
        with self.assertRaisesRegex(ValueError, 'grouped by stream'):
            m.chunk_statistics(revisited, {'a': 2, 'b': 8}, 1)

    def test_complete_grid(self):
        template = self.manifest['runs'][0]
        dataset = self.manifest['datasets']['RAND']
        self.manifest['datasets'] = {name: copy.deepcopy(dataset) for name in m.DATASETS}
        self.manifest['runs'] = [dict(template, algorithm=a, dataset=d, target_chunk_size=t, run_id=f'test-{i}') for i, (a, d, t) in enumerate(m.GRID)]
        result = m.analyze(self.save())
        self.assertEqual(len(result[1]), 200)
        self.assertEqual(len(result[3]), 0)
        self.assertEqual(len(result[4]), 8)


if __name__ == '__main__':
    unittest.main()
