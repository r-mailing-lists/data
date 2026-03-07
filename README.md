# R Mailing List Data


A collection of [R mailing list](https://www.r-project.org/mail.html)
archives in [Parquet](https://parquet.apache.org/) format, ready for
analysis in R, Python, or any language with Parquet support.

Data is sourced from the [R Mailing Lists archive
project](https://github.com/r-mailing-lists) and updated automatically.
You can also browse the archives at
[r-mailing-lists.thecoatlessprofessor.com](https://r-mailing-lists.thecoatlessprofessor.com).

## Quick start

### R

Requires [`jsonlite`](https://cran.r-project.org/package=jsonlite) and
[`nanoparquet`](https://cran.r-project.org/package=nanoparquet). Source
the helper script directly from GitHub:

``` r
source("https://raw.githubusercontent.com/r-mailing-lists/data/main/scripts/rml.R")
```

``` r
# See available lists
rml_available()
```

     [1] "bioc-devel"           "r-announce"           "r-devel"             
     [4] "r-help"               "r-help-es"            "r-package-devel"     
     [7] "r-packages"           "r-sig-db"             "r-sig-dcm"           
    [10] "r-sig-debian"         "r-sig-dynamic-models" "r-sig-ecology"       
    [13] "r-sig-epi"            "r-sig-fedora"         "r-sig-finance"       
    [16] "r-sig-genetics"       "r-sig-geo"            "r-sig-gr"            
    [19] "r-sig-gui"            "r-sig-hpc"            "r-sig-insurance"     
    [22] "r-sig-jobs"           "r-sig-mac"            "r-sig-meta-analysis" 
    [25] "r-sig-mixed-models"   "r-sig-networks"       "r-sig-robust"        
    [28] "r-sig-teaching"       "r-sig-windows"        "r-ug-ottawa"         
    [31] "rcpp-devel"          

``` r
# Read only metadata columns (skips body text — much faster)
r_devel <- rml_read("r-devel",
  col_select = c("from_name", "date", "subject", "thread_id", "month"))
cat(nrow(r_devel), "messages x", ncol(r_devel), "columns\n")
```

    63399 messages x 5 columns

``` r
head(r_devel[, c("date", "from_name", "subject")], 5)
```

    # A data frame: 5 × 3
      date                from_name       subject                                   
    * <dttm>              <chr>           <chr>                                     
    1 1997-04-01 10:28:56 Martin Maechler "R-alpha: Re: R-Prerelease  ---- Mailing …
    2 1997-04-01 10:35:43 Kurt Hornik     "R-alpha: Re: R-Prerelease  ---- Mailing …
    3 1997-04-03 09:50:54 Martin Maechler "R-alpha: Re: Pretest Version + Notes ---…
    4 1997-04-03 14:45:55 Martin Maechler "R-alpha: R0.50-pre6:  \"stack imbalance …
    5 1997-04-06 21:56:59 Ross Ihaka      "R-alpha: Some name changes"              

``` r
# Top 10 posters in the last year
recent <- r_devel[r_devel$date >= as.POSIXct(Sys.Date() - 365), ]
head(sort(table(recent$from_name), decreasing = TRUE), 10)
```


                     Duncan Murdoch                 Martin Maechler 
                                 38                              33 
                  Dirk Eddelbuettel                     Ivan Krylov 
                                 29                              28 
                        Kurt Hornik                    Mikael Jagan 
                                 19                              18 
                    Michael Chirico                      Ben Bolker 
                                 17                              16 
                   Henrik Bengtsson Suharto Anggono Suharto Anggono 
                                 15                              15 

``` r
# Message counts per list (thread summaries — single small download)
threads <- rml_read_threads(col_select = c("list", "message_count"))
agg <- aggregate(message_count ~ list, data = threads, FUN = sum)
head(agg[order(-agg$message_count), ], 10)
```

                     list message_count
    4              r-help        398464
    3             r-devel         63399
    17          r-sig-geo         29558
    1          bioc-devel         21300
    25 r-sig-mixed-models         20627
    5           r-help-es         15379
    15      r-sig-finance         15274
    23          r-sig-mac         15070
    6     r-package-devel         12120
    31         rcpp-devel         10988

``` r
# Top contributors across all lists
contribs <- rml_read_contributors()
head(contribs[order(-contribs$message_count), c("name", "message_count", "list_count")], 10)
```

    # A data frame: 10 × 3
       name               message_count list_count
     * <chr>                      <int>      <int>
     1 Prof Brian Ripley           8966          9
     2 Duncan Murdoch              8774         11
     3 David Winsemius             6376          9
     4 Gabor Grothendieck          5900         13
     5 Ben Bolker                  5543          8
     6 Dirk Eddelbuettel           5488         14
     7 Uwe Ligges                  5114         11
     8 Martin Maechler             4955         18
     9 Peter Dalgaard BSA          4222          4
    10 Bert Gunter                 3788          9

### Python

Requires [`polars`](https://pola.rs/). Download the helper script:

``` bash
curl -O https://raw.githubusercontent.com/r-mailing-lists/data/main/scripts/rml.py
```

``` python
from rml import rml_available, rml_read, rml_read_threads, rml_read_contributors
import polars as pl

# See available lists
rml_available()

# Read a single list (downloads and caches parquet files automatically)
r_devel = rml_read("r-devel")

# Top 10 posters in 2025
(r_devel
   .filter(pl.col("date").dt.year() == 2025)
   .group_by("from_name")
   .len()
   .sort("len", descending=True)
   .head(10))

# Message counts per list (thread summaries — single small download)
(rml_read_threads()
   .group_by("list")
   .agg(pl.col("message_count").sum())
   .sort("message_count", descending=True))

# Top contributors across all lists
(rml_read_contributors()
   .sort("message_count", descending=True)
   .head(20))
```

### Working with a local clone

If you prefer working with local files, clone the repo and read parquet
files directly:

``` r
# R
library(nanoparquet)
r_devel <- read_parquet("data/messages/r-devel.parquet")
```

``` python
# Python
import polars as pl
r_devel = pl.read_parquet("data/messages/r-devel.parquet")
all_msgs = pl.read_parquet("data/messages/*.parquet")
```

## Data overview

**631,099** messages across **31** mailing lists

| List                 | Messages | Authors | First Message | Last Message |
|:---------------------|:---------|:--------|:--------------|:-------------|
| r-help               | 398,464  | 39,318  | Apr 1997      | Feb 2026     |
| r-devel              | 63,399   | 6,758   | Apr 1997      | Mar 2026     |
| r-sig-geo            | 29,558   | 3,737   | Jul 2003      | Mar 2026     |
| bioc-devel           | 21,300   | 1,756   | Mar 2004      | Mar 2026     |
| r-sig-mixed-models   | 20,627   | 3,242   | Jan 2007      | Mar 2026     |
| r-help-es            | 15,379   | 1,021   | Mar 2009      | Feb 2026     |
| r-sig-finance        | 15,274   | 2,285   | Jun 2004      | Feb 2026     |
| r-sig-mac            | 15,070   | 1,870   | Jan 1970      | Mar 2026     |
| r-package-devel      | 12,120   | 1,170   | May 2015      | Mar 2026     |
| rcpp-devel           | 10,988   | 828     | Nov 2009      | Jan 2026     |
| r-sig-ecology        | 7,404    | 1,419   | Apr 2008      | Mar 2026     |
| r-sig-meta-analysis  | 5,628    | 564     | Jun 2017      | Mar 2026     |
| r-sig-debian         | 3,656    | 535     | Feb 2005      | Dec 2025     |
| r-sig-hpc            | 2,152    | 404     | Oct 2008      | Dec 2024     |
| r-sig-db             | 1,559    | 403     | Apr 2001      | Nov 2020     |
| r-packages           | 1,339    | 606     | Sep 2003      | Jan 2026     |
| r-sig-gui            | 1,236    | 293     | Oct 2002      | Feb 2018     |
| r-sig-fedora         | 919      | 136     | May 2008      | Sep 2025     |
| r-sig-teaching       | 885      | 242     | Oct 2006      | Jan 2026     |
| r-announce           | 703      | 123     | Apr 1997      | Feb 2026     |
| r-sig-dynamic-models | 696      | 164     | Oct 2009      | Feb 2026     |
| r-sig-epi            | 575      | 172     | Nov 2005      | Mar 2026     |
| r-sig-robust         | 523      | 159     | Nov 2005      | Dec 2025     |
| r-sig-genetics       | 481      | 63      | May 2008      | Mar 2026     |
| r-sig-jobs           | 441      | 271     | Feb 2007      | Feb 2024     |
| r-ug-ottawa          | 197      | 75      | Jan 2009      | Dec 2022     |
| r-sig-gr             | 176      | 83      | Sep 2002      | Nov 2025     |
| r-sig-windows        | 139      | 18      | Aug 2015      | Feb 2026     |
| r-sig-insurance      | 117      | 40      | Apr 2009      | Dec 2022     |
| r-sig-dcm            | 67       | 17      | Jul 2010      | Sep 2024     |
| r-sig-networks       | 27       | 21      | Jul 2008      | May 2019     |

<div id="fig-timeline">

<img src="README_files/figure-commonmark/fig-timeline-1.png"
id="fig-timeline"
data-fig-alt="Monthly message volume across R mailing lists over time" />

Figure 1

</div>

## Example: Reply network on r-devel

The `in_reply_to` field links each message to its parent, making it
straightforward to build a “who replies to whom” network.

<div id="fig-reply-network">

<img src="README_files/figure-commonmark/fig-reply-network-1.png"
id="fig-reply-network"
data-fig-alt="Network graph showing reply relationships between top r-devel contributors" />

Figure 2

</div>

## Data dictionary

### `data/messages/<list>.parquet`

One Parquet file per mailing list. All files share the same schema.

| Column | Type | Description |
|----|----|----|
| `list` | string | Mailing list name (e.g., `r-devel`) |
| `id` | string | Unique message ID (`msg-<hash>`) |
| `message_id` | string | Original RFC 2822 Message-ID header |
| `from_name` | string | Author display name |
| `from_email_hash` | string | SHA-256 hash of author email (privacy-preserving) |
| `date` | timestamp | Message date (UTC) |
| `subject` | string | Subject line with `Re:`/`Fwd:` prefixes stripped |
| `in_reply_to` | string | ID of the parent message (null for thread starters) |
| `body` | string | Full message body text |
| `body_snippet` | string | First 200 characters of the body |
| `thread_id` | string | Thread grouping ID (`thread-<hash>`) |
| `thread_depth` | integer | Depth in thread tree (0 = root message) |
| `month` | string | `YYYY-MM` for temporal bucketing |

### `data/threads.parquet`

Thread-level summaries for all lists.

| Column            | Type      | Description                       |
|-------------------|-----------|-----------------------------------|
| `list`            | string    | Mailing list name                 |
| `id`              | string    | Thread ID (`thread-<hash>`)       |
| `subject`         | string    | Thread subject                    |
| `message_count`   | integer   | Number of messages in thread      |
| `started`         | timestamp | Date of first message             |
| `last_reply`      | timestamp | Date of most recent reply         |
| `root_message_id` | string    | ID of the thread-starting message |

### `data/contributors.parquet`

Aggregated contributor statistics across all lists.

| Column          | Type    | Description                        |
|-----------------|---------|------------------------------------|
| `name`          | string  | Author display name                |
| `message_count` | integer | Total messages across all lists    |
| `list_count`    | integer | Number of distinct lists posted to |
| `lists`         | string  | Comma-separated list names         |

## Privacy

Email addresses are not included in this dataset. Author identity is
represented by display name and a SHA-256 hash of the email address,
which allows grouping messages by author without exposing contact
information. The original emails are publicly archived on the source
mailing list servers.

## License

The mailing list content is publicly archived by the [R
Project](https://www.r-project.org/mail.html) via [ETH
Zurich](https://stat.ethz.ch/pipermail/) and
[R-Forge](https://lists.r-forge.r-project.org/pipermail/). This dataset
reformats that public content for easier analysis. The tooling in this
repository is licensed under the [MIT License](LICENSE).
