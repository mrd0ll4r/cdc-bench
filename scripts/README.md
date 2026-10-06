# Experiment Scripts

These scripts specify the current artifact procedure. The exact versions and environment used for the published measurements require the historical run records listed in [REPRODUCIBILITY.md](../REPRODUCIBILITY.md).

**The scripts are intended to be executed from the repo root, e.g., `./scripts/run-all-experiments.sh`.**

Requires Bash 4+.

## Preparation

To run the experiments, you'll first need to download the datasets.
This will create TAR archives, one per dataset, which will then be analyzed and subsequently converted to one
concatenated file per dataset.

By default, data is stored in `<repo root>/data/` and copied to `<repo root>/fast_data/` for throughput experiments.
The latter should be mounted as a RAMdisk with at least 12GB of space.
The scripts assume that the binary was built using the Docker builder and is placed in `<repo root>/out/`.
You can adjust any of these paths in the [`utils.sh`](utils.sh) script.

### Datasets

First, collect the datasets using the following scripts:
- `get-db.sh` generates 25 DB images using QEMU/KVM and guest customization; see the [construction details and limitations](../REPRODUCIBILITY.md#db-construction).
- `get-vmb.sh` generates the VMB dataset. This requires QEMU and is intended to be run on a Debian host.
- `get-code.sh` downloads the CODE dataset.
- `get-lnx.sh` downloads the LNX dataset.
- `get-pdf.sh` downloads the PDF dataset.
    Note that this downloads the arXiv PDF buckets from S3, see [the docs on arXiv](https://info.arxiv.org/help/bulk_data_s3.html).
    You'll need the [aws-cli](https://github.com/aws/aws-cli) set up.
    The buckets are "Requester Pays", i.e., downloading may incur costs.
    Please refer to the documentation on arXiv.
- `get-rand.sh` creates a random binary file for the RAND dataset and a `random_small.bin` for the hash value
    distribution experiment.
- `get-web.sh` requests daily WEB captures for January 2024; see [retrieval details and limitations](../REPRODUCIBILITY.md#web-retrieval).

### Dataset Metadata

The `file-sizes.sh` script calculates file size distributions for the dataset TAR files.
It is possible to evaluate them for all datasets in parallel like so:
```bash
set -e
echo "Analyzing file sizes in parallel..."

bash -c 'DATASET="code.tar" make sizes > csv/sizes_code.txt' &
bash -c 'DATASET="web.tar" make sizes > csv/sizes_web.txt' &
bash -c 'DATASET="pdf.tar" make sizes > csv/sizes_pdf.txt' &
bash -c 'DATASET="lnx.tar" make sizes > csv/sizes_lnx.txt' &

sleep 1
echo "Waiting for jobs to finish..."
wait $(jobs -p)
```

The `datasets-entropy.sh` script calculates dataset entropy.
**TODO Marcel** fix the script, it uses `ent` still

The `dataset-composition.sh` script calculates the number of binary and text files per dataset.
**TODO Marcel** fix the script, it expects archives extracted into subdirectories per dataset.

### Dataset Concatenation

**TODO Marcel** Add a quick script to convert TAR to CAT.
Do not delete the TAR files, please.

### Mounts

Make sure `$FAST_DATA_PATH` (as per [`utils.sh`](utils.sh)) is mounted as `tmpfs`.

## Experiments

Once datasets and the run environment are prepared, `run-all-experiments.sh` orchestrates the current experiments from the repository root. The current `speed.sh` measures RAND only, irrespective of `DATASETS`; it defaults to ten repetitions and one warm-up per algorithm at the first target. It does not mount `fast_data` or enforce affinity, frequency, or NUMA policy. Record those settings using [the checklist](../REPRODUCIBILITY.md#author-input-checklist) before running experiments.
