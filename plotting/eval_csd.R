library(readr)
library(ggplot2)
library(xtable)
library(dplyr)
library(tidyr)
library(scales)
library(ggsci)
library(stringr)
library(bit64)
library(RColorBrewer)
library(forcats)
library(ztable)
library(arrow)
library(purrr)
library(grid)
options(ztable.type = "latex", digits=1)

source("base_setup.R")
source("plot_setup.R")
source("table_setup.R")
source("tikz_setup.R")
source("util.R")

######################################################################
# CHUNK SIZE DISTRIBUTIONS
######################################################################
# Note: The complete CSD dataset is too large to be stored in one R vector.
# However, we converted it to an Arrow dataset, which can be imported from disk
# and operated on without this limitation.

process_data <- function(csd_data) {
  df <- csd_data %>%
    filter(algorithm %in% ALGORITHM_ORDER) %>% 
    group_by(algorithm, dataset, target_chunk_size) %>%
    summarize(
      mean = mean(chunk_size),
      sd = sd(chunk_size),
      .groups = 'drop'
    ) %>% 
    collect() %>%
    pivot_wider(
      id_cols = c(algorithm, dataset),
      names_from = target_chunk_size,
      values_from = c(mean, sd),
      names_sep = "_"
    )
  
  target_sizes <- c(512, 770, 1024, 2048, 4096, 5482, 8192)
  col_order <- unlist(sapply(target_sizes, function(size) c(paste("mean", size, sep = "_"), paste("sd", size, sep = "_"))))
  
  as.data.frame(df[, c("algorithm", "dataset", col_order)])
}

######################################################
library(duckdb)
con <- dbConnect(duckdb::duckdb())
duckdb_df <- dbGetQuery(con, "
SELECT 
    dataset, 
    algorithm, 
    -- Mean and SD for all target_chunk_size values
    AVG(CASE WHEN target_chunk_size = 512 THEN chunk_size END) AS mean_512,
    STDDEV(CASE WHEN target_chunk_size = 512 THEN chunk_size END) AS sd_512,

    AVG(CASE WHEN target_chunk_size = 1024 THEN chunk_size END) AS mean_1024,
    STDDEV(CASE WHEN target_chunk_size = 1024 THEN chunk_size END) AS sd_1024,

    AVG(CASE WHEN target_chunk_size = 2048 THEN chunk_size END) AS mean_2048,
    STDDEV(CASE WHEN target_chunk_size = 2048 THEN chunk_size END) AS sd_2048,

    AVG(CASE WHEN target_chunk_size = 4096 THEN chunk_size END) AS mean_4096,
    STDDEV(CASE WHEN target_chunk_size = 4096 THEN chunk_size END) AS sd_4096,

    AVG(CASE WHEN target_chunk_size = 8192 THEN chunk_size END) AS mean_8192,
    STDDEV(CASE WHEN target_chunk_size = 8192 THEN chunk_size END) AS sd_8192

FROM read_csv_auto('csv/csd_*.csv.gz', ignore_errors=True)
GROUP BY dataset, algorithm;
")
######################################################

df <- as.data.frame(duckdb_df)
df <- df[df$algorithm %in% ALGORITHM_ORDER, ] 
df$dataset <- factor(df$dataset, levels = DATASET_ORDER)
df$algorithm <- factor(df$algorithm, levels = ALGORITHM_ORDER)
df <- df %>%
  mutate(dataset = factor(dataset, levels = DATASET_ORDER),
         algorithm = factor(algorithm, levels = ALGORITHM_ORDER)) %>%
  arrange(dataset, algorithm)

df <- df[order(df$dataset, df$algorithm), ]

color_scale_df <- df %>%
  mutate(
    sd_512 = ifelse(((df$sd_512 - df$mean_512) / df$mean_512 + 1) / 2 > 1, 1, ((df$sd_512 - df$mean_512) / df$mean_512 + 1) / 2),
    sd_1024 = ifelse(((df$sd_1024 - df$mean_1024) / df$mean_1024 + 1) / 2 > 1, 1, ((df$sd_1024 - df$mean_1024) / df$mean_1024 + 1) / 2),
    sd_2048 = ifelse(((df$sd_2048 - df$mean_2048) / df$mean_2048 + 1) / 2 > 1, 1, ((df$sd_2048 - df$mean_2048) / df$mean_2048 + 1) / 2),
    sd_4096 = ifelse(((df$sd_4096 - df$mean_4096) / df$mean_4096 + 1) / 2 > 1, 1, ((df$sd_4096 - df$mean_4096) / df$mean_4096 + 1) / 2),
    sd_8192 = ifelse(((df$sd_8192 - df$mean_8192) / df$mean_8192 + 1) / 2 > 1, 1, ((df$sd_8192 - df$mean_8192) / df$mean_8192 + 1) / 2),
    
    mean_512 = ifelse(abs(df$mean_512 - 512) > 512, 512, abs(df$mean_512 - 512)),
    mean_1024 = ifelse(abs(df$mean_1024 - 1024) > 1024, 1024, abs(df$mean_1024 - 1024)),
    mean_2048 = ifelse(abs(df$mean_2048 - 2048) > 2048, 2048, abs(df$mean_2048 - 2048)),
    mean_4096 = ifelse(abs(df$mean_4096 - 4096) > 4096, 4096, abs(df$mean_4096 - 4096)),
    mean_8192 = ifelse(abs(df$mean_8192 - 8192) > 8192, 8192, abs(df$mean_8192 - 8192)),
  )

cgroup=c("Algorithm", "Dataset", "512 B", "1 KB", "2 KB", "4 KB", "8 KB")
n.cgroup=c(1, 1, 2, 2, 2, 2, 2)

rgroup=c("RANDOM", "CODE", "WEB", "DB", "VMB")
n.rgroup=c(8, 8, 8, 8, 8)

ztab <- color_scale_df %>% 
  rename_algorithms() %>% 
  ztable() %>%
  addcgroup(cgroup=cgroup, n.cgroup=n.cgroup) %>% 
  addrgroup(rgroup=rgroup,n.rgroup=n.rgroup,cspan.rgroup=1) %>% 
  makeHeatmap(margin=2)

for (col_name in c("mean_512", "sd_512", "mean_1024", "sd_1024", "mean_2048", "sd_2048", "mean_4096", "sd_4096", "mean_8192", "sd_8192")) {
  ztab$x[[col_name]] <- as.character(as.integer(df[[col_name]]))
}

writeLines(capture.output(ztab), "tab/csd_means_sd_full.tex")

### Overview table: equal-weight relative target error and CV, without clipping

overview_targets <- c(512, 1024, 2048, 4096, 8192)
overview_datasets <- c("random", "code", "web", "vmb", "db")
overview <- expand_grid(algorithm = ALGORITHM_ORDER, dataset = overview_datasets) %>%
  left_join(df, by = c("algorithm", "dataset"))

# Use the original measured means/SDs, not the detailed table's color scores.
means <- as.matrix(overview[paste0("mean_", overview_targets)])
sds <- as.matrix(overview[paste0("sd_", overview_targets)])
means[!is.finite(means) | means <= 0] <- NA_real_
sds[!is.finite(sds) | sds < 0] <- NA_real_
overview$error <- rowMeans(abs(sweep(means, 2, overview_targets, "/") - 1))
overview$cv <- rowMeans(sds / means)
# rowMeans deliberately propagates NA: an aggregate requires all five targets.
saveRDS(list(measured = df, overview = overview), "tab/csd_overview.audit.rds")

overview_table <- overview %>%
  select(algorithm, dataset, error, cv) %>%
  mutate(error = error * 100) %>%
  pivot_wider(names_from = dataset, values_from = c(error, cv)) %>%
  select(algorithm, all_of(paste0("error_", overview_datasets)),
         all_of(paste0("cv_", overview_datasets))) %>%
  rename_algorithms()

overview_lines <- c(
  "\\begingroup", "\\small\\setlength{\\tabcolsep}{5pt}",
  "\\begin{tabular}{lrrrrrrrrrr}", "\\toprule",
  "& \\multicolumn{5}{c}{Mean absolute relative target error (\\%)} & \\multicolumn{5}{c}{Mean coefficient of variation} \\\\",
  "\\cmidrule(lr){2-6}\\cmidrule(lr){7-11}",
  "Algorithm & RAND & CODE & WEB & VMB & DB & RAND & CODE & WEB & VMB & DB \\\\",
  "\\midrule"
)
for (i in seq_len(nrow(overview_table))) {
  values <- as.numeric(overview_table[i, -1])
  cells <- ifelse(is.na(values), "\\textemdash{}", sprintf("%.2f", values))
  overview_lines <- c(overview_lines,
                      paste0(paste(c(as.character(overview_table$algorithm[i]), cells),
                                   collapse = " & "), " \\\\"))
}
overview_lines <- c(overview_lines, "\\bottomrule", "\\end{tabular}", "\\endgroup")
if (anyNA(overview_table)) {
  overview_lines <- c(overview_lines, paste0(
    "\\par\\smallskip\\footnotesize\\textbf{REBUTTAL-DATA-PENDING:} ",
    "Dashes denote unavailable aggregates, not zero. Each aggregate requires all five target settings."))
}
writeLines(overview_lines, "tab/csd_overview.tex")
rm(overview_targets, overview_datasets, overview, means, sds, overview_table,
   overview_lines, values, cells)

rm(df, ztab, cgroup, rgroup, n.cgroup, n.rgroup, color_scale_df)
gc()

# TODO algorithm_as_factor cleanup

csd_ecdf_plot <- function(df) {
  target_chunk_size <- as.numeric(df$target_chunk_size[1])
  
  # Calculate ECDF for each algorithm manually
  df_ecdf <- df %>%
    group_by(algorithm) %>%
    arrange(chunk_size) %>%
    mutate(ecdf_value = ecdf(chunk_size)(chunk_size)) %>%
    ungroup()
  
  ggplot(df_ecdf, aes(x = chunk_size, y = ecdf_value, 
                      color = algorithm, linetype = algorithm)) +
    geom_step() +
    xlab("Chunk Size (B)") +
    ylab("Empirical CDF") +
    coord_cartesian(xlim = c(0, target_chunk_size * 4), 
                    ylim = c(0, 1)) +
    theme_bw() + 
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "none"
    )
}


con <- dbConnect(duckdb::duckdb())

for (dataset_name in DATASET_ORDER) {
  query <- sprintf(
    "SELECT dataset, algorithm, target_chunk_size, chunk_size 
     FROM read_csv_auto('csv/csd_%s.csv.gz', ignore_errors=True)
     WHERE algorithm != 'fsc' AND target_chunk_size = 1024
     ORDER BY RANDOM() LIMIT 10000;",
    dataset_name
  )
  chunk_sizes_df <- dbGetQuery(con, query) %>% rename_algorithms()
  p <- chunk_sizes_df %>% csd_ecdf_plot()
  ggsave(paste0(paste("csd", dataset_name, sep="_"), ".pdf"), plot = p, width = 2, height = 2)
  print_plot(p, paste("csd", dataset_name, sep="_"), height=2, width=2)
}

p %>% 
  get_legend_plot(8) %>% 
  print_plot("csd_legendonly", height=1, width=6)



csd_density_plot <- function(df) {
  df <- filter(df, !(algorithm %in% c("fsc")))
  target_chunk_size <- as.numeric(df$target_chunk_size[1])
  
  df_means <- df %>%
    group_by(algorithm) %>%
    summarize(mean_chunk_size = mean(chunk_size)) %>%
    collect()
  
  ggplot(df, aes(x = chunk_size, color = algorithm, linetype = algorithm)) +
    geom_freqpoly(bins = 100, aes(y = after_stat(density))) +
    xlab("Chunk Size (B)") +
    ylab("Density") +
    xlim(c(0, target_chunk_size * 4)) +
    geom_point(data = df_means, 
               aes(x = mean_chunk_size, y = 1e-6, color = algorithm),  # set a nonzero y-value
               size = 3, show.legend = FALSE)
}

#### QuickCDC variants only
t2 <- t %>%
  filter(algorithm %in% QUICKCDC_ALGORITHMS | algorithm == "gear_nc_1")

print(xtable(t), file="tab/csd_means_sd_quickcdc.tex", add.to.row=addtorow,include.colnames=F,floating=FALSE)

#### Rabin variants only
t2 <- t %>%
  filter(algorithm %in% RABIN_ALGORITHMS)

print(xtable(t2), file="tab/csd_means_sd_rabin.tex", add.to.row=addtorow,include.colnames=F,floating=FALSE)

#### Buzhash variants only
t2 <- t %>%
  filter(algorithm %in% BUZHASH_ALGORITHMS)

print(xtable(t2), file="tab/csd_means_sd_buzhash.tex", add.to.row=addtorow,include.colnames=F,floating=FALSE)

#### Adler32 variants only
t2 <- t %>%
  filter(algorithm %in% ADLER32_ALGORITHMS)

print(xtable(t2), file="tab/csd_means_sd_adler32.tex", add.to.row=addtorow,include.colnames=F,floating=FALSE)

#### Gear variants only
t2 <- t %>%
  filter(algorithm %in% GEAR_ALGORITHMS)

print(xtable(t2), file="tab/csd_means_sd_gear.tex", add.to.row=addtorow,include.colnames=F,floating=FALSE)

#### BFBC variants only
t2 <- t %>%
  filter(algorithm %in% BFBC_ALGORITHMS)

print(xtable(t2), file="tab/csd_means_sd_bfbc.tex", add.to.row=addtorow,include.colnames=F,floating=FALSE)

rm(t,t2,d,addtorow)
gc()

######################################################################
# Compare NC-gear variants

csd_data <- open_dataset(sprintf("%s/parquet/csd", csv_dir), hive_style=TRUE, format="parquet")

d <- csd_data %>%
  filter(algorithm %in% c("gear","gear_nc_1","gear_nc_2","gear_nc_3"))  %>%
  filter(dataset == "code") %>%
  filter(target_chunk_size == 8192) %>% 
  collect()

###############
# Dataset eval_dataset, eval_target_cs target
p <- d %>% 
  csd_density_plot()
print_plot(p,sprintf("csd_gear_nc_%s_%d",eval_dataset,eval_target_cs))

###############
# All Datasets, eval_target_cs target
p <- d %>%
  filter(target_chunk_size==eval_target_cs) %>%
  csd_density_plot()+
  facet_wrap(~dataset,dir="v")

print_plot(p,sprintf("csd_gear_nc_dataset_faceted_%d",eval_target_cs),height=8)

###############
# Dataset eval_dataset, all targets

p <- d %>%
  filter(dataset==eval_dataset) %>%
  csd_density_plot()+
  facet_wrap(~target_chunk_size,dir="v")

print_plot(p,sprintf("csd_gear_nc_%s_target_faceted",eval_dataset),height=8)

rm(d,p,eval_target_cs,eval_dataset)
gc()

################
# All datasets on target 770

p <- csd_data %>%
  filter(algorithm %in% ALGORITHMS_TO_COMPARE) %>%
  filter(target_chunk_size == 770) %>%
  filter(dataset == "random") %>%
  csd_density_plot()
print_plot(p,sprintf("csd_random_770",eval_dataset), height=8)

p <- csd_data %>%
  filter(algorithm %in% ALGORITHMS_TO_COMPARE) %>%
  filter(target_chunk_size == 770) %>%
  filter(dataset == "code") %>%
  csd_density_plot()
print_plot(p,sprintf("csd_code_770",eval_dataset),height=8)

p <- csd_data %>%
  filter(algorithm %in% ALGORITHMS_TO_COMPARE) %>%
  filter(target_chunk_size == 770) %>%
  filter(dataset == "web") %>%
  csd_density_plot()
print_plot(p,sprintf("csd_web_770",eval_dataset),height=8)

p <- csd_data %>%
  filter(algorithm %in% ALGORITHMS_TO_COMPARE) %>%
  filter(target_chunk_size == 770) %>%
  filter(dataset == "pdf") %>%
  csd_density_plot()
print_plot(p,sprintf("csd_pdf_770",eval_dataset),height=8)

p <- csd_data %>%
  filter(algorithm %in% ALGORITHMS_TO_COMPARE) %>%
  filter(target_chunk_size == 770) %>%
  filter(dataset == "lnx") %>%
  csd_density_plot()
print_plot(p,sprintf("csd_lnx_770",eval_dataset),height=8)

p <- csd_data %>%
  filter(algorithm %in% ALGORITHMS_TO_COMPARE) %>%
  filter(target_chunk_size == 770) %>%
  filter(dataset == "zero") %>%
  csd_density_plot()
print_plot(p,sprintf("csd_zero_770",eval_dataset),height=8)


######################################################################
# Plot Gear variants

for (dataset_name in c("random", "code")) {
  TARGET_CS <- 2048
  if (dataset_name == 'random') {
    dataset_path <- sprintf("%s/parquet/csd", csv_dir)
  } else {
    dataset_path <- sprintf("%s/parquet/csd_cat", csv_dir)
  }
  d <- open_dataset(dataset_path, hive_style=TRUE, format="parquet") %>% 
    filter(dataset == dataset_name) %>%
    filter(target_chunk_size == TARGET_CS) %>%
    filter(algorithm %in% GEAR_ALGORITHMS) %>%
    filter(algorithm != "gear64_simd" & algorithm != "gear64") %>% 
    collect()
  
  df_means <- d %>%
    group_by(algorithm) %>%
    summarize(mean_chunk_size = mean(chunk_size))
  
  labels <- c("gear" = "Vanilla", "gear_nc_1" = "NC-1", "gear_nc_2" = "NC-2", "gear_nc_3" = "NC-3")
  p <- d %>%
    ggplot(aes(x = chunk_size / 1000, color = algorithm, linetype = algorithm)) +
    geom_freqpoly(bins=100, aes(y = after_stat(density))) +
    xlab("Chunk Size (KB)") +
    ylab("Density") +
    xlim(c(0, TARGET_CS * 2 / 1000)) +
    geom_point(data = df_means, aes(x = mean_chunk_size / 1000, y = 0, color = algorithm), size = 2, show.legend = FALSE) +
    theme(legend.position = "none", legend.title = element_blank()) +
    scale_color_discrete(labels = labels) +
    scale_linetype_discrete(labels = labels)
  
  print_plot(p, paste("csd_gear_variants", dataset_name, sep="_"), height=1.8, width=2)
}

print_plot(get_legend_plot(p, 4), "csd_gear_variants_legendonly", width=3.5, height=0.5)


rm(labels,df_means,target_cs,d,p)


######################################################################
# Compare Rabin variants

d <- csd_data %>%
  filter(algorithm %in% RABIN_ALGORITHMS)
eval_target_cs <- 4096
eval_dataset <- "random"

###############
# Dataset eval_dataset, eval_target_cs target
p <- d  %>%
  filter(dataset==eval_dataset) %>%
  filter(target_chunk_size == eval_target_cs) %>%
  csd_density_plot()
print_plot(p,sprintf("csd_rabin_%s_%d_v1",eval_dataset,eval_target_cs))

p <- d  %>%
  filter(dataset==eval_dataset) %>%
  filter(target_chunk_size == eval_target_cs)  %>%
  csd_density_plot2(spread=3)

print_plot(p,sprintf("csd_rabin_%s_%d_v2",eval_dataset,eval_target_cs))

###############
# All Datasets, eval_target_cs target
p <- d %>%
  filter(target_chunk_size==eval_target_cs) %>%
  csd_density_plot() +
  facet_wrap(~dataset,dir="v")

print_plot(p,sprintf("csd_rabin_dataset_faceted_%d_v1",eval_target_cs),height=8)

p <- d %>%
  filter(target_chunk_size==eval_target_cs) %>%
  csd_density_plot2()+
  facet_wrap(~dataset,dir="v")

print_plot(p,sprintf("csd_rabin_dataset_faceted_%d_v2",eval_target_cs),height=8)

###############
# Dataset eval_dataset, all targets

p <- d %>%
  filter(dataset==eval_dataset) %>%
  csd_density_plot() +
  facet_wrap(~target_chunk_size,dir="v")

print_plot(p,sprintf("csd_rabin_%s_target_faceted_v1",eval_dataset),height=8)

p <- d %>%
  filter(dataset==eval_dataset) %>%
  csd_density_plot2() +
  facet_wrap(~target_chunk_size,dir="v")

print_plot(p,sprintf("csd_rabin_%s_target_faceted_v2",eval_dataset),height=8)

rm(d,p)
gc()


################
# All datasets on target 1024 or 770

ALGORITHMS_TO_COMPARE <- c("ae","ram","mii","pci","rabin_32","bfbc","bfbc_custom_div")

df <- open_dataset(sprintf("%s/parquet/csd_cat", csv_dir), hive_style=TRUE, format="parquet") %>%
  filter(target_chunk_size == 1024 | (target_chunk_size == 770 & algorithm == "mii")) %>%
  filter(algorithm %in% ALGORITHMS_TO_COMPARE) %>%
  filter(!(algorithm %in% c("fsc"))) %>% 
  filter(dataset %in% DATASET_ORDER)

df_rand <- open_dataset(sprintf("%s/parquet/csd", csv_dir), hive_style=TRUE, format="parquet") %>%
  filter(dataset == 'random') %>%
  filter(target_chunk_size == 1024 | (target_chunk_size == 770 & algorithm == "mii")) %>%
  filter(algorithm %in% ALGORITHMS_TO_COMPARE) %>%
  filter(!(algorithm %in% c("fsc")))

combined_df <- rbind(collect(df), collect(df_rand))
combined_df$algorithm <- factor(combined_df$algorithm, levels = ALGORITHM_ORDER)
combined_df$dataset <- factor(combined_df$dataset, levels = DATASET_ORDER)

# render per algorithm (lines are datasets)
for (algorithm_name in unique(df$algorithm)) {
  algo_df <- combined_df %>%
    filter(algorithm == algorithm_name) %>%
    rename_algorithms() %>%
    rename_datasets()
  
  p <- ggplot(algo_df, aes(x = chunk_size, color = dataset, linetype = dataset)) +
    geom_freqpoly(bins=100, aes(y = after_stat(density))) +
    xlab("Chunk Size (B)") +
    ylab("Density") +
    xlim(c(0, 1024 * 2)) +
    theme(legend.position = "bottom")
  
  print_plot(p, paste("csd", algorithm_name, sep="_"), height=2)
}

# render per dataset (lines are algorithms)
for (dataset_name in DATASET_ORDER) {
  dataset_df <- combined_df %>%
    filter(dataset == dataset_name) %>%
    rename_algorithms() %>%
    rename_datasets()
  
  p <- ggplot(dataset_df, aes(x = chunk_size, color = algorithm, linetype = algorithm)) +
    geom_freqpoly(bins=100, aes(y = after_stat(density))) +
    xlab("Chunk Size (B)") +
    ylab("Density") +
    xlim(c(0, 1024 * 2)) +
    theme(legend.position = "none")
  
  print_plot(p, paste("csd", dataset_name, sep="_"), height=1.6, width=2)
}

print_plot(get_legend_plot(p, 4), "csd_legendonly", height=1, width=4)


p <- combined_df %>% 
  rename_algorithms() %>% 
  rename_datasets() %>% 
  ggplot(aes(x = chunk_size, color = algorithm, linetype = algorithm)) +
  geom_freqpoly(bins=100, aes(y = after_stat(density))) +
  xlab("Chunk Size (B)") +
  ylab("Density") +
  xlim(c(0, 1024 * 2)) +
  facet_wrap(~dataset, ncol = 2, scales = "free_y") +
  theme(legend.position = "bottom")

print_plot(p, "csd", width=8, height=6)

rm(d,p)
gc()

#########################################
# Gear NC chunk size distributions

p <- ggplot(data_filtered, aes(x=g_norm, y=n_norm, linetype=window_size, fill=window_size)) +
  geom_line(position=position_jitter(width=0,height=0.005)) +
  geom_area(alpha=0.1,position="identity") +
  labs(x="Normalized Codomain", y="Density") +
  scale_fill_manual(values=hue_pal()(6), name="Window Size (B)") +
  scale_color_manual(values=hue_pal()(6), name="Window Size (B)")

