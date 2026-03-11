#!/usr/bin/env Rscript

# Convert processed JSON mailing list archives to Parquet format
#
# Usage: Rscript scripts/build-parquet.R <processed_data_dir> <output_dir>
#   processed_data_dir: path to directory containing per-list folders of monthly JSON
#   output_dir:         path to write parquet files (default: data/)

library(jsonlite)
library(nanoparquet)

args <- commandArgs(trailingOnly = TRUE)
input_dir <- if (length(args) >= 1) args[1] else "data/processed"
output_dir <- if (length(args) >= 2) args[2] else "data"
aliases_file <- if (length(args) >= 3) args[3] else "aliases.json"

messages_dir <- file.path(output_dir, "messages")
dir.create(messages_dir, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Load aliases for name resolution
# ---------------------------------------------------------------------------

alias_lookup <- NULL
if (file.exists(aliases_file)) {
  alias_data <- fromJSON(aliases_file, simplifyDataFrame = FALSE)
  alias_lookup <- data.frame(
    from_email_hash = unlist(lapply(alias_data$aliases, `[[`, "email_hashes")),
    canonical_name  = rep(
      vapply(alias_data$aliases, `[[`, "", "canonical_name"),
      lengths(lapply(alias_data$aliases, `[[`, "email_hashes"))
    ),
    stringsAsFactors = FALSE
  )
  message("Loaded ", length(alias_data$aliases), " alias groups (",
          nrow(alias_lookup), " email hashes)")
} else {
  message("No aliases file found at ", aliases_file, " — using raw names")
}

resolve_aliases <- function(df) {
  if (is.null(alias_lookup)) return(df)
  merged <- merge(df, alias_lookup, by = "from_email_hash", all.x = TRUE)
  merged$from_name <- ifelse(is.na(merged$canonical_name),
                             merged$from_name, merged$canonical_name)
  merged$canonical_name <- NULL
  merged
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

read_month_json <- function(path, list_name) {
  d <- fromJSON(path, simplifyDataFrame = FALSE)
  msgs <- d$messages
  if (length(msgs) == 0) return(NULL)

  data.frame(
    list            = list_name,
    id              = vapply(msgs, `[[`, "", "id"),
    message_id      = vapply(msgs, `[[`, "", "message_id"),
    from_name       = vapply(msgs, `[[`, "", "from_name"),
    from_email_hash = vapply(msgs, `[[`, "", "from_email_hash"),
    date            = vapply(msgs, `[[`, "", "date"),
    subject         = vapply(msgs, `[[`, "", "subject_clean"),
    in_reply_to     = vapply(msgs, \(m) m$in_reply_to %||% NA_character_, ""),
    body            = vapply(msgs, `[[`, "", "body_plain"),
    body_snippet    = vapply(msgs, `[[`, "", "body_snippet"),
    thread_id       = vapply(msgs, `[[`, "", "thread_id"),
    thread_depth    = vapply(msgs, `[[`, 0L, "thread_depth"),
    month           = vapply(msgs, `[[`, "", "month"),
    stringsAsFactors = FALSE
  )
}

MAX_FILE_MB <- 75

write_messages_parquet <- function(df, path) {
  write_parquet(df, path, compression = "zstd",
                options = parquet_options(compression_level = 19))
}

# Split a large parquet file into decade-based chunks
split_large_parquet <- function(msgs, list_name, messages_dir) {
  msgs$year <- as.integer(format(msgs$date, "%Y"))
  year_range <- range(msgs$year, na.rm = TRUE)

  # Build decade breaks
  breaks <- seq(
    floor(year_range[1] / 10) * 10,
    ceiling((year_range[2] + 1) / 10) * 10,
    by = 10
  )

  paths <- character()
  for (i in seq_len(length(breaks) - 1)) {
    chunk <- msgs[!is.na(msgs$year) & msgs$year >= breaks[i] & msgs$year < breaks[i + 1], ]
    if (nrow(chunk) == 0) next
    chunk$year <- NULL
    label <- paste0(breaks[i], "-", breaks[i + 1] - 1)
    out <- file.path(messages_dir, paste0(list_name, "-", label, ".parquet"))
    write_messages_parquet(chunk, out)
    message("  -> ", out, " (", nrow(chunk), " messages, ",
            round(file.size(out) / 1e6, 1), " MB)")
    paths <- c(paths, out)
  }
  msgs$year <- NULL
  paths
}

read_threads_json <- function(path, list_name) {
  d <- fromJSON(path, simplifyDataFrame = FALSE)
  threads <- d$threads
  if (length(threads) == 0) return(NULL)

  data.frame(
    list            = list_name,
    id              = vapply(threads, `[[`, "", "id"),
    subject         = vapply(threads, `[[`, "", "subject"),
    message_count   = vapply(threads, `[[`, 0L, "message_count"),
    started         = vapply(threads, `[[`, "", "started"),
    last_reply      = vapply(threads, `[[`, "", "last_reply"),
    root_message_id = vapply(threads, `[[`, "", "root_message_id"),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Process each list
# ---------------------------------------------------------------------------

list_dirs <- list.dirs(input_dir, full.names = TRUE, recursive = FALSE)
list_dirs <- list_dirs[!grepl("^_", basename(list_dirs))]

all_threads <- list()
summary_rows <- list()

for (list_path in list_dirs) {
  list_name <- basename(list_path)
  json_files <- list.files(list_path, pattern = "^\\d{4}-\\d{2}\\.json$", full.names = TRUE)

  if (length(json_files) == 0) {
    message("Skipping ", list_name, " (no monthly JSON files)")
    next
  }

  message("Processing ", list_name, " (", length(json_files), " months)...")

  msg_frames <- list()
  thread_frames <- list()

  for (jf in json_files) {
    mf <- read_month_json(jf, list_name)
    if (!is.null(mf)) msg_frames <- c(msg_frames, list(mf))

    tf <- read_threads_json(jf, list_name)
    if (!is.null(tf)) thread_frames <- c(thread_frames, list(tf))
  }

  if (length(msg_frames) == 0) next

  msgs <- do.call(rbind, msg_frames)
  msgs$date <- as.POSIXct(msgs$date, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  msgs$thread_depth <- as.integer(msgs$thread_depth)

  # Resolve from_name via aliases (canonical names)
  msgs <- resolve_aliases(msgs)

  out_path <- file.path(messages_dir, paste0(list_name, ".parquet"))
  write_messages_parquet(msgs, out_path)
  file_mb <- file.size(out_path) / 1e6
  message("  -> ", out_path, " (", nrow(msgs), " messages, ",
          round(file_mb, 1), " MB)")

  if (file_mb > MAX_FILE_MB) {
    message("  ** ", round(file_mb, 1), " MB exceeds ",
            MAX_FILE_MB, " MB limit — splitting by decade")
    file.remove(out_path)
    split_large_parquet(msgs, list_name, messages_dir)
  }

  if (length(thread_frames) > 0) {
    threads <- do.call(rbind, thread_frames)
    all_threads <- c(all_threads, list(threads))
  }

  summary_rows <- c(summary_rows, list(data.frame(
    list = list_name,
    messages = nrow(msgs),
    threads = if (length(thread_frames) > 0) nrow(do.call(rbind, thread_frames)) else 0L,
    first_date = min(msgs$date, na.rm = TRUE),
    last_date = max(msgs$date, na.rm = TRUE),
    stringsAsFactors = FALSE
  )))
}

# ---------------------------------------------------------------------------
# Write threads.parquet
# ---------------------------------------------------------------------------

if (length(all_threads) > 0) {
  threads_df <- do.call(rbind, all_threads)
  threads_df$started <- as.POSIXct(threads_df$started, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  threads_df$last_reply <- as.POSIXct(threads_df$last_reply, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  threads_path <- file.path(output_dir, "threads.parquet")
  write_parquet(threads_df, threads_path, compression = "zstd",
                options = parquet_options(compression_level = 19))
  message("Wrote ", threads_path, " (", nrow(threads_df), " threads, ",
          round(file.size(threads_path) / 1e6, 1), " MB)")
}

# ---------------------------------------------------------------------------
# Write contributors.parquet
# ---------------------------------------------------------------------------

contrib_path <- file.path(input_dir, "_contributors.json")
if (file.exists(contrib_path)) {
  contrib <- fromJSON(contrib_path, simplifyDataFrame = FALSE)
  contrib_df <- data.frame(
    name          = vapply(contrib, `[[`, "", "name"),
    message_count = vapply(contrib, `[[`, 0L, "messageCount"),
    list_count    = vapply(contrib, \(x) length(x$lists), 0L),
    lists         = vapply(contrib, \(x) paste(vapply(x$lists, `[[`, "", "slug"), collapse = ","), ""),
    list_counts   = vapply(contrib, \(x) paste(vapply(x$lists, \(l) paste0(l$slug, ":", l$count), ""), collapse = ","), ""),
    first_message = vapply(contrib, \(x) x$firstDate %||% NA_character_, ""),
    last_message  = vapply(contrib, \(x) x$lastDate %||% NA_character_, ""),
    stringsAsFactors = FALSE
  )
  contrib_out <- file.path(output_dir, "contributors.parquet")
  write_parquet(contrib_df, contrib_out, compression = "zstd",
                options = parquet_options(compression_level = 19))
  message("Wrote ", contrib_out, " (", nrow(contrib_df), " contributors, ",
          round(file.size(contrib_out) / 1e6, 1), " MB)")
}

# ---------------------------------------------------------------------------
# Write summary.json (used by README.qmd)
# ---------------------------------------------------------------------------

if (length(summary_rows) > 0) {
  summary_df <- do.call(rbind, summary_rows)
  summary_df$first_date <- as.character(summary_df$first_date)
  summary_df$last_date <- as.character(summary_df$last_date)
  write_json(summary_df, file.path(output_dir, "summary.json"), pretty = TRUE, auto_unbox = TRUE)
  message("Wrote ", file.path(output_dir, "summary.json"))
}

message("Done!")
