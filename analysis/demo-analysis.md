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

``` r
library(nanoparquet)
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

read_messages <- function(col_select = NULL) {
  files <- list.files("../data/messages", pattern = "\\.parquet$", full.names = TRUE)
  do.call(rbind, lapply(files, read_parquet, col_select = col_select))
}
```

## Message volume over time

``` r
msgs <- read_messages(col_select = c("list", "from_name", "date", "month"))

monthly <- msgs |>
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
data-fig-alt="Monthly message volume across R mailing lists over time" />

Figure 1

</div>

## Top posters by list

``` r
r_devel <- read_parquet(
  "../data/messages/r-devel.parquet",
  col_select = c("from_name", "date", "subject")
)

recent <- r_devel[r_devel$date >= as.POSIXct(Sys.Date() - 365), ]
head(sort(table(recent$from_name), decreasing = TRUE), 10)
```


                     Duncan Murdoch                 Martin Maechler 
                                 36                              33 
                  Dirk Eddelbuettel                     Ivan Krylov 
                                 28                              28 
                        Kurt Hornik                    Mikael Jagan 
                                 18                              18 
                    Michael Chirico                      Ben Bolker 
                                 17                              16 
                   Henrik Bengtsson Suharto Anggono Suharto Anggono 
                                 15                              15 

## Reply network on r-devel

The `in_reply_to` field links each message to its parent, making it
straightforward to build a “who replies to whom” network.

``` r
library(igraph)
library(ggraph)

r_devel <- read_parquet(
  "../data/messages/r-devel.parquet",
  col_select = c("message_id", "from_name", "in_reply_to")
)

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
data-fig-alt="Network graph showing reply relationships between top r-devel contributors" />

Figure 2

</div>

## Contributors across lists

``` r
contribs <- read_parquet("../data/contributors.parquet")
contribs |>
  arrange(desc(message_count)) |>
  head(20) |>
  select(name, message_count, list_count) |>
  knitr::kable()
```

| name               | message_count | list_count |
|:-------------------|--------------:|-----------:|
| Brian Ripley       |         21042 |         10 |
| Duncan Murdoch     |         13418 |         13 |
| Peter Dalgaard     |         13311 |         10 |
| David Winsemius    |         11757 |          7 |
| Gabor Grothendieck |          9502 |         10 |
| Uwe Ligges         |          9076 |         13 |
| Ben Bolker         |          7526 |          8 |
| Martin Maechler    |          7421 |         19 |
| Bert Gunter        |          6719 |          9 |
| Dirk Eddelbuettel  |          6510 |         13 |
| Thomas Lumley      |          4808 |          8 |
| jim holtman        |          4608 |          3 |
| Roger Bivand       |          4371 |         12 |
| arun               |          4242 |          2 |
| Douglas Bates      |          3768 |         10 |
| Petr PIKAL         |          3550 |          3 |
| Hadley Wickham     |          3325 |         15 |
| Simon Urbanek      |          3309 |          9 |
| Greg Snow          |          3026 |         10 |
| John Fox           |          2852 |          9 |
