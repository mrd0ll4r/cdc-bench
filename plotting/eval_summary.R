# Table X directly from the existing experiment CSVs (plain or gzip).
# In RStudio: set the working directory to plotting/, then click Source.
# Edit these settings for your input layout. Requires DBI and duckdb.
csv_dir <- "csv"
perf_dir <- "../csv"
output_path <- "tab/summary.tex"
allow_missing <- FALSE  # TRUE only for review placeholders
include_fsc <- FALSE    # TRUE adds an unranked FSC reference

# Command-line use remains supported. Sourcing never reads process arguments
# or quits the R/RStudio session. CLI defaults retain the single-directory layout.
if (!interactive() && sys.nframe() == 0L) {
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
}
if (!dir.exists(csv_dir)) stop(paste("Experiment directory does not exist:", csv_dir))
if (!dir.exists(perf_dir)) stop(paste("Performance directory does not exist:", perf_dir))
if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("duckdb", quietly = TRUE)) {
  stop(paste0(
    "DBI and duckdb are required in the active R library. In the R console, ",
    "run renv::install(c(\"DBI\", \"duckdb\")) from plotting/, then source this script again."
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

key_of <- function(x) paste(x$algorithm, x$dataset, sep = ":")
check_integer <- function(x, field, zero = FALSE) {
  minimum <- if (zero) 0 else 1
  if (any(!is.finite(x) | x < minimum | x != trunc(x) | x > 2^53 - 1)) {
    stop(paste("Invalid integer", field))
  }
}
csd <- new.env(parent = emptyenv())
dedup <- new.env(parent = emptyenv())
perf <- new.env(parent = emptyenv())
local({
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sql_strings <- function(x) paste(DBI::dbQuoteString(con, x), collapse = ", ")
  input_query <- function(file, extra, domain = datasets) {
    columns <- c(keys, extra)
    # Read only the header before DuckDB can disambiguate duplicate names.
    # read.csv(connection, nrows = 0) can still scan/type-convert the data body.
    input <- if (endsWith(file, ".gz")) gzfile(file, "rt") else base::file(file, "rt")
    header_line <- tryCatch(readLines(input, n = 1L, warn = FALSE), finally = close(input))
    if (!length(header_line)) stop(paste("Empty CSV input:", file))
    header <- names(utils::read.csv(text = header_line, colClasses = "character",
                                   check.names = FALSE))
    if (anyDuplicated(header) || !all(columns %in% header)) {
      stop(paste("Missing or duplicate columns in", file, "(required:", paste(columns, collapse = ", "), ")"))
    }
    dataset_sql <- "CASE WHEN UPPER(dataset) = 'RANDOM' THEN 'RAND' ELSE UPPER(dataset) END"
    selected_columns <- as.character(DBI::dbQuoteIdentifier(con, columns))
    selected_columns[columns == "dataset"] <- paste(dataset_sql, "AS dataset")
    paste0("SELECT ", paste(selected_columns, collapse = ", "),
           " FROM read_csv_auto(", sql_strings(normalizePath(file)),
           ", header = true, delim = ',', all_varchar = true, ignore_errors = false)",
           " WHERE algorithm IN (", sql_strings(algorithms), ") AND ", dataset_sql,
           " IN (", sql_strings(domain), ") AND TRY_CAST(target_chunk_size AS DOUBLE) = 2048")
  }
  read_input <- function(file, extra, callback, domain = datasets) {
    # Only selected deduplication rows and timing samples cross into R.
    callback(DBI::dbGetQuery(con, input_query(file, extra, domain)))
  }
  for (file in files$csd) {
    message("Reading CSD: ", file)
    # Aggregate inside DuckDB: raw chunk rows never become an R vector, and
    # readr's chunked-reader row-index limit is not involved.
    groups <- DBI::dbGetQuery(con, paste0(
      "WITH selected AS (", input_query(file, "chunk_size"), "), ",
      "typed AS (SELECT algorithm, dataset, TRY_CAST(chunk_size AS DOUBLE) AS chunk FROM selected), ",
      "checked AS (SELECT *, chunk IS NOT NULL AND ISFINITE(chunk) AND chunk >= 1 ",
      "AND chunk = FLOOR(chunk) AND chunk <= 9007199254740991 AS valid FROM typed) ",
      "SELECT algorithm, dataset, CAST(COUNT(*) AS DOUBLE) AS n, ",
      "BOOL_OR(NOT valid) AS invalid, ",
      "SUM(CASE WHEN valid THEN chunk END) AS bytes, ",
      "AVG(CASE WHEN valid THEN chunk END) AS mean, ",
      "STDDEV_SAMP(CASE WHEN valid THEN chunk END) AS sd ",
      "FROM checked GROUP BY algorithm, dataset"))
    for (i in seq_len(nrow(groups))) {
      group <- groups[i, ]
      key <- key_of(group)
      if (group$invalid) stop(paste("Invalid integer chunk_size for", key, "in", file))
      if (!is.null(csd[[key]])) {
        stop(paste("Overlapping CSD inputs for", key, "in", csd[[key]]$file, "and", file))
      }
      check_integer(group$bytes, "CSD byte total")
      csd[[key]] <- list(n = group$n, mean = group$mean, sd = group$sd,
                         bytes = group$bytes, file = file)
    }
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
})

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
    selected$sd_chunk_size[i] <- csd_row$sd
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
metrics <- c("median_throughput_mib_s", "error", "cv", "savings_min", "savings_max")
metric_fields <- c("median_throughput_mib_s", "error", "cv", "savings", "savings")
higher_is_better <- c(TRUE, FALSE, FALSE, TRUE, TRUE)
values <- matrix(NA_real_, nrow = length(algorithms), ncol = length(metrics),
                 dimnames = list(algorithms, metrics))
extrema <- matrix("", nrow = length(algorithms), ncol = length(metrics),
                  dimnames = list(algorithms, metrics))
for (i in seq_along(algorithms)) {
  group <- selected[selected$algorithm == algorithms[i], ]
  group <- group[match(datasets, group$dataset), ]
  for (j in seq_along(metrics)) {
    if (metrics[j] == "median_throughput_mib_s") {
      values[i, j] <- throughput$median_throughput_mib_s[i]
      next
    }
    v <- group[[metric_fields[j]]]
    if (all(is.finite(v))) {
      values[i, j] <- if (metrics[j] == "savings_min") min(v) else max(v)
      extrema[i, j] <- paste(codes[v == values[i, j]], collapse = ",")
    }
  }
}
# Rank unrounded values; do not rank incomplete CDC domains or include FSC.
ranks <- lapply(seq_along(metrics), function(j) {
  v <- values[seq_len(8), j]
  if (anyNA(v)) numeric() else head(sort(unique(v), decreasing = higher_is_better[j]), 2)
})
lines <- c(
  "\\begingroup",
  "\\setlength{\\tabcolsep}{4pt}",
  "\\begin{tabular}{lrrrrr}",
  "\\toprule",
  "Algorithm & Throughput & \\multicolumn{2}{c}{Chunk Sizes} & \\multicolumn{2}{c}{Storage Savings} \\\\",
  "\\cmidrule(lr){3-4}\\cmidrule(lr){5-6}",
  " & (MiB/s) $\\uparrow$ & Max. Err. $\\downarrow$ & Max. CV $\\downarrow$ & Min. $\\uparrow$ & Max. $\\uparrow$ \\\\",
  "\\midrule"
)
for (i in seq_along(algorithms)) {
  cells <- character(length(metrics))
  for (j in seq_along(metrics)) {
    v <- values[i, j]
    cells[j] <- if (is.na(v)) "\\textemdash{}" else sprintf("%.2f", v)
    rank <- match(v, ranks[[j]])
    if (i <= 8 && !is.na(rank)) {
      cells[j] <- paste0(if (rank == 1) "\\textbf{" else "\\underline{", cells[j], "}")
    }
    if (nzchar(extrema[i, j])) cells[j] <- paste0(cells[j], "\\textsuperscript{", extrema[i, j], "}")
  }
  lines <- c(lines, paste0(paste(c(labels[i], cells), collapse = " & "), " \\\\"))
}
lines <- c(lines, "\\bottomrule", "\\end{tabular}", "\\endgroup")
if (anyNA(values)) {
  lines <- c(lines, "% REBUTTAL-DATA-PENDING: missing values; see the audit for coverage.")
}
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
writeLines(lines, output_path)
source_files <- normalizePath(as.character(unlist(files)), mustWork = TRUE)
audit_path <- paste0(sub("\\.tex$", "", output_path), ".audit.rds")
saveRDS(list(input_directory = normalizePath(csv_dir),
             performance_directory = normalizePath(perf_dir),
             source_files = file.info(source_files)[, c("size", "mtime"), drop = FALSE],
             configurations = selected, throughput_configurations = throughput,
             performance_samples = as.list(perf),
             values = values, extrema = extrema),
        audit_path)
message("Wrote table: ", normalizePath(output_path))
message("Wrote audit: ", normalizePath(audit_path))
