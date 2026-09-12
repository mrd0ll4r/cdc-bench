# Extended-results author input and analysis

**RESULTS PENDING / AUTHOR INPUT REQUIRED.** No experimental measurements are
included. `inputs/manifest.pending.json` deliberately contains zero runs. The two
header-only CSVs specify the input format; they are not results. Existing plot
coordinates and previously aggregated tables cannot supply the requested tails or
repetition uncertainty. This script only analyzes supplied data; it never runs a
benchmark. It is independent of the deduplication analysis branch.

## Required grid and provenance

Supply one selected run per Cartesian-product setting (200 total):

- Exact implementation identifiers: `rabin_32`, `buzhash_32`, `gear`, `ae`, `ram`,
  `pci`, `mii`, `seq-cdc`. Do not use aliases or mix variants.
- Datasets: `RAND`, `CODE`, `WEB`, `VMB`, `DB`.
- Configured targets, in bytes: `512`, `1024`, `2048`, `4096`, `8192`.

The target is the value passed to the configuration, including MII. Do not replace
it with a predicted or observed mean. Record exact effective algorithm parameters
(window, mask, horizon, thresholds, seed, and other applicable parameters) in each
run. A setting is complete only when chunks, timings, and provenance all validate.
All supplied settings get chunk and timing summaries; a separate table compares
DB with RAND at 2048 bytes. Multiple runs for the same setting are rejected: select
and document one run containing all intended repetitions, never silently pool
independent campaigns. A run ID identifies this selected chunking/timing bundle.

Use a JSON manifest shaped as follows. Angle-bracket strings are **author input
placeholders**, and this illustration intentionally will not validate as data:

```json
{
  "schema_version": 1,
  "chunk_population": "all-emitted",
  "timing_measure": "cpu-task-clock",
  "datasets": {
    "RAND": {
      "dataset_size": "<exact total bytes>",
      "dataset_fingerprint": "sha256:<64 lowercase hex digits>",
      "provenance": "<dataset construction, version/seed, ordered stream inventory and fingerprint procedure>",
      "stream_sizes": {"<stream identifier>": "<exact byte count>"}
    }
  },
  "runs": [{
    "algorithm": "rabin_32",
    "dataset": "RAND",
    "target_chunk_size": 2048,
    "run_id": "<unique safe identifier>",
    "dataset_fingerprint": "sha256:<same dataset fingerprint>",
    "chunk_population": "all-emitted",
    "environment_id": "<hardware/OS/compiler/build-affinity environment record>",
    "source_revision": "<exact implementation commit and dirty-state record>",
    "command": "<full measurement command and warm-up/repetition selection procedure>",
    "parameters": {"<parameter name>": "<effective value>"},
    "chunk_count": "<expected all-emitted chunk count>",
    "timing_repetitions": "<expected repetition count, at least 2>",
    "chunks_csv": "<relative path under manifest directory>",
    "timings_csv": "<relative path under manifest directory>"
  }]
}
```

Replace numeric placeholders with JSON integers. The fingerprint must identify
exact input bytes **and their ordered stream boundaries**; describe the construction
and hashing procedure in `provenance` and retain its inventory. Supply every stream,
including empty ones (size zero). Stream metadata is checked against dataset size.
The exporter validates coverage and fingerprint consistency, not the original
input contents; the author is responsible for the fingerprint's authenticity.
`environment_id` must resolve to a retained environment record. All timing inputs
use the same declared measure (`cpu-task-clock` or `wall-clock`), in seconds. For
compatibility with existing R throughput figures, use perf `task-clock` converted
from milliseconds to seconds. Never mix task-clock and wall-clock repetitions.
DB/RAND comparisons require identical environment, source revision, and effective
parameters for the same algorithm and configured target.

## Raw CSVs

UTF-8 CSV headers and column order must exactly match the header files.

`chunks_csv`: `stream_id,chunk_index,chunk_size,is_final`

One row per **all-emitted** positive-size chunk, including the final partial chunk
of every stream, without filtering small or large chunks. A zero-length stream
emits zero chunks. A stream means one independent chunker input; retain actual
reset/concatenation boundaries. Group records by stream; within each stream use
contiguous zero-based chunk indices in order. Only the last chunk has `is_final=1`;
all others have `0`, even if the last chunk happens to meet a natural boundary.
The validator rejects duplicate/out-of-order IDs, revisited streams, missing final
markers, excluded terminal bytes, mismatched counts, and stream-byte totals.
CSV byte totals must equal the complete dataset size for every setting.

`timings_csv`: `repetition,elapsed_seconds,processed_bytes`

One row per retained measurement, with contiguous zero-based repetition IDs.
Elapsed seconds must be positive and finite. Every repetition must process exactly
`dataset_size` bytes. Warm-ups must be identified in the run's provenance and
excluded consistently before export; the analyzer performs no trimming or outlier
removal. Retain all original raw repetitions and selection records. The manifest's
repetition count is an explicit completeness check, with a minimum of two; it is
not a statistical adequacy claim. Supply the original intended count, not two
selected observations.

## Statistics and output

Chunk quantiles use the inverse empirical CDF (nearest rank): sorted observation
`ceil(n*p)`, with one-based ranks. Thus an even-size population's chunk median is
the lower central observation. We report Q1, median, Q3, P99, P99.9, and maximum in
bytes. The tail statistic is **byte-weighted**:

`sum(size for all emitted chunks with size > 4 * configured_target) / dataset_size`.

A chunk equal to `4 * configured_target` is excluded from this numerator. Mean and
sample SD use the same population; sample SD has divisor `n-1`, matching R `sd()`.
SD is undefined (JSON null / CSV blank) for one chunk. These summaries cannot be
mixed with historical statistics that excluded final partial chunks.

Timing statistics summarize per-repetition throughput
`processed_bytes / elapsed_seconds / 2**20` in MiB/s (not inverse median duration).
Median averages the two central values for even sample counts. Q1 and Q3 use R's
default type 7: linear interpolation at zero-based index `(n-1)*p`; IQR is Q3-Q1.
This timing convention matches the existing R analysis and differs deliberately
from the explicitly discrete chunk-quantile convention. No confidence interval or
unverified +/-2% claim is inferred. The DB-versus-RAND CSV records the signed median
throughput change `100*(DB/RAND - 1)`; inspect the supplied repetitions and quartiles
before writing conclusions.

```sh
python3 analysis/extended_results.py /path/to/author-input/manifest.json --output out/extended-results
python3 -m unittest discover -s analysis/tests -v
```

Production export rejects any missing grid setting. To create an explicitly
incomplete review artifact only:

```sh
python3 analysis/extended_results.py analysis/inputs/manifest.pending.json --output out/extended-results-pending --allow-missing
```

Outputs go into a new/empty directory, protecting existing exports:

- `summary.csv` and `provenance.json`: full precision normalized statistics,
  including `algorithm,dataset,target_chunk_size,dataset_size,chunk_count,
  mean_chunk_size,sd_chunk_size,median_throughput_mib_s,run_id,
  dataset_fingerprint,chunk_population`, exact parameter JSON and provenance.
- `timing-repetitions.csv`: normalized per-repetition values; `raw/` retains
  byte-for-byte timing CSVs and the original manifest. **Chunk inputs remain in
  their original locations**; preserve these immutable files. Provenance records
  each absolute input path and SHA-256 plus the manifest and analysis checksums.
  The export is not a self-contained archive of chunk data.
- `db-rand-comparison.csv`, `missing-settings.csv` (every missing algorithm/dataset/
  target), `extended-coverage.tex`, `extended-db-rand.tex`, `extended-chunks.tex`,
  and `extended-timings.tex`. Empty CSV outputs retain headers and contain no observations. Missing
  measurements appear as pending in TeX and are never replaced with zeros.

Chunk records are streamed, and exact statistics use a histogram of distinct
sizes plus stream metadata. Memory scales with distinct sizes and stream count,
not chunk count; one configuration is processed at a time. Raw chunks are never
copied into RAM or duplicated into the export. A second streaming pass hashes the
sources; do not modify inputs during analysis. Timing inputs are small and retained
in memory. Extreme cases with very many distinct sizes still require corresponding
histogram memory. No external statistics dependencies are required (Python 3.11+).

The committed tests use tiny synthetic fixtures only, including a complete
synthetic 200-setting grid, even-sample timing quartiles, exact tail boundaries,
sample SD, and malformed/missing/duplicate/population-mismatch rejection. They are
not evidence about algorithm performance.
