.SILENT:

# Produces an optimized and fast release build.
build:
	./build-in-docker.sh
	chmod +x scripts/*

# Run BFBC analysis on all datasets. Ouput is stored in ./data/bfbc/.
bfbc:
	./scripts/bfbc-analyze.sh

# Run speed benchmark on all chunkers.
speed:
	./scripts/speed.sh

# Produce comprehensive results on chunk size distribution.
csd:
	./scripts/chunk-sizes.sh

# Produce comprehensive dedup results (values in [0,1], the higher the better).
dedup:
	./scripts/dedup.sh

# Get average of produced chunk sizes (last chunk is omitted).
# Usage: cdc-algorithm-tester ... | make avg
avg:
	tail -n +2 | head -n -1 | awk -F, '{ sum += $$4 } END { if (NR > 0) print sum/NR }'

# Prints a CSV with the entropy of each dataset.
ent:
	./scripts/datasets-entropy.sh

# Prints a comma separated list of file sizes within a dataset (DATASET must be set).
sizes:
	./scripts/file-sizes.sh

# Print a CSV with the optimal divisors for each target chunk size in each dataset.
bfbc_divisors:
	./scripts/bfbc-divisors.sh

# Validate that the produced chunks add up to the original file size.
# Usage: cdc-algorithm-tester --input-file <input-file> ... | make validate <input-file>
validate:
	./scripts/validate.sh $(word 2, $(MAKECMDGOALS))
