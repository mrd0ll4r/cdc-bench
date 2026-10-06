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
library(grid)

source("base_setup.R")
source("plot_setup.R")
source("table_setup.R")
source("tikz_setup.R")
source("util.R")

######################################################################
# DEDUPLICATION RATIO
######################################################################

dedup_data <- tibble()
infiles <- Sys.glob(sprintf("%s/dedup_*.csv.gz", csv_dir))
for (f in infiles) {
  tmp <- read_csv(f, col_types = "fcIiI") %>%
    mutate(algorithm = as.character(algorithm))
  
  if (isempty(dedup_data)) {
    dedup_data <- tmp
  } else {
    dedup_data <- dedup_data %>%
      mutate(algorithm = as.character(algorithm))
    dedup_data <- rows_append(dedup_data, tmp)
  }
  rm(tmp)
}

# temp fix for zero dataset_size on vmb because directory is symlink
library(bit64)
dedup_data <- dedup_data %>%
  mutate(dataset_size = if_else(dataset == "vmb", as.integer64(305448681472), dataset_size))

dedup_data <- dedup_data %>%
  filter(dataset %in% c("code","web","vmb","db")) %>%
  algorithm_as_factor() %>%
  mutate(unique_ratio=unique_chunks_size_sum/dataset_size) %>%
  mutate(dedup_ratio=1-unique_ratio) %>%
  mutate(target_chunk_size = as.factor(target_chunk_size))

######################################################################
# Dedup and metadata file size comparison with gzip compression

dataset_sizes <- c(code=117234841088, vmb=305448681472, db=155909947392, web=49004421120)

chunk_counts <- open_dataset(sprintf("%s/parquet/csd_cat", csv_dir), hive_style=TRUE, format="parquet") %>% 
  filter(algorithm == 'rabin_32') %>%
  group_by(dataset, target_chunk_size) %>%
  summarise(no_of_chunks = n(), .groups = 'drop') %>% 
  collect()

df <- d %>%
  mutate(target_chunk_size = as.integer(as.character(target_chunk_size))) %>% 
  left_join(chunk_counts, by = c("dataset", "target_chunk_size")) %>% 
  filter(algorithm == 'rabin_32' & target_chunk_size != 770 & target_chunk_size != 5482 ) %>%
  mutate(
    size = 0,
    algorithm = as.character(target_chunk_size),
    dedupped_size = dataset_sizes[dataset] * (1-dedup_ratio),
    metadata_cost = no_of_chunks * 28
    ) %>%
  select(dataset, algorithm, size, dedupped_size, metadata_cost) %>%
  add_row(dataset = "code", algorithm = "None", size = dataset_sizes["code"], dedupped_size = 0, metadata_cost = 0) %>%
  add_row(dataset = "web", algorithm = "None", size = dataset_sizes["web"], dedupped_size = 0, metadata_cost = 0) %>%
  add_row(dataset = "pdf", algorithm = "None", size = dataset_sizes["pdf"], dedupped_size = 0, metadata_cost = 0) %>%
  add_row(dataset = "lnx", algorithm = "None", size = dataset_sizes["lnx"], dedupped_size = 0, metadata_cost = 0) %>% 
  add_row(dataset = "code", algorithm = "GZIP", size = 2255491072, dedupped_size = 0, metadata_cost = 0) %>%
  add_row(dataset = "web", algorithm = "GZIP", size = 7101403136, dedupped_size = 0, metadata_cost = 0) %>%
  add_row(dataset = "pdf", algorithm = "GZIP", size = 9340710912, dedupped_size = 0, metadata_cost = 0) %>%
  add_row(dataset = "lnx", algorithm = "GZIP", size = 11164160000, dedupped_size = 0, metadata_cost = 0)

for (dataset_name in unique(d$dataset)) {
  df_long <- df %>%
    filter(dataset == dataset_name) %>% 
    pivot_longer(cols = c(size, dedupped_size, metadata_cost),
                 names_to = "measure",
                 values_to = "value") %>%
    mutate(algorithm = factor(algorithm, levels = c("None", "GZIP", "512", "1024", "2048", "4096", "8192")),
           measure = factor(measure, levels = c("size", "dedupped_size", "metadata_cost"),
                                                labels = c("Size", "Chunks", "Metadata")))
  
  integer_breaks_gb <- function(x) {
    x <- x / 1e9
    rng <- range(x, na.rm = TRUE)
    seq(from = floor(rng[1]), to = ceiling(rng[2]), by = 3)
  }
  
  p <- ggplot(df_long, aes(x = algorithm, y = value / 1e9, fill = measure, group = interaction(dataset, measure))) +  # Divide by 1e9 here for scale
    geom_bar(data = subset(df_long, measure != "size"), aes(fill = measure), stat = "identity", position = position_stack(reverse = TRUE)) +
    geom_bar(stat = "identity", position = position_stack(reverse = TRUE)) +
    geom_bar(stat = "identity", position = position_stack(reverse = TRUE), color = "black", fill = NA, size = 0.25) +
    scale_fill_manual(values = c("Size" = "#7F7F7F", "Chunks" = "#DDDDDD", "Metadata" = "#BBBBBB")) +
    labs(x = "Algorithm", y = "File Size (GB)", fill = "Measure") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position="none") +
    scale_y_continuous(
      labels = scales::comma,  # Simplified labels
      breaks = integer_breaks_gb(df_long$value)  # Applying function for breaks
    )

  print_plot(p, paste("post_file_size_", dataset_name, sep=""), height=1.6, width=2)
}

# Remove item from legend by reconstructing plot
df_long <- df %>%
  filter(dataset == dataset_name) %>% 
  pivot_longer(cols = c(size, dedupped_size, metadata_cost),
               names_to = "measure",
               values_to = "value") %>%
  mutate(algorithm = factor(algorithm, levels = c("None", "GZIP", "512", "1024", "2048", "4096", "8192")),
         measure = factor(measure, levels = c("dedupped_size", "metadata_cost"),
                          labels = c("Chunks", "Metadata")))
p <- ggplot(df_long, aes(x = algorithm, y = value, fill = measure, group = interaction(dataset, measure))) +
  geom_bar(data = subset(df_long, measure != "size"), aes(fill = measure), stat = "identity", position = position_stack(reverse = TRUE)) +
  geom_bar(stat = "identity", position = position_stack(reverse = TRUE)) +
  geom_bar(stat = "identity", position = position_stack(reverse = TRUE), color = "black", fill = NA, size = 0.25) +
  scale_fill_manual(values = c("Size" = "#7F7F7F", "Chunks" = "#DDDDDD", "Metadata" = "#BBBBBB")) +
  labs(x = "Algorithm", y = "File Size (GB)", fill = "Measure", title = NULL) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  scale_y_continuous(labels = function(x) format(round(x / 1e9, 2)))
print_plot(get_legend_plot(p, 2), "post_file_size_legendonly", height=0.8, width=4)

######################################################################
# Dedup overview per dataset

for (dataset_name in unique(dedup_data$dataset)) {
  filtered_data <- dedup_data %>%
    filter(dataset == dataset_name) %>%
    rename_datasets() %>% 
    rename_algorithms()
  
  p <- filtered_data %>% 
    ggplot(aes(x = target_chunk_size, y = dedup_ratio, 
               color = algorithm, linetype = algorithm, shape = algorithm, group = algorithm)) +
    geom_line(position = position_dodge(0.2), linewidth = 0.8) +  # Slightly increased dodge
    geom_point(position = position_jitterdodge(jitter.width = 0.3, dodge.width = 0.2), 
               size = 1.5, fill = "white") +  # Increased jitter
    ylab("Dedup. Ratio") +
    xlab("Target Chunk Size") +
    theme(legend.position = "none") + 
    guides(color = guide_legend(nrow = 1), 
           linetype = guide_legend(nrow = 1), 
           shape = guide_legend(nrow = 1)) +  
    scale_linetype_manual(values = c("solid", "dashed", "dotted", "dotdash", 
                                     "longdash", "twodash", "13", "44", "1343")) +
    scale_shape_manual(values = c(21, 22, 23, 24, 25, 1, 2, 3, 4)) +
    scale_color_manual(values = c(
      "#1b9e77", "#d95f02", "#7570b3", "#e7298a", 
      "#66a61e", "#e6ab02", "#a6761d", "#666666", "#1f78b4"
    )) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  print_plot(p, paste("dedup_overview", dataset_name, sep="_"), height=2, width=2)
}

p %>% 
  get_legend_plot(9) %>% 
  print_plot("dedup_overview_legendonly", height=1, width=6)

rm(p)
gc()

#########################################
# Gear NC variants

d <- dedup_data %>%
  filter(algorithm %in% GEAR_ALGORITHMS) %>% 
  filter(!(algorithm %in% c("gear64", "gear64_simd"))) %>% 
  filter(target_chunk_size %in% POWER_OF_TWO_SIZES)

for (dataset_name in unique(d$dataset)) {
  filtered_data <- d %>%
    filter(dataset == dataset_name) %>%
    rename_datasets()
  
  filtered_data$algorithm <- as.factor(filtered_data$algorithm)
  filtered_data$algorithm <- factor(recode(filtered_data$algorithm, !!!c(
    gear = "Vanilla", gear_nc_1 = "NC-1", gear_nc_2 = "NC-2", gear_nc_3 = "NC-3"
  )))
  
  p <- filtered_data %>% 
    ggplot(aes(x=target_chunk_size, y=dedup_ratio, color=algorithm, group=algorithm)) +
    geom_line(position=position_dodge(0.1)) +
    geom_point(position=position_dodge(0.1), size=1, shape=21, fill="white") +
    scale_y_continuous(labels = function(x) sprintf("%.2f", x)) +  # Formatting to two decimal places
    ylab("Dedup. Ratio") +
    xlab("Target Chunk Size") +
   # theme(legend.position="none",
  #        axis.text.x = element_text(angle = 45, hjust = 1)) +
    guides(color = guide_legend(nrow = 4)) +
    scale_color_futurama()
  
  if (dataset_name == "web") {
    p <- p + scale_y_continuous(
      labels = function(x) sprintf("%.2f", x),
      breaks = pretty(filtered_data$dedup_ratio, n = 3)
    )
  }
  
  print_plot(p, paste("dedup_gear_variants", dataset_name, sep="_"), height=1.8, width=2)
}

p %>% 
  get_legend_plot(4) %>% 
  print_plot("dedup_gear_variants_legendonly", height=1)

rm(p,d)
gc()


######################################################################
# Compare different window sizes for rabin, buzhash

comparison_plot <- function(df, dataset_name) {
  df %>%
    filter(dataset == dataset_name, target_chunk_size %in% POWER_OF_TWO_SIZES) %>%
    mutate(window_size = str_split_i(algorithm,"_",-1)) %>%
    mutate(window_size = fct_relevel(window_size, "16", "32", "48", "64", "128", "256")) %>% 
    mutate(algo_group = str_split_i(algorithm,"_",1)) %>%
    rename_datasets() %>% 
    rename_algorithms() %>% 
    ggplot(aes(x=target_chunk_size, y=dedup_ratio, color=window_size, group=window_size)) +
    geom_line(position=position_dodge(0.1)) +
    geom_point(position=position_dodge(0.1), size=1, shape=21, fill="white") +
    ylab("Dedup. Ratio") +
    xlab("Target Chunk Size") +
    scale_color_jama(name="Window Size (B)") +
    theme(legend.position = "none") + 
    scale_y_continuous(labels = function(x) format(x, nsmall = 2), breaks = pretty_breaks(n = 4)) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
}

for (dataset_name in unique(dedup_data$dataset)) {
  p <- dedup_data %>%
    filter(algorithm %in% RABIN_ALGORITHMS) %>%
    comparison_plot(dataset_name)
  
  print_plot(p, paste("dedup_rabin_window_sizes_", dataset_name, sep=""), height=1.8, width=2)
  
  p <- dedup_data %>%
    filter(algorithm %in% BUZHASH_ALGORITHMS) %>%
    comparison_plot(dataset_name)
  
  print_plot(p, paste("dedup_buzhash_window_sizes_", dataset_name, sep=""), height=1.8, width=2)
}

print_plot(get_legend_plot(p, 6), "dedup_window_sizes_legendonly", height=1)

####################
# Overview: Evaluate on WEB, facet wrap by algorithm group

# Rabin
p <- dedup_data %>%
  filter(dataset=="web") %>%
  filter(target_chunk_size %in% POWER_OF_TWO_SIZES) %>%
  filter(algorithm %in% RABIN_ALGORITHMS) %>%
  mutate(window_size = str_split_i(algorithm,"_",-1)) %>%
  mutate(algo_group = str_split_i(algorithm,"_",1)) %>%
  ggplot(aes(x=target_chunk_size, y=dedup_ratio, color=window_size, group=window_size)) +
  geom_line(position=position_dodge(0.1)) +
  geom_point(position=position_dodge(0.1), size=1, shape=21, fill="white") +
  labs(x="Target Chunk Size (B)",y="Dedup. Ratio") +
  scale_color_jama(name="Window Size (B)", # Legend label
                   breaks=c("16", "32", "48", "64", "128", "256"),
                   labels=c("16","32","48","64","128","256")) +
  theme(legend.position = "none")

print_plot(p,"dedup_comparison_window_sizes_web_algorithm_rabin",height=1.6)

# Buzhash
p <- dedup_data %>%
  filter(dataset=="web") %>%
  filter(target_chunk_size %in% POWER_OF_TWO_SIZES) %>%
  filter(algorithm %in% BUZHASH_ALGORITHMS) %>%
  mutate(window_size = str_split_i(algorithm,"_",-1)) %>%
  mutate(algo_group = str_split_i(algorithm,"_",1)) %>%
  ggplot(aes(x=target_chunk_size, y=dedup_ratio, color=window_size, group=window_size)) +
  geom_line(position=position_dodge(0.1)) +
  geom_point(position=position_dodge(0.1), size=1, shape=21, fill="white") +
  labs(x="Target Chunk Size (B)",y="Dedup. Ratio") +
  scale_color_jama(name="Window Size (B)", # Legend label
                   breaks=c("16", "32", "48", "64", "128", "256"),
                   labels=c("16","32","48","64","128","256")) +
  theme(legend.position = "none")

print_plot(p,"dedup_comparison_window_sizes_web_algorithm_buzhash",height=1.6)

# Legend
dummy_plot <- p + theme_void() +
  theme(
    legend.position = "bottom",
    legend.text = element_text(size = 10), # Adjusts the legend text size
    legend.direction = "horizontal", # Ensures the legend items are laid out horizontally
    legend.key.size = unit(0.5, "cm") # Adjusts the legend key size
  ) +
  guides(color = guide_legend(ncol = 3, override.aes = list(size = 3)))

legend <- cowplot::get_legend(dummy_plot)

if (!dev.cur()) dev.new()
grid.newpage()
grid.draw(legend)
legend_plot <- recordPlot()
dev.off()
dev.new()

print_plot(legend_plot, "dedup_comparison_window_sizes_legendonly", height=0.8)


rm(p,d)
gc()

######################################################################
# Compare QuickCDC variants to plain gear-nc-1

d <- dedup_data %>%
  filter(target_chunk_size %in% POWER_OF_TWO_SIZES) %>%
  filter(!(dataset %in% c("random","zero"))) %>%
  filter(algorithm %in% QUICKCDC_RABIN_ALGORITHMS_NOSKIP | algorithm == "rabin_64") %>%
  # filter out hash variants, they should be identical to the array versions
  filter(!grepl("hash", algorithm, fixed=TRUE))

# Create table
t <- d %>%
  pivot_wider(id_cols=c(algorithm,dataset),names_from=target_chunk_size,values_from=dedup_ratio)

addtorow <- list()
addtorow$pos <- list(0)
addtorow$command <- '&& \\multicolumn{5}{c}{Deduplication Ratio}\\\\
\\cmidrule(lr){3-7}
algorithm & dataset & CS=512B & 1KiB & 2KiB & 4KiB & 8KiB\\\\'

print(xtable(t, digits=6), file="tab/dedup_quickcdc_variants_all_datasets.tex", add.to.row=addtorow,include.colnames=F,floating=FALSE)

rm(t,d,addtorow)
gc()
