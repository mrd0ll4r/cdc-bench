#!/bin/bash -e

source .venv/bin/activate
mkdir -p csv

########################
# Computational Performance Measurements


########################
# Chunk size distributions

bash -c 'DATASETS="random" make csd | gzip -9 > csv/csd_random.csv.gz' 
bash -c 'DATASETS="code" make csd | gzip -9 > csv/csd_code.csv.gz' 
bash -c 'DATASETS="web" make csd | gzip -9 > csv/csd_web.csv.gz' 
bash -c 'DATASETS="db" make csd | gzip -9 > csv/csd_db.csv.gz' 
bash -c 'DATASETS="vmb" make csd | gzip -9 > csv/csd_vmb.csv.gz' 

sleep 1
echo "Waiting for csd jobs to finish..."
wait $(jobs -p)
exit 0
########################
# Deduplication ratios

echo "Starting deduplication ratio measurements..."

bash -c 'DATASETS="random" make dedup | gzip -9 > csv/dedup_random.csv.gz' 
bash -c 'DATASETS="code" make dedup | gzip -9 > csv/dedup_code.csv.gz' 
bash -c 'DATASETS="web" make dedup | gzip -9 > csv/dedup_web.csv.gz' 
bash -c 'DATASETS="db" make dedup | gzip -9 > csv/dedup_db.csv.gz' 
bash -c 'DATASETS="vmb" make dedup | gzip -9 > csv/dedup_vmb.csv.gz' 

########################
# Hash value distributions

# echo "Starting hash value distribution experiments in the background..."
# ./scripts/hash-value-distributions.sh &

########################

sleep 1
echo "Waiting for dedup jobs to finish..."
wait $(jobs -p)

########################

echo "Splitting chunk size distribution measurements by algorithm..."

for f in csv/csd_*.csv.gz; do
        echo "splitting $f..."
        header=$(zcat "$f" | head -n 1)
        b=$(basename "$f" ".csv.gz")
        filter="{print > (\"csv/${b}_\" \$1 \".csv\")}"
        zcat "$f" | awk "$filter" FS=,

        # Clean up the empty _algorithm file produced (from the header)
        rm "csv/${b}_algorithm.csv"

        echo "compressing..."
        for ff in csv/${b}_*.csv; do
                # prepend the header
                sed -i -e "1i $header" "$ff"
                gzip -9 "$ff"
        done
done


echo "All done."
