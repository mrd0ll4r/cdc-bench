library(testthat)
source("plotting/dedup_pareto.R")
library(ggplot2)
theme_set(theme_bw(10))
tmp <- tempfile("pareto-tests-"); dir.create(tmp)
d <- expand.grid(algorithm=names(PARETO_ALGORITHMS),dataset=PARETO_DATASETS,
                 target_chunk_size=PARETO_TARGETS,stringsAsFactors=FALSE)
d$dedup_ratio <- .4
means <- d[PARETO_KEYS]; means$mean_chunk_size <- 250
matched <- match_pareto_summaries(d,means)

test_that("28-byte accounting agrees with independent totals", {
  r <- calculate_dedup_pareto(matched)
  expect_equal(nrow(r),180)
  expect_equal(unique(r$metadata_bytes),28)
  expect_equal(unique(r$adjusted_savings),1-(600+28*4)/1000)
})
test_that("dominance retains ties and is isolated by dataset", {
  expect_equal(pareto_nondominated(c(100,50,50,100),c(.5,.7,.7,.3)),c(TRUE,TRUE,TRUE,FALSE))
  m <- matched[1:2,]; m$dataset <- c("code","web")
  m$mean_chunk_size <- c(100,50); m$dedup_ratio <- c(.3,.5)
  expect_true(all(calculate_dedup_pareto(m)$nondominated))
  m$dataset <- "code"
  expect_equal(calculate_dedup_pareto(m)$nondominated,c(TRUE,FALSE))
})
test_that("negative savings remain visible", {
  m <- matched[matched$dataset == "code",][1,]
  m$mean_chunk_size <- 10; m$dedup_ratio <- .2
  r <- calculate_dedup_pareto(m)
  expect_equal(r$adjusted_savings,-2.6)
  expect_equal(ggplot_build(plot_dedup_pareto(r,"code"))$data[[1]]$y,-2.6)
})
test_that("missing or invalid inputs stop generation and retain diagnostics", {
  writer <- function(...) stop("must not plot")
  expect_error(run_dedup_pareto(d,means[-1,],tmp,writer),"Incomplete Pareto inputs")
  coverage <- readr::read_csv(file.path(tmp,"dedup-pareto-coverage.csv"),show_col_types=FALSE)
  expect_equal(sum(coverage$status == "missing achieved mean"),1)
  expect_error(match_pareto_summaries(rbind(d,d[1,]),means),"Duplicate deduplication")
  expect_error(match_pareto_summaries(d,rbind(means,means[1,])),"Duplicate mean-size")
  for (value in c(NA,Inf,-.1,1.1)) {
    bad <- d; bad$dedup_ratio[1] <- value
    expect_equal(sum(match_pareto_summaries(bad,means)$status == "invalid ratio or mean"),1)
  }
  bad <- means; bad$algorithm[bad$algorithm == "rabin_32"] <- "rabin"
  expect_equal(sum(match_pareto_summaries(d,bad)$status != "ok"),20)
})
test_that("separate figures and legend use the existing algorithm coding", {
  r <- calculate_dedup_pareto(matched)
  p <- plot_dedup_pareto(r,"code")
  built <- ggplot_build(p)
  # Compare against the old overview's factor order and unnamed scales.
  legacy <- d[d$dataset == "code",]
  legacy$algorithm <- factor(unname(PARETO_ALGORITHMS[legacy$algorithm]),
    levels=unname(PARETO_ALGORITHMS[sort(names(PARETO_ALGORITHMS))]))
  old <- ggplot(legacy,aes(target_chunk_size,dedup_ratio,color=algorithm,shape=algorithm)) +
    geom_point() + scale_color_manual(values=c("#1b9e77","#d95f02","#7570b3","#e7298a",
      "#66a61e","#e6ab02","#a6761d","#666666","#1f78b4")) +
    scale_shape_manual(values=c(21,22,23,24,25,1,2,3,4))
  old_scales <- ggplot_build(old)$plot$scales
  expect_equal(built$plot$scales$get_scales("colour")$map(DEDUP_LABELS),old_scales$get_scales("colour")$map(DEDUP_LABELS))
  expect_equal(built$plot$scales$get_scales("shape")$map(DEDUP_LABELS),old_scales$get_scales("shape")$map(DEDUP_LABELS))
  expect_equal(nrow(p$data),45)
  expect_equal(p$theme$legend.position,"none")
  expect_equal(p$theme$text$size,11)
  expect_equal(ggplot2::calc_element("axis.text.x",p$theme)$size,8.8)
  expect_equal(ggplot2::calc_element("axis.title.x",p$theme)$size,11)
  previous_theme <- theme_set(theme_bw(20))
  expect_equal(plot_dedup_pareto(r,"code")$theme$text$size,11)
  theme_set(previous_theme)
  names <- character()
  writer <- function(plot,name,width,height) {
    expect_s3_class(ggplot_build(plot),"ggplot_built")
    if (grepl("legendonly",name)) expect_equal(c(width,height),c(7,1)) else expect_equal(c(width,height),c(2,2))
    names <<- c(names,name)
  }
  run_dedup_pareto(d,means,tmp,writer)
  expect_equal(names,paste0("dedup_pareto_",c(PARETO_DATASETS,"legendonly")))
})
test_that("DuckDB reads the sole chunk source and averages all emitted rows", {
  input <- file.path(tmp,"chunks with ' quote"); dir.create(input)
  chunks <- d[rep(seq_len(nrow(d)),each=3),PARETO_KEYS]
  chunks$chunk_size <- rep(c(400,400,50),nrow(d))
  files <- file.path(input,paste0("csd_",PARETO_DATASETS,".csv.gz"))
  for (i in seq_along(files)) readr::write_csv(chunks[chunks$dataset == PARETO_DATASETS[i],],files[i])
  m <- aggregate_pareto_means(files)
  expect_equal(nrow(m),180)
  expect_equal(m$mean_chunk_size,rep(850/3,180))
  expect_true(all(match_pareto_summaries(d,m)$status == "ok"))
  expect_error(aggregate_pareto_means(character()),"No CSD input files")
  expect_error(aggregate_pareto_means(c(files,files[1])),"Repeated CSD")
  for (value in c(NA,1.5,Inf,0,-1)) {
    bad <- chunks[1:3,]; bad$chunk_size[1] <- value
    file <- file.path(tmp,"bad.csv.gz"); readr::write_csv(bad,file)
    expect_error(aggregate_pareto_means(file),"Invalid chunk sizes")
  }
})
unlink(tmp,recursive=TRUE)
