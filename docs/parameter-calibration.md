# Parameter calibration and historical reproduction

The publication targets are 512, 1024, 2048, 4096, and 8192 bytes. The parameter
functions in `scripts/utils.sh` preserve the current artifact settings. Historical
run commands must be checked against those settings before claiming exact reproduction. Candidate-search outputs must not overwrite those settings.
The former 770/5482 exploratory rows are excluded from current PCI searches and
the legacy 770-only export was removed; archived data are retained.

| Target (B) | AE horizon in helper (B) | MII window in helper (bytes) |
| --- | --- | --- |
| 512 | 348 | 5 |
| 1024 | 793 | 6 |
| 2048 | 1793 | 6 |
| 4096 | 3840 | 7 |
| 8192 | 7936 | 7 |

AE's large-horizon approximation is `h = target - 256`. At the approximate 2 KiB
horizon 1792, the probability of observing byte 255 is 0.9991005324523875.
The historical 2 KiB setting is 1793 and remains unchanged. That probability is
not a bound on the error of the predicted mean; at small horizons, `h+256` is
outside the proposed approximation regime.

MII's parameter counts bytes, so its predicate uses `w-1` increasing adjacent
comparisons. The factor 1.14 multiplies the inverse probability term only.
Rounded predictions for `w=5,6,7,8` are 147, 877, 6248, 51341. Selection minimizes
absolute distance to the rounded lookup value; existing loop order breaks ties
toward the smaller window. These are predictions, not measurements.

AUTHOR INPUT REQUIRED: for target 512, distances to 147 and 877 both equal 365,
so the helper chooses w=5. The published RAND table instead reports a mean of
887 B at this target (also reported at 1024/2048), inconsistent with the w=5
prediction. Preserve the helper and published results; recover the historical
command record before assigning either window to that result. The table above
states current helper behavior, not a verified reconstruction of all paper runs.

In `src/main.rs`, Rabin and Buzhash use `round(log2(target-32))`; Gear uses
`round(log2(target))`. Rust floating-point rounding sends halfway cases away
from zero. All five publication targets yield mask widths 9 through 13 in
both rules. No algorithm implementation or historical parameter was changed.

## Available procedures and provenance

- `scripts/simulate-ae-params.py`: simulations over horizons 1–9999, 10,000 chunks
  each, in blocks of 100 bytes. Python random is not explicitly seeded. The
  script emits means and does not automatically select a horizon.
- `scripts/simulate-mii-params.py`: evaluates the empirical formula for windows
  0–19. The historical filename is retained; this is not a simulation or a
  validation of 1.14. It has no seed.
- `scripts/simulate-pci-params.py`: current search over windows 30–65 and thresholds
  4w–8w (bisection), seed 20250901, minimum relative target error, ties to smaller
  window then threshold. Its existence does not prove historical seed provenance
  or that rerunning it yields the exact published pairs.
- `scripts/simulate-seq-params.sh` (a shell script): enumerates sequence lengths
  4/5, triggers 50–120 in steps of 5, and skips 32/64/128/256/512/1024; runs the
  compiled chunker on `data/random_small.bin`. It neither generates this file nor
  selects the final candidate. Parallel output order is not a selection rule.
- `scripts/get-rand.sh`: obtains bytes from `/dev/urandom`; it does not record a
  seed and does not currently generate the SeqCDC script's small input file.

AUTHOR INPUT REQUIRED: historical calibration input identity/checksum, output
records, AE seed if recorded, provenance of the MII fit, and SeqCDC final
selection record. Do not retroactively describe the current PCI seed as the
historical seed without those records.

## Residual report, without running experiments

Run `python3 scripts/calibration-report.py` to produce all nine calibration rows
with calculated predictions and explicit `RESULTS PENDING` measurement fields.
Supply measured RAND means using
`python3 scripts/calibration-report.py --measurements means.csv > residuals.csv`.
Input columns are `algorithm,parameter,mean_bytes,provenance`; algorithm is `ae`
or `mii`, and parameter is an AE horizon in the table above or MII window 5–8.
Provenance must identify the source run/input and chunk inclusion policy. Supply
one mean per configuration, with terminal chunks handled consistently. Duplicate,
unsupported, non-finite, non-positive, or unprovenanced measurements are rejected.
Partial files are accepted; omitted configurations remain visibly pending.

The signed prediction error is `prediction/mean - 1`; AE target error is
`mean/target - 1`. MII correction error compares the same window and measurement
before/after multiplying the inverse-probability term by 1.14. The target error
is intentionally not conflated with approximation error. Blank corrected fields
for AE are inapplicable, not missing measurements.

Validate without experiments with
`python3 -m unittest discover -s tests -p test_calibration_report.py`.
