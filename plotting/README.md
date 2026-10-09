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
at 2 KiB: minimum/maximum storage savings and worst-case chunk-size metrics
over CODE/WEB/VMB/DB, plus median
throughput on RAND, matching the existing experiments. Columns appear as
Throughput, Chunk Sizes (Max. Err., Max. CV), then Storage Savings (Min., Max.).
Error and savings use fractions with two decimals; throughput uses MiB/s.
The table inherits the document font size and uses 4 pt column padding.
Columns are ranked independently; no caption or explanatory note is generated.
In RStudio, set the
working directory to this `plotting/` directory, open `eval_summary.R`, and
click **Source** (or run `source("eval_summary.R")` in the R console). Edit the
settings at the top if needed: they default to CSD/dedup in `csv/`, performance
in `../csv/`, and output in `tab/summary.tex`. Missing packages can be installed
in the R console with `renv::install(c("DBI", "duckdb"))`.

For command-line use, from this directory run
`Rscript eval_summary.R` to use `csv/`, like the other evaluation scripts.
Pass a different input directory explicitly only if the experiment files are
stored elsewhere. If CSD/dedup files are in `csv/` and timings in `../csv/`, run
`Rscript eval_summary.R --perf-dir ../csv`. The script reports both resolved
directories and input counts. Only RAND timings are used;
`--allow-missing` produces a review table with dashes for incomplete metrics.
Keep startup profiles enabled: `--vanilla`
skips the `.Rprofile` that activates this project's `renv` library. The summary
uses `DBI` and `duckdb`, as does the CSD evaluation. If they are missing, run
`Rscript -e 'renv::install(c("DBI", "duckdb"))'` from this directory.
DuckDB reads the compressed CSVs and aggregates CSD counts, bytes, means and
sample SDs directly; raw chunk rows are never loaded into R.
No intermediate summary CSV is needed. See
[quantitative table definitions and input requirements](../analysis/quantitative_tables.md).
