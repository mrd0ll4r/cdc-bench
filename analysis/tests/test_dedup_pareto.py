import csv
from fractions import Fraction
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "dedup_pareto.py"
spec = importlib.util.spec_from_file_location("dedup_pareto", SCRIPT)
p = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = p
spec.loader.exec_module(p)


class DedupTests(unittest.TestCase):
    def fixture(self):
        return [dict(algorithm=a, dataset=d, target_chunk_size=t, dataset_size=102400,
                     chunk_count=100, unique_chunks_size_sum=51200, mean_chunk_size=1024,
                     run_id=f"synthetic-{a}-{d}-{t}", dataset_fingerprint=f"synthetic-{d}",
                     chunk_population="all-emitted")
                for a in p.ALGORITHMS for d in p.DATASETS for t in p.TARGETS]

    def load(self, rows, output=False):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.csv"
            with path.open("w", newline="") as stream:
                extra = sorted(set().union(*(row.keys() for row in rows)) - set(p.REQUIRED))
                writer = csv.DictWriter(stream, fieldnames=[*p.REQUIRED, *extra])
                writer.writeheader()
                writer.writerows(rows)
            result = p.load_measurements(path)
            if output:
                p.write_outputs(result, path, Path(directory) / "output")
                with (Path(directory) / "output/dedup-adjusted.csv").open() as generated:
                    data = list(csv.DictReader(generated))
                self.assertEqual(len(data), 540)
                self.assertEqual({r["dataset"] for r in data}, set(p.DATASETS))
                self.assertEqual({r["metadata_bytes"] for r in data}, {"28", "48", "64"})
                self.assertTrue((Path(directory) / "output/dedup-provenance.json").is_file())
            return result

    def test_complete_grid_and_output(self):
        self.assertEqual(len(self.load(self.fixture(), output=True)), 180)

    def test_metadata_arithmetic_and_negative_savings(self):
        row = p.Measurement("fsc", "CODE", 512, 1000, 100, 800, "x", "x")
        self.assertEqual(row.savings(28), Fraction(-13, 5))
        self.assertEqual(row.savings(48), Fraction(-23, 5))
        self.assertEqual(row.savings(64), Fraction(-31, 5))
        self.assertIn("-260", p.figure_tex([row], 28))

    def test_pareto_tradeoffs_ties_and_strict_dominance(self):
        # Means 10,20,20,10 and savings .5,.5,.5,.7 at metadata=0.
        rows = [p.Measurement(a, "CODE", 512, 1000, n, u, a, "x")
                for a, n, u in [("fsc", 100, 500), ("ae", 50, 500), ("ram", 50, 500), ("mii", 100, 300)]]
        self.assertEqual(p.nondominated(rows, 0), set(rows[1:]))

    def test_duplicate_and_incomplete_rejected(self):
        for rows in (self.fixture()[:-1], self.fixture() + self.fixture()[:1]):
            with self.assertRaises(ValueError):
                self.load(rows)

    def test_population_and_provenance_checks(self):
        for field, value in [("mean_chunk_size", "1023"), ("chunk_population", "exclude-final"),
                             ("dataset_fingerprint", "other"), ("dataset_size", 102401),
                             ("run_id", ""), ("dataset", "PDF"), ("target_chunk_size", 770),
                             ("unique_chunks_size_sum", 102401), ("chunk_count", 0),
                             ("mean_chunk_size", "nan"), ("algorithm", "buzhash_64")]:
            rows = self.fixture()
            rows[1][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                self.load(rows)

    def test_optional_table_columns_are_accepted(self):
        rows = self.fixture()
        rows[0]["sd_chunk_size"] = "100"
        rows[0]["median_throughput_mib_s"] = "1234"
        self.assertEqual(len(self.load(rows)), 180)

    def test_rounded_mean(self):
        rows = self.fixture()
        rows[0]["mean_chunk_size"] = "1024.0001"
        self.assertEqual(self.load(rows)[0].mean, 1024)


if __name__ == "__main__":
    unittest.main()
