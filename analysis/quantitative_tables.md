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

The overview is sized for a single paper column: `Alg.` labels the first column,
dataset headers are rotated 45 degrees, and the body uses `scriptsize` with
1.5 pt cell padding. Short group headings identify mean target error (%) and
mean CV. An `adjustbox` maximum width of `columnwidth` prevents overflow without
enlarging tables that already fit; the paper already loads `adjustbox` and
`graphicx`. Use a normal `table` float rather than `table*`.

Each aggregate requires all five settings. Missing/invalid means or SDs produce
an unavailable aggregate, shown as a dash with `REBUTTAL-DATA-PENDING`; an absent
SD does not suppress an otherwise complete target-error aggregate. All eight
CDC algorithms and all five datasets are retained. The `.audit.rds` file beside
the table contains the measured statistics, unrounded aggregates and color scores.

## Table X: raw experiment summary

From the framework's `plotting/` directory, use the same `csv/` input directory
as the other evaluation scripts:

```sh
Rscript eval_summary.R
```

This uses `csv/` relative to the working directory and writes `tab/summary.tex`.
If your raw files live elsewhere, explicitly pass their directory and output:
`Rscript eval_summary.R ../csv tab/summary.tex` is appropriate only when the
complete experiment outputs live in the parent directory's `csv/`.
If CSD/dedup files are in `plotting/csv/` and timings are in the parent `csv/`, use:

```sh
Rscript eval_summary.R --perf-dir ../csv
```

`--perf-dir DIR` selects a separate directory for performance CSVs only; it
defaults to `CSV_DIR`. Files need not be moved or copied. The throughput column
uses the existing RAND timings at 2048 B, as in the paper's efficiency analysis.
It is labeled RAND throughput and is not a worst-case value across datasets.
DB snapshot timings are ignored. No new benchmark runs are needed when the
existing CSD/dedup files cover the four realistic datasets and RAND timings
cover the selected algorithms. With `--allow-missing`, unavailable metrics
remain dashes while independent complete metrics are still reported.
The script prints the resolved input directories and selected file counts, and
missing-data errors identify the absent measurements rather than only keys.
The output directory is created automatically. Copy the
result into the paper's `tables/summary.tex`, or pass that path as the second
argument. `--help` prints usage. No intermediate summary CSV is needed.

The script uses `DBI` and `duckdb`, also used by `eval_csd.R`. Run from `plotting/` without
`--vanilla` or `--no-init-file` so `.Rprofile` activates the project's `renv`
library. If either package is missing, install it in the project library with
`Rscript -e 'renv::install(c("DBI", "duckdb"))'`, then retry.
It accepts plain CSV and `.csv.gz` files
with the existing experiment schemas:

| Files | Columns used | Derived measurements |
| --- | --- | --- |
| `csd_*.csv[.gz]` | `algorithm,dataset,target_chunk_size,chunk_size` | Count and sum of all emitted chunks, mean, sample SD (N-1) |
| `dedup_*.csv[.gz]` | `algorithm,dataset,dataset_size,target_chunk_size,unique_chunks_size_sum` | Unique chunk bytes |
| `perf_*.csv[.gz]` | `algorithm,dataset,dataset_size,target_chunk_size,iteration,event,value` | Per-iteration MiB/s from `task-clock` in milliseconds; then median throughput |

Only target 2048 for `rabin_32,buzhash_32,gear,ae,ram,pci,mii,seq-cdc` is used.
CSD/dedup inputs use CODE/WEB/VMB/DB; performance inputs use RAND. Dataset names
are case-insensitive, and `random` is accepted as RAND. Other algorithms,
targets, datasets and performance events are ignored. The existing RAND
experiments populate the throughput column; the script starts no experiments.

DuckDB reads the CSVs directly, including gzip files. It filters the evaluation
domain and computes CSD `COUNT`, `SUM`, `AVG` and `STDDEV_SAMP` inside the database;
only grouped statistics enter R. This avoids the large-file row-index failure
in `readr::read_csv_chunked` ([readr issue #1554](https://github.com/tidyverse/readr/issues/1554)).
The original CSV headers are checked before querying, malformed CSV records
are rejected, and invalid selected chunk sizes cause an error rather than being
silently omitted. Deduplication rows and timing samples are also read through
DuckDB. Terminal chunks and every duplicate occurrence count toward
N and input bytes. The sum of emitted chunk sizes supplies input bytes S.
Positive byte counts in dedup outputs must match S, and input sizes must agree
across algorithms for each dataset. RAND performance byte counts must agree
across selected algorithms and repetition files; they are independent of the
realistic-dataset CSD totals. A zero dedup `dataset_size`
(the historical VMB symlink issue) is ignored in favor of measured CSD bytes;
no dataset size is hardcoded. Unique bytes cannot exceed input bytes.

Keep one coherent experiment set in the selected directories. Canonical
`csd_code.csv[.gz]` files (likewise for web, vmb and db) take precedence over
their `csd_code_*` split copies. Without the
canonical file, disjoint split files are accepted. Overlapping CSD configurations
across files, repeated dedup rows, duplicate task-clock events for one iteration
within a performance file, malformed values, and compressed/uncompressed copies
of the same input are rejected. Timing repetitions may span multiple files and
iteration numbers may restart in each file. For each configuration, the median
uses all individual per-iteration throughput values across those files, matching
`eval_perf.R`; it is not a median of file medians. Recorded byte counts must
still agree. The audit retains each timing sample's source file and iteration.
Keep only the intended repetition files, since copied files with different names
cannot be distinguished from independent runs. These legacy CSVs do not contain dataset fingerprints or
run IDs: byte-count checks and source-file records cannot establish identical
dataset content/order. Select matching runs using the original run records.

Add `--allow-missing` only for review placeholders: storage and chunk-size
extrema require all four realistic datasets, throughput requires RAND timings,
and CDC ranking is withheld for incomplete metrics.
Independent complete metrics remain available. Add `--include-fsc` to include a
complete FSC reference outside the eight-algorithm CDC rankings. Missing inputs
fail by default and the error names the incomplete configurations.

Table X reports minimum `1 - (unique_bytes + 64*chunk_count)/input_bytes`, maximum
absolute relative target error, and maximum CV across CODE/WEB/VMB/DB, alongside
median throughput on RAND. The 64-byte allowance per emitted chunk is illustrative;
negative savings are retained. Superscripts identify all datasets attaining an
extremum. Best and second distinct CDC values are bold and underlined, with ties
retained; FSC does not affect rankings. Calculations use R double precision and
round only for the two-decimal display. Ties use equality of unrounded values.
The accompanying `.audit.rds` records source-file paths, sizes and modification
times, derived measurements per realistic-dataset configuration, separate RAND
throughput configurations, timing samples, unrounded summary
metrics and extremal datasets. No manually supplied provenance columns are needed.

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
