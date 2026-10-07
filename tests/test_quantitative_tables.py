import csv
import importlib.util
import tempfile
import unittest
from decimal import Decimal as D
from pathlib import Path

spec = importlib.util.spec_from_file_location('quantitative_tables', Path(__file__).parents[1] / 'analysis/quantitative_tables.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)


class QuantitativeTablesTest(unittest.TestCase):
    def rows(self):
        return {(a, ds, t): dict(mean_chunk_size=D(t), sd_chunk_size=D(t),
                dataset_size=D(819200), chunk_count=D(819200)/t,
                unique_chunks_size_sum=D(409600), median_throughput_mib_s=D(100),
                run_id=f'{a}-{ds}-{t}', dataset_fingerprint=ds, chunk_population='all-emitted')
                for a in q.ALGORITHMS for ds in q.DATASETS for t in q.TARGETS}

    def csv(self, rows, table='x', **options):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'input.csv'
            with path.open('w', newline='') as f:
                w = csv.DictWriter(f, fieldnames=q.BASE + q.X_FIELDS)
                w.writeheader()
                for (a, ds, t), row in rows.items():
                    w.writerow(dict(algorithm=a, dataset=ds, target_chunk_size=t, **row))
            return q.load_rows(path, table, **options)

    def test_five_target_weighting_absolute_error_and_unclipped_cv(self):
        rows = self.rows()
        # +100% and -50% must not cancel, and each target has equal weight.
        rows['ae', 'RAND', 512]['mean_chunk_size'] = D(1024)
        rows['ae', 'RAND', 1024]['mean_chunk_size'] = D(512)
        rows['ae', 'RAND', 8192]['sd_chunk_size'] = D(81920)
        error, cv = q.overview(rows)['ae']['RAND']
        self.assertEqual(error, D('0.3'))
        self.assertEqual(cv, D('2.9'))
        self.assertIn('30.00', q.render_ix(q.overview(rows), q.ALGORITHMS))

    def test_negative_savings_and_all_tied_datasets(self):
        rows = self.rows()
        for ds in q.REAL:
            rows['ram', ds, 2048]['unique_chunks_size_sum'] = D(819200)
        result = q.summary(rows)
        self.assertEqual(result['ram'][0], (D('-0.03125'), q.REAL))
        self.assertEqual(result['ae'][1], (D(100), q.REAL))
        self.assertIn('-3.12', q.render_x(result, q.ALGORITHMS))
        self.assertIn('C,W,V,D', q.render_x(result, q.ALGORITHMS))

    def test_best_second_and_direction_with_ties(self):
        rows = self.rows()
        for ds in q.REAL:
            rows['ae', ds, 2048]['median_throughput_mib_s'] = D(300)
            rows['gear', ds, 2048]['median_throughput_mib_s'] = D(300)
            rows['ram', ds, 2048]['median_throughput_mib_s'] = D(200)
        text = q.render_x(q.summary(rows), q.ALGORITHMS)
        self.assertEqual(text.count(r'\textbf{300.00}'), 2)
        self.assertIn(r'\underline{200.00}', text)

    def test_missing_grid_rejected_and_review_marked(self):
        rows = self.rows()
        del rows['ae', 'CODE', 2048]
        with self.assertRaisesRegex(ValueError, 'missing/incomplete'):
            self.csv(rows)
        loaded, algorithms, missing = self.csv(rows, allow_missing=True)
        self.assertEqual(missing, [('ae', 'CODE', 2048)])
        summary = q.summary(loaded)
        self.assertIsNone(summary['ae'][0][0])
        text = q.render_x(summary, algorithms)
        self.assertIn('REBUTTAL-DATA-PENDING', text)
        self.assertNotIn(r'\textbf{100.00}', text)  # no partial ranking

    def test_missing_sd_does_not_destroy_available_target_error(self):
        rows = self.rows()
        rows['ae', 'RAND', 512]['sd_chunk_size'] = ''
        loaded, _, _ = self.csv(rows, 'ix', allow_missing=True)
        self.assertEqual(q.overview(loaded)['ae']['RAND'], (D(0), None))

    def test_identity_and_population_validation(self):
        for field, value, pattern in [('dataset_fingerprint', 'different', 'fingerprint'),
                                      ('chunk_population', 'non-final-only', 'all-emitted'),
                                      ('run_id', '', 'run/fingerprint')]:
            with self.subTest(field=field):
                rows = self.rows()
                rows['ae', 'CODE', 2048][field] = value
                with self.assertRaisesRegex(ValueError, pattern):
                    self.csv(rows)

    def test_accounting_and_invalid_numbers(self):
        for field, value in [('mean_chunk_size', D(2047)), ('chunk_count', D('1.5')),
                             ('unique_chunks_size_sum', D(999999)), ('sd_chunk_size', D('NaN'))]:
            with self.subTest(field=field):
                rows = self.rows()
                rows['ae', 'CODE', 2048][field] = value
                with self.assertRaises(ValueError):
                    self.csv(rows)

    def test_duplicate_and_unexpected_domain(self):
        rows = self.rows()
        rows['other', 'CODE', 2048] = rows['ae', 'CODE', 2048]
        with self.assertRaisesRegex(ValueError, 'unknown'):
            self.csv(rows)
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'duplicate.csv'
            p.write_text(','.join(q.BASE + q.IX_FIELDS) + '\n' + 'ae,CODE,2048,r,fp,all-emitted,2048,50\n' * 2)
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                q.load_rows(p, 'ix', allow_missing=True)

    def test_duplicate_csv_header(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'input.csv'
            p.write_text(','.join(q.BASE + q.IX_FIELDS + ('mean_chunk_size',)) + '\n')
            with self.assertRaisesRegex(ValueError, 'Duplicate CSV column'):
                q.load_rows(p, 'ix', allow_missing=True)

    def test_distinct_worst_datasets_for_each_metric(self):
        rows = self.rows()
        rows['ae', 'CODE', 2048]['unique_chunks_size_sum'] = D(819200)
        rows['ae', 'WEB', 2048]['median_throughput_mib_s'] = D(5)
        rows['ae', 'VMB', 2048]['mean_chunk_size'] = D(4096)
        rows['ae', 'DB', 2048]['sd_chunk_size'] = D(8192)
        result = q.summary(rows)['ae']
        self.assertEqual([d for _, d in result], [('CODE',), ('WEB',), ('VMB',), ('DB',)])
        self.assertEqual(result[2][0], D(1))
        self.assertEqual(result[3][0], D(4))

    def test_ix_needs_no_storage_or_timing_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'ix.csv'
            p.write_text(','.join(q.BASE + q.IX_FIELDS) + '\n' + 'ae,CODE,2048,r,fp,all-emitted,2048,50\n')
            rows, _, _ = q.load_rows(p, 'ix', allow_missing=True)
            self.assertEqual(rows['ae', 'CODE', 2048]['mean_chunk_size'], D(2048))

    def test_optional_fsc_requires_complete_domain_without_affecting_rank(self):
        rows = self.rows()
        with self.assertRaisesRegex(ValueError, 'missing/incomplete'):
            self.csv(rows, include_fsc=True)
        for ds in q.DATASETS:
            for t in q.TARGETS:
                rows['fsc', ds, t] = dict(rows['ae', ds, t], median_throughput_mib_s=D(999))
        loaded, algorithms, missing = self.csv(rows, include_fsc=True)
        self.assertFalse(missing)
        text = q.render_x(q.summary(loaded, algorithms), algorithms)
        self.assertIn('FSC', text)
        self.assertNotIn(r'\textbf{999.00}', text)
        self.assertIn(r'\textbf{100.00}', text)


if __name__ == '__main__':
    unittest.main()
