library(testthat)
source("plotting/dedup_pareto.R")
tmp <- tempfile("pareto-tests-")
dir.create(tmp)
d <- expand.grid(algorithm=names(PARETO_ALGORITHMS), dataset=PARETO_DATASETS,
                 target_chunk_size=PARETO_TARGETS, stringsAsFactors=FALSE)
d$dedup_ratio <- .4
means <- d[PARETO_KEYS]
means$mean_chunk_size <- 250
means <- pareto_mean_summary(means)
matched <- match_pareto_summaries(d,means)

test_that("summary arithmetic agrees with independent byte/count accounting", {
  r <- calculate_dedup_pareto(matched)
  expect_equal(nrow(r),540)
  # Four emitted chunks totaling 1000 bytes, 600 unique bytes.
  expect_equal(unique(r$adjusted_savings),1-(600+c(28,48,64)*4)/1000)
  expect_equal(unique(r$raw_savings),.4)
  expect_true(all(matched$status == "ok"))
})
test_that("wide summaries preserve means and normalize dataset labels", {
  wide <- data.frame(algorithm="ae",dataset="CODE",mean_512=511.123456789,mean_2048=2041.23456789)
  m <- pareto_mean_summary(wide)
  expect_equal(m$target_chunk_size,c(512,2048))
  expect_equal(m$mean_chunk_size,c(wide$mean_512,wide$mean_2048))
  expect_equal(m$dataset,c("code","code"))
  expect_equal(load_pareto_means(summary=wide)$mean_chunk_size,m$mean_chunk_size)
  path <- file.path(tmp,"means.csv")
  readr::write_csv(wide,path)
  expect_equal(load_pareto_means(path=path)$mean_chunk_size,m$mean_chunk_size)
  readr::write_csv(wide,paste0(path,".gz"))
  expect_equal(load_pareto_means(path=paste0(path,".gz"))$mean_chunk_size,m$mean_chunk_size)
  # Explicit file selection takes precedence over a session's summary.
  expect_equal(load_pareto_means(summary=means,path=path)$mean_chunk_size,m$mean_chunk_size)
  expect_error(pareto_mean_summary(wide[c("algorithm","dataset")]),"Missing mean-size")
  expect_error(pareto_mean_summary(wide["mean_512"]),"Missing mean-summary keys")
})
test_that("LaTeX output is never used as an input fallback", {
  out <- file.path(tmp,"tex-only")
  dir.create(file.path(out,"tab"),recursive=TRUE)
  writeLines("not numerical input",file.path(out,"tab/csd_means_sd_full.tex"))
  previous <- getwd()
  tryCatch({
    setwd(out)
    expect_warning(m <- load_pareto_means(),"No saved CSD mean summary")
    expect_equal(nrow(m),0)
    expect_error(load_pareto_means(path="tab/csd_means_sd_full.tex"),"LaTeX is output only")
  },finally=setwd(previous))
})
test_that("dominance maximizes both axes and retains exact ties", {
  expect_equal(pareto_nondominated(c(100,50,50,100),c(.5,.7,.7,.3)),c(TRUE,TRUE,TRUE,FALSE))
  expect_equal(pareto_nondominated(c(10,10),c(.1,.2)),c(FALSE,TRUE))
  expect_equal(pareto_nondominated(c(11,10),c(.1,.1)),c(TRUE,FALSE))
})
test_that("dominance is isolated by dataset and metadata cost", {
  m <- matched[1:2,]
  m$algorithm <- c("ae","ram"); m$dataset <- "code"
  m$mean_chunk_size <- c(100,50); m$dedup_ratio <- c(.3,.5)
  expect_equal(calculate_dedup_pareto(m,c(0,28))$nondominated,c(TRUE,TRUE,TRUE,FALSE))
  m$dataset <- c("code","web")
  expect_true(all(calculate_dedup_pareto(m)$nondominated))
})
test_that("negative savings remain visible", {
  m <- matched[1,]; m$mean_chunk_size <- 10; m$dedup_ratio <- .2
  r <- calculate_dedup_pareto(m)
  expect_equal(r$adjusted_savings,c(-2.6,-4.6,-6.2))
  expect_equal(ggplot2::ggplot_build(plot_dedup_pareto(r,28))$data[[1]]$y,-260)
})
test_that("missing and mismatched keys are explicit", {
  m <- match_pareto_summaries(d[-1,],means[-2,])
  expect_equal(sum(m$status == "ok"),178)
  expect_true(all(c("missing deduplication ratio","missing achieved mean") %in% m$status))
  other <- d; other$algorithm[other$algorithm == "rabin_32"] <- "rabin"
  expect_equal(sum(match_pareto_summaries(other,means)$status != "ok"),20)
  other <- means; other$dataset[other$dataset == "code"] <- "rand"
  expect_equal(sum(match_pareto_summaries(d,other)$status != "ok"),45)
})
test_that("duplicates and invalid summaries cannot silently enter results", {
  expect_error(match_pareto_summaries(rbind(d,d[1,]),means),"Duplicate deduplication")
  expect_error(match_pareto_summaries(d,rbind(means,means[1,])),"Duplicate mean-size")
  for (value in c(NA,Inf,-.1,1.1)) {
    bad <- d; bad$dedup_ratio[1] <- value
    expect_equal(sum(match_pareto_summaries(bad,means)$status == "invalid ratio or mean"),1)
  }
  for (value in c(NA,Inf,0,-1)) {
    bad <- means; bad$mean_chunk_size[1] <- value
    expect_equal(sum(match_pareto_summaries(d,bad)$status == "invalid ratio or mean"),1)
  }
  expect_error(calculate_dedup_pareto(matched,-1),"Invalid metadata costs")
})
test_that("two summaries alone produce all outputs without chunk files", {
  names <- character()
  writer <- function(plot,name,width,height) {
    expect_equal(nrow(ggplot2::ggplot_build(plot)$layout$layout),4)
    names <<- c(names,name)
  }
  out <- file.path(tmp,"output")
  result <- run_dedup_pareto(d,means,out,writer)
  expect_equal(names,paste0("dedup-pareto-",c(28,48,64)))
  expect_equal(nrow(readr::read_csv(file.path(out,"dedup-adjusted.csv"),show_col_types=FALSE)),540)
  expect_equal(nrow(readr::read_csv(file.path(out,"dedup-pareto-coverage.csv"),show_col_types=FALSE)),180)
})
test_that("missing artifacts produce coverage and empty panels", {
  expect_warning(empty <- load_pareto_means(path=file.path(tmp,"absent.csv")),"No saved CSD")
  writer <- function(plot,...) {
    p <- ggplot2::ggplot_build(plot)
    expect_equal(nrow(p$layout$layout),4)
    expect_equal(nrow(p$data[[3]]),4)
  }
  expect_warning(r <- run_dedup_pareto(d,empty,file.path(tmp,"empty"),writer),"180/180")
  expect_equal(nrow(r$results),0)
})
test_that("saved chunk sizes yield weighted means across batches and datasets", {
  input <- file.path(tmp,"chunks")
  dir.create(input)
  chunks <- d[rep(seq_len(nrow(d)),each=3),PARETO_KEYS]
  chunks$chunk_size <- rep(c(400,400,50),nrow(d))
  files <- file.path(input,paste0("csd_",PARETO_DATASETS,".csv.gz"))
  for (i in seq_along(files))
    readr::write_csv(chunks[chunks$dataset == PARETO_DATASETS[i],],files[i])
  m <- aggregate_pareto_means(files,chunk_size=7)
  expect_equal(nrow(m),180)
  expect_equal(m$mean_chunk_size,rep(850/3,180))
  expect_true(all(match_pareto_summaries(d,m)$status == "ok"))
  # No cached aggregate exists in this fresh evaluation directory.
  output <- file.path(tmp,"fresh-session")
  dir.create(output)
  previous <- getwd()
  tryCatch({
    setwd(output)
    loaded <- load_pareto_means(chunk_dir=input)
    expect_true(file.exists("tab/csd_means.csv"))
    expect_equal(loaded$mean_chunk_size,m$mean_chunk_size)
    writer <- function(plot,...) expect_s3_class(plot,"ggplot")
    r <- run_dedup_pareto(d,loaded,plot_writer=writer)
    expect_equal(nrow(r$results),540)
    expect_true(all(r$coverage$status == "ok"))
    # Cache reuse requires no access to the per-chunk inputs.
    cached <- load_pareto_means(chunk_dir="not-present")
    expect_equal(cached,loaded)
    expect_warning(missing <- load_pareto_means(path="explicit-missing.csv",chunk_dir=input),
                   "No saved CSD mean summary")
    expect_equal(nrow(missing),0)
  },finally=setwd(previous))
})
test_that("malformed chunks cannot silently create a mean summary", {
  file <- file.path(tmp,"invalid-chunks.csv.gz")
  bad <- d[1:3,PARETO_KEYS]; bad$chunk_size <- c(100,NA,20)
  readr::write_csv(bad,file)
  expect_error(aggregate_pareto_means(file,chunk_size=2),"Invalid chunk sizes")
  bad$chunk_size <- c(100,1.5,20)
  readr::write_csv(bad,file)
  expect_error(aggregate_pareto_means(file,chunk_size=2),"Invalid chunk sizes")
  expect_error(aggregate_pareto_means(c(file,file)),"Repeated CSD")
})
unlink(tmp,recursive=TRUE)
