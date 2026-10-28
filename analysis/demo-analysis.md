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

      [1] "abernethy-reliability"      "acs-r"                     
      [3] "adegenet-forum"             "aroma-affymetrix"          
      [5] "basta-users"                "batman-users"              
      [7] "bioc-devel"                 "bioc-ggtree"               
      [9] "bioc-sig-proteomics"        "bioc-sig-sequencing"       
     [11] "biocbug"                    "bioconductor"              
     [13] "bioconductor-teaching"      "biogeobears"               
     [15] "blavaan"                    "boostheaders-devel"        
     [17] "braingraph-help"            "breedr"                    
     [19] "brms-users"                 "brumail"                   
     [21] "camtrapr"                   "canopy-phylogeny"          
     [23] "cardinalmsi"                "catlearn-package"          
     [25] "cellnet-r"                  "chnosz-help"               
     [27] "cipsr-users"                "codex2"                    
     [29] "comparegroupsforum"         "corpling-with-r"           
     [31] "cran2deb-discuss"           "cranvas"                   
     [33] "ctmm-user"                  "ctsem-mail"                
     [35] "dartr"                      "datatable-help"            
     [37] "davis-rug"                  "deducer"                   
     [39] "dirichletreg-news"          "distance-sampling"         
     [41] "distr-distr"                "dublin-r"                  
     [43] "dynr"                       "epls-r-users"              
     [45] "eventstudies-discussion"    "expm-developers"           
     [47] "ez4r"                       "fieldimager"               
     [49] "flr-list"                   "forensim-help"             
     [51] "fresh-tor4"                 "ftree-community"           
     [53] "garnett-users"              "gbm-dev"                   
     [55] "genabel-announce"           "genabel-devel"             
     [57] "genomic-sem-users"          "genoplotr-help"            
     [59] "geomorph-r-package"         "ggplot2"                   
     [61] "ggplot2-dev"                "ggvis"                     
     [63] "gsoc-dowd"                  "gsoc-porta"                
     [65] "gsoc-r"                     "gur-ugr"                   
     [67] "gwidgets-questions"         "hbayesdm-users"            
     [69] "hkrug"                      "hmecology"                 
     [71] "houston-r"                  "hyperspec-help"            
     [73] "ib-usp-r-users"             "immcantation-news"         
     [75] "inlinedocs-support"         "ipmpack-users"             
     [77] "irace-package"              "isorix"                    
     [79] "israel-r-user-group"        "jiebar"                    
     [81] "knitr"                      "konfound-it"               
     [83] "lavaan"                     "linguagem-r-ufba"          
     [85] "listpackage-discuss"        "lubridate"                 
     [87] "maaslin-users"              "maduser"                   
     [89] "mailman"                    "manipulatr"                
     [91] "mapfastr"                   "matchit"                   
     [93] "matr-forum"                 "mediation-information"     
     [95] "metacoder-discussions"      "methylkit"                 
     [97] "methylkit-discussion"       "metrology-devel"           
     [99] "mirt-package"               "mixvir"                    
    [101] "monetr-users"               "monterey-grumps"           
    [103] "mosaics-user-group"         "mplusautomation"           
    [105] "msstats"                    "mvabund-faqs"              
    [107] "mvabund-updates"            "mxmaps"                    
    [109] "nat-user"                   "netlogor"                  
    [111] "nichemapr"                  "nimble-announce"           
    [113] "nimble-users"               "nlsy-links"                
    [115] "nmf-user"                   "nmof-news"                 
    [117] "orchestra-users"            "oscr-package"              
    [119] "packrat-discuss"            "pez-users"                 
    [121] "phenopix-developers"        "phylobase-devl"            
    [123] "phylogram"                  "picante-devel"             
    [125] "piecepackr"                 "pomp-announce"             
    [127] "poppr"                      "qcawithr"                  
    [129] "qtinterfaces-devel"         "r-and-cpp"                 
    [131] "r-announce"                 "r-br"                      
    [133] "r-devel"                    "r-ecologia"                
    [135] "r-forge-testing-testing"    "r-forum"                   
    [137] "r-gregmisc-devel"           "r-help"                    
    [139] "r-help-es"                  "r-hiphop"                  
    [141] "r-inla-discussion-group"    "r-lang"                    
    [143] "r-marketing-bugs"           "r-package-devel"           
    [145] "r-package-xlsx"             "r-packages"                
    [147] "r-sig-db"                   "r-sig-dcm"                 
    [149] "r-sig-debian"               "r-sig-dynamic-models"      
    [151] "r-sig-ecology"              "r-sig-epi"                 
    [153] "r-sig-fedora"               "r-sig-finance"             
    [155] "r-sig-genetics"             "r-sig-geo"                 
    [157] "r-sig-gr"                   "r-sig-gui"                 
    [159] "r-sig-hpc"                  "r-sig-insurance"           
    [161] "r-sig-jobs"                 "r-sig-mac"                 
    [163] "r-sig-mediawiki"            "r-sig-meta-analysis"       
    [165] "r-sig-mixed-models"         "r-sig-networks"            
    [167] "r-sig-phylo"                "r-sig-qa"                  
    [169] "r-sig-robust"               "r-sig-rugs"                
    [171] "r-sig-teaching"             "r-sig-wiki"                
    [173] "r-sig-windows"              "r-soc"                     
    [175] "r-study-tokyo"              "r-swat"                    
    [177] "r-ug-ottawa"                "rangemapper-news"          
    [179] "rapache"                    "rattle-users"              
    [181] "rbigdataprogramming"        "rcicr-users"               
    [183] "rcpp-devel"                 "rcppoctave-user"           
    [185] "rcytoscape"                 "rdevtools"                 
    [187] "red-r"                      "reddyproc-users"           
    [189] "remoterengine-devel"        "repitools-help"            
    [191] "rgeos-devel"                "rhadoop"                   
    [193] "rhipe"                      "right-user"                
    [195] "riskassessment-news"        "rkoholiki"                 
    [197] "rkward"                     "rkward-devel"              
    [199] "rkward-users"               "rmetrics-core"             
    [201] "rnomads-user"               "robustbase-authors"        
    [203] "ropengov-forum"             "roxygen-devel"             
    [205] "rpackageggir"               "rphree-general"            
    [207] "rpostgresql-dev"            "rprotobuf-yada"            
    [209] "rpy-list"                   "rqtl-announce"             
    [211] "rqtl-disc"                  "rqtl2-disc"                
    [213] "rquantlib-devel"            "rrook"                     
    [215] "rropen"                     "rserlang-develop"          
    [217] "rsiena-help"                "rsnns"                     
    [219] "rspatial-devel"             "rugbcn"                    
    [221] "rworldmap"                  "sciviews-help"             
    [223] "sciviews-news"              "secrgroup"                 
    [225] "seewave"                    "segoptim-user-group"       
    [227] "seqinr-forum"               "sequenza-user-group"       
    [229] "sevillarusers"              "shiny-discuss"             
    [231] "shinyapps-users"            "siamcat-users"             
    [233] "simmer-devel"               "simplephenotypes"          
    [235] "simsalabim-communicate"     "sorvi-admin"               
    [237] "spades-users"               "sparkr-dev"                
    [239] "spdep-devel"                "spocc-spabund-users"       
    [241] "sprint-developer"           "sprint-user"               
    [243] "sqldf"                      "stan-dev"                  
    [245] "stan-users"                 "statforling-with-r"        
    [247] "statistics-and-r-community" "stats-rosuda-devel"        
    [249] "stitch-imputation"          "subread"                   
    [251] "synbreed-news"              "taiwanruser"               
    [253] "tessera-users"              "tidylpa"                   
    [255] "tikzdevice-bugs"            "tinn-r"                    
    [257] "titancna"                   "tlocoh-info"               
    [259] "tmb-users"                  "traminer-users"            
    [261] "travelr-announce"           "travelr-discussion"        
    [263] "trophicposition-support"    "tropical-r"                
    [265] "tsdyn"                      "uhcluster-members"         
    [267] "unmarked"                   "viennar-meetup"            
    [269] "vim-r-plugin"               "wallaceecomod"             
    [271] "whatif"                     "workflowr-announce"        
    [273] "yuima-wishlist"             "zelig"                     
    [275] "zipfr-users"               

``` r
# Read a single list (use col_select to skip the body — much faster)
r_devel <- rml_read("r-devel",
  col_select = c("from_name", "date", "subject", "thread_id", "month"))

str(r_devel)
```

    Classes 'tbl' and 'data.frame': 63737 obs. of  5 variables:
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
    3 acs-r                             1
    4 acs-r                             1
    5 acs-r                             2
    6 acs-r                             2

``` r
# Contributor statistics across all lists
contribs <- rml_read_contributors()
head(contribs)
```

    # A data frame: 6 × 7
      name     message_count list_count lists list_counts first_message last_message
    * <chr>            <int>      <int> <chr> <chr>       <chr>         <chr>       
    1 Brian R…         17996         15 r-he… r-help:117… 1998-06-04T1… 2026-10-27T…
    2 Duncan …         12607         16 r-he… r-help:733… 2000-02-16T2… 2026-10-26T…
    3 David W…         11781         19 r-he… r-help:110… 2003-03-07T1… 2026-08-23T…
    4 Peter D…         10835         12 r-he… r-help:707… 1997-04-01T0… 2026-10-27T…
    5 Bob Car…         10387          3 stan… stan-users… 2011-11-07T1… 2017-06-06T…
    6 Gabor G…         10252         28 r-he… r-help:804… 2002-01-12T1… 2026-10-03T…

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

                           Ivan Krylov                    Martin Maechler 
                                    37                                 37 
                     Dirk Eddelbuettel iuke-tier@ey m@iii@g oii uiow@@edu 
                                    31                                 23 
                        Duncan Murdoch                        Kurt Hornik 
                                    22                                 22 
                         Simon Urbanek                     Peter Dalgaard 
                                    20                                 18 
                            Ben Bolker    Suharto Anggono Suharto Anggono 
                                    16                                 16 

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
| Brian Ripley       |         17996 |         15 |
| Duncan Murdoch     |         12607 |         16 |
| David Winsemius    |         11781 |         19 |
| Peter Dalgaard     |         10835 |         12 |
| Bob Carpenter      |         10387 |          3 |
| Gabor Grothendieck |         10252 |         28 |
| Uwe Ligges         |          8677 |         22 |
| Dirk Eddelbuettel  |          8076 |         26 |
| Ben Bolker         |          6552 |         18 |
| Bert Gunter        |          6050 |         10 |
| Martin Maechler    |          5902 |         27 |
| Simon Urbanek      |          4950 |         17 |
| Hadley Wickham     |          4634 |         26 |
| jim holtman        |          4469 |          8 |
| Ben Goodrich       |          4458 |          6 |
| Jeff Newmiller     |          4427 |         10 |
| Martin Morgan      |          4347 |          8 |
| Roger Bivand       |          4326 |         17 |
| Henrik Bengtsson   |          4221 |         17 |
| Jim Lemon          |          3886 |          6 |
