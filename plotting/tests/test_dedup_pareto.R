library(testthat)
source("plotting/dedup_pareto.R")

fixture <- function() {
  d <- expand.grid(algorithm=names(PARETO_ALGORITHMS), dataset=PARETO_DATASETS,
                   target_chunk_size=PARETO_TARGETS, stringsAsFactors=FALSE)
  d$dataset_size <- 1000
  d$unique_chunks_size_sum <- 600
  c <- d[rep(seq_len(nrow(d)), each=4), PARETO_KEYS]
  c$chunk_size <- rep(c(400, 400, 150, 50), nrow(d))
  list(dedup=d, chunks=c)
}
write_fixture <- function(x, dir) {
  dir.create(dir, recursive=TRUE, showWarnings=FALSE)
  files <- file.path(dir, paste0("csd_", PARETO_DATASETS, ".csv.gz"))
  for (i in seq_along(files)) readr::write_csv(x$chunks[x$chunks$dataset == PARETO_DATASETS[i], ], files[i])
  files
}
f <- fixture()
tmp <- tempfile("pareto-tests-")
dir.create(tmp)
files <- write_fixture(f, file.path(tmp, "csv"))
summaries <- read_pareto_chunks(files, chunk_size=73)
matched <- match_pareto_records(f$dedup, summaries)

# Independent arithmetic from four emitted chunks, including two identical sizes
# and a small final chunk, deliberately spanning reader-batch boundaries.
test_that("streaming preserves all chunks and exact configuration grouping", {
  expect_equal(nrow(summaries), 180)
  expect_true(all(summaries$chunk_count == 4))
  expect_true(all(summaries$chunk_bytes == 1000))
  expect_true(all(matched$status == "ok"))
})
test_that("metadata accounting and sensitivity are correct", {
  result <- calculate_dedup_pareto(matched)
  expect_equal(nrow(result), 540)
  expect_equal(unique(result$mean_chunk_size), 250)
  expect_equal(unique(result$raw_savings), .4)
  expect_equal(unique(result$adjusted_savings), c(.288, .208, .144))
})
test_that("dominance retains ties and tradeoffs but excludes dominated points", {
  expect_equal(pareto_nondominated(c(100,50,50,100), c(500,500,500,300)), c(FALSE,TRUE,TRUE,TRUE))
  expect_equal(pareto_nondominated(c(10,10),c(100,101)), c(TRUE,FALSE))
  expect_equal(pareto_nondominated(c(11,10),c(100,100)), c(FALSE,TRUE))
})
test_that("dominance is computed separately for each dataset and cost", {
  m <- matched[1:2, ]
  m$algorithm <- c("ae","ram"); m$dataset <- "code"
  m$chunk_count <- c(50,100); m$unique_chunks_size_sum <- c(900,100)
  # At zero overhead both are a tradeoff; at 28 B smaller N wins both axes.
  r <- calculate_dedup_pareto(m, c(0,28))
  expect_equal(r$nondominated, c(TRUE,TRUE,TRUE,FALSE))
  m$dataset <- c("code","web")
  expect_true(all(calculate_dedup_pareto(m)$nondominated))
})
test_that("negative savings remain in data and plot coordinates", {
  m <- matched[1, ]; m$chunk_count <- 100; m$unique_chunks_size_sum <- 800
  r <- calculate_dedup_pareto(m)
  expect_equal(r$adjusted_savings, c(-2.6,-4.6,-6.2))
  p <- ggplot2::ggplot_build(plot_dedup_pareto(r,28))
  expect_equal(p$data[[1]]$y, -260)
})
test_that("missing configurations remain explicit without a new input contract", {
  m <- match_pareto_records(f$dedup[-1, ], summaries[-2, ])
  expect_equal(sum(m$status == "ok"), 178)
  expect_true("missing deduplication result" %in% m$status)
  expect_true("missing chunk records" %in% m$status)
  expect_equal(nrow(calculate_dedup_pareto(m)), 534)
})
test_that("inconsistent and invalid byte populations never enter plots", {
  d <- f$dedup; d$dataset_size[1] <- 1001
  m <- match_pareto_records(d, summaries)
  expect_equal(sum(m$status == "CSD/dedup byte totals differ"), 1)
  d <- f$dedup; d$dataset_size[d$dataset == "vmb"] <- 0
  m <- match_pareto_records(d, summaries)
  expect_equal(sum(m$status == "invalid byte/count totals"),45)
  expect_false("vmb" %in% calculate_dedup_pareto(m)$dataset)
  d <- f$dedup; d$unique_chunks_size_sum[1] <- 1001
  expect_equal(sum(match_pareto_records(d, summaries)$status != "ok"),1)
  d <- f$dedup; d$dataset_size[1] <- 2000
  s <- summaries
  ix <- with(s, algorithm == d$algorithm[1] & dataset == d$dataset[1] & target_chunk_size == d$target_chunk_size[1])
  s$chunk_bytes[ix] <- 2000
  expect_equal(sum(match_pareto_records(d,s)$status == "inconsistent dataset size across configurations"),45)
})
test_that("duplicate results and duplicate file paths are rejected", {
  expect_error(match_pareto_records(rbind(f$dedup, f$dedup[1, ]), summaries), "Duplicate dedup")
  expect_error(match_pareto_records(f$dedup, rbind(summaries,summaries[1, ])), "Duplicate CSD")
  expect_error(read_pareto_chunks(c(files,files[1])), "Repeated CSD")
})
test_that("algorithm variants are not guessed or joined across algorithms", {
  d <- f$dedup; d$algorithm[d$algorithm == "rabin_32"] <- "rabin"
  m <- match_pareto_records(d, summaries)
  expect_equal(sum(m$status == "missing deduplication result"),20)
  expect_false("rabin_32" %in% calculate_dedup_pareto(m)$algorithm)
})
test_that("invalid chunk rows and schema are rejected", {
  for (value in c(NA,0,-1,1.5,Inf)) {
    bad <- f$chunks[1:2, ]; bad$chunk_size[1] <- value
    file <- file.path(tmp,"invalid.csv.gz"); readr::write_csv(bad,file)
    expect_error(read_pareto_chunks(file), "Invalid chunk sizes|Malformed CSD rows")
  }
  file <- file.path(tmp,"schema.csv"); readr::write_csv(f$chunks[1:2,PARETO_KEYS],file)
  expect_error(read_pareto_chunks(file), "Missing CSD columns")
})
test_that("integer precision limits are enforced", {
  expect_false(pareto_integer(2^53))
  expect_true(pareto_integer(2^53-1))
  m <- matched[1, ]; m$unique_chunks_size_sum <- 2^53-1
  expect_error(calculate_dedup_pareto(m), "exact integer range")
})
test_that("existing exports drive complete end-to-end outputs", {
  out <- file.path(tmp,"output"); names <- character()
  writer <- function(plot,name,width,height) {
    expect_s3_class(plot,"ggplot")
    expect_equal(length(ggplot2::ggplot_build(plot)$layout$layout$PANEL),4)
    names <<- c(names,name)
  }
  result <- run_dedup_pareto(f$dedup, files, out, writer, chunk_size=71)
  expect_equal(names, paste0("dedup-pareto-",c(28,48,64)))
  expect_equal(nrow(readr::read_csv(file.path(out,"dedup-adjusted.csv"),show_col_types=FALSE)),540)
  expect_equal(nrow(readr::read_csv(file.path(out,"dedup-pareto-coverage.csv"),show_col_types=FALSE)),180)
  expect_equal(nrow(readr::read_csv(file.path(out,"dedup-pareto-sources.csv"),show_col_types=FALSE)),4)
})
test_that("an absent CSD export produces explicit empty panels and coverage", {
  writer <- function(plot,...) expect_s3_class(ggplot2::ggplot_build(plot),"ggplot_built")
  expect_warning(r <- run_dedup_pareto(f$dedup, character(), file.path(tmp,"empty"),writer), "180/180")
  expect_equal(nrow(r$results),0)
})
unlink(tmp, recursive=TRUE)
