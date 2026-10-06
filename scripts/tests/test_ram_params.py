"""Numerical checks without running a benchmark or sampling a random stream."""
import importlib.util
import math
from pathlib import Path
import subprocess
import sys
import unittest
from decimal import Decimal, localcontext

SCRIPT = Path(__file__).resolve().parents[1] / 'get-ram-param.py'
spec = importlib.util.spec_from_file_location('ram_params', SCRIPT)
ram = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ram)


def decimal_mean(h):
    # Independent summation-by-parts form: E[g(M)] = g(255) - sum F(m)*delta g(m).
    with localcontext() as ctx:
        ctx.prec = 70
        d = Decimal
        return d(h) + d(256) - sum(
            (d(m + 1) / 256) ** h * (d(256) / (255 - m) - d(256) / (256 - m))
            for m in range(255)
        )


class RAMParametersTest(unittest.TestCase):
    def test_single_byte_horizon_is_harmonic_number(self):
        self.assertAlmostEqual(ram.exact_mean(1), 1 + math.fsum(1 / k for k in range(1, 257)), places=12)

    def test_decimal_independent_identity(self):
        for h in (1, 2, 300, 327, 774, 780, 1792, 3840, 7936):
            with self.subTest(h=h):
                self.assertAlmostEqual(ram.exact_mean(h), float(decimal_mean(h)), places=10)

    def test_published_prediction_values(self):
        self.assertAlmostEqual(ram.exact_mean(327), 543.5800258479173, places=10)
        self.assertAlmostEqual(ram.exact_mean(780), 1029.8590110329908, places=10)

    def test_historical_cli_outputs_unchanged(self):
        for target, expected in zip((512, 1024, 2048, 4096, 8192), (327, 780, 1792, 3840, 7936)):
            for mode in ([], ['--mode', 'legacy']):
                with self.subTest(target=target, mode=mode):
                    self.assertEqual(subprocess.check_output([sys.executable, str(SCRIPT), str(target), *mode], text=True).strip(), str(expected))

    def test_exact_integer_optimum(self):
        for target, expected in zip((512, 1024, 2048, 4096, 8192), (300, 774, 1792, 3840, 7936)):
            with self.subTest(target=target):
                self.assertEqual(ram.exact_horizon(target), expected)
                self.assertLess(abs(decimal_mean(expected) - target), abs(decimal_mean(expected - 1) - target))
                self.assertLess(abs(decimal_mean(expected) - target), abs(decimal_mean(expected + 1) - target))
        self.assertEqual(ram.exact_horizon(ram.exact_mean(1)), 1)
        self.assertEqual(subprocess.check_output([sys.executable, str(SCRIPT), '512', '--mode', 'exact'], text=True).strip(), '300')

    def test_invalid_exact_targets_and_cli(self):
        for target in (0, -1, 1, float('nan'), float('inf')):
            with self.subTest(target=target):
                with self.assertRaises(ValueError):
                    ram.exact_horizon(target)
                result = subprocess.run([sys.executable, str(SCRIPT), str(target), '--mode', 'exact'], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b'')


if __name__ == '__main__':
    unittest.main()
