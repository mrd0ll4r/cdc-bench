#!/usr/bin/env python3
"""Calculate AE/MII predictions and compare explicitly supplied RAND means.

No benchmark is run. CSV input columns: algorithm,parameter,mean_bytes,provenance.
algorithm is ae or mii; parameter is AE's historical horizon or MII's byte window.
Means must describe the same completed-chunk population for each configuration.
Partial input is allowed: unavailable rows remain RESULTS PENDING.
"""
import argparse
import csv
import math
import sys

AE_SETTINGS = {348: 512, 793: 1024, 1793: 2048, 3840: 4096, 7936: 8192}
MII_WINDOWS = (5, 6, 7, 8)
KEYS = {('ae', h) for h in AE_SETTINGS} | {('mii', w) for w in MII_WINDOWS}
PENDING = 'RESULTS PENDING'


def mii_prediction(w, factor=1.14):
    return factor * 256**w / math.comb(256, w) + w


def read_measurements(stream):
    reader = csv.DictReader(stream)
    if not {'algorithm', 'parameter', 'mean_bytes', 'provenance'} <= set(reader.fieldnames or []):
        raise ValueError('required columns: algorithm,parameter,mean_bytes,provenance')
    values = {}
    for line, row in enumerate(reader, 2):
        key = (row['algorithm'], int(row['parameter']))
        mean = float(row['mean_bytes'])
        if key not in KEYS:
            raise ValueError(f'line {line}: unsupported calibration configuration {key}')
        if key in values:
            raise ValueError(f'line {line}: duplicate calibration configuration {key}')
        if not math.isfinite(mean) or mean <= 0 or not row['provenance'].strip():
            raise ValueError(f'line {line}: mean must be positive and finite, with provenance')
        values[key] = (mean, row['provenance'])
    return values


def report_rows(measurements):
    for algorithm, parameter in sorted(KEYS):
        measured = measurements.get((algorithm, parameter))
        mean, provenance = measured if measured else (None, PENDING)
        target = AE_SETTINGS.get(parameter, '') if algorithm == 'ae' else ''
        uncorrected = parameter + 256 if algorithm == 'ae' else mii_prediction(parameter, 1.0)
        corrected = mii_prediction(parameter) if algorithm == 'mii' else None
        yield {
            'algorithm': algorithm, 'parameter': parameter, 'target_bytes': target,
            'p_max_255': -math.expm1(parameter * math.log1p(-1/256)) if algorithm == 'ae' else '',
            'prediction_bytes': uncorrected, 'corrected_prediction_bytes': corrected or '',
            'mean_bytes': mean if mean is not None else PENDING,
            'prediction_relative_error': uncorrected / mean - 1 if mean is not None else PENDING,
            'corrected_relative_error': (corrected / mean - 1 if mean is not None else PENDING) if corrected is not None else '',
            'target_relative_error': (mean / target - 1 if mean is not None else PENDING) if target else '',
            'provenance': provenance,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--measurements', help='CSV of explicitly supplied measured RAND means')
    args = parser.parse_args()
    try:
        measurements = {}
        if args.measurements:
            with open(args.measurements, newline='') as stream:
                measurements = read_measurements(stream)
        rows = list(report_rows(measurements))
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    writer = csv.DictWriter(sys.stdout, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)


if __name__ == '__main__':
    main()
