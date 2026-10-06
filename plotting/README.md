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

Running `eval_dedup.R` also produces the Pareto analysis using its existing
`dedup_ratio` values and the achieved means already computed by `eval_csd.R`.
Small helper functions live in `dedup_pareto.R`. No benchmark rerun is required.
Existing numerical summaries avoid rereading individual chunks. If no summary
exists yet, the script aggregates the saved chunk-size results once and caches it.

Mean sources, in order of preference:

- An explicit path selected with `options(cdc.csd_mean_summary="/path/to/summary.csv")`.
- The existing in-memory `duckdb_df` summary from the CSD evaluation.
- `tab/csd_means.csv`, which `eval_csd.R` now saves from its existing aggregate
  before display rounding or target-error transformations.
- If no summary is available, `csd_*.csv.gz` in the same `csv_dir` used for dedup
  results. Means are calculated in bounded batches and saved to
  `tab/csd_means.csv` for subsequent runs. This processes saved measurements;
  it does not execute any benchmark or rechunk the datasets.

The CSV accepts the existing wide aggregate (`mean_512`, `mean_1024`, etc.) or
long columns `algorithm,dataset,target_chunk_size,mean_chunk_size`. Compressed
`.csv.gz` summaries are also accepted. LaTeX tables and figures are outputs only;
they are never read as data. Use the unrounded numerical aggregate.

If the CSD aggregate is still available as `duckdb_df`, `eval_dedup.R` can use it
directly. To persist it without recomputing anything:

```r
dir.create("tab", showWarnings=FALSE, recursive=TRUE)
readr::write_csv(duckdb_df, "tab/csd_means.csv")
```

The loader reports which source it used and how many configurations it found.
If neither a summary nor saved chunk-size files are available, the warning lists
the paths searched and missing means remain explicit in the coverage report.
An explicit summary path never falls back to another result collection.
Existing formatted tables alone are insufficient for this workflow.

Use one collection of CSD exports without overlapping copies or repeated runs.
The fallback combines chunk-size sums and chunk counts across batches, including
duplicates and final partial chunks; it does not average per-batch means.
Remove the cached summary or select the appropriate CSV explicitly when switching
to a different result collection.

For fractional deduplication savings d = 1 - U/S and achieved mean c = S/N,
metadata-adjusted savings is `d - m/c`, equivalent to `1 - (U + m*N)/S`.
Here N counts all emitted chunks, including duplicates and final partial chunks;
U is unique chunk bytes and S is input bytes. The analysis does not need these
three totals separately. Metadata costs m=28,48,64 B/chunk are illustrative.
The deduplication ratio must be fractional savings in [0,1], not an input/unique
size multiplier. The ratios come from the same code as the configured-target
figures, including its existing VMB dataset-size correction.

Use summaries from the same result collection and population: exact algorithm
variant, dataset, and configured target. Means must cover all emitted chunks,
not unique chunks or an unweighted average of per-file means. Matching keys
cannot establish identical run provenance; the summaries do not contain enough
information to detect different inputs or parameter settings with the same keys.
Duplicate keys fail instead of silently averaging results. Missing or invalid
values are excluded and reported explicitly.

Negative adjusted savings remain visible. Within each dataset and metadata cost,
rings mark configurations for which no available point has both larger/equal
mean and greater/equal savings, with at least one strict improvement. All exact
ties remain. Comparisons use the supplied values without additional rounding.
No points are interpolated.

Outputs use the existing `print_plot()` exporter:

- `fig/dedup-pareto-{28,48,64}.tex` and `.png`: CODE, WEB, VMB, DB panels.
- `tab/dedup-adjusted.csv`: matched summaries, costs, savings, dominance flags.
- `tab/dedup-pareto-coverage.csv`: status of all 180 publication configurations.

Missing configurations produce a warning and explicit coverage status. Panels
show available configurations out of 45, with empty panels labeled accordingly;
frontiers refer only to available results. Review coverage and summary consistency
before using figures in the paper. Generated TeX names match the manuscript's
existing placeholders. Configured-target figures remain.

Run synthetic analysis tests from the repository root:

```sh
Rscript --vanilla plotting/tests/test_dedup_pareto.R
```
