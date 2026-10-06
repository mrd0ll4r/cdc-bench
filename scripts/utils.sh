#!/bin/bash -e

# Finds the best match for parameter w in MII to achieve given target chunk size.
get_w_for_mii() {
  MII_AVGS=(1 2 4 10 32 147 877 6248 51341 476910) # mapping from w to average chunk size for w=0..10
  target=$1
  closest=0
  distance=$(($target - ${MII_AVGS[0]}))
  for i in "${!MII_AVGS[@]}"; do
    current=${MII_AVGS[$i]}
    if [ "$current" -eq "$target" ]; then
      echo "$i"
      return
    fi
    current_distance=$(($target - $current))
    if [ $current_distance -lt 0 ]; then
      current_distance=$(($current_distance * -1))
    fi
    if [ $current_distance -lt $distance ]; then
      closest=$i
      distance=$current_distance
    fi
  done
  echo "$closest"
}

# Returns the best match for parameter w in AE to achieve given target chunk size.
get_w_for_ae() {
  case $1 in
  512)
    echo "348"
    ;;
  1024)
    echo "793"
    ;;
  2048)
    echo "1793"
    ;;
  4096)
    echo "3840"
    ;;
  8192)
    echo "7936"
    ;;
  *)
    echo "Error: Target chunk size not supported for AE."
    exit 1
    ;;
  esac
}

# Finds the best match for parameters w and t in PCI to achieve given target chunk size.
get_w_and_t_for_pci() {
  case $1 in
  512)
    echo "58 253"
    ;;
  1024)
    echo "34 157"
    ;;
  2048)
    echo "61 273"
    ;;
  4096)
    echo "39 183"
    ;;
  8192)
    echo "57 262"
    ;;
  *)
    echo "Error: Target chunk size not supported for PCI."
    exit 1
    ;;
  esac
}

get_params_for_seq() {
  case $1 in
  512)
    echo "4 65 512"
    ;;
  1024)
    echo "5 85 32"
    ;;
  2048)
    echo "5 85 256"
    ;;
  4096)
    echo "5 120 1024"
    ;;
  8192)
    echo "5 55 1024"
    ;;
  *)
    echo "Error: Target chunk size not supported for SeqCDC."
    exit 1
    ;;
  esac
}

get_subalgos() {
  local subalgos=()
  case $1 in
  "nc-gear")
    subalgos=("nc-gear 1" "nc-gear 2" "nc-gear 3")
    ;;
  "gear64")
    subalgos=("gear64" "gear64 --allow-simd-impl")
    ;;
  "quickcdc")
    subalgos=(
      "--quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 nc-gear 1"                                                     # 2/2 nc1
      "--quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 nc-gear 1"                                                     # 3/3 nc1
      "--quickcdc-use-hashmap --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 nc-gear 1"                              # 2/2 nc1 hash
      "--quickcdc-use-hashmap --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 nc-gear 1"                              # 3/3 nc1 hash
      "--quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 rabin 32"                                                      # 2/2 rabin32
      "--quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 rabin 32"                                                      # 3/3 rabin32
      "--quickcdc-use-hashmap --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 rabin 32"                               # 2/2 rabin32 hash
      "--quickcdc-use-hashmap --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 rabin 32"                               # 3/3 rabin32 hash
      "--quickcdc-min-chunk-size 0 --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 nc-gear 1"                         # 2/2 nc1 noskip
      "--quickcdc-min-chunk-size 0 --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 nc-gear 1"                         # 3/3 nc1 noskip
      "--quickcdc-min-chunk-size 0 --quickcdc-use-hashmap --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 nc-gear 1"  # 2/2 nc1 hash noskip
      "--quickcdc-min-chunk-size 0 --quickcdc-use-hashmap --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 nc-gear 1"  # 3/3 nc1 hash noskip
      "--quickcdc-min-chunk-size 0 --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 rabin 32"                          # 2/2 rabin32 noskip
      "--quickcdc-min-chunk-size 0 --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 rabin 32"                          # 3/3 rabin32 noskip
      "--quickcdc-min-chunk-size 0 --quickcdc-use-hashmap --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 rabin 32"   # 2/2 rabin32 hash noskip
      "--quickcdc-min-chunk-size 0 --quickcdc-use-hashmap --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 rabin 32"   # 3/3 rabin32 hash noskip
    )
    ;;
  "rabin")
    subalgos=(
      # "rabin 16"
      "rabin 32"
      # "rabin 48"
      # "rabin 64"
      # "rabin 128"
      # "rabin 256"
    )
    ;;
  "adler32")
    subalgos=(
      "adler32 16"
      "adler32 32"
      "adler32 48"
      "adler32 64"
      "adler32 128"
      "adler32 256"
    )
    ;;
  "buzhash")
    subalgos=(
      # "buzhash 16"
      "buzhash 32"
      # "buzhash 48"
      # "buzhash 64"
      # "buzhash 128"
      # "buzhash 256"
    )
    ;;
  "bfbc")
    subalgos=("bfbc" "bfbc_custom_div") # the name bfbc_custom_div is just a marker and will be evaluated in get_cmd
    ;;
  *)
    subalgos=("$1")
    ;;
  esac
  for subalgo in "${subalgos[@]}"; do echo "$subalgo"; done
}

get_algo_name() {
  case "$1" in
  "nc-gear"*)
    local level=$(echo "$1" | awk -F' ' '{print $2}')
    echo "gear_nc_$level"
    ;;
  "gear64 --allow-simd-impl")
    echo "gear64_simd"
    ;;
  "--quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 nc-gear 1")
    echo "quick_2"
    ;;
  "--quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 nc-gear 1")
    echo "quick_3"
    ;;
  "--quickcdc-use-hashmap --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 nc-gear 1")
    echo "quick_hash_2"
    ;;
  "--quickcdc-use-hashmap --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 nc-gear 1")
    echo "quick_hash_3"
    ;;
  "--quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 rabin 32")
    echo "quick_2_rabin_32"
    ;;
  "--quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 rabin 32")
    echo "quick_3_rabin_32"
    ;;
  "--quickcdc-use-hashmap --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 rabin 32")
    echo "quick_hash_2_rabin_32"
    ;;
  "--quickcdc-use-hashmap --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 rabin 32")
    echo "quick_hash_3_rabin_32"
    ;;
  "--quickcdc-min-chunk-size 0 --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 nc-gear 1")
    echo "quick_2_noskip"
    ;;
  "--quickcdc-min-chunk-size 0 --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 nc-gear 1")
    echo "quick_3_noskip"
    ;;
  "--quickcdc-min-chunk-size 0 --quickcdc-use-hashmap --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 nc-gear 1")
    echo "quick_hash_2_noskip"
    ;;
  "--quickcdc-min-chunk-size 0 --quickcdc-use-hashmap --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 nc-gear 1")
    echo "quick_hash_3_noskip"
    ;;
  "--quickcdc-min-chunk-size 0 --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 rabin 32")
    echo "quick_2_rabin_32_noskip"
    ;;
  "--quickcdc-min-chunk-size 0 --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 rabin 32")
    echo "quick_3_rabin_32_noskip"
    ;;
  "--quickcdc-min-chunk-size 0 --quickcdc-use-hashmap --quickcdc-front-feature-vector-length 2 --quickcdc-end-feature-vector-length 2 rabin 32")
    echo "quick_hash_2_rabin_32_noskip"
    ;;
  "--quickcdc-min-chunk-size 0 --quickcdc-use-hashmap --quickcdc-front-feature-vector-length 3 --quickcdc-end-feature-vector-length 3 rabin 32")
    echo "quick_hash_3_rabin_32_noskip"
    ;;
  "bfbc_custom_div")
    echo "bfbc_custom_div"
    ;;
  "rabin"*)
    echo "${1/ /_}"
    ;;
  "adler32"*)
    echo "${1/ /_}"
    ;;
  "buzhash"*)
    echo "${1/ /_}"
    ;;
  *)
    echo "$subalgo"
    ;;
  esac
}

# Get cmd args for execution of algorithm. Pass arguments in the following order: algorithm, dataset, target chunk size.
get_cmd_args() {
  local args_and_algo="$1"
  local params="$3"
  case "$1" in
  "pci")
    params="$(get_w_and_t_for_pci "$3")"
    ;;
  "ae")
    params="$(get_w_for_ae "$3")"
    ;;
  "ram")
    params="$(python3 scripts/get-ram-param.py "$3")"
    ;;
  "mii")
    params="$(get_w_for_mii "$3")"
    ;;
  "seq-cdc")
    params="$(get_params_for_seq "$3")"
    ;;
  "nop")
    params=""
    ;;
  *"quickcdc"*)
    # if --quickcdc-min-chunk-size is not set, set it to half of the target chunk size, otherwise we assume min=0 with regards to the target chunk size
    if [[ $1 != *quickcdc-min-chunk-size* ]]; then
      local min=$(($3 / 2))
      args_and_algo="--quickcdc-min-chunk-size $min $1"
      params="$(($3 - $min))"
    fi
    ;;
  "bfbc")
    args_and_algo="bfbc chunk --frequency-file $DATA_PATH/bfbc/$2.stats --byte-pair-indices 0 1 2 --min-chunk-size $(($3 - 128))"
    params=""
    ;;
  "bfbc_custom_div")
    local divisors="$(python3 scripts/get-bfbc-divisors.py "$2" "$3" 2)"
    args_and_algo="bfbc chunk --frequency-file $DATA_PATH/bfbc/$2.stats --byte-pair-indices $divisors --min-chunk-size 2"
    params=""
    ;;
  esac
  echo "$args_and_algo $params"
}

# Get command string for chunker. Pass arguments in the following order: algorithm, dataset, target chunk size.
get_cmd() {
  local args="$(get_cmd_args "$1" "$2" "$3")"
  echo "$BIN -i $DATA_PATH/$2 $args"
}

# Global settings
export BIN=./out/cdc-algorithm-tester
export DATA_PATH=data
export FAST_DATA_PATH=fast_data

if [ -z "${TARGET_CHUNK_SIZES}" ]; then
  TARGET_CHUNK_SIZES=(512 1024 2048 4096 8192)
else
  # shellcheck disable=SC2207
  TARGET_CHUNK_SIZES=($(echo "$TARGET_CHUNK_SIZES" | tr ',' ' '))
fi

if [ -z "${ALGOS}" ]; then
  ALGOS=("fsc" "ae" "ram" "mii" "pci" "rabin" "buzhash" "gear" "seq-cdc")
  # detect if we are running speed tests
  if [[ "$0" == *"speed"* ]]; then
    ALGOS=("nop" "${ALGOS[@]}")
  fi
else
  # shellcheck disable=SC2207
  ALGOS=($(echo "$ALGOS" | tr ',' ' '))
fi

if [ -z "${DATASETS}" ]; then
  DATASETS=("random" "web" "code" "db" "vmb")
else
  # shellcheck disable=SC2207
  DATASETS=($(echo "$DATASETS" | tr ',' ' '))
fi

mkdir -p "$DATA_PATH"
mkdir -p "$FAST_DATA_PATH"

