# Table X from one provenance-checked run summary per configuration.
# Run from plotting/: Rscript --vanilla eval_summary.R INPUT.csv tab/summary.tex
# Optional: --allow-missing (review only), --include-fsc (unranked reference).
# See ../analysis/quantitative_tables.md for the input contract.

args <- commandArgs(trailingOnly = TRUE)
allow_missing <- "--allow-missing" %in% args
include_fsc <- "--include-fsc" %in% args
paths <- args[!args %in% c("--allow-missing", "--include-fsc")]
if (length(paths) != 2L) {
  stop("Usage: Rscript eval_summary.R INPUT.csv OUTPUT.tex [--allow-missing] [--include-fsc]")
}
algorithms <- c("rabin_32", "buzhash_32", "gear", "ae", "ram", "pci", "mii", "seq-cdc")
labels <- c("Rabin", "Buzhash", "Gear", "AE", "RAM", "PCI", "MII", "SeqCDC")
if (include_fsc) {
  algorithms <- c(algorithms, "fsc")
  labels <- c(labels, "FSC")
}
datasets <- c("CODE", "WEB", "VMB", "DB")
codes <- c("C", "W", "V", "D")
keys <- c("algorithm", "dataset", "target_chunk_size")
provenance <- c("run_id", "dataset_fingerprint", "chunk_population")
fields <- c("mean_chunk_size", "sd_chunk_size", "dataset_size", "chunk_count",
            "unique_chunks_size_sum", "median_throughput_mib_s")
rows <- read.csv(paths[1], colClasses = "character", check.names = FALSE,
                 na.strings = c("", "NA", "N/A"), strip.white = TRUE,
                 fill = FALSE, row.names = NULL)
if (anyDuplicated(names(rows)) || !all(c(keys, provenance, fields) %in% names(rows))) {
  stop("Input requires unique column names and all key, provenance and measurement columns")
}
rows[keys] <- lapply(rows[keys], trimws)
if (anyNA(rows[keys]) || any(!rows$algorithm %in% c(algorithms, "fsc")) ||
    any(!rows$dataset %in% c("RAND", datasets)) ||
    any(!rows$target_chunk_size %in% c("512", "1024", "2048", "4096", "8192"))) {
  stop("Unknown algorithm, dataset, or configured target")
}
if (anyDuplicated(rows[keys])) stop("Duplicate configuration")
for (field in fields) {
  value <- suppressWarnings(as.numeric(rows[[field]]))
  supplied <- !is.na(rows[[field]])
  zero_allowed <- field %in% c("sd_chunk_size", "unique_chunks_size_sum")
  if (any(supplied & (!is.finite(value) | value < 0 | (!zero_allowed & value == 0)))) {
    stop(paste("Invalid measured value:", field))
  }
  if (field %in% c("dataset_size", "chunk_count", "unique_chunks_size_sum") &&
      any(supplied & (value != trunc(value) | value > 2^53 - 1))) {
    stop(paste("Expected exact integer bytes/count within R's numeric range:", field))
  }
  rows[[field]] <- value
}
measured <- rowSums(!is.na(rows[fields])) > 0
if (any(measured & (is.na(rows$chunk_population) | rows$chunk_population != "all-emitted")) ||
    any(vapply(rows[provenance], function(x) any(measured & (is.na(x) | trimws(x) == "")), logical(1)))) {
  stop("Measured rows require a run ID, dataset fingerprint and all-emitted population")
}
if (any(rows$unique_chunks_size_sum > rows$dataset_size, na.rm = TRUE) ||
    any(rows$chunk_count > rows$dataset_size, na.rm = TRUE) ||
    any(abs(rows$mean_chunk_size - rows$dataset_size / rows$chunk_count) >
        1e-6 * rows$dataset_size / rows$chunk_count, na.rm = TRUE)) {
  stop("Inconsistent all-emitted byte/count accounting")
}
for (ds in unique(rows$dataset[measured])) {
  selected <- rows[measured & rows$dataset == ds, ]
  if (length(unique(selected$dataset_fingerprint)) != 1L ||
      length(unique(na.omit(selected$dataset_size))) > 1L) {
    stop(paste("Inconsistent dataset fingerprint or byte count:", ds))
  }
}
grid <- expand.grid(algorithm = algorithms, dataset = datasets,
                    target_chunk_size = "2048", stringsAsFactors = FALSE)
selected <- merge(grid, rows, by = keys, all.x = TRUE, sort = FALSE)
if (!allow_missing && anyNA(selected[fields])) {
  stop("Incomplete evaluation domain; use --allow-missing only for review placeholders")
}
selected$savings <- 1 - (selected$unique_chunks_size_sum + 64 * selected$chunk_count) / selected$dataset_size
selected$error <- abs(selected$mean_chunk_size / 2048 - 1)
selected$cv <- selected$sd_chunk_size / selected$mean_chunk_size
metrics <- c("savings", "median_throughput_mib_s", "error", "cv")
values <- matrix(NA_real_, nrow = length(algorithms), ncol = 4,
                 dimnames = list(algorithms, metrics))
extrema <- matrix("", nrow = length(algorithms), ncol = 4,
                  dimnames = list(algorithms, metrics))
for (i in seq_along(algorithms)) {
  group <- selected[selected$algorithm == algorithms[i], ]
  group <- group[match(datasets, group$dataset), ]
  for (j in seq_along(metrics)) {
    v <- group[[metrics[j]]]
    if (all(is.finite(v))) {
      values[i, j] <- if (j <= 2) min(v) else max(v)
      extrema[i, j] <- paste(codes[v == values[i, j]], collapse = ",")
    }
  }
}
# Rank unrounded values; do not rank incomplete CDC domains or include FSC.
ranks <- lapply(seq_along(metrics), function(j) {
  v <- values[seq_len(8), j]
  if (anyNA(v)) numeric() else head(sort(unique(v), decreasing = j <= 2), 2)
})
lines <- c(
  "\\begingroup", "\\scriptsize\\setlength{\\tabcolsep}{3pt}",
  "\\begin{tabular}{lrrrr}", "\\toprule",
  "Algorithm & Min. $D_{64}$ & Min. throughput & Max. error & Max. CV \\\\",
  "& (\\%) $\\uparrow$ & (MiB/s) $\\uparrow$ & (\\%) $\\downarrow$ & $\\downarrow$ \\\\",
  "\\midrule"
)
for (i in seq_along(algorithms)) {
  cells <- character(4)
  for (j in seq_along(metrics)) {
    v <- values[i, j]
    cells[j] <- if (is.na(v)) "\\textemdash{}" else sprintf("%.2f", v * if (j %in% c(1, 3)) 100 else 1)
    rank <- match(v, ranks[[j]])
    if (i <= 8 && !is.na(rank)) {
      cells[j] <- paste0(if (rank == 1) "\\textbf{" else "\\underline{", cells[j], "}")
    }
    if (nzchar(extrema[i, j])) cells[j] <- paste0(cells[j], "\\textsuperscript{", extrema[i, j], "}")
  }
  lines <- c(lines, paste0(paste(c(labels[i], cells), collapse = " & "), " \\\\"))
}
lines <- c(lines, "\\bottomrule", "\\end{tabular}", "\\endgroup",
           paste0("\\par\\smallskip\\footnotesize Superscripts identify every dataset attaining the extremum: ",
                  "C = CODE, W = WEB, V = VMB, D = DB. Bold: best; underline: second distinct value ",
                  "among the eight CDC algorithms, retaining ties in unrounded values. Arrows indicate ",
                  "preferred direction. Ranking is withheld for any incomplete metric."))
if (anyNA(values)) {
  lines <- c(lines, paste0("\\par\\smallskip\\footnotesize\\textbf{REBUTTAL-DATA-PENDING:} ",
                          "Dashes denote unavailable worst-case values, not zero. Each value requires all four realistic datasets."))
}
writeLines(lines, paths[2])
saveRDS(list(input = normalizePath(paths[1]), source_rows = rows, values = values, extrema = extrema),
        sub("\\.tex$", "", paths[2]) |> paste0(".audit.rds"))
