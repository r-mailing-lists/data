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

**1,008,637** messages across **275** mailing lists

| List                       | Messages | Authors | First Message | Last Message |
|:---------------------------|:---------|:--------|:--------------|:-------------|
| r-help                     | 398,803  | 36,566  | Apr 1997      | Oct 2026     |
| r-devel                    | 63,737   | 5,576   | Apr 1997      | Oct 2026     |
| bioconductor               | 61,316   | 7,259   | Nov 2001      | Sep 2014     |
| r-sig-geo                  | 29,588   | 3,456   | Jul 2003      | Oct 2026     |
| stan-users                 | 26,736   | 1,416   | Aug 2012      | Jun 2017     |
| lavaan                     | 23,445   | 3,177   | Sep 2012      | Oct 2026     |
| shiny-discuss              | 23,336   | 3,762   | Nov 2012      | Jan 2024     |
| bioc-devel                 | 21,557   | 1,700   | Mar 2004      | Oct 2026     |
| ggplot2                    | 21,320   | 3,063   | Nov 2008      | Jan 2025     |
| r-sig-mixed-models         | 20,674   | 3,092   | Jan 2007      | Oct 2026     |
| r-br                       | 20,633   | 1,057   | Mar 2011      | Oct 2025     |
| r-inla-discussion-group    | 16,090   | 1,682   | Feb 2011      | Oct 2026     |
| r-help-es                  | 15,408   | 899     | Mar 2009      | Sep 2026     |
| r-sig-finance              | 15,315   | 2,132   | Jun 2004      | Sep 2026     |
| r-sig-mac                  | 15,122   | 1,721   | Jan 1970      | Oct 2026     |
| stan-dev                   | 14,007   | 73      | Nov 2011      | Dec 2016     |
| r-package-devel            | 12,405   | 1,129   | May 2015      | Oct 2026     |
| rcpp-devel                 | 11,011   | 794     | Nov 2009      | May 2026     |
| unmarked                   | 7,729    | 1,059   | Feb 2010      | Oct 2026     |
| r-sig-ecology              | 7,613    | 1,318   | Apr 2008      | Oct 2026     |
| distance-sampling          | 6,855    | 1,278   | Sep 1998      | Oct 2026     |
| r-sig-phylo                | 6,509    | 1,035   | Feb 2008      | Oct 2026     |
| shinyapps-users            | 6,426    | 1,537   | Nov 2013      | Sep 2018     |
| rkward-devel               | 6,143    | 418     | Nov 2002      | Sep 2025     |
| nimble-users               | 5,843    | 590     | Jul 2014      | Oct 2026     |
| r-sig-meta-analysis        | 5,649    | 551     | Jun 2017      | Oct 2026     |
| mirt-package               | 5,602    | 667     | Apr 2013      | Apr 2026     |
| aroma-affymetrix           | 4,763    | 548     | Feb 2007      | Feb 2021     |
| rqtl-disc                  | 4,744    | 626     | Sep 2004      | Oct 2026     |
| rpy-list                   | 3,768    | 499     | Jan 2004      | Jun 2021     |
| r-sig-debian               | 3,678    | 501     | Feb 2005      | Sep 2026     |
| davis-rug                  | 3,651    | 365     | Sep 2012      | May 2026     |
| geomorph-r-package         | 3,636    | 394     | Jul 2016      | Oct 2026     |
| rpackageggir               | 3,417    | 525     | Nov 2014      | Jul 2025     |
| datatable-help             | 3,415    | 439     | Mar 2010      | Apr 2018     |
| israel-r-user-group        | 3,141    | 204     | Aug 2009      | Mar 2021     |
| methylkit-discussion       | 3,131    | 532     | May 2013      | Jul 2026     |
| ctmm-user                  | 2,997    | 418     | Feb 2017      | Oct 2026     |
| manipulatr                 | 2,804    | 528     | Mar 2009      | Dec 2023     |
| msstats                    | 2,636    | 391     | Jan 2014      | Oct 2026     |
| secrgroup                  | 2,548    | 335     | Nov 2013      | Aug 2026     |
| dartr                      | 2,425    | 272     | Nov 2018      | Sep 2026     |
| bioc-sig-sequencing        | 2,295    | 227     | Feb 2008      | Sep 2011     |
| rhadoop                    | 2,167    | 385     | Feb 2012      | May 2016     |
| r-sig-hpc                  | 2,152    | 382     | Oct 2008      | Dec 2024     |
| adegenet-forum             | 1,994    | 453     | Feb 2008      | Feb 2025     |
| hmecology                  | 1,964    | 342     | Dec 2012      | Oct 2026     |
| knitr                      | 1,964    | 339     | Jan 2012      | Oct 2023     |
| stats-rosuda-devel         | 1,938    | 358     | Sep 2006      | Jul 2017     |
| taiwanruser                | 1,774    | 417     | Feb 2012      | Sep 2026     |
| biogeobears                | 1,636    | 256     | Oct 2013      | Oct 2026     |
| camtrapr                   | 1,626    | 304     | Dec 2016      | Oct 2026     |
| bioc-ggtree                | 1,586    | 392     | Mar 2016      | Nov 2025     |
| r-sig-db                   | 1,559    | 391     | Apr 2001      | Nov 2020     |
| deducer                    | 1,538    | 295     | Aug 2009      | May 2022     |
| blavaan                    | 1,472    | 165     | Feb 2016      | Apr 2026     |
| rhipe                      | 1,461    | 176     | Nov 2009      | May 2016     |
| rkward-users               | 1,446    | 158     | Apr 2007      | Oct 2025     |
| simmer-devel               | 1,399    | 123     | Apr 2016      | Sep 2024     |
| genabel-devel              | 1,350    | 64      | Nov 2010      | Dec 2018     |
| r-packages                 | 1,347    | 570     | Sep 2003      | Oct 2026     |
| rattle-users               | 1,339    | 306     | Aug 2006      | Aug 2024     |
| tmb-users                  | 1,321    | 178     | Jun 2016      | Oct 2026     |
| genomic-sem-users          | 1,282    | 206     | Sep 2018      | Sep 2026     |
| r-sig-gui                  | 1,236    | 262     | Oct 2002      | Feb 2018     |
| sparkr-dev                 | 1,226    | 93      | Aug 2014      | Sep 2019     |
| rapache                    | 1,198    | 231     | May 2009      | Aug 2019     |
| gsoc-r                     | 1,181    | 261     | Mar 2010      | Jul 2026     |
| rqtl2-disc                 | 1,180    | 149     | Sep 2017      | Sep 2026     |
| corpling-with-r            | 1,170    | 155     | Nov 2006      | Jul 2024     |
| r-lang                     | 1,161    | 201     | Mar 2007      | Nov 2019     |
| nichemapr                  | 1,160    | 134     | Feb 2016      | Oct 2026     |
| zelig                      | 1,085    | 259     | Feb 2007      | Apr 2015     |
| seewave                    | 1,081    | 261     | Apr 2010      | Aug 2025     |
| brms-users                 | 1,042    | 143     | Jan 2017      | Jun 2018     |
| poppr                      | 1,018    | 214     | Mar 2014      | Apr 2025     |
| cardinalmsi                | 950      | 134     | Feb 2015      | Mar 2025     |
| r-sig-fedora               | 931      | 129     | May 2008      | Apr 2026     |
| braingraph-help            | 892      | 88      | Dec 2015      | May 2025     |
| r-sig-teaching             | 886      | 222     | Oct 2006      | Sep 2026     |
| rkoholiki                  | 852      | 93      | Nov 2009      | Dec 2025     |
| subread                    | 839      | 136     | Jul 2013      | Apr 2021     |
| wallaceecomod              | 839      | 179     | Jan 2017      | Sep 2026     |
| ggplot2-dev                | 832      | 56      | Dec 2011      | Mar 2017     |
| r-swat                     | 786      | 154     | Aug 2021      | Oct 2026     |
| rropen                     | 775      | 217     | Oct 2014      | May 2016     |
| rmetrics-core              | 741      | 220     | Sep 2007      | Nov 2017     |
| fieldimager                | 725      | 102     | Mar 2020      | Mar 2026     |
| phylobase-devl             | 724      | 28      | Feb 2008      | Apr 2014     |
| r-announce                 | 714      | 111     | Apr 1997      | Sep 2026     |
| r-sig-dynamic-models       | 697      | 159     | Oct 2009      | Mar 2026     |
| ggvis                      | 693      | 182     | Aug 2013      | Jun 2024     |
| sequenza-user-group        | 691      | 156     | Aug 2014      | Oct 2026     |
| r-sig-epi                  | 676      | 166     | Nov 2005      | Oct 2026     |
| nat-user                   | 639      | 103     | Apr 2015      | Jan 2026     |
| tsdyn                      | 634      | 83      | Dec 2006      | Feb 2024     |
| matchit                    | 614      | 158     | Feb 2007      | Jan 2020     |
| irace-package              | 594      | 102     | Jul 2016      | Sep 2025     |
| r-sig-genetics             | 591      | 61      | May 2008      | Oct 2026     |
| hbayesdm-users             | 562      | 120     | Dec 2016      | Apr 2026     |
| rdevtools                  | 561      | 127     | Mar 2012      | Jan 2023     |
| oscr-package               | 551      | 78      | Feb 2016      | Oct 2026     |
| flr-list                   | 539      | 47      | Oct 2011      | Apr 2019     |
| ez4r                       | 533      | 124     | Feb 2011      | Feb 2023     |
| r-sig-robust               | 525      | 152     | Nov 2005      | Jul 2026     |
| mplusautomation            | 514      | 165     | Dec 2012      | Aug 2026     |
| r-soc                      | 507      | 111     | Mar 2009      | Jan 2020     |
| packrat-discuss            | 497      | 153     | Nov 2013      | Jun 2021     |
| statforling-with-r         | 493      | 61      | Aug 2008      | Aug 2024     |
| roxygen-devel              | 469      | 58      | May 2008      | Aug 2015     |
| sevillarusers              | 457      | 51      | Nov 2014      | Jul 2019     |
| qcawithr                   | 449      | 67      | Mar 2020      | Aug 2026     |
| r-sig-jobs                 | 442      | 267     | Feb 2007      | Mar 2026     |
| r-sig-wiki                 | 398      | 32      | Jan 2006      | Aug 2010     |
| spocc-spabund-users        | 389      | 74      | Jul 2024      | Oct 2026     |
| r-ecologia                 | 385      | 71      | Oct 2012      | Jun 2017     |
| traminer-users             | 383      | 94      | May 2010      | Jul 2023     |
| r-study-tokyo              | 364      | 65      | Jan 2010      | Oct 2026     |
| rsiena-help                | 354      | 67      | Feb 2010      | May 2019     |
| qtinterfaces-devel         | 349      | 22      | Sep 2009      | May 2014     |
| rugbcn                     | 340      | 52      | Aug 2011      | Jul 2020     |
| codex2                     | 318      | 68      | Feb 2015      | Jan 2025     |
| vim-r-plugin               | 318      | 58      | Dec 2013      | Mar 2024     |
| sorvi-admin                | 300      | 27      | Nov 2011      | Nov 2021     |
| tidylpa                    | 299      | 116     | Apr 2018      | Aug 2025     |
| seqinr-forum               | 296      | 58      | Jul 2008      | Mar 2023     |
| gsoc-porta                 | 273      | 8       | Jun 2013      | Aug 2014     |
| tikzdevice-bugs            | 268      | 47      | Jul 2009      | Nov 2013     |
| rpostgresql-dev            | 255      | 85      | Feb 2011      | Aug 2026     |
| rprotobuf-yada             | 237      | 13      | Oct 2009      | Oct 2016     |
| spades-users               | 237      | 21      | Mar 2016      | Nov 2020     |
| maaslin-users              | 222      | 99      | Apr 2014      | Jan 2020     |
| acs-r                      | 212      | 47      | Apr 2013      | Apr 2021     |
| rbigdataprogramming        | 203      | 50      | Oct 2012      | Jun 2020     |
| basta-users                | 199      | 48      | Nov 2011      | Nov 2025     |
| rnomads-user               | 198      | 40      | Sep 2014      | Apr 2023     |
| r-ug-ottawa                | 197      | 66      | Jan 2009      | Dec 2022     |
| sqldf                      | 193      | 66      | Feb 2013      | Feb 2021     |
| bioconductor-teaching      | 189      | 23      | Jul 2020      | Oct 2026     |
| r-sig-gr                   | 177      | 79      | Sep 2002      | Sep 2026     |
| breedr                     | 175      | 41      | Jul 2015      | Nov 2024     |
| titancna                   | 167      | 31      | Aug 2014      | Nov 2023     |
| rrook                      | 166      | 43      | Apr 2011      | Aug 2015     |
| canopy-phylogeny           | 164      | 43      | Sep 2016      | Sep 2023     |
| isorix                     | 163      | 30      | Apr 2021      | Apr 2026     |
| rcytoscape                 | 163      | 11      | May 2011      | Mar 2019     |
| mediation-information      | 158      | 31      | May 2011      | Jan 2021     |
| metacoder-discussions      | 154      | 41      | Feb 2017      | Apr 2026     |
| cranvas                    | 153      | 25      | Jun 2011      | Dec 2015     |
| rworldmap                  | 149      | 56      | Jul 2013      | Dec 2023     |
| tinn-r                     | 147      | 28      | Feb 2014      | Oct 2021     |
| r-sig-windows              | 146      | 21      | Aug 2015      | Sep 2026     |
| stitch-imputation          | 145      | 35      | Mar 2017      | Apr 2026     |
| tessera-users              | 142      | 28      | Jun 2014      | Jun 2016     |
| mosaics-user-group         | 141      | 38      | Jun 2011      | Jan 2024     |
| segoptim-user-group        | 141      | 29      | Jan 2019      | Jan 2025     |
| garnett-users              | 138      | 38      | Feb 2019      | Aug 2026     |
| inlinedocs-support         | 137      | 59      | Nov 2009      | Jun 2014     |
| maduser                    | 136      | 57      | Sep 2009      | Apr 2014     |
| rkward                     | 134      | 17      | Oct 2025      | Oct 2026     |
| rcppoctave-user            | 133      | 8       | Oct 2013      | Nov 2016     |
| jiebar                     | 126      | 68      | Feb 2015      | Aug 2026     |
| gbm-dev                    | 123      | 14      | Mar 2015      | Feb 2020     |
| brumail                    | 119      | 34      | Feb 2011      | Sep 2025     |
| r-sig-insurance            | 117      | 39      | Apr 2009      | Dec 2022     |
| nmof-news                  | 115      | 1       | Jun 2011      | Oct 2025     |
| ib-usp-r-users             | 109      | 40      | Feb 2016      | Jun 2020     |
| gur-ugr                    | 108      | 28      | Oct 2008      | Apr 2020     |
| r-package-xlsx             | 107      | 47      | Jan 2012      | Nov 2021     |
| rspatial-devel             | 107      | 10      | Apr 2011      | Dec 2015     |
| tlocoh-info                | 105      | 34      | Sep 2013      | May 2021     |
| trophicposition-support    | 104      | 52      | May 2017      | Aug 2026     |
| rqtl-announce              | 96       | 2       | Sep 2004      | Jul 2026     |
| tropical-r                 | 95       | 22      | Aug 2012      | May 2016     |
| comparegroupsforum         | 93       | 30      | Oct 2013      | Dec 2021     |
| epls-r-users               | 88       | 7       | Mar 2019      | Apr 2026     |
| mxmaps                     | 88       | 26      | Mar 2019      | Jan 2025     |
| houston-r                  | 83       | 20      | Mar 2009      | Feb 2012     |
| rquantlib-devel            | 75       | 15      | Feb 2010      | Feb 2017     |
| konfound-it                | 70       | 11      | Jun 2018      | Jul 2026     |
| ipmpack-users              | 69       | 35      | Aug 2012      | May 2019     |
| genoplotr-help             | 67       | 12      | Jun 2010      | Nov 2020     |
| r-sig-dcm                  | 67       | 17      | Jul 2010      | Sep 2024     |
| r-and-cpp                  | 65       | 15      | Apr 2014      | May 2024     |
| nmf-user                   | 61       | 16      | Nov 2011      | Jul 2020     |
| nimble-announce            | 58       | 4       | Oct 2014      | Aug 2026     |
| hkrug                      | 55       | 13      | Apr 2012      | Mar 2015     |
| statistics-and-r-community | 54       | 19      | Oct 2018      | Feb 2025     |
| reddyproc-users            | 51       | 14      | Jul 2013      | Nov 2019     |
| linguagem-r-ufba           | 50       | 16      | Nov 2017      | Dec 2017     |
| rcicr-users                | 48       | 12      | Oct 2014      | Mar 2019     |
| ropengov-forum             | 47       | 10      | Dec 2013      | Mar 2019     |
| rsnns                      | 44       | 23      | Dec 2016      | Jun 2025     |
| boostheaders-devel         | 37       | 7       | Feb 2013      | Jan 2015     |
| dynr                       | 37       | 14      | Feb 2019      | Nov 2025     |
| r-forum                    | 35       | 18      | Dec 2008      | Sep 2013     |
| remoterengine-devel        | 35       | 2       | Aug 2009      | Oct 2009     |
| monetr-users               | 34       | 6       | Jul 2013      | Nov 2015     |
| pomp-announce              | 32       | 1       | May 2010      | Jul 2015     |
| dublin-r                   | 31       | 14      | May 2011      | Apr 2026     |
| cellnet-r                  | 27       | 17      | Aug 2014      | Nov 2018     |
| listpackage-discuss        | 27       | 10      | May 2011      | Mar 2017     |
| monterey-grumps            | 27       | 9       | Nov 2014      | Jun 2019     |
| r-sig-networks             | 27       | 21      | Jul 2008      | May 2019     |
| red-r                      | 27       | 8       | Sep 2009      | Dec 2010     |
| expm-developers            | 26       | 9       | Feb 2009      | Mar 2025     |
| mapfastr                   | 26       | 13      | Jul 2012      | Apr 2020     |
| r-sig-mediawiki            | 26       | 10      | Aug 2006      | Feb 2015     |
| hyperspec-help             | 21       | 8       | Dec 2009      | Jul 2017     |
| lubridate                  | 20       | 13      | Feb 2013      | Jan 2023     |
| matr-forum                 | 20       | 6       | May 2014      | Feb 2016     |
| r-sig-qa                   | 20       | 12      | Oct 2001      | Oct 2012     |
| gsoc-dowd                  | 19       | 3       | Jun 2015      | Sep 2015     |
| genabel-announce           | 16       | 2       | Aug 2013      | Dec 2018     |
| mixvir                     | 16       | 5       | Jun 2022      | Jun 2025     |
| netlogor                   | 16       | 4       | Oct 2022      | Aug 2023     |
| batman-users               | 15       | 7       | Mar 2013      | Jun 2015     |
| forensim-help              | 15       | 8       | Nov 2011      | Jul 2015     |
| r-marketing-bugs           | 14       | 6       | Feb 2015      | Oct 2020     |
| picante-devel              | 13       | 4       | May 2008      | Nov 2008     |
| methylkit                  | 12       | 1       | Jan 2012      | Jan 2014     |
| workflowr-announce         | 12       | 1       | Apr 2018      | Aug 2023     |
| eventstudies-discussion    | 11       | 5       | Nov 2013      | Aug 2014     |
| r-hiphop                   | 10       | 6       | Apr 2021      | Oct 2023     |
| viennar-meetup             | 10       | 1       | Oct 2018      | Apr 2020     |
| repitools-help             | 8        | 6       | Apr 2010      | Apr 2016     |
| uhcluster-members          | 8        | 1       | Mar 2009      | Jul 2009     |
| whatif                     | 8        | 7       | Feb 2008      | May 2021     |
| immcantation-news          | 7        | 2       | Apr 2024      | Aug 2026     |
| cipsr-users                | 6        | 1       | Oct 2014      | Mar 2015     |
| riskassessment-news        | 6        | 4       | Nov 2011      | Apr 2021     |
| biocbug                    | 5        | 1       | Nov 2003      | Mar 2004     |
| catlearn-package           | 5        | 2       | Feb 2018      | Oct 2019     |
| r-forge-testing-testing    | 5        | 1       | Aug 2019      | Aug 2019     |
| r-sig-rugs                 | 5        | 2       | Jul 2010      | Feb 2013     |
| sciviews-help              | 5        | 3       | Jun 2009      | Aug 2010     |
| sprint-developer           | 5        | 1       | May 2013      | Aug 2013     |
| travelr-announce           | 5        | 1       | May 2010      | Aug 2010     |
| zipfr-users                | 5        | 5       | Jan 2010      | May 2018     |
| dirichletreg-news          | 4        | 1       | Apr 2012      | Dec 2014     |
| mvabund-updates            | 4        | 1       | Nov 2012      | Jun 2013     |
| nlsy-links                 | 4        | 3       | Jun 2019      | Mar 2022     |
| pez-users                  | 4        | 2       | Jan 2018      | Jan 2018     |
| phylogram                  | 4        | 3       | Mar 2018      | Sep 2022     |
| simsalabim-communicate     | 4        | 2       | Oct 2008      | Nov 2008     |
| spdep-devel                | 4        | 3       | May 2010      | Mar 2017     |
| synbreed-news              | 4        | 3       | Jul 2010      | Jan 2012     |
| bioc-sig-proteomics        | 3        | 2       | May 2011      | Sep 2011     |
| metrology-devel            | 3        | 1       | Apr 2011      | Apr 2011     |
| rgeos-devel                | 3        | 2       | May 2010      | Feb 2020     |
| rphree-general             | 3        | 2       | Jun 2014      | Jun 2014     |
| sciviews-news              | 3        | 1       | Jun 2009      | Jun 2009     |
| siamcat-users              | 3        | 3       | Jun 2015      | Nov 2020     |
| simplephenotypes           | 3        | 2       | Jun 2021      | Jun 2021     |
| sprint-user                | 3        | 1       | May 2013      | May 2013     |
| abernethy-reliability      | 2        | 1       | Jan 2014      | Jun 2014     |
| fresh-tor4                 | 2        | 2       | Oct 2009      | Oct 2009     |
| mailman                    | 2        | 2       | Jul 2011      | Sep 2011     |
| orchestra-users            | 2        | 1       | Aug 2009      | Aug 2009     |
| phenopix-developers        | 2        | 2       | Nov 2014      | Sep 2015     |
| r-gregmisc-devel           | 2        | 1       | May 2015      | Jun 2015     |
| right-user                 | 2        | 2       | Feb 2015      | Feb 2015     |
| chnosz-help                | 1        | 1       | Aug 2011      | Aug 2011     |
| cran2deb-discuss           | 1        | 1       | Jul 2011      | Jul 2011     |
| ctsem-mail                 | 1        | 1       | May 2020      | May 2020     |
| distr-distr                | 1        | 1       | Mar 2012      | Mar 2012     |
| ftree-community            | 1        | 1       | May 2017      | May 2017     |
| gwidgets-questions         | 1        | 1       | Mar 2013      | Mar 2013     |
| mvabund-faqs               | 1        | 1       | Jul 2013      | Jul 2013     |
| piecepackr                 | 1        | 1       | Aug 2024      | Aug 2024     |
| rangemapper-news           | 1        | 1       | Sep 2010      | Sep 2010     |
| robustbase-authors         | 1        | 1       | Nov 2013      | Nov 2013     |
| rserlang-develop           | 1        | 1       | Oct 2010      | Oct 2010     |
| travelr-discussion         | 1        | 1       | Aug 2010      | Aug 2010     |
| yuima-wishlist             | 1        | 1       | Aug 2011      | Aug 2011     |

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
| `from_name` | string | Author display name (alias-resolved to canonical form). A sender the archive shows under an email address gets the name they gave on other messages, or else the address without its domain |
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

Sender email addresses are not included in this dataset. Author identity
is represented by display name and a SHA-256 hash of the email address,
which allows grouping messages by author without exposing contact
information. Message text is kept as the source archive shows it, so an
address written in a message, or quoted from another, can still appear
there. The original emails are publicly archived on the source mailing
list servers, except those of `r-sig-phylo`, whose archive there is open
to list members only.

## License

The mailing list content is publicly archived by the [R
Project](https://www.r-project.org/mail.html) via [ETH
Zurich](https://stat.ethz.ch/pipermail/) and
[R-Forge](https://lists.r-forge.r-project.org/pipermail/), except that
of `r-sig-phylo`, whose archive is open to list members only and which
is included here with addresses hidden. This dataset reformats that
content for easier analysis. The tooling in this repository is licensed
under the [MIT License](LICENSE).
