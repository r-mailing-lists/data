# R Mailing List Data: Demo Analysis


- [Setup](#setup)
- [Message volume over time](#message-volume-over-time)
- [Top posters by list](#top-posters-by-list)
- [Reply network on r-devel](#reply-network-on-r-devel)
- [Contributors across lists](#contributors-across-lists)

This notebook demonstrates how to work with the R mailing list Parquet
data. See the [main README](../README.md) for setup instructions and
data dictionary.

## Setup

### Using convenience functions

Source the helper script to download and cache data automatically — no
cloning required:

``` r
source("https://raw.githubusercontent.com/r-mailing-lists/data/main/scripts/rml.R")
```

``` r
library(dplyr, warn.conflicts = FALSE)
library(scales)
library(ggplot2)

theme_set(
  theme_minimal(base_size = 13) +
    theme(
      panel.grid.minor = element_blank(),
      plot.title.position = "plot"
    )
)

# Load aliases for name resolution
resolve_aliases <- function(df) {
  aliases_file <- "../aliases.json"
  if (!file.exists(aliases_file)) return(df)
  alias_data <- jsonlite::fromJSON(aliases_file)
  lookup <- data.frame(
    from_email_hash = unlist(alias_data$aliases$email_hashes),
    canonical_name = rep(alias_data$aliases$canonical_name,
                         lengths(alias_data$aliases$email_hashes)),
    stringsAsFactors = FALSE
  )
  df |>
    left_join(lookup, by = "from_email_hash") |>
    mutate(from_name = ifelse(is.na(canonical_name), from_name, canonical_name)) |>
    select(-canonical_name)
}
```

The helper provides four main functions:

``` r
# See all available mailing lists
rml_available()
```

      [1] "abernethy-reliability"   "adegenet-forum"         
      [3] "basta-users"             "batman-users"           
      [5] "bioc-devel"              "bioc-ggtree"            
      [7] "bioc-sig-proteomics"     "bioc-sig-sequencing"    
      [9] "biocbug"                 "bioconductor"           
     [11] "biogeobears"             "blavaan"                
     [13] "boostheaders-devel"      "braingraph-help"        
     [15] "brms-users"              "camtrapr"               
     [17] "canopy-phylogeny"        "catlearn-package"       
     [19] "chnosz-help"             "cipsr-users"            
     [21] "corpling-with-r"         "cran2deb-discuss"       
     [23] "ctmm-user"               "ctsem-mail"             
     [25] "dartr"                   "datatable-help"         
     [27] "davis-rug"               "deducer"                
     [29] "dirichletreg-news"       "distance-sampling"      
     [31] "distr-distr"             "dynr"                   
     [33] "eventstudies-discussion" "expm-developers"        
     [35] "ez4r"                    "flr-list"               
     [37] "forensim-help"           "fresh-tor4"             
     [39] "ftree-community"         "genabel-announce"       
     [41] "genabel-devel"           "genoplotr-help"         
     [43] "geomorph-r-package"      "ggplot2"                
     [45] "ggvis"                   "gsoc-dowd"              
     [47] "gsoc-porta"              "gsoc-r"                 
     [49] "gwidgets-questions"      "hmecology"              
     [51] "hyperspec-help"          "immcantation-news"      
     [53] "inlinedocs-support"      "ipmpack-users"          
     [55] "irace-package"           "isorix"                 
     [57] "israel-r-user-group"     "knitr"                  
     [59] "lavaan"                  "listpackage-discuss"    
     [61] "mailman"                 "manipulatr"             
     [63] "mediation-information"   "metacoder-discussions"  
     [65] "metrology-devel"         "mirt-package"           
     [67] "mixvir"                  "monetr-users"           
     [69] "mplusautomation"         "mvabund-faqs"           
     [71] "mvabund-updates"         "nat-user"               
     [73] "netlogor"                "nimble-users"           
     [75] "nlsy-links"              "nmf-user"               
     [77] "nmof-news"               "orchestra-users"        
     [79] "oscr-package"            "pez-users"              
     [81] "phenopix-developers"     "phylobase-devl"         
     [83] "phylogram"               "picante-devel"          
     [85] "piecepackr"              "pomp-announce"          
     [87] "poppr"                   "qcawithr"               
     [89] "qtinterfaces-devel"      "r-and-cpp"              
     [91] "r-announce"              "r-devel"                
     [93] "r-forge-testing-testing" "r-gregmisc-devel"       
     [95] "r-help"                  "r-help-es"              
     [97] "r-hiphop"                "r-inla-discussion-group"
     [99] "r-marketing-bugs"        "r-package-devel"        
    [101] "r-package-xlsx"          "r-packages"             
    [103] "r-sig-db"                "r-sig-dcm"              
    [105] "r-sig-debian"            "r-sig-dynamic-models"   
    [107] "r-sig-ecology"           "r-sig-epi"              
    [109] "r-sig-fedora"            "r-sig-finance"          
    [111] "r-sig-genetics"          "r-sig-geo"              
    [113] "r-sig-gr"                "r-sig-gui"              
    [115] "r-sig-hpc"               "r-sig-insurance"        
    [117] "r-sig-jobs"              "r-sig-mac"              
    [119] "r-sig-mediawiki"         "r-sig-meta-analysis"    
    [121] "r-sig-mixed-models"      "r-sig-networks"         
    [123] "r-sig-phylo"             "r-sig-qa"               
    [125] "r-sig-robust"            "r-sig-rugs"             
    [127] "r-sig-teaching"          "r-sig-wiki"             
    [129] "r-sig-windows"           "r-ug-ottawa"            
    [131] "rangemapper-news"        "rattle-users"           
    [133] "rcicr-users"             "rcpp-devel"             
    [135] "rcppoctave-user"         "rdevtools"              
    [137] "reddyproc-users"         "remoterengine-devel"    
    [139] "repitools-help"          "rgeos-devel"            
    [141] "rhadoop"                 "rhipe"                  
    [143] "right-user"              "riskassessment-news"    
    [145] "rmetrics-core"           "rnomads-user"           
    [147] "robustbase-authors"      "ropengov-forum"         
    [149] "roxygen-devel"           "rpackageggir"           
    [151] "rphree-general"          "rprotobuf-yada"         
    [153] "rqtl-announce"           "rqtl-disc"              
    [155] "rqtl2-disc"              "rquantlib-devel"        
    [157] "rserlang-develop"        "rsiena-help"            
    [159] "rsnns"                   "rspatial-devel"         
    [161] "rworldmap"               "sciviews-help"          
    [163] "sciviews-news"           "secrgroup"              
    [165] "seewave"                 "seqinr-forum"           
    [167] "sequenza-user-group"     "shiny-discuss"          
    [169] "shinyapps-users"         "simmer-devel"           
    [171] "simplephenotypes"        "simsalabim-communicate" 
    [173] "sorvi-admin"             "spades-users"           
    [175] "spdep-devel"             "spocc-spabund-users"    
    [177] "sprint-developer"        "sprint-user"            
    [179] "sqldf"                   "stan-dev"               
    [181] "stan-users"              "synbreed-news"          
    [183] "tidylpa"                 "tikzdevice-bugs"        
    [185] "tlocoh-info"             "tmb-users"              
    [187] "traminer-users"          "travelr-announce"       
    [189] "travelr-discussion"      "trophicposition-support"
    [191] "tsdyn"                   "uhcluster-members"      
    [193] "unmarked"                "viennar-meetup"         
    [195] "vim-r-plugin"            "wallaceecomod"          
    [197] "yuima-wishlist"          "zipfr-users"            

``` r
# Read a single list (use col_select to skip the body — much faster)
r_devel <- rml_read("r-devel",
  col_select = c("from_name", "date", "subject", "thread_id", "month"))

str(r_devel)
```

    Classes 'tbl' and 'data.frame': 63736 obs. of  5 variables:
     $ from_name: chr  "Martin Maechler" "Kurt Hornik" "Martin Maechler" "Martin Maechler" ...
     $ date     : POSIXct, format: "1997-04-01 08:28:56" "1997-04-01 08:35:43" ...
     $ subject  : chr  "R-alpha: Re: R-Prerelease  ---- Mailing list  \"R-devel\"" "R-alpha: Re: R-Prerelease  ---- Mailing list  \"R-devel\"" "R-alpha: Re: Pretest Version + Notes --- write.table" "R-alpha: R0.50-pre6:  \"stack imbalance in ...\" //  is.vector(matrix...)" ...
     $ thread_id: chr  "thread-0823a0ef3954" "thread-0823a0ef3954" "thread-87797c263db4" "thread-95d55ddd69bf" ...
     $ month    : chr  "1997-04" "1997-04" "1997-04" "1997-04" ...

``` r
# Thread-level summaries across all lists
threads <- rml_read_threads(col_select = c("list", "message_count"))
head(threads)
```

    # A data frame: 6 × 2
      list                  message_count
    * <chr>                         <int>
    1 abernethy-reliability             1
    2 abernethy-reliability             1
    3 adegenet-forum                    1
    4 adegenet-forum                    2
    5 adegenet-forum                    1
    6 adegenet-forum                    1

``` r
# Contributor statistics across all lists
contribs <- rml_read_contributors()
head(contribs)
```

    # A data frame: 6 × 7
      name     message_count list_count lists list_counts first_message last_message
    * <chr>            <int>      <int> <chr> <chr>       <chr>         <chr>       
    1 Brian R…         17995         15 r-he… r-help:117… 1998-06-04T1… 2026-09-07T…
    2 Duncan …         12600         14 r-he… r-help:733… 2000-02-16T2… 2026-10-06T…
    3 David W…         11694         16 r-he… r-help:110… 2003-03-07T1… 2026-08-23T…
    4 Peter D…         10834         12 r-he… r-help:707… 1997-04-01T0… 2026-10-11T…
    5 Bob Car…         10378          2 stan… stan-users… 2011-11-07T1… 2017-06-06T…
    6 Gabor G…         10081         19 r-he… r-help:804… 2002-01-12T1… 2026-10-03T…

### Working directly with Parquet files

To work from local copies, download the files from the [`parquet`
release](https://github.com/r-mailing-lists/data/releases/tag/parquet)
(`gh release download parquet --repo r-mailing-lists/data --dir data`)
and read them directly with
[`nanoparquet`](https://cran.r-project.org/package=nanoparquet):

``` r
library(nanoparquet)

# Single list
r_devel <- read_parquet("data/r-devel.parquet")

# All lists: every file except the two summaries
files <- setdiff(list.files("data", pattern = "\\.parquet$"),
                 c("threads.parquet", "contributors.parquet"))
all_msgs <- do.call(rbind, lapply(file.path("data", files), read_parquet,
  col_select = c("list", "from_name", "date", "subject", "month")))

# Threads and contributors
threads <- read_parquet("data/threads.parquet")
contribs <- read_parquet("data/contributors.parquet")
```

## Message volume over time

``` r
# Read all lists into one data frame
all_msgs <- do.call(rbind, lapply(rml_available(), function(l) {
  rml_read(l, col_select = c("list", "from_name", "date", "month"))
}))

monthly <- all_msgs |>
  filter(date >= as.POSIXct("1997-01-01", tz = "UTC")) |>
  count(list, month) |>
  mutate(date = as.Date(paste0(month, "-01")))

top_lists <- monthly |>
  group_by(list) |>
  summarise(total = sum(n)) |>
  slice_max(total, n = 5) |>
  pull(list)

monthly |>
  filter(list %in% top_lists) |>
  ggplot(aes(date, n, color = list)) +
  geom_line(alpha = 0.7, linewidth = 0.5) +
  geom_smooth(se = FALSE, linewidth = 1, span = 0.15) +
  scale_y_continuous(labels = label_comma()) +
  scale_x_date(date_breaks = "5 years", date_labels = "%Y") +
  labs(
    title = "Monthly message volume (top 5 lists)",
    x = NULL, y = "Messages per month", color = "List"
  )
```

<div id="fig-timeline">

<img src="demo-analysis_files/figure-commonmark/fig-timeline-1.png"
id="fig-timeline"
data-fig-alt="Monthly message volume across R mailing lists over time"
alt="Monthly message volume across R mailing lists over time" />

Figure 1

</div>

## Top posters by list

``` r
r_devel <- rml_read("r-devel",
  col_select = c("from_name", "from_email_hash", "date", "subject")) |>
  resolve_aliases()

recent <- r_devel[r_devel$date >= as.POSIXct(Sys.Date() - 365), ]
head(sort(table(recent$from_name), decreasing = TRUE), 10)
```

                       Martin Maechler                        Ivan Krylov 
                                    39                                 38 
                     Dirk Eddelbuettel iuke-tier@ey m@iii@g oii uiow@@edu 
                                    31                                 23 
                        Duncan Murdoch                        Kurt Hornik 
                                    22                                 22 
                        Peter Dalgaard                      Simon Urbanek 
                                    21                                 20 
       Suharto Anggono Suharto Anggono                         Ben Bolker 
                                    17                                 16 

## Reply network on r-devel

The `in_reply_to` field links each message to its parent, making it
straightforward to build a “who replies to whom” network.

``` r
library(igraph)
library(ggraph)

r_devel <- rml_read("r-devel",
  col_select = c("message_id", "from_name", "from_email_hash", "in_reply_to")) |>
  resolve_aliases()

# Build edges: replier -> original author
author_lookup <- r_devel |> select(message_id, from_name)

edges <- r_devel |>
  filter(!is.na(in_reply_to)) |>
  inner_join(author_lookup, by = c("in_reply_to" = "message_id"), suffix = c("_from", "_to")) |>
  filter(from_name_from != from_name_to) |>
  count(from = from_name_from, to = from_name_to, name = "replies")

# Keep only the most active participants
top_authors <- r_devel |>
  count(from_name, sort = TRUE) |>
  head(30) |>
  pull(from_name)

edges_top <- edges |>
  filter(from %in% top_authors, to %in% top_authors, replies >= 5)

g <- graph_from_data_frame(edges_top, directed = TRUE)

# Size nodes by total messages
msg_counts <- r_devel |>
  filter(from_name %in% V(g)$name) |>
  count(from_name)
V(g)$messages <- msg_counts$n[match(V(g)$name, msg_counts$from_name)]

# The layout and the label placement are both random. A fixed seed means
# the picture only changes when the data does.
set.seed(2026)
ggraph(g, layout = "fr") +
  geom_edge_link(
    aes(width = replies, alpha = replies),
    arrow = arrow(length = unit(2, "mm"), type = "closed"),
    end_cap = circle(4, "mm")
  ) +
  geom_node_point(aes(size = messages), color = "#3B6EA8") +
  geom_node_text(aes(label = name), repel = TRUE, size = 3, max.overlaps = 20) +
  scale_edge_width(range = c(0.3, 2.5), guide = "none") +
  scale_edge_alpha(range = c(0.15, 0.6), guide = "none") +
  scale_size_continuous(range = c(2, 12), labels = label_comma(), name = "Messages") +
  labs(title = "Reply network among top r-devel contributors") +
  theme_void(base_size = 13) +
  theme(plot.title.position = "plot", legend.position = "bottom")
```

<div id="fig-reply-network">

<img src="demo-analysis_files/figure-commonmark/fig-reply-network-1.png"
id="fig-reply-network"
data-fig-alt="Network graph showing reply relationships between top r-devel contributors"
alt="Network graph showing reply relationships between top r-devel contributors" />

Figure 2

</div>

## Contributors across lists

``` r
contribs <- rml_read_contributors()
contribs |>
  arrange(desc(message_count)) |>
  head(20) |>
  select(name, message_count, list_count) |>
  knitr::kable()
```

| name               | message_count | list_count |
|:-------------------|--------------:|-----------:|
| Brian Ripley       |         17995 |         15 |
| Duncan Murdoch     |         12600 |         14 |
| David Winsemius    |         11694 |         16 |
| Peter Dalgaard     |         10834 |         12 |
| Bob Carpenter      |         10378 |          2 |
| Gabor Grothendieck |         10081 |         19 |
| Uwe Ligges         |          8576 |         19 |
| Dirk Eddelbuettel  |          7984 |         23 |
| Ben Bolker         |          6270 |         11 |
| Bert Gunter        |          6050 |         10 |
| Martin Maechler    |          5901 |         26 |
| jim holtman        |          4445 |          6 |
| Ben Goodrich       |          4432 |          2 |
| Jeff Newmiller     |          4378 |          7 |
| Martin Morgan      |          4347 |          8 |
| Simon Urbanek      |          4332 |         14 |
| Roger Bivand       |          4314 |         16 |
| Jim Lemon          |          3886 |          6 |
| Thomas Lumley      |          3794 |          9 |
| Marc Schwartz      |          3770 |         10 |
