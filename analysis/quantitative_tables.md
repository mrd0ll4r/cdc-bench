# Quantitative tables for the extended manuscript

Addresses R1.W5a–b,D7 and R2.D5. Both tables are generated in R; no separate
Python generator or unit-test suite is used.

## Table IX: existing CSD evaluation

Run `eval_csd.R` from `plotting/` with the existing R dependencies and selected
`csv/csd_*.csv.gz` experiment files. Its overview section writes
`tab/csd_overview.tex` directly from the unrounded means and sample SDs already
computed by DuckDB. It uses all emitted chunks, including terminal chunks and
every occurrence of duplicate chunks. Select one intended CSD run per
configuration beforehand; the input glob must not combine replicate runs.

For each algorithm/dataset, equally average `abs(mean/target - 1)` and `SD/mean`
over targets 512, 1024, 2048, 4096, 8192 bytes. Error is displayed as a percentage;
CV is dimensionless. Neither metric is clipped or weighted by target size or
chunk count. The detailed mean/SD table keeps its existing color encoding.

The overview retains the original color scores independently of the displayed
metrics. For each algorithm/dataset, the error color score is the mean of
`min(abs(mean - target), target)` in bytes over the five targets; the dispersion
color score is the mean of `min(SD / (2 * mean), 1)`. Clipping happens at each
target before averaging. These are the original scores, not clipped versions
of the new aggregate metrics. Nine Reds shades are scaled linearly from the
minimum to the maximum score separately across each entire block, as before.
Lower color scores are lighter; displayed percentages and CVs remain unclipped.
Each cell uses black or white text, whichever has higher contrast against its
background. Missing values are uncolored; a constant block uses the lightest
shade. The generated TeX includes its own color definitions and needs the
paper's existing `xcolor`/`colortbl` support.

Each aggregate requires all five settings. Missing/invalid means or SDs produce
an unavailable aggregate, shown as a dash with `REBUTTAL-DATA-PENDING`; an absent
SD does not suppress an otherwise complete target-error aggregate. All eight
CDC algorithms and all five datasets are retained. The `.audit.rds` file beside
the table contains the measured statistics, unrounded aggregates and color scores.

## Table X: R summary evaluation

From `plotting/`, run:

```sh
Rscript --vanilla eval_summary.R /path/to/run-summaries.csv tab/summary.tex
```

Copy the result into the paper's `tables/summary.tex`. Add `--allow-missing` only
for review placeholders; add `--include-fsc` to display a complete FSC reference
outside CDC rankings. This script uses base R and requires no extra packages.

One CSV row represents one selected, provenance-checked run summary per
`algorithm,dataset,target_chunk_size`. Required columns are:

```csv
algorithm,dataset,target_chunk_size,run_id,dataset_fingerprint,chunk_population,mean_chunk_size,sd_chunk_size,dataset_size,chunk_count,unique_chunks_size_sum,median_throughput_mib_s
```

Algorithms are `rabin_32,buzhash_32,gear,ae,ram,pci,mii,seq-cdc`; datasets are
`RAND,CODE,WEB,VMB,DB`. Configured targets are 512, 1024, 2048, 4096, 8192 bytes.
Table X requires all eight algorithms at target 2048 across CODE/WEB/VMB/DB.
Other valid target/dataset rows may be supplied but are not aggregated.

Supply unrounded mean and sample SD (denominator N-1) in bytes, integer input
bytes/chunk count/unique bytes, and the median throughput in MiB/s (2^20 bytes).
The population must be `all-emitted`, including terminal and duplicate chunks.
Run IDs identify the selected run bundle and timing repetitions. Fingerprints
must identify identical dataset content/order across configurations. Authors
must verify that measurements belong to those runs and the same population.
The script rejects duplicate keys/headers, invalid or inconsistent accounting,
missing provenance, and differing dataset fingerprints or input byte counts.
Mean must agree with input bytes / emitted chunks within relative 1e-6.

Empty fields, `NA`, and `N/A` represent missing values. Zero is a valid measured
SD or unique-byte count. Missing values fail by default. In review mode each
metric requires all four datasets, and ranking is withheld for incomplete CDC
metrics. Available independent metrics may still be shown.

Table X reports the minimum of `1 - (unique_bytes + 64*chunk_count)/input_bytes`,
minimum median throughput, maximum absolute relative target error, and maximum
CV across CODE/WEB/VMB/DB. The 64-byte allowance per emitted chunk is illustrative;
negative savings are retained. Superscripts identify all datasets attaining an
extremum. Best and second distinct CDC values are bold and underlined, with ties
retained; FSC does not affect rankings. Calculations use R double precision and
round only for the two-decimal display. Ties use equality of unrounded values,
so apparent display ties may have different formatting. Integer byte/count
inputs above 2^53-1 are rejected. The accompanying `.audit.rds` preserves input
rows, provenance, unrounded metrics, and extremal datasets.

## Data still required

Neither script runs experiments or infers measurements from rounded manuscript
tables. Keep the input/run records and audits with the results. Publication
checks must reject `REBUTTAL-DATA-PENDING` in either generated table.

MII's integer windows permit only coarse expected chunk sizes. The historical
512 B configuration remains unresolved: the current nearest-prediction helper
selects w=5 (about 147 B predicted), whereas the manuscript's rounded RAND mean
is 887 B (consistent with w=6, about 877 B predicted). Resolve this from run
records before replacing placeholders. Do not relabel 887 B as a 147 B target
or silently regenerate data. This revision changes no parameter selections.
