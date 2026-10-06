# Helpers for eval_dedup.R. Reuse achieved-mean and deduplication summaries.
PARETO_DATASETS <- c("code", "web", "vmb", "db")
PARETO_ALGORITHMS <- c(fsc="FSC", ae="AE", ram="RAM", mii="MII", pci="PCI",
                       rabin_32="Rabin", buzhash_32="Buzhash", gear="Gear", `seq-cdc`="SeqCDC")
PARETO_TARGETS <- c(512, 1024, 2048, 4096, 8192)
PARETO_KEYS <- c("algorithm", "dataset", "target_chunk_size")

pareto_select <- function(x) {
  if (!all(PARETO_KEYS %in% names(x))) stop("Missing configuration columns")
  x$algorithm <- as.character(x$algorithm)
  x$dataset <- tolower(as.character(x$dataset))
  x$target_chunk_size <- suppressWarnings(as.numeric(as.character(x$target_chunk_size)))
  x[x$algorithm %in% names(PARETO_ALGORITHMS) & x$dataset %in% PARETO_DATASETS &
      x$target_chunk_size %in% PARETO_TARGETS, , drop=FALSE]
}


# Accept the existing wide DuckDB summary (mean_512, mean_1024, ...) or a
# long summary. No chunk counts, input-byte totals, or unique-byte totals needed.
pareto_mean_summary <- function(summary, rounded=FALSE) {
  x <- as.data.frame(summary)
  if (!all(c("algorithm", "dataset") %in% names(x))) stop("Missing mean-summary keys")
  if (!all(c("target_chunk_size", "mean_chunk_size") %in% names(x))) {
    columns <- intersect(paste0("mean_", PARETO_TARGETS), names(x))
    if (!length(columns)) stop("Missing mean-size columns")
    x <- do.call(rbind, lapply(columns, function(column) data.frame(
      algorithm=x$algorithm, dataset=x$dataset,
      target_chunk_size=as.numeric(sub("mean_", "", column)), mean_chunk_size=x[[column]])))
  }
  x <- pareto_select(x)[, c(PARETO_KEYS, "mean_chunk_size")]
  x$mean_chunk_size <- suppressWarnings(as.numeric(as.character(x$mean_chunk_size)))
  x$mean_rounded <- rep(rounded, nrow(x))
  x
}

# Read the actual printed means from the existing generated table, not drawing
# coordinates. This fallback is explicitly approximate (whole-byte rounding).
read_pareto_mean_table <- function(path) {
  rows <- list(); dataset <- NULL
  for (line in readLines(path, warn=FALSE)) {
    if (grepl("\\\\textbf\\{(RANDOM|RAND|CODE|WEB|VMB|DB)\\}", line)) {
      dataset <- tolower(sub(".*\\\\textbf\\{([^}]+)\\}.*", "\\1", line))
      next
    }
    fields <- strsplit(line, "&", fixed=TRUE)[[1]]
    label <- trimws(fields[1])
    if (is.null(dataset) || !(dataset %in% PARETO_DATASETS) || !(label %in% PARETO_ALGORITHMS)) next
    if (length(fields) != 16) stop("Unexpected mean-table layout in ", path)
    values <- fields[c(3,6,9,12,15)]
    values <- gsub("\\\\(?:cellcolor|color)\\{[^}]*\\}", "", values, perl=TRUE)
    values <- suppressWarnings(as.numeric(trimws(values)))
    if (any(!is.finite(values) | values <= 0)) stop("Invalid printed mean in ", path)
    rows[[length(rows)+1]] <- data.frame(algorithm=names(PARETO_ALGORITHMS)[match(label,PARETO_ALGORITHMS)],
      dataset=dataset, target_chunk_size=PARETO_TARGETS, mean_chunk_size=values)
  }
  if (!length(rows)) stop("No supported mean-size rows in ", path)
  pareto_mean_summary(do.call(rbind, rows), rounded=TRUE)
}

load_pareto_means <- function(summary=NULL, path=NULL) {
  if (is.null(path) && !is.null(summary)) {
    result <- pareto_mean_summary(summary)
    attr(result,"source") <- "in-memory CSD summary"
    return(result)
  }
  if (is.null(path)) {
    candidates <- c("tab/csd_means.csv", "tab/csd_means_sd_full.tex")
    path <- candidates[file.exists(candidates)][1]
  }
  if (length(path) != 1 || is.na(path) || !file.exists(path)) {
    warning("No saved CSD mean summary found; Pareto coverage will show missing means.", call.=FALSE)
    return(data.frame(algorithm=character(),dataset=character(),target_chunk_size=numeric(),
                      mean_chunk_size=numeric(),mean_rounded=logical()))
  }
  result <- if (tolower(tools::file_ext(path)) == "tex") read_pareto_mean_table(path) else {
    x <- readr::read_csv(path, show_col_types=FALSE, name_repair="check_unique")
    if (nrow(readr::problems(x))) stop("Malformed CSD mean summary")
    pareto_mean_summary(x)
  }
  attr(result,"source") <- normalizePath(path)
  result
}

match_pareto_summaries <- function(dedup, means) {
  if (!all(c(PARETO_KEYS,"dedup_ratio") %in% names(dedup))) stop("Missing deduplication summary columns")
  d <- pareto_select(dedup)[, c(PARETO_KEYS,"dedup_ratio")]
  d$dedup_ratio <- suppressWarnings(as.numeric(as.character(d$dedup_ratio)))
  if (anyDuplicated(d[PARETO_KEYS])) stop("Duplicate deduplication configurations")
  if (anyDuplicated(means[PARETO_KEYS])) stop("Duplicate mean-size configurations")
  d$has_dedup <- rep(TRUE,nrow(d)); means$has_mean <- rep(TRUE,nrow(means))
  grid <- expand.grid(algorithm=names(PARETO_ALGORITHMS), dataset=PARETO_DATASETS,
                      target_chunk_size=PARETO_TARGETS, stringsAsFactors=FALSE)
  x <- merge(merge(grid,d,by=PARETO_KEYS,all.x=TRUE),means,by=PARETO_KEYS,all.x=TRUE)
  x$status <- "ok"
  x$status[is.na(x$has_dedup)] <- "missing deduplication ratio"
  x$status[!is.na(x$has_dedup) & is.na(x$has_mean)] <- "missing achieved mean"
  present <- !is.na(x$has_dedup) & !is.na(x$has_mean)
  valid <- is.finite(x$dedup_ratio) & x$dedup_ratio >= 0 & x$dedup_ratio <= 1 &
    is.finite(x$mean_chunk_size) & x$mean_chunk_size >= 1
  x$status[present & !valid] <- "invalid ratio or mean"
  x$has_dedup <- x$has_mean <- NULL
  x
}

# Maximize both axes. Equal supplied values retain all ties; no tolerance or
# rounding is applied before comparing the available summary values.
pareto_nondominated <- function(mean, savings) {
  vapply(seq_along(mean),function(i) !any(mean >= mean[i] & savings >= savings[i] &
    (mean > mean[i] | savings > savings[i])),logical(1))
}

calculate_dedup_pareto <- function(matched, costs=c(28,48,64)) {
  if (!length(costs) || any(!is.finite(costs) | costs < 0)) stop("Invalid metadata costs")
  rows <- matched[matched$status == "ok",setdiff(names(matched),"status"),drop=FALSE]
  do.call(rbind,lapply(costs,function(cost) {
    x <- rows
    x$metadata_bytes <- rep(cost,nrow(x))
    x$raw_savings <- x$dedup_ratio
    x$adjusted_savings <- x$dedup_ratio-cost/x$mean_chunk_size
    x$nondominated <- rep(FALSE,nrow(x))
    for (dataset in PARETO_DATASETS) {
      ix <- which(x$dataset == dataset)
      x$nondominated[ix] <- pareto_nondominated(x$mean_chunk_size[ix],x$adjusted_savings[ix])
    }
    x
  }))
}

plot_dedup_pareto <- function(results, cost) {
  x <- results[results$metadata_bytes == cost, , drop=FALSE]
  x$dataset <- factor(x$dataset, levels=PARETO_DATASETS)
  x$algorithm <- factor(x$algorithm, levels=names(PARETO_ALGORITHMS))
  counts <- table(x$dataset)
  panel_labels <- setNames(paste0(toupper(PARETO_DATASETS), " (", counts, "/45)"), PARETO_DATASETS)
  empty_x <- if (nrow(x)) exp(mean(log(range(x$mean_chunk_size)))) else 1
  empty <- data.frame(dataset=factor(PARETO_DATASETS[counts == 0], levels=PARETO_DATASETS),
                      mean_chunk_size=rep(empty_x, sum(counts == 0)),
                      adjusted_savings=rep(0, sum(counts == 0)))
  rounding_note <- if (any(x$mean_rounded)) "\nRounded mean-size table: savings and frontier are approximate" else ""
  ggplot2::ggplot(x, ggplot2::aes(mean_chunk_size, adjusted_savings*100)) +
    ggplot2::geom_point(ggplot2::aes(colour=algorithm, shape=algorithm), size=2) +
    ggplot2::geom_point(data=x[x$nondominated, , drop=FALSE], shape=1, size=4, colour="black") +
    ggplot2::geom_text(data=empty, label="No matched results", size=3) +
    ggplot2::facet_wrap(~dataset, ncol=2, drop=FALSE, labeller=ggplot2::as_labeller(panel_labels)) +
    ggplot2::scale_x_log10() +
    ggplot2::scale_colour_manual(values=c("#666666", "#d95f02", "#1b9e77", "#7570b3", "#e7298a",
                                          "#000000", "#a6761d", "#e6ab02", "#66a61e"),
                                 breaks=names(PARETO_ALGORITHMS), labels=PARETO_ALGORITHMS, drop=FALSE) +
    ggplot2::scale_shape_manual(values=c(0, 2, 3, 4, 5, 6, 7, 8, 9),
                                breaks=names(PARETO_ALGORITHMS), labels=PARETO_ALGORITHMS, drop=FALSE) +
    ggplot2::labs(x="Achieved mean chunk size (B)", y="Metadata-adjusted savings (%)",
      colour=NULL, shape=NULL,
      subtitle=paste0(sprintf("Metadata: %d B/chunk; rings: nondominated available configurations", cost), rounding_note)) +
    ggplot2::theme_bw(base_size=9) + ggplot2::theme(legend.position="bottom") +
    ggplot2::guides(colour=ggplot2::guide_legend(nrow=2), shape=ggplot2::guide_legend(nrow=2))
}

run_dedup_pareto <- function(dedup, means, output_dir="tab", plot_writer=print_plot) {
  matched <- match_pareto_summaries(dedup,means)
  results <- calculate_dedup_pareto(matched)
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  readr::write_csv(matched,file.path(output_dir,"dedup-pareto-coverage.csv"))
  readr::write_csv(results,file.path(output_dir,"dedup-adjusted.csv"))
  if (any(matched$status != "ok")) warning(sprintf(
    "Pareto analysis: %d/180 configurations unavailable; see dedup-pareto-coverage.csv. Frontiers cover available results only.",
    sum(matched$status != "ok")),call.=FALSE)
  if (any(results$mean_rounded)) warning(
    "Using rounded mean-size table values: adjusted savings and frontier membership are approximate.",call.=FALSE)
  for (cost in c(28,48,64))
    plot_writer(plot_dedup_pareto(results,cost),paste0("dedup-pareto-",cost),width=7,height=5)
  invisible(list(results=results,coverage=matched))
}
