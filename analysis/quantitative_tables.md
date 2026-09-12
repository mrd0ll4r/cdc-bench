# Quantitative tables for the extended manuscript

Addresses R1.W5a–b,D7 and R2.D5. `quantitative_tables.py` uses only Python's
standard library and generates the replacement Table IX (`tab/csd_overview.tex`)
and Table X (`tables/summary.tex`). It does not run experiments or infer results
from published rounded numbers or figure coordinates.

## Input contract

One CSV row represents one selected, provenance-checked run summary per
`algorithm,dataset,target_chunk_size`. Algorithms are `rabin_32,buzhash_32,gear,ae,
ram,pci,mii,seq-cdc`; datasets are `RAND,CODE,WEB,VMB,DB`; configured targets are
512, 1024, 2048, 4096, 8192 **bytes**, including MII's nominal target labels.
Unknown values and duplicate keys fail. Select the intended run beforehand;
the generator does not average replicate distribution runs.

Required for both tables: the three key columns, `run_id`,
`dataset_fingerprint`, `chunk_population`, `mean_chunk_size`, `sd_chunk_size`.
The population must be `all-emitted`, including terminal chunks and every
occurrence of duplicate chunks. Supply exact, unrounded measured mean and
sample SD (denominator N-1, matching the existing R `sd()` analysis), in bytes. A nonblank run ID and fingerprint are
mandatory wherever any measured value is supplied. Fingerprints must identify
identical dataset content/order across configurations. The generator validates
matching fingerprints per dataset; authors must check that each supplied
summary actually came from the identified run.

Table X additionally requires integer `dataset_size`, `chunk_count`,
`unique_chunks_size_sum` (bytes, count, bytes) and `median_throughput_mib_s`
(MiB/s, where MiB = 2^20 bytes). These must refer to the same configuration and
dataset population as the mean/SD. `run_id` identifies the selected run bundle,
including the timing repetitions whose median is supplied. Timing samples must
follow the paper's benchmark procedure. No timing runs are combined here.
Input bytes must agree across configurations, unique bytes cannot exceed input
bytes, and mean must agree with input bytes / total emitted chunks to relative
1e-6, allowing decimal serialization but not incompatible chunk populations.

Table IX needs the complete 8 × 5 × 5 grid. Table X needs all eight algorithms,
four realistic datasets, and target 2048. A complete all-target CSV can serve
both; Table X validates its supplied rows but aggregates only its stated domain.
FSC rows are recognized but excluded by default. `--include-fsc` requires its
complete additional domain and displays FSC as a reference outside CDC rankings.

Empty strings, `NA`, and `N/A` are the only missing markers. Zero is a measured
value, permitted for SD and unique bytes; nonfinite, negative, and impossible
counts fail. Missing rows/values fail by default. `--allow-missing` is for review
builds only: an aggregate is unavailable unless *all* of its five targets (IX)
or four datasets (X) exist. Available independent metrics may still be shown.
Dashes represent unavailable values, never zero or an average over a subset.

## Statistics and ranking

Table IX equally averages `abs(mean/target - 1)` and `SD/mean` across the five
targets, separately for every algorithm/dataset. Errors print as percentages;
CV is dimensionless. No clipping or weighting by target size/chunk count occurs.

Table X uses configured target 2048 and reports the minimum of
`1 - (unique_bytes + 28*total_chunk_count)/input_bytes`, minimum median throughput,
maximum absolute relative target error, and maximum CV across CODE/WEB/VMB/DB.
28 bytes per emitted chunk is an illustrative cost assumption, not a measured
storage-system cost. Negative savings are retained. Superscripts identify every
dataset attaining an extremum. Values are formatted to two decimals only at
rendering; calculations and exact ties use decimal arithmetic. Best and second
*distinct* values among the eight CDC algorithms use bold and underline with ties
retained. If any algorithm lacks a metric, its whole ranking is withheld. Apparent
ties introduced solely by two-decimal display may therefore have different
formatting; audit JSON retains precise values for review.

MII has coarse integer-window settings, so target error includes unattainable
nominal targets. **Historical configuration remains unresolved at 512 B:** the
current nearest-prediction helper selects w=5 (about 147 B predicted), whereas
the manuscript's rounded RAND mean is 887 B (consistent with w=6, about 877 B
predicted). This task changes neither parameter selection nor measurements.
Resolve the historical configuration from run records before replacing MII
placeholders; do not relabel 887 B as a 147 B target or silently regenerate data.

## Commands

From the framework repository:

```sh
python3 analysis/quantitative_tables.py --template --output /tmp/table-input.csv
# Fill that template with author-supplied exact results and run provenance.
python3 analysis/quantitative_tables.py --input /tmp/table-input.csv --table ix --output /path/to/paper/tab/csd_overview.tex
python3 analysis/quantitative_tables.py --input /tmp/table-input.csv --table x --output /path/to/paper/tables/summary.tex
python3 -m unittest discover -s tests -p test_quantitative_tables.py
```

Add `--allow-missing` to generate review placeholders. Generated audit JSON beside
each TeX file preserves the input path, source keys/provenance, exact values, and
missing configurations. Inspect and retain these audits with the result data;
only reviewed TeX needs to enter the manuscript. Regenerating IX/X from the same
CSV ensures that input provenance and metric definitions stay consistent.
Publication checks must reject `REBUTTAL-DATA-PENDING` in generated TeX files.
