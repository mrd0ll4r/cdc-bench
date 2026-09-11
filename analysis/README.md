# Matched-run deduplication analysis

`dedup_pareto.py` uses Python 3's standard library. It does not run benchmarks or
recover measurements from existing plots. Supply author-verified normalized data:

```sh
python3 analysis/dedup_pareto.py matched-results.csv --output-dir /tmp/dedup-results
python3 -m unittest discover -s analysis/tests -p 'test_dedup_pareto.py'
```

Required CSV columns:

| Column | Meaning |
|---|---|
| `algorithm` | `fsc`, `ae`, `ram`, `mii`, `pci`, `rabin_32`, `buzhash_32`, `gear`, `seq-cdc` |
| `dataset` | CODE, WEB, VMB, DB (case insensitive) |
| `target_chunk_size` | Configured target bytes: 512, 1024, 2048, 4096, 8192 |
| `dataset_size` | Exact input bytes S |
| `chunk_count` | Total emitted chunks N, including repeated chunks and final partial chunks |
| `unique_chunks_size_sum` | Exact sum of unique emitted chunk bytes U |
| `mean_chunk_size` | Arithmetic mean of **all** N chunks; must agree with S/N within relative 1e-6 |
| `run_id` | Nonempty stable run identifier resolving to the source records/configuration |
| `dataset_fingerprint` | Nonempty content digest or manifest identifier for the exact byte population |
| `chunk_population` | Literal `all-emitted` |

Extra columns, including `sd_chunk_size` and `median_throughput_mib_s` for the
quantitative-table pipeline, are accepted and ignored here. Provide one row for
every algorithm/dataset/target combination (180 rows). Do not replace configured
MII targets with its horizon/window or predicted mean: repeated underlying MII
settings may legitimately appear under several configured targets. The script
requires the complete grid and rejects duplicates instead of silently averaging
runs or dropping unavailable algorithms. Choose the run in the source manifest.

The supplier must attest that S, N, U and the mean in a row come from that same
run, with identical file order, boundary-reset policy and chunk inclusion policy.
The dedup script's historical output lacks N and provenance; it **cannot** be used
alone. Do not join chunk counts from a different algorithm or a filtered CSD export
that excludes terminal chunks. Join source records by dataset fingerprint,
algorithm, exact configuration and run identity before normalizing. The script
checks byte accounting and dataset identity across configurations, but identifiers
alone cannot prove provenance. Store the source manifest alongside the input.

Outputs:

- `dedup-adjusted.csv`: raw savings and `1 - (U + m*N)/S`, for m=28,48,64 bytes.
  Negative savings are preserved. Means used for plotting are recomputed as S/N.
- `dedup-pareto-{28,48,64}.tex`: four PGFPlots panels with every measured point,
  a common algorithm legend and a larger ring around nondominated configurations.
  A point dominates another if both mean and adjusted savings are at least as
  high and one is strictly higher. Equal coordinates retain all ties. There is
  no interpolation, fitted curve, or implication of measured equal-size comparisons.
- `dedup-provenance.json`: input/script SHA-256 hashes, grid and analysis choices.

After reviewing the input provenance and outputs, copy the three generated TeX
files to the paper's `fig/` directory, replacing its explicit `RESULTS PENDING`
placeholders. Keep the CSV and manifest with the experiment record. The 28 B model
is illustrative metadata per emitted chunk, not a measured implementation cost;
48/64 B are sensitivity assumptions. This model excludes compression, per-unique
index overhead beyond the allowance, replication, and complete system cost.
