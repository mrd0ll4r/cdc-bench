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


# Let DuckDB scan and aggregate the saved chunk files; only the small grouped
# summary enters R. AVG includes repeated chunks and final partial chunks.
aggregate_pareto_means <- function(files) {
  files <- normalizePath(files,mustWork=TRUE)
  if (!length(files)) stop("No CSD input files")
  if (anyDuplicated(files)) stop("Repeated CSD input paths")
  if (!requireNamespace("duckdb",quietly=TRUE) || !requireNamespace("DBI",quietly=TRUE))
    stop("DuckDB aggregation requires the R packages duckdb and DBI, as used by eval_csd.R.")
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con,shutdown=TRUE),add=TRUE)
  quoted <- function(x) paste(DBI::dbQuoteString(con,x),collapse=",")
  message("Aggregating ",length(files)," saved CSD files with DuckDB.")
  query <- sprintf("
    SELECT algorithm, lower(dataset) AS dataset, target_chunk_size,
           AVG(chunk_size) AS mean_chunk_size,
           SUM(CASE WHEN chunk_size IS NULL OR NOT isfinite(chunk_size)
                         OR chunk_size < 1 OR chunk_size != floor(chunk_size)
                    THEN 1 ELSE 0 END) AS invalid_chunks
    FROM read_csv_auto([%s], header=true, ignore_errors=false, nullstr='NA',
         types={'algorithm':'VARCHAR', 'dataset':'VARCHAR',
                'target_chunk_size':'DOUBLE', 'chunk_size':'DOUBLE'})
    WHERE algorithm IN (%s) AND lower(dataset) IN (%s)
          AND target_chunk_size IN (%s)
    GROUP BY algorithm, lower(dataset), target_chunk_size
    ORDER BY algorithm, dataset, target_chunk_size",
    quoted(files),quoted(names(PARETO_ALGORITHMS)),quoted(PARETO_DATASETS),
    paste(PARETO_TARGETS,collapse=","))
  result <- DBI::dbGetQuery(con,query)
  if (any(result$invalid_chunks > 0)) stop("Invalid chunk sizes in CSD inputs")
  result[,c(PARETO_KEYS,"mean_chunk_size")]
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

calculate_dedup_pareto <- function(matched) {
  x <- matched[matched$status == "ok",setdiff(names(matched),"status"),drop=FALSE]
  x$metadata_bytes <- rep(64,nrow(x))
  x$raw_savings <- x$dedup_ratio
  x$adjusted_savings <- x$dedup_ratio-64/x$mean_chunk_size
  x$nondominated <- rep(FALSE,nrow(x))
  for (dataset in PARETO_DATASETS) {
    ix <- which(x$dataset == dataset)
    x$nondominated[ix] <- pareto_nondominated(x$mean_chunk_size[ix],x$adjusted_savings[ix])
  }
  x
}

# Named scales shared with the configured-target deduplication plots. This is
# their existing factor order after rename_algorithms(), made explicit.
DEDUP_LABELS <- c("AE","Buzhash","FSC","Gear","MII","PCI","Rabin","RAM","SeqCDC")
DEDUP_COLORS <- setNames(c("#1b9e77","#d95f02","#7570b3","#e7298a","#66a61e",
                           "#e6ab02","#a6761d","#666666","#1f78b4"),DEDUP_LABELS)
DEDUP_SHAPES <- setNames(c(21,22,23,24,25,1,2,3,4),DEDUP_LABELS)
dedup_algorithm_scales <- function() list(
  ggplot2::scale_color_manual(values=DEDUP_COLORS,limits=DEDUP_LABELS,drop=FALSE),
  ggplot2::scale_shape_manual(values=DEDUP_SHAPES,limits=DEDUP_LABELS,drop=FALSE))

# Match the checked-in dedup_overview exports explicitly, independent of the
# current R session theme (11 pt titles, 8.8 pt ticks, 5.5 pt outer margins).
dedup_plot_theme <- function() {
  ggplot2::theme_bw(base_size=11) +
    ggplot2::theme(legend.position="none",axis.text.x=ggplot2::element_text(angle=45,hjust=1))
}

plot_dedup_pareto <- function(results, dataset) {
  x <- results[results$dataset == dataset,,drop=FALSE]
  x$algorithm <- factor(unname(PARETO_ALGORITHMS[x$algorithm]),levels=DEDUP_LABELS)
  ggplot2::ggplot(x,ggplot2::aes(mean_chunk_size,adjusted_savings)) +
    ggplot2::geom_point(ggplot2::aes(colour=algorithm,shape=algorithm),size=1.5,fill="white") +
    ggplot2::geom_point(data=x[x$nondominated,,drop=FALSE],shape=1,size=3,colour="black",show.legend=FALSE) +
    ggplot2::scale_x_log10(labels=scales::label_number(accuracy=1,big.mark="",decimal.mark=".")) +
    dedup_algorithm_scales() +
    ggplot2::labs(x="Mean chunk size (B)",y="Dedup. Ratio",colour=NULL,shape=NULL) +
    dedup_plot_theme() +
    ggplot2::guides(colour=ggplot2::guide_legend(nrow=1),shape=ggplot2::guide_legend(nrow=1))
}

dedup_legend_plot <- function(p) {
  grobs <- ggplot2::ggplotGrob(p + ggplot2::theme(
    legend.position="bottom",legend.title=ggplot2::element_blank(),
    legend.text=ggplot2::element_text(size=10),legend.direction="horizontal"))
  ix <- which(grepl("^guide-box",grobs$layout$name) &
                vapply(grobs$grobs,function(g) inherits(g,"gtable"),logical(1)))
  legend <- grobs$grobs[[ix[1]]]
  ggplot2::ggplot() + ggplot2::annotation_custom(legend) + ggplot2::theme_void()
}

run_dedup_pareto <- function(dedup, means, output_dir="tab", plot_writer=print_plot) {
  matched <- match_pareto_summaries(dedup,means)
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  readr::write_csv(matched,file.path(output_dir,"dedup-pareto-coverage.csv"))
  if (any(matched$status != "ok"))
    stop("Incomplete Pareto inputs; see ",file.path(output_dir,"dedup-pareto-coverage.csv"))
  results <- calculate_dedup_pareto(matched)
  readr::write_csv(results,file.path(output_dir,"dedup-adjusted.csv"))
  for (dataset in PARETO_DATASETS) {
    p <- plot_dedup_pareto(results,dataset)
    plot_writer(p,paste0("dedup_pareto_",dataset),width=2,height=2)
  }
  plot_writer(dedup_legend_plot(p),"dedup_pareto_legendonly",width=7,height=1)
  invisible(list(results=results,coverage=matched))
}
