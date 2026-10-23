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

### Working with local files

The Parquet files are published as assets of the [`parquet`
release](https://github.com/r-mailing-lists/data/releases/tag/parquet),
not committed to the repository. To keep local copies, download them
with the [GitHub CLI](https://cli.github.com/):

``` bash
gh release download parquet --repo r-mailing-lists/data --dir data
```

and read them directly:

``` r
# R
library(nanoparquet)
r_devel <- read_parquet("data/r-devel.parquet")
```

``` python
# Python
import polars as pl
r_devel = pl.read_parquet("data/r-devel.parquet")
```

Any single file is also available at
`https://github.com/r-mailing-lists/data/releases/download/parquet/<file>`.

For more in-depth analysis examples (message volume trends, top
contributors), see the [demo analysis](analysis/demo-analysis.md).

## Data overview

**960,999** messages across **199** mailing lists

| List                    | Messages | Authors | First Message | Last Message |
|:------------------------|:---------|:--------|:--------------|:-------------|
| r-help                  | 398,802  | 37,119  | Apr 1997      | Oct 2026     |
| r-devel                 | 63,736   | 5,864   | Apr 1997      | Oct 2026     |
| bioconductor            | 61,316   | 7,388   | Nov 2001      | Sep 2014     |
| r-sig-geo               | 29,588   | 3,501   | Jul 2003      | Oct 2026     |
| stan-users              | 26,736   | 1,452   | Aug 2012      | Jun 2017     |
| lavaan                  | 23,445   | 3,308   | Sep 2012      | Oct 2026     |
| shiny-discuss           | 23,336   | 3,840   | Nov 2012      | Jan 2024     |
| bioc-devel              | 21,554   | 1,709   | Mar 2004      | Oct 2026     |
| ggplot2                 | 21,320   | 3,103   | Nov 2008      | Jan 2025     |
| r-sig-mixed-models      | 20,670   | 3,114   | Jan 2007      | Oct 2026     |
| r-br                    | 20,633   | 1,057   | Mar 2011      | Oct 2025     |
| r-inla-discussion-group | 16,090   | 1,765   | Feb 2011      | Oct 2026     |
| r-help-es               | 15,408   | 899     | Mar 2009      | Sep 2026     |
| r-sig-finance           | 15,315   | 2,164   | Jun 2004      | Sep 2026     |
| r-sig-mac               | 15,117   | 1,726   | Jan 1970      | Oct 2026     |
| stan-dev                | 14,007   | 75      | Nov 2011      | Dec 2016     |
| r-package-devel         | 12,402   | 1,130   | May 2015      | Oct 2026     |
| rcpp-devel              | 11,011   | 801     | Nov 2009      | May 2026     |
| unmarked                | 7,728    | 1,096   | Feb 2010      | Sep 2026     |
| r-sig-ecology           | 7,610    | 1,329   | Apr 2008      | Oct 2026     |
| distance-sampling       | 6,855    | 1,316   | Sep 1998      | Oct 2026     |
| r-sig-phylo             | 6,509    | 1,035   | Feb 2008      | Oct 2026     |
| shinyapps-users         | 6,426    | 1,551   | Nov 2013      | Sep 2018     |
| nimble-users            | 5,843    | 630     | Jul 2014      | Oct 2026     |
| r-sig-meta-analysis     | 5,648    | 551     | Jun 2017      | Oct 2026     |
| mirt-package            | 5,602    | 716     | Apr 2013      | Apr 2026     |
| rqtl-disc               | 4,744    | 654     | Sep 2004      | Oct 2026     |
| r-sig-debian            | 3,678    | 504     | Feb 2005      | Sep 2026     |
| davis-rug               | 3,651    | 379     | Sep 2012      | May 2026     |
| geomorph-r-package      | 3,634    | 427     | Jul 2016      | Sep 2026     |
| rpackageggir            | 3,417    | 545     | Nov 2014      | Jul 2025     |
| datatable-help          | 3,415    | 441     | Mar 2010      | Apr 2018     |
| israel-r-user-group     | 3,141    | 209     | Aug 2009      | Mar 2021     |
| ctmm-user               | 2,995    | 441     | Feb 2017      | Oct 2026     |
| manipulatr              | 2,804    | 538     | Mar 2009      | Dec 2023     |
| secrgroup               | 2,548    | 356     | Nov 2013      | Aug 2026     |
| dartr                   | 2,425    | 289     | Nov 2018      | Sep 2026     |
| bioc-sig-sequencing     | 2,295    | 227     | Feb 2008      | Sep 2011     |
| rhadoop                 | 2,167    | 385     | Feb 2012      | May 2016     |
| r-sig-hpc               | 2,152    | 383     | Oct 2008      | Dec 2024     |
| adegenet-forum          | 1,994    | 454     | Feb 2008      | Feb 2025     |
| knitr                   | 1,964    | 344     | Jan 2012      | Oct 2023     |
| hmecology               | 1,963    | 366     | Dec 2012      | Oct 2026     |
| biogeobears             | 1,636    | 273     | Oct 2013      | Oct 2026     |
| camtrapr                | 1,626    | 315     | Dec 2016      | Oct 2026     |
| bioc-ggtree             | 1,586    | 405     | Mar 2016      | Nov 2025     |
| r-sig-db                | 1,559    | 391     | Apr 2001      | Nov 2020     |
| deducer                 | 1,538    | 319     | Aug 2009      | May 2022     |
| blavaan                 | 1,472    | 175     | Feb 2016      | Apr 2026     |
| rhipe                   | 1,461    | 177     | Nov 2009      | May 2016     |
| simmer-devel            | 1,399    | 129     | Apr 2016      | Sep 2024     |
| genabel-devel           | 1,350    | 65      | Nov 2010      | Dec 2018     |
| r-packages              | 1,347    | 570     | Sep 2003      | Oct 2026     |
| rattle-users            | 1,339    | 311     | Aug 2006      | Aug 2024     |
| tmb-users               | 1,319    | 194     | Jun 2016      | Sep 2026     |
| r-sig-gui               | 1,236    | 264     | Oct 2002      | Feb 2018     |
| gsoc-r                  | 1,181    | 264     | Mar 2010      | Jul 2026     |
| rqtl2-disc              | 1,180    | 159     | Sep 2017      | Sep 2026     |
| corpling-with-r         | 1,170    | 160     | Nov 2006      | Jul 2024     |
| seewave                 | 1,081    | 271     | Apr 2010      | Aug 2025     |
| brms-users              | 1,042    | 144     | Jan 2017      | Jun 2018     |
| poppr                   | 1,018    | 220     | Mar 2014      | Apr 2025     |
| r-sig-fedora            | 931      | 129     | May 2008      | Apr 2026     |
| braingraph-help         | 892      | 91      | Dec 2015      | May 2025     |
| r-sig-teaching          | 886      | 224     | Oct 2006      | Sep 2026     |
| wallaceecomod           | 839      | 188     | Jan 2017      | Sep 2026     |
| rmetrics-core           | 741      | 222     | Sep 2007      | Nov 2017     |
| phylobase-devl          | 724      | 28      | Feb 2008      | Apr 2014     |
| r-announce              | 714      | 112     | Apr 1997      | Sep 2026     |
| r-sig-dynamic-models    | 697      | 160     | Oct 2009      | Mar 2026     |
| ggvis                   | 693      | 182     | Aug 2013      | Jun 2024     |
| sequenza-user-group     | 691      | 159     | Aug 2014      | Oct 2026     |
| r-sig-epi               | 674      | 166     | Nov 2005      | Oct 2026     |
| nat-user                | 639      | 108     | Apr 2015      | Jan 2026     |
| tsdyn                   | 634      | 90      | Dec 2006      | Feb 2024     |
| irace-package           | 594      | 114     | Jul 2016      | Sep 2025     |
| r-sig-genetics          | 589      | 61      | May 2008      | Oct 2026     |
| rdevtools               | 561      | 130     | Mar 2012      | Jan 2023     |
| oscr-package            | 551      | 86      | Feb 2016      | Oct 2026     |
| flr-list                | 539      | 49      | Oct 2011      | Apr 2019     |
| ez4r                    | 533      | 125     | Feb 2011      | Feb 2023     |
| r-sig-robust            | 525      | 152     | Nov 2005      | Jul 2026     |
| mplusautomation         | 514      | 172     | Dec 2012      | Aug 2026     |
| roxygen-devel           | 469      | 59      | May 2008      | Aug 2015     |
| qcawithr                | 449      | 69      | Mar 2020      | Aug 2026     |
| r-sig-jobs              | 442      | 267     | Feb 2007      | Mar 2026     |
| r-sig-wiki              | 398      | 32      | Jan 2006      | Aug 2010     |
| spocc-spabund-users     | 387      | 74      | Jul 2024      | Oct 2026     |
| traminer-users          | 383      | 96      | May 2010      | Jul 2023     |
| rsiena-help             | 354      | 67      | Feb 2010      | May 2019     |
| qtinterfaces-devel      | 349      | 22      | Sep 2009      | May 2014     |
| vim-r-plugin            | 318      | 62      | Dec 2013      | Mar 2024     |
| sorvi-admin             | 300      | 28      | Nov 2011      | Nov 2021     |
| tidylpa                 | 299      | 124     | Apr 2018      | Aug 2025     |
| seqinr-forum            | 296      | 58      | Jul 2008      | Mar 2023     |
| gsoc-porta              | 273      | 8       | Jun 2013      | Aug 2014     |
| tikzdevice-bugs         | 268      | 48      | Jul 2009      | Nov 2013     |
| rprotobuf-yada          | 237      | 13      | Oct 2009      | Oct 2016     |
| spades-users            | 237      | 25      | Mar 2016      | Nov 2020     |
| basta-users             | 199      | 49      | Nov 2011      | Nov 2025     |
| rnomads-user            | 198      | 40      | Sep 2014      | Apr 2023     |
| r-ug-ottawa             | 197      | 66      | Jan 2009      | Dec 2022     |
| sqldf                   | 193      | 70      | Feb 2013      | Feb 2021     |
| r-sig-gr                | 177      | 79      | Sep 2002      | Sep 2026     |
| canopy-phylogeny        | 164      | 43      | Sep 2016      | Sep 2023     |
| isorix                  | 163      | 31      | Apr 2021      | Apr 2026     |
| mediation-information   | 158      | 31      | May 2011      | Jan 2021     |
| metacoder-discussions   | 154      | 44      | Feb 2017      | Apr 2026     |
| rworldmap               | 149      | 57      | Jul 2013      | Dec 2023     |
| r-sig-windows           | 146      | 21      | Aug 2015      | Sep 2026     |
| inlinedocs-support      | 137      | 60      | Nov 2009      | Jun 2014     |
| rcppoctave-user         | 133      | 8       | Oct 2013      | Nov 2016     |
| r-sig-insurance         | 117      | 39      | Apr 2009      | Dec 2022     |
| nmof-news               | 115      | 1       | Jun 2011      | Oct 2025     |
| r-package-xlsx          | 107      | 49      | Jan 2012      | Nov 2021     |
| rspatial-devel          | 107      | 10      | Apr 2011      | Dec 2015     |
| tlocoh-info             | 105      | 34      | Sep 2013      | May 2021     |
| trophicposition-support | 104      | 54      | May 2017      | Aug 2026     |
| rqtl-announce           | 96       | 2       | Sep 2004      | Jul 2026     |
| rquantlib-devel         | 75       | 15      | Feb 2010      | Feb 2017     |
| ipmpack-users           | 69       | 35      | Aug 2012      | May 2019     |
| genoplotr-help          | 67       | 12      | Jun 2010      | Nov 2020     |
| r-sig-dcm               | 67       | 17      | Jul 2010      | Sep 2024     |
| r-and-cpp               | 65       | 16      | Apr 2014      | May 2024     |
| nmf-user                | 61       | 17      | Nov 2011      | Jul 2020     |
| reddyproc-users         | 51       | 14      | Jul 2013      | Nov 2019     |
| rcicr-users             | 48       | 12      | Oct 2014      | Mar 2019     |
| ropengov-forum          | 47       | 10      | Dec 2013      | Mar 2019     |
| rsnns                   | 44       | 23      | Dec 2016      | Jun 2025     |
| boostheaders-devel      | 37       | 7       | Feb 2013      | Jan 2015     |
| dynr                    | 37       | 14      | Feb 2019      | Nov 2025     |
| remoterengine-devel     | 35       | 2       | Aug 2009      | Oct 2009     |
| monetr-users            | 34       | 6       | Jul 2013      | Nov 2015     |
| pomp-announce           | 32       | 1       | May 2010      | Jul 2015     |
| listpackage-discuss     | 27       | 10      | May 2011      | Mar 2017     |
| r-sig-networks          | 27       | 21      | Jul 2008      | May 2019     |
| expm-developers         | 26       | 9       | Feb 2009      | Mar 2025     |
| r-sig-mediawiki         | 26       | 10      | Aug 2006      | Feb 2015     |
| hyperspec-help          | 21       | 8       | Dec 2009      | Jul 2017     |
| r-sig-qa                | 20       | 12      | Oct 2001      | Oct 2012     |
| gsoc-dowd               | 19       | 3       | Jun 2015      | Sep 2015     |
| genabel-announce        | 16       | 2       | Aug 2013      | Dec 2018     |
| mixvir                  | 16       | 5       | Jun 2022      | Jun 2025     |
| netlogor                | 16       | 4       | Oct 2022      | Aug 2023     |
| batman-users            | 15       | 7       | Mar 2013      | Jun 2015     |
| forensim-help           | 15       | 8       | Nov 2011      | Jul 2015     |
| r-marketing-bugs        | 14       | 6       | Feb 2015      | Oct 2020     |
| picante-devel           | 13       | 4       | May 2008      | Nov 2008     |
| eventstudies-discussion | 11       | 5       | Nov 2013      | Aug 2014     |
| r-hiphop                | 10       | 6       | Apr 2021      | Oct 2023     |
| viennar-meetup          | 10       | 1       | Oct 2018      | Apr 2020     |
| repitools-help          | 8        | 6       | Apr 2010      | Apr 2016     |
| uhcluster-members       | 8        | 1       | Mar 2009      | Jul 2009     |
| immcantation-news       | 7        | 2       | Apr 2024      | Aug 2026     |
| cipsr-users             | 6        | 1       | Oct 2014      | Mar 2015     |
| riskassessment-news     | 6        | 4       | Nov 2011      | Apr 2021     |
| biocbug                 | 5        | 1       | Nov 2003      | Mar 2004     |
| catlearn-package        | 5        | 2       | Feb 2018      | Oct 2019     |
| r-forge-testing-testing | 5        | 1       | Aug 2019      | Aug 2019     |
| r-sig-rugs              | 5        | 2       | Jul 2010      | Feb 2013     |
| sciviews-help           | 5        | 3       | Jun 2009      | Aug 2010     |
| sprint-developer        | 5        | 1       | May 2013      | Aug 2013     |
| travelr-announce        | 5        | 1       | May 2010      | Aug 2010     |
| zipfr-users             | 5        | 5       | Jan 2010      | May 2018     |
| dirichletreg-news       | 4        | 1       | Apr 2012      | Dec 2014     |
| mvabund-updates         | 4        | 1       | Nov 2012      | Jun 2013     |
| nlsy-links              | 4        | 3       | Jun 2019      | Mar 2022     |
| pez-users               | 4        | 2       | Jan 2018      | Jan 2018     |
| phylogram               | 4        | 3       | Mar 2018      | Sep 2022     |
| simsalabim-communicate  | 4        | 3       | Oct 2008      | Nov 2008     |
| spdep-devel             | 4        | 3       | May 2010      | Mar 2017     |
| synbreed-news           | 4        | 3       | Jul 2010      | Jan 2012     |
| bioc-sig-proteomics     | 3        | 2       | May 2011      | Sep 2011     |
| metrology-devel         | 3        | 1       | Apr 2011      | Apr 2011     |
| rgeos-devel             | 3        | 2       | May 2010      | Feb 2020     |
| rphree-general          | 3        | 2       | Jun 2014      | Jun 2014     |
| sciviews-news           | 3        | 1       | Jun 2009      | Jun 2009     |
| simplephenotypes        | 3        | 2       | Jun 2021      | Jun 2021     |
| sprint-user             | 3        | 1       | May 2013      | May 2013     |
| abernethy-reliability   | 2        | 1       | Jan 2014      | Jun 2014     |
| fresh-tor4              | 2        | 2       | Oct 2009      | Oct 2009     |
| mailman                 | 2        | 2       | Jul 2011      | Sep 2011     |
| orchestra-users         | 2        | 1       | Aug 2009      | Aug 2009     |
| phenopix-developers     | 2        | 2       | Nov 2014      | Sep 2015     |
| r-gregmisc-devel        | 2        | 1       | May 2015      | Jun 2015     |
| right-user              | 2        | 2       | Feb 2015      | Feb 2015     |
| chnosz-help             | 1        | 1       | Aug 2011      | Aug 2011     |
| cran2deb-discuss        | 1        | 1       | Jul 2011      | Jul 2011     |
| ctsem-mail              | 1        | 1       | May 2020      | May 2020     |
| distr-distr             | 1        | 1       | Mar 2012      | Mar 2012     |
| ftree-community         | 1        | 1       | May 2017      | May 2017     |
| gwidgets-questions      | 1        | 1       | Mar 2013      | Mar 2013     |
| mvabund-faqs            | 1        | 1       | Jul 2013      | Jul 2013     |
| piecepackr              | 1        | 1       | Aug 2024      | Aug 2024     |
| rangemapper-news        | 1        | 1       | Sep 2010      | Sep 2010     |
| robustbase-authors      | 1        | 1       | Nov 2013      | Nov 2013     |
| rserlang-develop        | 1        | 1       | Oct 2010      | Oct 2010     |
| travelr-discussion      | 1        | 1       | Aug 2010      | Aug 2010     |
| yuima-wishlist          | 1        | 1       | Aug 2011      | Aug 2011     |

## Reply network on r-devel

The `in_reply_to` field links each message to its parent, making it
straightforward to build a “who replies to whom” network.

<div id="fig-reply-network">

<img src="README_files/figure-commonmark/fig-reply-network-1.png"
id="fig-reply-network"
data-fig-alt="Network graph showing reply relationships between top r-devel contributors"
alt="Network graph showing reply relationships between top r-devel contributors" />

Figure 1

</div>

## Data dictionary

### `<list>.parquet`

One Parquet file per mailing list. All files share the same schema.

| Column | Type | Description |
|----|----|----|
| `list` | string | Mailing list name (e.g., `r-devel`) |
| `id` | string | Unique message ID (`msg-<hash>`) |
| `message_id` | string | Original RFC 2822 Message-ID header |
| `from_name` | string | Author display name (alias-resolved to canonical form) |
| `from_email_hash` | string | SHA-256 hash of author email (privacy-preserving) |
| `date` | timestamp | Message date (UTC) |
| `subject` | string | Subject line with `Re:`/`Fwd:` prefixes stripped |
| `in_reply_to` | string | ID of the parent message (null for thread starters) |
| `body` | string | Full message body text |
| `body_snippet` | string | First 200 characters of the body |
| `thread_id` | string | Thread grouping ID (`thread-<hash>`) |
| `thread_depth` | integer | Depth in thread tree (0 = root message) |
| `month` | string | `YYYY-MM` for temporal bucketing |
| `source_url` | string | Address of the message’s own page in the source archive (null when none is known, and for every list hosted on R-Forge) |
| `restored_from` | string | Addresses of the pages the message’s text was restored from, separated by one space (null when nothing was restored) |
| `spam` | boolean | True for a message a person confirmed as spam (see `scripts/spam.tsv`); the message stays in the file |

One list, `r-sig-phylo`, has an archive that is members-only at the
source. In its data every address the parser can read is hidden, except
the R lists’ own posting addresses, and `message_id` and `in_reply_to`
are opaque codes that still tie a reply to its parent;
`from_email_hash`, though, is still the unsalted SHA-256 of the real
address, so an address someone already has can be checked against it.

### `threads.parquet`

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

### `contributors.parquet`

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
mailing list servers, except those of `r-sig-phylo`, whose archive there
is open to list members only.

## License

The mailing list content is publicly archived by the [R
Project](https://www.r-project.org/mail.html) via [ETH
Zurich](https://stat.ethz.ch/pipermail/) and
[R-Forge](https://lists.r-forge.r-project.org/pipermail/), except that
of `r-sig-phylo`, whose archive is open to list members only and which
is included here with addresses hidden. This dataset reformats that
content for easier analysis. The tooling in this repository is licensed
under the [MIT License](LICENSE).
