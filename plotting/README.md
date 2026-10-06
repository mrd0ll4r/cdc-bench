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
Small helper functions live in `dedup_pareto.R`. No benchmark rerun or rereading
individual chunks is required.

Mean sources, in order of preference:

- An explicit path selected with `options(cdc.csd_mean_summary="/path/to/summary")`.
- The existing in-memory `duckdb_df` summary from the CSD evaluation.
- `tab/csd_means.csv`, which `eval_csd.R` now saves from its existing aggregate
  before display rounding or target-error transformations.
- The existing generated `tab/csd_means_sd_full.tex` table. This fallback reads
  numeric mean cells, not plot coordinates. Its whole-byte rounding makes savings
  and frontier membership approximate; warnings, plots, and `mean_rounded`
  output flags identify this case. An explicit path can also select this table.

The CSV accepts the existing wide aggregate (`mean_512`, `mean_1024`, etc.) or
long columns `algorithm,dataset,target_chunk_size,mean_chunk_size`. No separate
normalized CSV needs to be prepared when one of the existing artifacts is available.
Unrounded numerical summaries are preferred for final figures. The existing
paper table omits FSC; that configuration remains missing unless its means are
available in a numerical summary.

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
ties remain. Comparisons use the supplied values without additional rounding;
frontiers based on rounded table means are approximate. No points are interpolated.

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
