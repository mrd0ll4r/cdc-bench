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

## Achieved-size and metadata-adjusted analysis

Use [`../analysis/dedup_pareto.py`](../analysis/dedup_pareto.py) with the
[matched-run input contract](../analysis/README.md) for the rebuttal's achieved-size
analysis. It requires all emitted chunk counts for the corresponding algorithm,
configuration and dataset identity; the historical dedup CSV alone is insufficient.
The R script retains configured-target plots but no longer generates the obsolete
Rabin-only metadata chart with hard-coded PDF/LNX dataset sizes.
