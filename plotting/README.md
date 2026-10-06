# Evaluation Code

This directory contains R code to evaluate the results of the experiments.
We use `renv` for dependency management.

## Setup

Open a new R session in this directory.
That should kickstart `renv` and produce a warning about dependencies not having been loaded.
Load them using `renv::restore()`.

Some evaluations use Parquet files generated from the existing CSV results by
`parquet_translate.R`. The deduplication and Pareto analyses read CSV directly.

## Evaluation

The `eval_*` scripts perform evaluations.
They roughly correspond to the sections of the paper:
- `eval_file_sizes.R` and `eval_hash_value_distribution.R` analyze metadata about the datasets and the hash value
    distributions of the evaluated algorithms.
- `eval_perf.R` evaluates computational performance, i.e., throughput and microarchitectural performance metrics.
- `eval_csd.R` evaluates chunk size distributions.
- `eval_dedup.R` evaluates deduplication.

## Achieved-size and metadata-adjusted analysis

Running `eval_dedup.R` also produces the Pareto analysis, using the same
`csv/dedup_*.csv.gz` exports and the existing `csv/csd_*.csv.gz` chunk records.
No Python command, normalized input CSV, Parquet conversion, or new benchmark
run is needed for this analysis. Small helper functions live in `dedup_pareto.R`.

CSD files are streamed in bounded batches. For each exact algorithm variant,
dataset, and configured target, all rows are counted as emitted chunks N and
all chunk sizes are summed as S, including duplicates and final partial chunks.
These totals join to unique bytes U in the dedup exports. The analysis requires
S to equal the dedup export's dataset size. It does not use the legacy plot's
hard-coded VMB size override. Zero/missing/mismatched sizes are reported, not
silently repaired. Duplicate dedup configurations fail rather than averaging runs.
Use one consistent result collection: no mix of repeated runs or overlapping CSD
exports. The old CSVs do not record run IDs or input fingerprints, so matching
keys and sizes cannot prove identical input content or historical parameters.
Do not invent provenance fields or relabel ambiguous algorithm variants.

Achieved mean is S/N. Adjusted savings is `1 - (U + m*N)/S`, for illustrative
metadata costs m=28,48,64 B per emitted chunk. Negative savings remain visible.
Within each dataset and cost, rings mark points for which no other available
configuration has both larger/equal mean and greater/equal savings, with at least
one strict improvement. All exact ties remain. Integer byte/count comparisons
avoid rounding the ratios for dominance; values outside R's exact integer range
are rejected. There are no interpolated points or connecting frontier lines.

Outputs use the existing `print_plot()` exporter:

- `fig/dedup-pareto-{28,48,64}.tex` and `.png`: CODE, WEB, VMB, DB panels.
- `tab/dedup-adjusted.csv`: matched measurements, costs, savings, dominance flags.
- `tab/dedup-pareto-coverage.csv`: status of all 180 publication configurations.
- `tab/dedup-pareto-sources.csv`: input paths, file sizes, and modification times
  (an input inventory, not recovered historical run provenance).

Missing configurations produce a warning and explicit coverage status. Panels
show available configurations out of 45, with empty panels labeled accordingly;
frontiers refer only to the available measurements. Before using figures in the
paper, review the coverage report and input consistency. The generated TeX names
match the manuscript's existing placeholders. Configured-target figures remain.

Run synthetic analysis tests from the repository root:

```sh
Rscript --vanilla plotting/tests/test_dedup_pareto.R
```
