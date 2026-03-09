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

# Read only metadata columns (skips body text — much faster)
r_devel <- rml_read("r-devel",
  col_select = c("from_name", "date", "subject", "thread_id", "month"))

# Top 10 posters in the last year
recent <- r_devel[r_devel$date >= as.POSIXct(Sys.Date() - 365), ]
head(sort(table(recent$from_name), decreasing = TRUE), 10)

# Message counts per list (thread summaries — single small download)
threads <- rml_read_threads(col_select = c("list", "message_count"))
aggregate(message_count ~ list, data = threads, FUN = sum)

# Top contributors across all lists
contribs <- rml_read_contributors()
head(contribs[order(-contribs$message_count), ], 10)
```

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

For more in-depth analysis examples (message volume trends, top
contributors), see the [demo analysis](analysis/demo-analysis.md).

## Data overview

**468,228** messages across **31** mailing lists

| List                 | Messages | Authors | First Message | Last Message |
|:---------------------|:---------|:--------|:--------------|:-------------|
| r-help               | 232,933  | 26,065  | Apr 1997      | Mar 2026     |
| r-devel              | 69,483   | 6,167   | Apr 1997      | Mar 2026     |
| r-sig-mixed-models   | 27,561   | 3,096   | Jan 2007      | Mar 2026     |
| r-sig-geo            | 25,472   | 3,450   | Jul 2003      | Mar 2026     |
| bioc-devel           | 19,662   | 1,694   | Mar 2004      | Mar 2026     |
| r-help-es            | 14,652   | 987     | Mar 2009      | Feb 2026     |
| r-sig-mac            | 14,528   | 1,808   | Jan 1970      | Mar 2026     |
| r-sig-finance        | 13,551   | 2,156   | Jun 2004      | Feb 2026     |
| r-package-devel      | 11,733   | 1,147   | May 2015      | Mar 2026     |
| rcpp-devel           | 9,938    | 794     | Nov 2009      | Jan 2026     |
| r-sig-ecology        | 7,399    | 1,419   | Apr 2008      | Mar 2026     |
| r-sig-meta-analysis  | 5,028    | 540     | Jun 2017      | Mar 2026     |
| r-sig-debian         | 3,601    | 530     | Feb 2005      | Dec 2025     |
| r-sig-hpc            | 2,149    | 403     | Oct 2008      | Dec 2024     |
| r-packages           | 1,836    | 605     | Sep 2003      | Jan 2026     |
| r-sig-db             | 1,556    | 402     | Apr 2001      | Nov 2020     |
| r-sig-gui            | 1,236    | 293     | Oct 2002      | Feb 2018     |
| r-sig-fedora         | 917      | 136     | May 2008      | Sep 2025     |
| r-sig-teaching       | 847      | 236     | Oct 2006      | Jan 2026     |
| r-announce           | 718      | 123     | Apr 1997      | Feb 2026     |
| r-sig-dynamic-models | 697      | 164     | Oct 2009      | Feb 2026     |
| r-sig-epi            | 576      | 172     | Nov 2005      | Mar 2026     |
| r-sig-robust         | 524      | 159     | Nov 2005      | Dec 2025     |
| r-sig-genetics       | 474      | 61      | May 2008      | Mar 2026     |
| r-sig-jobs           | 434      | 271     | Feb 2007      | Feb 2024     |
| r-ug-ottawa          | 197      | 75      | Jan 2009      | Dec 2022     |
| r-sig-gr             | 176      | 83      | Sep 2002      | Nov 2025     |
| r-sig-windows        | 139      | 18      | Aug 2015      | Feb 2026     |
| r-sig-insurance      | 117      | 40      | Apr 2009      | Dec 2022     |
| r-sig-dcm            | 67       | 17      | Jul 2010      | Sep 2024     |
| r-sig-networks       | 27       | 21      | Jul 2008      | May 2019     |

## Reply network on r-devel

The `in_reply_to` field links each message to its parent, making it
straightforward to build a “who replies to whom” network.

<div id="fig-reply-network">

<img src="README_files/figure-commonmark/fig-reply-network-1.png"
id="fig-reply-network"
data-fig-alt="Network graph showing reply relationships between top r-devel contributors" />

Figure 1

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

| Column | Type | Description |
|----|----|----|
| `name` | string | Author display name |
| `message_count` | integer | Total messages across all lists |
| `list_count` | integer | Number of distinct lists posted to |
| `lists` | string | Comma-separated list slugs |
| `list_counts` | string | Per-list message counts (e.g. `r-devel:150,r-help:42`) |
| `first_message` | string | ISO 8601 date of earliest message |
| `last_message` | string | ISO 8601 date of most recent message |

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
