# Evaluation Code

This directory contains R code to evaluate the results of the experiments.
We use `renv` for dependency management.

## Setup

Open a new R session in this directory.
That should kickstart `renv` and produce a warning about dependencies not having been loaded.
Load them using `renv::restore()`.

The first step after executing the experiments is to convert the results from CSV to Parquet files.
For this, use the `parquet_translate.R` script.

## Evaluation

The `eval_*` scripts perform evaluations.
They roughly correspond to the sections of the paper:
- `eval_file_sizes.R` and `eval_hash_value_distribution.R` analyze metadata about the datasets and the hash value
    distributions of the evaluated algorithms.
- `eval_perf.R` evaluates computational performance, i.e., throughput and microarchitectural performance metrics.
- `eval_csd.R` evaluates chunk size distributions.
- `eval_dedup.R` evaluates deduplication.

## Quantitative manuscript tables

`eval_csd.R` writes the numerical CSD overview (`tab/csd_overview.tex`) directly
from the measured mean/SD data: equal-weight relative target error and CV over
five targets, without clipping. `eval_summary.R` reads the existing CSD,
deduplication and performance CSVs directly and writes the worst-case summary
at 2 KiB. From this directory, run
`Rscript eval_summary.R ../csv tab/summary.tex` (replace `../csv` with
the experiment output directory). Keep startup profiles enabled: `--vanilla`
skips the `.Rprofile` that activates this project's `renv` library. If `readr`
is missing after activation, run
`Rscript -e 'renv::restore(packages = "readr", prompt = FALSE)'` from this directory.
No intermediate summary CSV is needed. See
[quantitative table definitions and input requirements](../analysis/quantitative_tables.md).
