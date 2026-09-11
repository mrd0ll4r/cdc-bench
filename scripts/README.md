# Experiment Scripts

These are the scripts used to run the experiments for the paper.

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
- `get-web.sh` downloads the WEB dataset.

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

Once you have all datasets setup, simply execute `run-all-experiments.sh` from the repository root.

## RAM parameter modes

`python3 scripts/get-ram-param.py TARGET` retains the historical calculation and
SciPy solver used by the experiment scripts. `--mode legacy` makes this explicit.
For targets 512, 1024, 2048, 4096, and 8192 B, both forms return horizons 327, 780,
1792, 3840, and 7936. This mode is for reproducing the published configurations;
its inverse-of-mean-success-probability expression is not an exact mean length.

`python3 scripts/get-ram-param.py TARGET --mode exact` instead averages conditional
geometric waiting times over the maximum of `h` IID uniform bytes. The model
includes the first matching byte in the chunk and assumes an unbounded stream.
It returns the positive integer horizon whose theoretical mean is closest to the
target (smaller horizon on an exact tie). For the same targets it returns 300,
774, 1792, 3840, and 7936. This mode uses only the Python standard library.

The experiment command generator continues to use the default historical mode.
Do not relabel historical results as measurements with the corrected horizons.
For new experiments, record the chosen mode and check the chunker's boundary
indexing convention against this theoretical definition before comparing means;
the script does not change the chunker or account for terminal chunks.

Run numerical and compatibility checks with
`python3 -m unittest discover -s scripts/tests -p 'test_ram_params.py' -v`.
