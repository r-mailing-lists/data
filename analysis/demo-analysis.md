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
      [3] "adegenet-forum"             "amelia"                    
      [5] "aroma-affymetrix"           "basta-users"               
      [7] "batman-users"               "bioc-devel"                
      [9] "bioc-ggtree"                "bioc-sig-proteomics"       
     [11] "bioc-sig-sequencing"        "biocbug"                   
     [13] "bioconductor"               "bioconductor-teaching"     
     [15] "biogeobears"                "blavaan"                   
     [17] "boostheaders-devel"         "braingraph-help"           
     [19] "breedr"                     "brms-users"                
     [21] "brumail"                    "camtrapr"                  
     [23] "canopy-phylogeny"           "cardinalmsi"               
     [25] "catlearn-package"           "cellnet-r"                 
     [27] "chnosz-help"                "cipsr-users"               
     [29] "codex2"                     "comparegroupsforum"        
     [31] "corpling-with-r"            "cran2deb-discuss"          
     [33] "cranvas"                    "ctmm-user"                 
     [35] "ctsem-mail"                 "dartr"                     
     [37] "datatable-help"             "davis-rug"                 
     [39] "debian-r"                   "deducer"                   
     [41] "dirichletreg-news"          "distance-sampling"         
     [43] "distr-distr"                "dublin-r"                  
     [45] "dynr"                       "epls-r-users"              
     [47] "eventstudies-discussion"    "expm-developers"           
     [49] "ez4r"                       "fedora-r-devel"            
     [51] "fieldimager"                "flr-list"                  
     [53] "forensim-help"              "fresh-tor4"                
     [55] "ftree-community"            "garnett-users"             
     [57] "gbm-dev"                    "genabel-announce"          
     [59] "genabel-devel"              "genomic-sem-users"         
     [61] "genoplotr-help"             "geomorph-r-package"        
     [63] "ggplot2"                    "ggplot2-dev"               
     [65] "ggvis"                      "grass-stats"               
     [67] "gsoc-dowd"                  "gsoc-porta"                
     [69] "gsoc-r"                     "gur-ugr"                   
     [71] "gwidgets-questions"         "hbayesdm-users"            
     [73] "hkrug"                      "hmecology"                 
     [75] "houston-r"                  "hyperspec-help"            
     [77] "ib-usp-r-users"             "immcantation-news"         
     [79] "inlinedocs-support"         "ipmpack-users"             
     [81] "irace-package"              "isorix"                    
     [83] "israel-r-user-group"        "jiebar"                    
     [85] "knitr"                      "konfound-it"               
     [87] "lavaan"                     "linguagem-r-ufba"          
     [89] "listpackage-discuss"        "lubridate"                 
     [91] "maaslin-users"              "maduser"                   
     [93] "mailman"                    "manipulatr"                
     [95] "mapfastr"                   "matchit"                   
     [97] "matr-forum"                 "mediation-information"     
     [99] "metacoder-discussions"      "methylkit"                 
    [101] "methylkit-discussion"       "metrology-devel"           
    [103] "mirt-package"               "mixvir"                    
    [105] "monetr-users"               "monterey-grumps"           
    [107] "mosaics-user-group"         "mplusautomation"           
    [109] "msstats"                    "mvabund-faqs"              
    [111] "mvabund-updates"            "mxmaps"                    
    [113] "nat-user"                   "netlogor"                  
    [115] "nichemapr"                  "nimble-announce"           
    [117] "nimble-users"               "nlsy-links"                
    [119] "nmf-user"                   "nmof-news"                 
    [121] "orchestra-users"            "oscr-package"              
    [123] "packrat-discuss"            "pez-users"                 
    [125] "phenopix-developers"        "phylobase-devl"            
    [127] "phylogram"                  "picante-devel"             
    [129] "piecepackr"                 "pomp-announce"             
    [131] "poppr"                      "qcawithr"                  
    [133] "qtinterfaces-devel"         "r-and-cpp"                 
    [135] "r-announce"                 "r-br"                      
    [137] "r-devel"                    "r-ecologia"                
    [139] "r-forge-testing-testing"    "r-forum"                   
    [141] "r-gregmisc-devel"           "r-help"                    
    [143] "r-help-es"                  "r-hiphop"                  
    [145] "r-inla-discussion-group"    "r-lang"                    
    [147] "r-marketing-bugs"           "r-package-devel"           
    [149] "r-package-xlsx"             "r-packages"                
    [151] "r-pkg-team"                 "r-pt"                      
    [153] "r-sig-db"                   "r-sig-dcm"                 
    [155] "r-sig-debian"               "r-sig-dynamic-models"      
    [157] "r-sig-ecology"              "r-sig-epi"                 
    [159] "r-sig-fedora"               "r-sig-finance"             
    [161] "r-sig-genetics"             "r-sig-geo"                 
    [163] "r-sig-gr"                   "r-sig-gui"                 
    [165] "r-sig-hpc"                  "r-sig-insurance"           
    [167] "r-sig-jobs"                 "r-sig-mac"                 
    [169] "r-sig-mediawiki"            "r-sig-meta-analysis"       
    [171] "r-sig-mixed-models"         "r-sig-networks"            
    [173] "r-sig-phylo"                "r-sig-qa"                  
    [175] "r-sig-robust"               "r-sig-rugs"                
    [177] "r-sig-teaching"             "r-sig-wiki"                
    [179] "r-sig-windows"              "r-soc"                     
    [181] "r-study-tokyo"              "r-swat"                    
    [183] "r-ug-ottawa"                "rangemapper-news"          
    [185] "rapache"                    "rattle-users"              
    [187] "rbigdataprogramming"        "rcicr-users"               
    [189] "rcpp-devel"                 "rcppoctave-user"           
    [191] "rcytoscape"                 "rdevtools"                 
    [193] "red-r"                      "reddyproc-users"           
    [195] "relogit"                    "remoterengine-devel"       
    [197] "renjin-dev"                 "repitools-help"            
    [199] "rgeos-devel"                "rhadoop"                   
    [201] "rhipe"                      "rho-devel"                 
    [203] "right-user"                 "riskassessment-news"       
    [205] "rkoholiki"                  "rkward"                    
    [207] "rkward-devel"               "rkward-users"              
    [209] "rmetrics-core"              "rnomads-user"              
    [211] "robustbase-authors"         "ropengov-forum"            
    [213] "roxygen-devel"              "rpackageggir"              
    [215] "rphree-general"             "rpostgresql-dev"           
    [217] "rprotobuf-yada"             "rpy-list"                  
    [219] "rqtl-announce"              "rqtl-disc"                 
    [221] "rqtl2-disc"                 "rquantlib-devel"           
    [223] "rrook"                      "rropen"                    
    [225] "rserlang-develop"           "rsiena-help"               
    [227] "rsnns"                      "rspatial-devel"            
    [229] "rugbcn"                     "rworldmap"                 
    [231] "sciviews-help"              "sciviews-news"             
    [233] "secrgroup"                  "seewave"                   
    [235] "segoptim-user-group"        "seqinr-forum"              
    [237] "sequenza-user-group"        "sevillarusers"             
    [239] "shiny-discuss"              "shinyapps-users"           
    [241] "siamcat-users"              "simmer-devel"              
    [243] "simplephenotypes"           "simsalabim-communicate"    
    [245] "sorvi-admin"                "spades-users"              
    [247] "sparkr-dev"                 "spdep-devel"               
    [249] "spocc-spabund-users"        "sprint-developer"          
    [251] "sprint-user"                "sqldf"                     
    [253] "stan-announce"              "stan-dev"                  
    [255] "stan-users"                 "statet"                    
    [257] "statforling-with-r"         "statistics-and-r-community"
    [259] "statnet-help"               "stats-rosuda-devel"        
    [261] "stitch-imputation"          "subread"                   
    [263] "synbreed-news"              "taiwanruser"               
    [265] "tessera-users"              "tidylpa"                   
    [267] "tikzdevice-bugs"            "tinn-r"                    
    [269] "titancna"                   "tlocoh-info"               
    [271] "tmb-users"                  "traminer-users"            
    [273] "travelr-announce"           "travelr-discussion"        
    [275] "trophicposition-support"    "tropical-r"                
    [277] "tsdyn"                      "uhcluster-members"         
    [279] "unmarked"                   "viennar-meetup"            
    [281] "vim-r-plugin"               "wallaceecomod"             
    [283] "whatif"                     "workflowr-announce"        
    [285] "yuima-wishlist"             "zelig"                     
    [287] "zipfr-users"               

``` r
# Read a single list (use col_select to skip the body — much faster)
r_devel <- rml_read("r-devel",
  col_select = c("from_name", "date", "subject", "thread_id", "month"))

str(r_devel)
```

    Classes 'tbl' and 'data.frame': 63740 obs. of  5 variables:
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
    1 Debian …         30665          1 r-pk… r-pkg-team… 2018-05-04T0… 2026-10-28T…
    2 Debian …         23214          1 r-pk… r-pkg-team… 2018-05-06T0… 2026-10-28T…
    3 Brian R…         17998         16 r-he… r-help:117… 1998-06-04T1… 2026-10-27T…
    4 Duncan …         12607         16 r-he… r-help:733… 2000-02-16T2… 2026-10-26T…
    5 David W…         11781         19 r-he… r-help:110… 2003-03-07T1… 2026-08-23T…
    6 Peter D…         10837         12 r-he… r-help:707… 1997-04-01T0… 2026-10-29T…

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
                                    32                                 23 
                        Duncan Murdoch                        Kurt Hornik 
                                    22                                 22 
                         Simon Urbanek                     Peter Dalgaard 
                                    20                                 19 
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

| name                 | message_count | list_count |
|:---------------------|--------------:|-----------:|
| Debian FTP Masters   |         30665 |          1 |
| Debian testing watch |         23214 |          1 |
| Brian Ripley         |         17998 |         16 |
| Duncan Murdoch       |         12607 |         16 |
| David Winsemius      |         11781 |         19 |
| Peter Dalgaard       |         10837 |         12 |
| Bob Carpenter        |         10399 |          4 |
| Gabor Grothendieck   |         10252 |         28 |
| Uwe Ligges           |          8677 |         22 |
| Dirk Eddelbuettel    |          8531 |         28 |
| Ben Bolker           |          6552 |         18 |
| Bert Gunter          |          6050 |         10 |
| Martin Maechler      |          5910 |         29 |
| Simon Urbanek        |          4955 |         18 |
| Roger Bivand         |          4792 |         20 |
| Hadley Wickham       |          4635 |         27 |
| Ben Goodrich         |          4474 |          7 |
| jim holtman          |          4469 |          8 |
| Jeff Newmiller       |          4427 |         10 |
| Martin Morgan        |          4349 |          9 |
