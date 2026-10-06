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

Running `eval_dedup.R` produces the achieved-size Pareto analysis at a fixed
illustrative metadata cost of **28 B per emitted chunk**.

Inputs are the existing `dedup_*.csv.gz` and `csd_*.csv.gz` files in `csv_dir`.
The script uses its existing deduplication ratios and runs one DuckDB
`AVG(chunk_size)` query over the CSD files, grouped by exact algorithm, dataset,
and target. All emitted chunks count, including repeated and final partial
chunks. Only the grouped means enter R. There is no summary cache, session-object
lookup, alternate input path, or LaTeX input. No benchmarks are rerun.

Use one consistent result collection without overlapping exports or repeated runs.
The metadata-adjusted savings are `d - 28/c`, where d is fractional deduplication
savings and c is achieved mean size. This equals `1 - (U + 28*N)/S`.
Negative savings remain visible. Rings identify nondominated measured points
within each dataset, maximizing both adjusted savings and mean size; ties remain.

DuckDB/DBI are required, as for `eval_csd.R`. Malformed chunks and duplicate
summary keys fail. Missing/invalid configurations are recorded in
`tab/dedup-pareto-coverage.csv` and stop figure generation. Configuration keys
alone cannot establish matching input content or historical run settings.

The existing `print_plot()` exporter writes separate TeX/PNG assets:

- `fig/dedup_pareto_code`, `fig/dedup_pareto_web`, `fig/dedup_pareto_vmb`,
  and `fig/dedup_pareto_db`: each 2 by 2 inches, without a legend.
- `fig/dedup_pareto_legendonly`: shared legend, 7 by 1 inches.

The explicit 11-point theme, color/shape scales, and legend exporter are shared with the configured-target deduplication
figures. Ratio values are displayed as fractions, matching `dedup_overview`. The CSV `tab/dedup-adjusted.csv` contains the 180 configurations at 28 B.

Run the analysis tests from the repository root (including DuckDB integration):

```sh
Rscript --vanilla plotting/tests/test_dedup_pareto.R
```
