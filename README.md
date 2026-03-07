# R Mailing List Data


A collection of [R mailing list](https://www.r-project.org/mail.html)
archives in [Parquet](https://parquet.apache.org/) format, ready for
analysis in R, Python, or any language with Parquet support.

Data is sourced from the [R Mailing Lists archive
project](https://github.com/r-mailing-lists) and updated automatically.
You can also browse the archives at
[r-mailing-lists.thecoatlessprofessor.com](https://r-mailing-lists.thecoatlessprofessor.com).

## Quick start

Copy the helper functions below to download and read the data directly
from GitHub — no cloning required. Files are cached locally so repeated
calls are fast.

### R

``` r
# -- Helper functions (copy once) ---------------------------------------------
# Dependencies: jsonlite, nanoparquet

.rml_base_url <- "https://raw.githubusercontent.com/r-mailing-lists/data/main/data"
.rml_api_url  <- "https://api.github.com/repos/r-mailing-lists/data/contents/data/messages"
.rml_cache    <- file.path(tempdir(), "rml_cache")

.rml_ensure_cache <- function() {
  if (!dir.exists(.rml_cache)) dir.create(.rml_cache, recursive = TRUE)
  .rml_cache
}

.rml_download <- function(url, destfile) {
  .rml_ensure_cache()
  if (!file.exists(destfile)) {
    message("Downloading ", basename(destfile), "...")
    download.file(url, destfile, mode = "wb", quiet = TRUE)
  }
  destfile
}

.rml_file_index <- function() {
  cache_file <- file.path(.rml_ensure_cache(), "_index.json")
  if (!file.exists(cache_file)) {
    message("Fetching file index...")
    json <- jsonlite::fromJSON(.rml_api_url)
    jsonlite::write_json(json, cache_file)
  }
  jsonlite::fromJSON(cache_file)
}

rml_available <- function() {
  index <- .rml_file_index()
  files <- sub("\\.parquet$", "", index$name)
  sort(unique(sub("-\\d{4}-\\d{4}$", "", files)))
}

rml_read <- function(list_name, col_select = NULL) {
  index <- .rml_file_index()
  pattern <- paste0("^", list_name, "(-\\d{4}-\\d{4})?\\.parquet$")
  matches <- index$name[grepl(pattern, index$name)]
  if (length(matches) == 0) {
    stop("List '", list_name, "' not found. Run rml_available() to see options.",
         call. = FALSE)
  }
  frames <- lapply(matches, function(f) {
    dest <- file.path(.rml_ensure_cache(), f)
    .rml_download(paste0(.rml_base_url, "/messages/", f), dest)
    nanoparquet::read_parquet(dest, col_select = col_select)
  })
  if (length(frames) == 1) frames[[1]] else do.call(rbind, frames)
}

rml_read_threads <- function(col_select = NULL) {
  dest <- file.path(.rml_ensure_cache(), "threads.parquet")
  .rml_download(paste0(.rml_base_url, "/threads.parquet"), dest)
  nanoparquet::read_parquet(dest, col_select = col_select)
}

rml_read_contributors <- function(col_select = NULL) {
  dest <- file.path(.rml_ensure_cache(), "contributors.parquet")
  .rml_download(paste0(.rml_base_url, "/contributors.parquet"), dest)
  nanoparquet::read_parquet(dest, col_select = col_select)
}
```

``` r
# See available lists
rml_available()

# Top 10 r-devel posters in the last year
msgs <- rml_read("r-devel", col_select = c("from_name", "date"))
recent <- msgs[msgs$date >= as.POSIXct(Sys.Date() - 365), ]
head(sort(table(recent$from_name), decreasing = TRUE), 10)

# Message counts per list (uses thread summaries — single small download)
threads <- rml_read_threads(col_select = c("list", "message_count"))
agg <- aggregate(message_count ~ list, data = threads, FUN = sum)
agg[order(-agg$message_count), ]
```

### Python

``` python
# -- Helper functions (copy once) ---------------------------------------------
# Dependencies: polars

import json
import re
import tempfile
from pathlib import Path
from urllib.request import urlopen, urlretrieve

import polars as pl

_RAW_BASE = "https://raw.githubusercontent.com/r-mailing-lists/data/main/data"
_API_URL = "https://api.github.com/repos/r-mailing-lists/data/contents/data/messages"
_CACHE_DIR = Path(tempfile.gettempdir()) / "rml_cache"
_DECADE_RE = re.compile(r"^(.+)-(\d{4})-(\d{4})\.parquet$")


def _cached_download(url: str, filename: str) -> Path:
    _CACHE_DIR.mkdir(parents=True, exist_ok=True)
    dest = _CACHE_DIR / filename
    if not dest.exists():
        urlretrieve(url, dest)
    return dest


def _list_message_files() -> list[dict]:
    with urlopen(_API_URL) as resp:
        return json.loads(resp.read())


def rml_available() -> list[str]:
    files = _list_message_files()
    names: set[str] = set()
    for f in files:
        m = _DECADE_RE.match(f["name"])
        names.add(m.group(1) if m else f["name"].removesuffix(".parquet"))
    return sorted(names)


def rml_read(list_name: str) -> pl.DataFrame:
    files = _list_message_files()
    matched = [
        f for f in files
        if f["name"] == f"{list_name}.parquet"
        or (_DECADE_RE.match(f["name"]) and
            _DECADE_RE.match(f["name"]).group(1) == list_name)
    ]
    if not matched:
        raise ValueError(f"List '{list_name}' not found. See rml_available()")
    dfs = [
        pl.read_parquet(_cached_download(f["download_url"], f["name"]))
        for f in matched
    ]
    return pl.concat(dfs) if len(dfs) > 1 else dfs[0]


def rml_read_threads() -> pl.DataFrame:
    return pl.read_parquet(
        _cached_download(f"{_RAW_BASE}/threads.parquet", "threads.parquet")
    )


def rml_read_contributors() -> pl.DataFrame:
    return pl.read_parquet(
        _cached_download(f"{_RAW_BASE}/contributors.parquet", "contributors.parquet")
    )
```

``` python
# See available lists
rml_available()

# Top 10 r-devel posters in 2025
df = rml_read("r-devel")
(df.filter(pl.col("date").dt.year() == 2025)
   .group_by("from_name")
   .len()
   .sort("len", descending=True)
   .head(10))

# Message counts per list (uses thread summaries — single small download)
(rml_read_threads()
   .group_by("list")
   .agg(pl.col("message_count").sum())
   .sort("message_count", descending=True))
```

### Working with a local clone

If you prefer to work with local files, clone the repo and read the
parquet files directly:

``` r
# R
library(nanoparquet)
r_devel <- read_parquet("data/messages/r-devel.parquet")

# Read all lists into one data frame
files <- list.files("data/messages", pattern = "\\.parquet$", full.names = TRUE)
all_msgs <- do.call(rbind, lapply(files, read_parquet))
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
