# Parameter calibration and historical reproduction

The publication targets are 512, 1024, 2048, 4096, and 8192 bytes. The parameter
functions in `scripts/utils.sh` preserve the current artifact settings. The MII
benchmark mapping reconstructed below differs from the current helper at target
512. Execution logs are unavailable; the reconstruction is supported by code
history and manuscript summaries, not a recovered per-run command record.
No additional experiments are planned or needed for the descriptive residuals
reported here. Candidate-search outputs must not overwrite benchmark settings.
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

## MII benchmark mapping reconstructed from repository history

The benchmark-era mapping is **6, 6, 6, 7, 7** for the five targets:

- [Artifact commit 62268dc](https://github.com/mrd0ll4r/cdc-algorithm-tester/blob/62268dc/scripts/utils.sh)
  (March 17, 2025) uses predictions 130/770 for w=5/6. At target 512,
  w=6 is closer. Executing this revision's selection function returns 6,6,6,7,7.
- [Manuscript commit f68301e](https://github.com/mg98/cdc-investigation-tex/commit/f68301e)
  (March 19, 2025) already reports the RAND mean 887 B for the three smaller
  publication targets and 6242 B for the two larger ones.
- [Artifact commit 18dd4e0](https://github.com/mrd0ll4r/cdc-algorithm-tester/commit/18dd4e02293af7ce5552cf43ea2df046573848fd)
  (September 9, 2025) changes the lookup to 147/877. Both are 365 B from target
  512, so the existing tie rule now selects w=5. Its parent still selects w=6.

This explains the mismatch with the current helper. The table above describes
the current helper, not the benchmark mapping. The summaries support a historical
reconstruction but do not establish a particular executable revision for each run.
Reproducing the paper's reconstructed MII settings requires explicit windows
6,6,6,7,7; the current default helper does not reproduce its 512-byte configuration.
No helper behavior or existing result is changed by this documentation update.

## Residuals available from existing summaries

The existing manuscript RAND table reports AE means 512,1024,2048,4095,8191 B
for horizons 348,793,1793,3840,7936. The approximation h+256 exceeds these
rounded summaries by 92,25,1,1,1 B. The first two horizons are outside its
recommended regime. Differences at the other horizons are descriptive, not an
error bound.

For reconstructed MII windows 6 and 7, the table reports means 887 and 6242 B.
Using unrounded formula predictions, `(prediction / reported_mean - 1) * 100`
is approximately -13.2%/-12.2% without the 1.14 factor and -1.2%/+0.1% with it.
These are approximate residuals from rounded calibration summaries, not an
independent validation set. The source is the manuscript's
`tab/csd_means_sd_full.tex`; model predictions remain separate from measurements.
There are no reported empirical residuals here for windows 5 and 8, and no new
runs are requested to fill them.

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

The available scripts do not establish the historical calibration input
identity/checksum, AE seed, provenance of the MII fit, or final SeqCDC selection
record. These are provenance limitations, not requests for replacement runs.
Do not retroactively describe the current PCI seed as the historical seed.

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
This is a generic utility convention, not a publication requirement to collect
new observations. The manuscript analysis above is limited to existing rounded
summaries; it does not claim raw-data precision or a recovered chunk-inclusion
record. Its unavailable-window results are explicitly outside the empirical
analysis, rather than promised future measurements.

The signed prediction error is `prediction/mean - 1`; AE target error is
`mean/target - 1`. MII correction error compares the same window and measurement
before/after multiplying the inverse-probability term by 1.14. The target error
is intentionally not conflated with approximation error. Blank corrected fields
for AE are inapplicable, not missing measurements.

Validate without experiments with
`python3 -m unittest discover -s tests -p test_calibration_report.py`.
