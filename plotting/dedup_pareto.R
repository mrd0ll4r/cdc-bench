# Helpers for eval_dedup.R. Inputs are the existing dedup and CSD exports.
PARETO_DATASETS <- c("code", "web", "vmb", "db")
PARETO_ALGORITHMS <- c(fsc="FSC", ae="AE", ram="RAM", mii="MII", pci="PCI",
                       rabin_32="Rabin", buzhash_32="Buzhash", gear="Gear", `seq-cdc`="SeqCDC")
PARETO_TARGETS <- c(512, 1024, 2048, 4096, 8192)
PARETO_KEYS <- c("algorithm", "dataset", "target_chunk_size")

pareto_integer <- function(x, zero=FALSE) {
  is.finite(x) & x >= (if (zero) 0 else 1) & x <= 2^53 - 1 & x == floor(x)
}

pareto_select <- function(x) {
  if (!all(PARETO_KEYS %in% names(x))) stop("Missing configuration columns")
  x$algorithm <- as.character(x$algorithm)
  x$dataset <- tolower(as.character(x$dataset))
  x$target_chunk_size <- suppressWarnings(as.numeric(as.character(x$target_chunk_size)))
  x[x$algorithm %in% names(PARETO_ALGORITHMS) & x$dataset %in% PARETO_DATASETS &
      x$target_chunk_size %in% PARETO_TARGETS, , drop=FALSE]
}

# Sum all emitted chunks, including repeated chunks and terminal partial chunks.
# Aggregate each readr batch before retaining it; memory is bounded by chunk_size.
read_pareto_chunks <- function(files, chunk_size=1000000) {
  total <- data.frame(algorithm=character(), dataset=character(), target_chunk_size=numeric(),
                      chunk_count=numeric(), chunk_bytes=numeric())
  files <- normalizePath(files, mustWork=TRUE)
  if (anyDuplicated(files)) stop("Repeated CSD input file")
  for (file in files) {
    header <- names(readr::read_csv(file, n_max=0, show_col_types=FALSE, progress=FALSE,
                                   name_repair="check_unique"))
    if (!all(c(PARETO_KEYS, "chunk_size") %in% header)) stop("Missing CSD columns in ", file)
    callback <- readr::SideEffectChunkCallback$new(function(x, pos) {
      if (nrow(readr::problems(x))) stop("Malformed CSD rows in ", file)
      x <- pareto_select(x)
      if (!all(pareto_integer(x$chunk_size))) stop("Invalid chunk sizes in ", file)
      if (!nrow(x)) return(invisible(NULL))
      batch <- dplyr::summarise(dplyr::group_by(x, algorithm, dataset, target_chunk_size),
                                chunk_count=as.double(dplyr::n()),
                                chunk_bytes=sum(chunk_size), .groups="drop")
      total <<- as.data.frame(dplyr::summarise(
        dplyr::group_by(dplyr::bind_rows(total, batch), algorithm, dataset, target_chunk_size),
        chunk_count=sum(chunk_count), chunk_bytes=sum(chunk_bytes), .groups="drop"))
      if (!all(pareto_integer(total$chunk_count) & pareto_integer(total$chunk_bytes)))
        stop("CSD totals exceed the exact integer range")
    })
    readr::read_csv_chunked(file, callback, chunk_size=chunk_size, progress=FALSE,
      show_col_types=FALSE, col_types=readr::cols(.default=readr::col_skip(),
        algorithm=readr::col_character(), dataset=readr::col_character(),
        target_chunk_size=readr::col_double(), chunk_size=readr::col_double()))
  }
  total
}

match_pareto_records <- function(dedup, chunks) {
  required <- c(PARETO_KEYS, "dataset_size", "unique_chunks_size_sum")
  if (!all(required %in% names(dedup))) stop("Missing deduplication columns")
  d <- pareto_select(dedup)[, required]
  d$dataset_size <- as.numeric(d$dataset_size)
  d$unique_chunks_size_sum <- as.numeric(d$unique_chunks_size_sum)
  if (anyDuplicated(d[PARETO_KEYS])) stop("Duplicate deduplication configurations; select one result collection")
  if (anyDuplicated(chunks[PARETO_KEYS])) stop("Duplicate CSD summaries")
  d$has_dedup <- rep(TRUE, nrow(d))
  chunks$has_csd <- rep(TRUE, nrow(chunks))
  grid <- expand.grid(algorithm=names(PARETO_ALGORITHMS), dataset=PARETO_DATASETS,
                      target_chunk_size=PARETO_TARGETS, stringsAsFactors=FALSE)
  joined <- merge(merge(grid, d, by=PARETO_KEYS, all.x=TRUE), chunks, by=PARETO_KEYS, all.x=TRUE)
  joined$status <- "ok"
  joined$status[is.na(joined$has_dedup)] <- "missing deduplication result"
  joined$status[!is.na(joined$has_dedup) & is.na(joined$has_csd)] <- "missing chunk records"
  present <- !is.na(joined$has_dedup) & !is.na(joined$has_csd)
  valid <- pareto_integer(joined$dataset_size) & pareto_integer(joined$unique_chunks_size_sum) &
    pareto_integer(joined$chunk_count) & pareto_integer(joined$chunk_bytes) &
    joined$unique_chunks_size_sum <= joined$dataset_size & joined$chunk_count <= joined$chunk_bytes
  joined$status[present & !valid] <- "invalid byte/count totals"
  joined$status[present & valid & joined$chunk_bytes != joined$dataset_size] <- "CSD/dedup byte totals differ"
  # Do not compare configurations measured on different-size input populations.
  for (dataset in PARETO_DATASETS) {
    ix <- which(joined$dataset == dataset & joined$status == "ok")
    if (length(unique(joined$dataset_size[ix])) > 1)
      joined$status[ix] <- "inconsistent dataset size across configurations"
  }
  joined$has_dedup <- joined$has_csd <- NULL
  joined
}

# Within a dataset S is identical. Maximizing S/N and 1-(U+mN)/S is
# equivalent to minimizing N and U+mN; compare exact integer totals, not ratios.
pareto_nondominated <- function(count, stored) {
  vapply(seq_along(count), function(i) !any(count <= count[i] & stored <= stored[i] &
    (count < count[i] | stored < stored[i])), logical(1))
}

calculate_dedup_pareto <- function(matched, costs=c(28, 48, 64)) {
  if (!length(costs) || !all(pareto_integer(costs, zero=TRUE))) stop("Invalid metadata costs")
  rows <- matched[matched$status == "ok", setdiff(names(matched), "status"), drop=FALSE]
  do.call(rbind, lapply(costs, function(cost) {
    x <- rows
    x$metadata_bytes <- rep(cost, nrow(x))
    x$stored_bytes <- x$unique_chunks_size_sum + cost*x$chunk_count
    if (!all(pareto_integer(x$stored_bytes))) stop("Adjusted size exceeds the exact integer range")
    x$mean_chunk_size <- x$dataset_size/x$chunk_count
    x$raw_savings <- 1-x$unique_chunks_size_sum/x$dataset_size
    x$adjusted_savings <- 1-x$stored_bytes/x$dataset_size
    x$nondominated <- rep(FALSE, nrow(x))
    for (dataset in PARETO_DATASETS) {
      ix <- which(x$dataset == dataset)
      x$nondominated[ix] <- pareto_nondominated(x$chunk_count[ix], x$stored_bytes[ix])
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
      subtitle=sprintf("Illustrative metadata: %d B/chunk; rings: nondominated available configurations", cost)) +
    ggplot2::theme_bw(base_size=9) + ggplot2::theme(legend.position="bottom") +
    ggplot2::guides(colour=ggplot2::guide_legend(nrow=2), shape=ggplot2::guide_legend(nrow=2))
}

run_dedup_pareto <- function(dedup, csd_files, output_dir="tab", plot_writer=print_plot,
                              chunk_size=1000000, dedup_files=character()) {
  matched <- match_pareto_records(dedup, read_pareto_chunks(csd_files, chunk_size))
  results <- calculate_dedup_pareto(matched)
  dir.create(output_dir, recursive=TRUE, showWarnings=FALSE)
  readr::write_csv(matched, file.path(output_dir, "dedup-pareto-coverage.csv"))
  readr::write_csv(results, file.path(output_dir, "dedup-adjusted.csv"))
  files <- c(dedup_files, csd_files)
  info <- file.info(files)
  readr::write_csv(data.frame(path=normalizePath(files, mustWork=TRUE), bytes=info$size,
    modified_utc=format(info$mtime, tz="UTC", usetz=TRUE)), file.path(output_dir, "dedup-pareto-sources.csv"))
  if (any(matched$status != "ok")) warning(sprintf(
    "Pareto analysis: %d/180 configurations unavailable; see dedup-pareto-coverage.csv. Frontiers cover available results only.",
    sum(matched$status != "ok")), call.=FALSE)
  for (cost in c(28, 48, 64))
    plot_writer(plot_dedup_pareto(results, cost), paste0("dedup-pareto-", cost), width=7, height=5)
  invisible(list(results=results, coverage=matched))
}
