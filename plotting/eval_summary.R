# Table X directly from the existing experiment CSVs (plain or gzip).
# From plotting/: Rscript eval_summary.R
# Keep startup profiles enabled so .Rprofile activates the renv library.
# Defaults: csv/ and tab/summary.tex. Requires the existing readr dependency.
# Optional: --allow-missing (review only), --include-fsc (unranked reference).

args <- commandArgs(trailingOnly = TRUE)
usage <- "Usage: Rscript eval_summary.R [CSV_DIR [OUTPUT.tex]] [--perf-dir DIR] [--allow-missing] [--include-fsc]"
if ("--help" %in% args) {
  cat(usage, "\nReads csd_*.csv[.gz], dedup_*.csv[.gz], and perf_*.csv[.gz].\n",
      "Defaults: CSV_DIR=csv, OUTPUT.tex=tab/summary.tex; performance files use CSV_DIR unless --perf-dir is supplied.\n")
  quit(status = 0)
}
allow_missing <- "--allow-missing" %in% args
include_fsc <- "--include-fsc" %in% args
paths <- args
perf_option <- which(paths == "--perf-dir")
perf_dir <- NULL
if (length(perf_option)) {
  if (length(perf_option) != 1L || perf_option == length(paths) ||
      startsWith(paths[perf_option + 1L], "--")) stop(usage)
  perf_dir <- paths[perf_option + 1L]
  paths <- paths[-c(perf_option, perf_option + 1L)]
}
paths <- paths[!paths %in% c("--allow-missing", "--include-fsc")]
if (length(paths) > 2L || any(startsWith(paths, "--"))) stop(usage)
csv_dir <- if (length(paths)) paths[1] else "csv"
if (is.null(perf_dir)) perf_dir <- csv_dir
output_path <- if (length(paths) > 1L) paths[2] else "tab/summary.tex"
if (!dir.exists(csv_dir)) stop(paste("Experiment directory does not exist:", csv_dir))
if (!dir.exists(perf_dir)) stop(paste("Performance directory does not exist:", perf_dir))
if (!requireNamespace("readr", quietly = TRUE)) {
  stop(paste0(
    "readr is not available in the active R library. From plotting/, run ",
    "Rscript eval_summary.R without --vanilla or --no-init-file ",
    "so .Rprofile activates renv. If readr is still missing, run ",
    "Rscript -e 'renv::restore(packages = \"readr\", prompt = FALSE)' and retry."
  ), call. = FALSE)
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
fields <- c("mean_chunk_size", "sd_chunk_size", "dataset_size", "chunk_count",
            "unique_chunks_size_sum")

input_files <- function(prefix) {
  directory <- if (prefix == "perf") perf_dir else csv_dir
  files <- sort(list.files(directory, paste0("^", prefix, "_.*\\.csv(\\.gz)?$"), full.names = TRUE))
  # The experiment script leaves per-algorithm copies next to each original.
  # Prefer the full dataset file; otherwise accept splits, checking overlap below.
  if (prefix == "csd") {
    files <- files[!grepl("^csd_random[_.]", basename(files))]
    for (ds in c("random", tolower(datasets))) {
      stem <- paste0("csd_", ds)
      if (any(sub("\\.csv(\\.gz)?$", "", basename(files)) == stem)) {
        files <- files[!startsWith(basename(files), paste0(stem, "_"))]
      }
    }
  }
  if (anyDuplicated(sub("\\.gz$", "", files))) {
    stop(paste("Both compressed and uncompressed copies found for", prefix))
  }
  files
}
files <- lapply(c("csd", "dedup", "perf"), input_files)
names(files) <- c("csd", "dedup", "perf")
message("CSD/dedup directory: ", normalizePath(csv_dir))
message("Performance directory: ", normalizePath(perf_dir))
message(sprintf("Selected raw CSV files: %d CSD, %d dedup, %d performance",
                length(files$csd), length(files$dedup), length(files$perf)))

# Keep one selected record per algorithm/dataset, matching Table X's 2 KiB domain.
select_domain <- function(x, domain = datasets) {
  x$dataset <- toupper(x$dataset)
  x$dataset[x$dataset == "RANDOM"] <- "RAND"
  x[x$algorithm %in% algorithms & x$dataset %in% domain &
      !is.na(x$target_chunk_size) & x$target_chunk_size == 2048, , drop = FALSE]
}
key_of <- function(x) paste(x$algorithm, x$dataset, sep = ":")
check_integer <- function(x, field, zero = FALSE) {
  minimum <- if (zero) 0 else 1
  if (any(!is.finite(x) | x < minimum | x != trunc(x) | x > 2^53 - 1)) {
    stop(paste("Invalid integer", field))
  }
}
read_input <- function(file, extra, callback, domain = datasets) {
  columns <- c(keys, extra)
  header <- names(readr::read_csv(file, n_max = 0, name_repair = "minimal",
                                 col_types = readr::cols(.default = readr::col_character()),
                                 show_col_types = FALSE, progress = FALSE))
  if (anyDuplicated(header) || !all(columns %in% header)) {
    stop(paste("Missing or duplicate columns in", file, "(required:", paste(columns, collapse = ", "), ")"))
  }
  types <- readr::cols(.default = readr::col_skip())
  for (column in columns) types$cols[[column]] <- readr::col_character()
  # Bounded memory even for CSD files larger than an R vector. Parse as text so
  # unsupported perf events do not invalidate the task-clock measurements.
  readr::read_csv_chunked(file, readr::SideEffectChunkCallback$new(function(x, pos) {
    readr::stop_for_problems(x)
    callback(select_domain(x, domain))
  }), chunk_size = 1000000, col_types = types, progress = FALSE, show_col_types = FALSE)
}
csd <- new.env(parent = emptyenv())
dedup <- new.env(parent = emptyenv())
perf <- new.env(parent = emptyenv())
for (file in files$csd) {
  message("Reading CSD: ", file)
  read_input(file, "chunk_size", function(x) {
    for (group in split(x, key_of(x))) {
      key <- key_of(group)[1]
      chunks <- suppressWarnings(as.numeric(group$chunk_size))
      check_integer(chunks, "chunk_size")
      n <- as.double(length(chunks))
      mu <- mean(chunks)
      m2 <- sum((chunks - mu)^2)
      bytes <- sum(chunks)
      old <- csd[[key]]
      if (!is.null(old)) {
        if (old$file != file) stop(paste("Overlapping CSD inputs for", key, "in", old$file, "and", file))
        # Combine within-file batches using the pooled-variance identity.
        delta <- mu - old$mean
        m2 <- old$m2 + m2 + delta^2 * old$n * n / (old$n + n)
        mu <- old$mean + delta * n / (old$n + n)
        n <- old$n + n
        bytes <- old$bytes + bytes
      }
      check_integer(bytes, "CSD byte total")
      csd[[key]] <- list(n = n, mean = mu, m2 = m2, bytes = bytes, file = file)
    }
  })
}
for (file in files$dedup) {
  read_input(file, c("dataset_size", "unique_chunks_size_sum"), function(x) {
    for (i in seq_len(nrow(x))) {
      key <- key_of(x[i, ])[1]
      if (!is.null(dedup[[key]])) stop(paste("Duplicate dedup result for", key))
      size <- suppressWarnings(as.numeric(x$dataset_size[i]))
      unique_bytes <- suppressWarnings(as.numeric(x$unique_chunks_size_sum[i]))
      check_integer(size, "dedup dataset_size", zero = TRUE)
      check_integer(unique_bytes, "unique_chunks_size_sum", zero = TRUE)
      dedup[[key]] <- list(size = size, unique = unique_bytes, file = file)
    }
  })
}
for (file in files$perf) {
  read_input(file, c("dataset_size", "iteration", "event", "value"), function(x) {
    x <- x[!is.na(x$event) & x$event == "task-clock", , drop = FALSE]
    for (i in seq_len(nrow(x))) {
      key <- key_of(x[i, ])[1]
      size <- suppressWarnings(as.numeric(x$dataset_size[i]))
      iteration <- suppressWarnings(as.numeric(x$iteration[i]))
      milliseconds <- suppressWarnings(as.numeric(x$value[i]))
      check_integer(size, "perf dataset_size")
      check_integer(iteration, "perf iteration", zero = TRUE)
      if (!is.finite(milliseconds) || milliseconds <= 0) stop(paste("Invalid task-clock for", key))
      old <- perf[[key]]
      if (!is.null(old) && size != old$size) {
        stop(sprintf(paste0("Performance byte counts disagree for %s: %.0f bytes in %s ",
                            "(iteration %.0f), versus %.0f bytes in %s. Select matching dataset runs."),
                     key, size, file, iteration, old$size, old$files[1]), call. = FALSE)
      }
      # Iterations restart in each repetition file. Pool individual rates across
      # files, as eval_perf.R does, while rejecting duplicate events within a file.
      if (!is.null(old) && any(old$files == file & old$iterations == iteration)) {
        stop(sprintf("Duplicate task-clock for %s in %s, iteration %.0f. Select one event per iteration.",
                     key, file, iteration), call. = FALSE)
      }
      perf[[key]] <- list(size = size, files = c(old$files, file),
                         iterations = c(old$iterations, iteration),
                         throughput = c(old$throughput, size / (milliseconds / 1000) / 2^20))
    }
  }, domain = "RAND")
}

selected <- expand.grid(algorithm = algorithms, dataset = datasets,
                        target_chunk_size = 2048, stringsAsFactors = FALSE)
for (field in fields) selected[[field]] <- NA_real_
for (field in c("csd_file", "dedup_file")) selected[[field]] <- NA_character_
for (i in seq_len(nrow(selected))) {
  key <- key_of(selected[i, ])[1]
  csd_row <- csd[[key]]
  dedup_row <- dedup[[key]]
  if (!is.null(csd_row)) {
    selected$mean_chunk_size[i] <- csd_row$mean
    selected$sd_chunk_size[i] <- if (csd_row$n > 1) sqrt(csd_row$m2 / (csd_row$n - 1)) else NA_real_
    selected$dataset_size[i] <- csd_row$bytes
    selected$chunk_count[i] <- csd_row$n
    selected$csd_file[i] <- csd_row$file
  }
  if (!is.null(dedup_row)) {
    selected$unique_chunks_size_sum[i] <- dedup_row$unique
    selected$dedup_file[i] <- dedup_row$file
  }
  sizes <- c(if (!is.null(csd_row)) csd_row$bytes,
             if (!is.null(dedup_row) && dedup_row$size > 0) dedup_row$size)
  if (length(unique(sizes)) > 1L) stop(paste("CSD/dedup input byte counts disagree for", key))
  if (!is.null(dedup_row) && length(sizes) && dedup_row$unique > sizes[1]) stop(paste("Unique bytes exceed input bytes for", key))
}
for (ds in datasets) {
  sizes <- selected$dataset_size[selected$dataset == ds]
  if (length(unique(na.omit(sizes))) > 1L) stop(paste("Input byte counts differ across algorithms for", ds))
}
# Throughput uses the existing RAND benchmark, independently of the four
# realistic datasets used for storage savings and chunk-size statistics.
throughput <- data.frame(algorithm = algorithms, dataset = "RAND", target_chunk_size = 2048,
                         dataset_size = NA_real_, median_throughput_mib_s = NA_real_,
                         perf_file = NA_character_)
for (i in seq_along(algorithms)) {
  p <- perf[[paste(algorithms[i], "RAND", sep = ":")]]
  if (!is.null(p)) {
    throughput$dataset_size[i] <- p$size
    throughput$median_throughput_mib_s[i] <- median(p$throughput)
    throughput$perf_file[i] <- paste(unique(p$files), collapse = "; ")
  }
}
if (length(unique(na.omit(throughput$dataset_size))) > 1L) {
  stop("RAND input byte counts differ across algorithms")
}
incomplete <- !complete.cases(selected[fields])
missing_throughput <- is.na(throughput$median_throughput_mib_s)
if (!allow_missing && (any(incomplete) || any(missing_throughput))) {
  missing_fields <- apply(is.na(selected[fields]), 1, function(missing) paste(fields[missing], collapse = ", "))
  missing_groups <- split(key_of(selected[incomplete, ]), missing_fields[incomplete])
  details <- vapply(names(missing_groups), function(missing) {
    paste0("  Missing ", missing, ":\n    ", paste(missing_groups[[missing]], collapse = ", "))
  }, character(1))
  if (any(missing_throughput)) {
    details <- c(details, paste0("  Missing median_throughput_mib_s on RAND:\n    ",
                                paste(key_of(throughput[missing_throughput, ]), collapse = ", ")))
  }
  stop(paste0(
    "Incomplete raw measurements at 2048 B:\n", paste(details, collapse = "\n"),
    "\nMean, SD, input bytes and chunk count come from CSD; unique bytes from dedup; ",
    "throughput from RAND performance task-clock rows. Check the selected directories and filenames above. ",
    "Use --allow-missing only for review placeholders."
  ), call. = FALSE)
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
    if (j == 2L) {
      values[i, j] <- throughput$median_throughput_mib_s[i]
      next
    }
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
  "Algorithm & Min. $D_{64}$ & RAND throughput & Max. error & Max. CV \\\\",
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
                  "C = CODE, W = WEB, V = VMB, D = DB. Throughput is the median on RAND. Bold: best; underline: second distinct value ",
                  "among the eight CDC algorithms, retaining ties in unrounded values. Arrows indicate ",
                  "preferred direction. Ranking is withheld for any incomplete metric."))
if (anyNA(values)) {
  lines <- c(lines, paste0("\\par\\smallskip\\footnotesize\\textbf{REBUTTAL-DATA-PENDING:} ",
                          "Dashes denote unavailable values, not zero. Storage and chunk-size extrema require all four realistic datasets; throughput requires RAND timings."))
}
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
writeLines(lines, output_path)
source_files <- normalizePath(as.character(unlist(files)), mustWork = TRUE)
saveRDS(list(input_directory = normalizePath(csv_dir),
             performance_directory = normalizePath(perf_dir),
             source_files = file.info(source_files)[, c("size", "mtime"), drop = FALSE],
             configurations = selected, throughput_configurations = throughput,
             performance_samples = as.list(perf),
             values = values, extrema = extrema),
        paste0(sub("\\.tex$", "", output_path), ".audit.rds"))
