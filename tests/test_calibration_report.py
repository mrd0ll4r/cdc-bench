"""Deterministic numerical and input-contract checks; no benchmark runs."""
import importlib.util
import io
import math
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('calibration', ROOT / 'scripts/calibration-report.py')
calibration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(calibration)


class CalibrationTests(unittest.TestCase):
    def test_probability_and_predictions(self):
        rows = list(calibration.report_rows({}))
        ae = next(r for r in rows if (r['algorithm'], r['parameter']) == ('ae', 1793))
        self.assertAlmostEqual(ae['p_max_255'], 0.9991040459974954)
        self.assertEqual(ae['prediction_bytes'], 2049)
        # Independent factorial/product calculation of the inverse probability.
        for w, rounded in zip((5, 6, 7, 8), (147, 877, 6248, 51341)):
            inverse = math.factorial(w) / math.prod((256-i)/256 for i in range(w))
            self.assertAlmostEqual(calibration.mii_prediction(w), 1.14*inverse+w)
            self.assertEqual(round(calibration.mii_prediction(w)), rounded)

    def test_residual_sign_and_denominator(self):
        rows = list(calibration.report_rows({('ae', 348): (512, 'synthetic')}))
        ae = next(r for r in rows if (r['algorithm'], r['parameter']) == ('ae', 348))
        self.assertEqual(ae['prediction_relative_error'], 604/512-1)
        self.assertEqual(ae['target_relative_error'], 0)
        self.assertEqual(ae['corrected_relative_error'], '')
        self.assertTrue(any(r['mean_bytes'] == 'RESULTS PENDING' for r in rows))

    def test_mii_residual_is_against_same_window_mean(self):
        row = next(r for r in calibration.report_rows({('mii', 6): (900, 'synthetic')}) if r['algorithm'] == 'mii' and r['parameter'] == 6)
        self.assertAlmostEqual(row['corrected_relative_error'], calibration.mii_prediction(6)/900-1)
        self.assertEqual(row['target_bytes'], '')

    def test_reject_invalid_or_ambiguous_measurements(self):
        header = 'algorithm,parameter,mean_bytes,provenance\n'
        for data in ('ae,348,nan,run\n', 'ae,348,0,run\n', 'ae,348,512,\n',
                     'ae,1792,2048,run\n', 'ae,348,512,run\nae,348,513,run\n'):
            with self.subTest(data=data), self.assertRaises(ValueError):
                calibration.read_measurements(io.StringIO(header+data))
        with self.assertRaises(ValueError):
            calibration.read_measurements(io.StringIO('algorithm,mean_bytes\nae,512\n'))

    def test_historical_parameter_selection(self):
        command = 'source scripts/utils.sh; for t in 512 1024 2048 4096 8192; do echo "$t $(get_w_for_ae "$t") $(get_w_for_mii "$t") $(get_w_and_t_for_pci "$t") $(get_params_for_seq "$t")"; done'
        result = subprocess.check_output(['bash', '-c', command], cwd=ROOT, text=True)
        self.assertEqual(result.splitlines(), [
            '512 348 5 58 253 4 65 512', '1024 793 6 34 157 5 85 32',
            '2048 1793 6 61 273 5 85 256', '4096 3840 7 39 183 5 120 1024',
            '8192 7936 7 57 262 5 55 1024'])


if __name__ == '__main__':
    unittest.main()
