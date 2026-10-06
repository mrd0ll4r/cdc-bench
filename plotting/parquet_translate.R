library(dplyr)
library(bit64)
library(arrow)

csv_dir = "./csv"
output_dir= paste0(csv_dir, "/parquet/csd")

csd_datasets=c("code","db", "vmb", "web","random")

do_convert_csd = function(input_dataset_name, dataset_name, input_dir, output_dir) {
  outdir = paste0(output_dir, sprintf("/dataset=%s",dataset_name))
  if (dir.exists(outdir)) {
    print("exists, skipping")
    return()
  }

  infile = paste0(input_dir, sprintf("/csd_%s.csv.gz", input_dataset_name))
  if (!file.exists(infile)) {
    warning(sprintf("input file %s does not exist", infile))
    return()
  }

  read_csv_arrow(
    infile,
    col_types=schema(algorithm=utf8(), dataset=utf8(), target_chunk_size=int32(), chunk_size=int64()),
    as_data_frame=FALSE) %>%
    group_by(dataset, algorithm, target_chunk_size) %>%
    write_dataset(output_dir, format="parquet", hive_style = TRUE, compression="gzip")
}

for (ds in csd_datasets) {
  print(paste("converting", ds))

  do_convert_csd(ds, ds,csv_dir, output_dir)
  gc()
}
