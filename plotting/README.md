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
deduplication and performance CSVs directly and writes a numerical summary
at 2 KiB: worst-case storage/chunk-size metrics over CODE/WEB/VMB/DB and median
throughput on RAND, matching the existing experiments. From this directory, run
`Rscript eval_summary.R` to use `csv/`, like the other evaluation scripts.
Pass a different input directory explicitly only if the experiment files are
stored elsewhere. If CSD/dedup files are in `csv/` and timings in `../csv/`, run
`Rscript eval_summary.R --perf-dir ../csv`. The script reports both resolved
directories and input counts. Only RAND timings are used;
`--allow-missing` produces a review table with dashes for incomplete metrics.
Keep startup profiles enabled: `--vanilla`
skips the `.Rprofile` that activates this project's `renv` library. If `readr`
is missing after activation, run
`Rscript -e 'renv::restore(packages = "readr", prompt = FALSE)'` from this directory.
No intermediate summary CSV is needed. See
[quantitative table definitions and input requirements](../analysis/quantitative_tables.md).
