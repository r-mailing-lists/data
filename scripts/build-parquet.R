#!/usr/bin/env Rscript

# Convert processed JSON mailing list archives to Parquet format
#
# Usage: Rscript scripts/build-parquet.R <processed_data_dir> <output_dir> <aliases> <spam>
#   processed_data_dir: path to directory containing per-list folders of monthly JSON
#   output_dir:         path to write parquet files (default: data/)
#   aliases:            the alias file (default: aliases.json)
#   spam:               the messages a person confirmed as spam (default: scripts/spam.tsv)
#
# BUILD_PARQUET_MAX_TEXT_MB, when set, replaces MAX_TEXT_MB below: the text
# above which a list is written in five-year chunks. The tests lower it.

library(jsonlite)
library(nanoparquet)

# The functions that keep addresses out of sender names, from beside this script.
local({
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  here <- if (length(file_arg) == 1) dirname(sub("^--file=", "", file_arg)) else "scripts"
  source(file.path(here, "sender-names.R"))
})

args <- commandArgs(trailingOnly = TRUE)
input_dir <- if (length(args) >= 1) args[1] else "data/processed"
output_dir <- if (length(args) >= 2) args[2] else "data"
aliases_file <- if (length(args) >= 3) args[3] else "aliases.json"
spam_file <- if (length(args) >= 4) args[4] else "scripts/spam.tsv"

# ---------------------------------------------------------------------------
# Load the spam file
# ---------------------------------------------------------------------------

# scripts/spam.tsv is tab-separated with the header list, id, reason, flagged.
# Lines starting with # are comments. Only messages a person confirmed are in
# it. A file that is malformed stops the build, before anything is written: a
# half-read list of flags would publish messages as clean. A missing file is
# an empty list.
SPAM_COLUMNS <- c("list", "id", "reason", "flagged")
# The site shows the reason beside each hidden message, so it is one of these
# and never free text.
SPAM_REASONS <- c("advertising", "adult content", "harassment", "phishing", "scam")

read_spam <- function(path) {
  empty <- data.frame(list = character(), id = character(), reason = character(),
                      flagged = character(), stringsAsFactors = FALSE)
  if (!file.exists(path)) return(empty)

  lines <- sub("\r$", "", readLines(path, warn = FALSE, encoding = "UTF-8"))
  lines <- lines[nzchar(trimws(lines)) & !startsWith(lines, "#")]
  fail <- function(...) stop(path, ": ", ..., call. = FALSE)
  if (length(lines) == 0 || !identical(lines[1], paste(SPAM_COLUMNS, collapse = "\t"))) {
    fail("the header line must be ", paste(SPAM_COLUMNS, collapse = " <tab> "))
  }
  if (length(lines) == 1) return(empty)

  # The sentinel keeps strsplit() from dropping a field left empty at the end.
  fields <- strsplit(paste0(lines[-1], "\t."), "\t", fixed = TRUE)
  for (i in seq_along(fields)) {
    f <- fields[[i]][-length(fields[[i]])]
    if (length(f) != length(SPAM_COLUMNS) || any(!nzchar(trimws(f)))) {
      fail("line \"", lines[i + 1], "\" must have the four fields ", paste(SPAM_COLUMNS, collapse = ", "))
    }
    fields[[i]] <- f
  }
  spam <- as.data.frame(do.call(rbind, fields), stringsAsFactors = FALSE)
  names(spam) <- SPAM_COLUMNS

  bad_id <- !grepl("^msg-[0-9a-f]{12}$", spam$id)
  if (any(bad_id)) fail("not a message id (msg- and 12 hex digits): ", spam$id[bad_id][1])
  valid_date <- grepl("^\\d{4}-\\d{2}-\\d{2}$", spam$flagged) &
    !is.na(as.Date(spam$flagged, format = "%Y-%m-%d", optional = TRUE))
  if (!all(valid_date)) fail("not a date (YYYY-MM-DD): ", spam$flagged[!valid_date][1])
  bad_reason <- !spam$reason %in% SPAM_REASONS
  if (any(bad_reason)) {
    fail("not a reason (", paste(SPAM_REASONS, collapse = ", "), "): ", spam$reason[bad_reason][1])
  }
  spam
}

spam <- read_spam(spam_file)
message("Read ", nrow(spam), " flagged messages from ", spam_file)

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

# A lookup rather than merge(): merge() re-sorts the rows by the key and moves
# it to the first column, which changed both away from the documented layout.
#
# A list with a message whose identifier ends in "@hidden>" was written with
# addresses hidden, because its archive is members-only. The alias file is
# shared by all lists and knows nothing of that, so in such a list a canonical
# name that holds an address ("a@b.org", "a at b.org", "a AT b.org", with any
# whitespace around the word, as pull-archives.sh checks) is not applied: the
# name would bring back what was hidden, and each message keeps the name it
# came with. This is decided for the whole list (df holds one list), as a
# message without an identifier shows nothing of how it was written.
resolve_aliases <- function(df) {
  if (is.null(alias_lookup)) return(df)
  canonical <- alias_lookup$canonical_name[match(df$from_email_hash, alias_lookup$from_email_hash)]
  if (any(grepl("@hidden>$", df$message_id))) canonical[grepl("@|\\sat\\s", canonical, ignore.case = TRUE)] <- NA
  df$from_name <- ifelse(is.na(canonical), df$from_name, canonical)
  df
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
    # The message's own page at the source. The archive leaves the key out
    # when it has none, and always does for lists hosted on R-Forge. Kept as
    # the last column, and written for every list, so all files share a schema.
    source_url      = vapply(msgs, \(m) m$source_url %||% NA_character_, ""),
    # The pages the message's text was restored from, joined by one space. The
    # archive leaves the key out when nothing was restored.
    restored_from   = vapply(msgs, \(m) {
      urls <- unlist(m$restored_from)
      if (length(urls) == 0) NA_character_ else paste(urls, collapse = " ")
    }, ""),
    # Set once the rows of the list are read, from the spam file.
    spam            = FALSE,
    spam_reason     = NA_character_,
    stringsAsFactors = FALSE
  )
}

# A list is written in five-year chunks when the text of its messages passes
# MAX_TEXT_MB. Its file would then pass about 75 MB: zstd writes this mail at
# a fifth or so of the size of its text (4.8 to 6.8 times smaller, read from
# the published files on 2026-10-14, when R-help held about 890 MB of text
# and r-devel, the next largest list, about 180 MB). The text is measured
# before anything is written, so a large list is written once, in its chunks.
MAX_TEXT_MB <- local({
  value <- Sys.getenv("BUILD_PARQUET_MAX_TEXT_MB")
  limit <- if (nzchar(value)) suppressWarnings(as.numeric(value)) else 375
  if (is.na(limit) || limit <= 0) {
    stop("BUILD_PARQUET_MAX_TEXT_MB must be a positive number of MB, not \"", value, "\"",
         call. = FALSE)
  }
  limit
})

# The text of a data frame in MB: the bytes of all its character columns.
# Bytes rather than characters, NA as nothing, and summed as doubles, since a
# sum of integers stops at about 2 GB.
text_mb <- function(df) {
  chr <- vapply(df, is.character, logical(1))
  bytes <- vapply(df[chr], \(x) sum(as.numeric(nchar(x, type = "bytes")), na.rm = TRUE), numeric(1))
  sum(bytes) / 1e6
}

# Parse RFC 3339 date strings to POSIXct in UTC, correctly handling timezone offsets.
# R's as.POSIXct ignores offsets like -04:00 when using "%Y-%m-%dT%H:%M:%S",
# so we manually extract the offset and apply it.
parse_rfc3339_utc <- function(x) {
  # Extract sign, hours, minutes from offset (e.g. -04:00 or +01:00)
  offset_match <- regmatches(x, regexec("([+-])([0-9]{2}):([0-9]{2})$", x))
  has_offset <- vapply(offset_match, length, 0L) == 4

  offset_secs <- rep(0, length(x))
  base <- x

  # Handle +HH:MM / -HH:MM offsets
  if (any(has_offset)) {
    signs <- vapply(offset_match[has_offset], `[`, "", 2)
    hours <- as.integer(vapply(offset_match[has_offset], `[`, "", 3))
    mins  <- as.integer(vapply(offset_match[has_offset], `[`, "", 4))
    offset_secs[has_offset] <- ifelse(signs == "+", -1, 1) * (hours * 3600 + mins * 60)
    base[has_offset] <- sub("[+-][0-9]{2}:[0-9]{2}$", "", x[has_offset])
  }

  # Handle Z suffix (UTC, offset = 0)
  is_z <- grepl("Z$", base)
  base[is_z] <- sub("Z$", "", base[is_z])

  as.POSIXct(base, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC") + offset_secs
}

# Every file is written with zstd at level 9. Level 19 made the files a few
# percent smaller and took about twenty times as long to write.
ZSTD_LEVEL <- 9L

write_zstd <- function(df, path) {
  write_parquet(df, path, compression = "zstd",
                options = parquet_options(compression_level = ZSTD_LEVEL))
}

# Write a list as five-year chunks, <list>-<from>-<to>.parquet, on a grid of
# years that are multiples of five, leaving out ranges with no messages. A
# message whose date could not be read falls in no chunk.
split_large_parquet <- function(msgs, list_name, messages_dir) {
  msgs$year <- as.integer(format(msgs$date, "%Y"))
  year_range <- range(msgs$year, na.rm = TRUE)

  breaks <- seq(
    floor(year_range[1] / 5) * 5,
    ceiling((year_range[2] + 1) / 5) * 5,
    by = 5
  )

  paths <- character()
  for (i in seq_len(length(breaks) - 1)) {
    chunk <- msgs[!is.na(msgs$year) & msgs$year >= breaks[i] & msgs$year < breaks[i + 1], ]
    if (nrow(chunk) == 0) next
    chunk$year <- NULL
    label <- paste0(breaks[i], "-", breaks[i + 1] - 1)
    out <- file.path(messages_dir, paste0(list_name, "-", label, ".parquet"))
    write_zstd(chunk, out)
    mb <- round(file.size(out) / 1e6, 1)
    message("  -> ", out, " (", nrow(chunk), " messages, ", mb, " MB)")
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
# The names senders gave
# ---------------------------------------------------------------------------

list_dirs <- list.dirs(input_dir, full.names = TRUE, recursive = FALSE)
list_dirs <- list_dirs[!grepl("^_", basename(list_dirs))]

# How often each sender (email hash) used each name, over every list but one
# written with addresses hidden: a data frame of hash, name and n. A sender
# shown under an address in one list takes the name they gave in any list
# (scripts/sender-names.R), so every list is read for its names before any
# is written. A members-only list gives no names to the others.
read_sender_counts <- function(list_path) {
  json_files <- list.files(list_path, pattern = "^\\d{4}-\\d{2}\\.json$", full.names = TRUE)
  rows <- lapply(json_files, \(jf) {
    msgs <- fromJSON(jf, simplifyDataFrame = FALSE)$messages
    data.frame(hash = vapply(msgs, `[[`, "", "from_email_hash"), name = vapply(msgs, `[[`, "", "from_name"),
               hidden = vapply(msgs, \(m) endsWith(m$message_id %||% "", "@hidden>"), logical(1)),
               stringsAsFactors = FALSE)
  })
  rows <- do.call(rbind, rows)
  if (is.null(rows) || any(rows$hidden)) return(NULL)
  # The pairs that occur, counted: a table of every hash against every name
  # would be r-help's 30,000 senders by its 30,000 names, gigabytes of zeros.
  pair <- paste(rows$hash, rows$name, sep = "\r")
  first <- !duplicated(pair)
  data.frame(hash = rows$hash[first], name = rows$name[first],
             n = as.vector(table(factor(pair, levels = pair[first]))), stringsAsFactors = FALSE)
}

best_names <- best_sender_names(do.call(rbind, c(
  list(data.frame(hash = character(), name = character(), n = integer())),
  lapply(list_dirs, read_sender_counts))))
message("Read the names of ", length(best_names), " senders")
renames <- list()

# ---------------------------------------------------------------------------
# Process each list
# ---------------------------------------------------------------------------

all_threads <- list()
flagged_seen <- character()
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
  msgs$date <- parse_rfc3339_utc(msgs$date)
  msgs$thread_depth <- as.integer(msgs$thread_depth)

  # Resolve from_name via aliases (canonical names)
  msgs <- resolve_aliases(msgs)

  # A sender shown under an address takes the name they gave elsewhere, or
  # the address without its domain (scripts/sender-names.R).
  renamed <- is_address_name(msgs$from_name) | is_masked_name(msgs$from_name)
  if (any(renamed)) {
    new_names <- sender_names(msgs$from_name, msgs$from_email_hash, best_names)
    renames <- c(renames, list(data.frame(from = msgs$from_name[renamed], to = new_names[renamed],
                                          stringsAsFactors = FALSE)))
    msgs$from_name <- new_names
  }

  # Flag the messages the spam file names. Threads and contributors keep
  # counting them.
  list_spam <- spam$id[spam$list == list_name]
  msgs$spam <- msgs$id %in% list_spam
  msgs$spam_reason <- spam$reason[spam$list == list_name][match(msgs$id, list_spam)]
  flagged_seen <- c(flagged_seen, paste(list_name, msgs$id[msgs$spam]))

  # Fix the row order, with id breaking ties between messages sent in the same
  # second. These files are committed: an order that depends on how the input
  # happened to be listed rewrites them daily even when no mail has arrived.
  msgs <- msgs[order(msgs$date, msgs$id), ]
  rownames(msgs) <- NULL

  out_path <- file.path(messages_dir, paste0(list_name, ".parquet"))
  text_size <- text_mb(msgs)

  if (text_size > MAX_TEXT_MB) {
    message("  ** ", round(text_size, 1), " MB of text is over the ", MAX_TEXT_MB,
            " MB limit: writing five-year chunks")
    # Clear what an earlier run into this directory left for the list: its
    # whole file, and chunks cut on other intervals.
    unlink(out_path)
    old_splits <- list.files(messages_dir, pattern = paste0("^", list_name, "-\\d{4}"), full.names = TRUE)
    if (length(old_splits) > 0) {
      file.remove(old_splits)
      message("  Removed ", length(old_splits), " old split files")
    }
    split_large_parquet(msgs, list_name, messages_dir)
  } else {
    write_zstd(msgs, out_path)
    message("  -> ", out_path, " (", nrow(msgs), " messages, ", round(text_size, 1),
            " MB of text, ", round(file.size(out_path) / 1e6, 1), " MB)")
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

# A flag for a message that is not in the data is reported, not an error: the
# list may have been renamed, or the message not archived yet.
unknown <- spam[!paste(spam$list, spam$id) %in% flagged_seen, ]
for (i in seq_len(nrow(unknown))) {
  message("Spam file names no message: list ", unknown$list[i], ", id ", unknown$id[i])
}

# ---------------------------------------------------------------------------
# Write threads.parquet
# ---------------------------------------------------------------------------

if (length(all_threads) > 0) {
  threads_df <- do.call(rbind, all_threads)
  threads_df$started <- parse_rfc3339_utc(threads_df$started)
  threads_df$last_reply <- parse_rfc3339_utc(threads_df$last_reply)
  threads_df <- threads_df[order(threads_df$list, threads_df$started, threads_df$id), ]
  rownames(threads_df) <- NULL
  threads_path <- file.path(output_dir, "threads.parquet")
  write_zstd(threads_df, threads_path)
  message("Wrote ", threads_path, " (", nrow(threads_df), " threads, ",
          round(file.size(threads_path) / 1e6, 1), " MB)")
}

# ---------------------------------------------------------------------------
# Write contributors.parquet
# ---------------------------------------------------------------------------

contrib_path <- file.path(input_dir, "_contributors.json")
if (file.exists(contrib_path)) {
  contrib <- fromJSON(contrib_path, simplifyDataFrame = FALSE)
  # Each contributor's lists by message count, ties by name, so the two
  # comma-separated columns below do not depend on the order in the JSON.
  contrib <- lapply(contrib, \(x) {
    counts <- vapply(x$lists, `[[`, 0L, "count")
    slugs <- vapply(x$lists, `[[`, "", "slug")
    x$lists <- x$lists[order(-counts, slugs)]
    x
  })
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
  # Named as the messages were, so that a contributor's page finds them.
  contrib_df <- rename_contributors(contrib_df, do.call(rbind, c(
    list(data.frame(from = character(), to = character())), renames)))
  contrib_df <- contrib_df[order(-contrib_df$message_count, contrib_df$name,
                                 contrib_df$lists, contrib_df$first_message), ]
  rownames(contrib_df) <- NULL
  contrib_out <- file.path(output_dir, "contributors.parquet")
  write_zstd(contrib_df, contrib_out)
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
