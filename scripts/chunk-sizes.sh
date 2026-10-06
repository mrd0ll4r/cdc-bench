#!/bin/bash -e

source scripts/utils.sh

# Process a single parameter combination
process_combination() {
    source scripts/utils.sh
    local algo="$1"
    local dataset="$2"
    local cs="$3"
    
    local dataset_name="${dataset%%.*}"
    readarray -t subalgos < <(get_subalgos "$algo")
    
    # Find files specific to this dataset
    local dataset_files=$(find -L "$DATA_PATH/$dataset" -type f -path "*/*/[!.]*" | grep -v "/\.")
    
    for file in $dataset_files; do
        for subalgo in "${subalgos[@]}"; do
            subalgo_name=$(get_algo_name "$subalgo")
            local rel_path="${file#"$DATA_PATH"/}"
            local prefix=$(printf "%s,%s,%d" "$subalgo_name" "$dataset_name" "$cs")
            local cmd=$(get_cmd "$subalgo" "$rel_path" "$cs")
            echo "$cmd" >&2
            $cmd | awk -v prefix="$prefix" -F, '{print prefix "," $2}'
        done
    done
}

# Export required functions and variables for parallel execution
export -f process_combination
export -f get_subalgos
export -f get_algo_name
export -f get_cmd
export -f get_cmd_args
export DATA_PATH
export TMPDIR=~/tmp
ulimit -n 4096

# CSV header
echo "algorithm,dataset,target_chunk_size,chunk_size"

# Run in parallel with all parameter combinations (no files here)
#parallel --will-cite -j+0 process_combination \
#    ::: "${ALGOS[@]}" \
#    ::: "${DATASETS[@]}" \
#    ::: "${TARGET_CHUNK_SIZES[@]}"

for algo in "${ALGOS[@]}"; do
  for dataset in "${DATASETS[@]}"; do
    TARGET_CHUNK_SIZES=(512 1024 2048 4096 8192)
    for cs in "${TARGET_CHUNK_SIZES[@]}"; do
      process_combination "$algo" "$dataset" "$cs"
    done
  done
done
