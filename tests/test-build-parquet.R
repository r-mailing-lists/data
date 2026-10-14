#!/usr/bin/env Rscript

# Building the same messages twice must write byte-identical Parquet files,
# whatever order the archive JSON happens to list them in.
#
# The files are committed, so an unstable row order rewrites every large file
# daily even when no mail arrived, and makes every downstream "nothing
# changed, skip" check useless.
#
# Usage: Rscript tests/test-build-parquet.R   (from the repository root)

library(jsonlite)
library(nanoparquet)

# The archive leaves source_url out of a message it has no source page for.
# Here, as there, every third message goes without one.
source_page <- function(i) sprintf("https://stat.ethz.ch/pipermail/test-list/2020-January/%06d.html", i)

# A list whose archive is members-only is written with addresses hidden, and
# then its identifiers are opaque codes. A message that had none has none.
message_entry <- function(i, date, hash, linked, written = "raw") {
  entry <- list(
    id = sprintf("msg-%03d", i),
    message_id = switch(written, raw = sprintf("<m%03d@example.com>", i),
                        hidden = sprintf("<%032x@hidden>", i), none = ""),
    from_name = paste("Sender", hash), from_email_hash = hash, date = date,
    subject = paste("topic", i), subject_clean = paste("topic", i),
    body_plain = paste("body", i), body_snippet = paste("body", i),
    thread_id = sprintf("thread-%03d", i), thread_depth = 0L, month = substr(date, 1, 7)
  )
  if (linked && i %% 3 != 0) entry$source_url <- source_page(i)
  entry
}

thread_entry <- function(i, date) {
  list(
    id = sprintf("thread-%03d", i), subject = paste("topic", i), message_count = 1L,
    started = date, last_reply = date, root_message_id = sprintf("msg-%03d", i)
  )
}

# One month of one list. Within a month every message is sent in the same
# second, alternating between two senders unless told who sent what, so both
# the date and the sender tie. `written` says how each identifier is written.
month_archive <- function(list_name, month, ids, linked,
                          senders = ifelse(ids %% 2 == 0, "hash-a", "hash-b"), written = "raw") {
  date <- paste0(month, "-15T12:00:00Z")
  list(
    list = list_name, month = month,
    messages = unname(Map(\(i, hash, how) message_entry(i, date, hash, linked, how), ids, senders, written)),
    threads = lapply(ids, \(i) thread_entry(i, date))
  )
}

# The alias file gives hash-a a plain canonical name, hash-b none, and hash-c,
# hash-d and hash-e names that hold an address, written three ways: the last
# with the word in capitals and tabs around it.
alias_groups <- list(
  list(canonical_name = "Canonical A", email_hashes = list("hash-a")),
  list(canonical_name = "carol@example.org", email_hashes = list("hash-c")),
  list(canonical_name = "dave at example.org", email_hashes = list("hash-d")),
  list(canonical_name = "erin\tAT\texample.org", email_hashes = list("hash-e"))
)
alias_senders <- c("hash-a", "hash-b", "hash-c", "hash-d", "hash-e")

contributors <- list(
  list(name = "Sender hash-a", messageCount = 6L, firstDate = "2020-01-15T12:00:00Z",
       lastDate = "2020-02-15T12:00:00Z",
       lists = list(list(slug = "test-list", count = 3L), list(slug = "other-list", count = 3L))),
  list(name = "Sender hash-b", messageCount = 6L, firstDate = "2020-01-15T12:00:00Z",
       lastDate = "2020-02-15T12:00:00Z",
       lists = list(list(slug = "other-list", count = 3L), list(slug = "test-list", count = 3L)))
)

# Write the fixture, optionally with every list of entries reversed. test-list
# has source pages for most of its messages; forge-list, like every list hosted
# on R-Forge, has none. open-list and hidden-list each have one message from
# each of the five senders, and differ only in how their identifiers are
# written. hidden-list also has a sixth message, from hash-c, with no
# identifier at all.
write_fixture <- function(dir, reversed) {
  flip <- if (reversed) rev else identity
  lists <- list(
    "test-list" = list("2020-01" = month_archive("test-list", "2020-01", 1:6, linked = TRUE),
                       "2020-02" = month_archive("test-list", "2020-02", 7:12, linked = TRUE)),
    "forge-list" = list("2020-01" = month_archive("forge-list", "2020-01", 13:15, linked = FALSE)),
    "open-list" = list("2020-01" = month_archive("open-list", "2020-01", 16:20, linked = FALSE,
                                                 senders = alias_senders)),
    "hidden-list" = list("2020-01" = month_archive("hidden-list", "2020-01", 21:26, linked = FALSE,
                                                   senders = c(alias_senders, "hash-c"),
                                                   written = c(rep("hidden", 5), "none")))
  )
  for (list_name in names(lists)) {
    list_dir <- file.path(dir, list_name)
    dir.create(list_dir, recursive = TRUE)
    for (month in names(lists[[list_name]])) {
      archive <- lists[[list_name]][[month]]
      archive$messages <- flip(archive$messages)
      archive$threads <- flip(archive$threads)
      write_json(archive, file.path(list_dir, paste0(month, ".json")), auto_unbox = TRUE)
    }
  }
  people <- lapply(flip(contributors), \(p) { p$lists <- flip(p$lists); p })
  write_json(people, file.path(dir, "_contributors.json"), auto_unbox = TRUE)
}

build <- function(reversed) {
  root <- tempfile("build-parquet-test-")
  input <- file.path(root, "processed")
  output <- file.path(root, "out")
  write_fixture(input, reversed)
  aliases <- file.path(root, "aliases.json")
  write_json(list(aliases = alias_groups), aliases, auto_unbox = TRUE)
  status <- system2(file.path(R.home("bin"), "Rscript"),
                    c("scripts/build-parquet.R", input, output, aliases),
                    stdout = FALSE, stderr = FALSE)
  stopifnot("build-parquet.R failed" = status == 0)
  output
}

forward <- build(reversed = FALSE)
backward <- build(reversed = TRUE)

check <- function(description, ok) {
  cat(if (ok) "PASS  " else "FAIL  ", description, "\n", sep = "")
  ok
}

files <- c("messages/test-list.parquet", "messages/forge-list.parquet", "threads.parquet", "contributors.parquet")
msgs <- as.data.frame(read_parquet(file.path(forward, "messages", "test-list.parquet")))
forge_path <- file.path(forward, "messages", "forge-list.parquet")
forge <- as.data.frame(read_parquet(forge_path))
forge_schema <- read_parquet_schema(forge_path)
open <- as.data.frame(read_parquet(file.path(forward, "messages", "open-list.parquet")))
hidden <- as.data.frame(read_parquet(file.path(forward, "messages", "hidden-list.parquet")))
script <- readLines("scripts/build-parquet.R")
built <- list.files(forward, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)

results <- c(
  vapply(files, \(file) {
    check(paste(file, "is byte-identical whatever order the input is in"),
          unname(tools::md5sum(file.path(forward, file)) == tools::md5sum(file.path(backward, file))))
  }, logical(1)),
  check("messages are ordered by date, then id",
        identical(msgs$id, sprintf("msg-%03d", 1:12))),
  check("message columns are in the documented order",
        identical(names(msgs), c("list", "id", "message_id", "from_name", "from_email_hash", "date",
                                 "subject", "in_reply_to", "body", "body_snippet", "thread_id",
                                 "thread_depth", "month", "source_url"))),
  check("source_url is carried for the messages that have one and is NA for the rest",
        identical(msgs$source_url, ifelse(1:12 %% 3 != 0, source_page(1:12), NA_character_))),
  check("a list with no source pages has the same columns as one with them",
        identical(names(forge), names(msgs))),
  check("and its source_url column is text, every value NA",
        is.character(forge$source_url) && all(is.na(forge$source_url)) &&
          identical(forge_schema$type[forge_schema$name == "source_url"], "BYTE_ARRAY")),
  check("threads.parquet and contributors.parquet keep their columns",
        identical(names(read_parquet(file.path(forward, "threads.parquet"))),
                  c("list", "id", "subject", "message_count", "started", "last_reply", "root_message_id")) &&
          identical(names(read_parquet(file.path(forward, "contributors.parquet"))),
                    c("name", "message_count", "list_count", "lists", "list_counts",
                      "first_message", "last_message"))),
  check("aliases still resolve to the canonical name",
        all(msgs$from_name[msgs$from_email_hash == "hash-a"] == "Canonical A") &&
          all(msgs$from_name[msgs$from_email_hash == "hash-b"] == "Sender hash-b")),
  check("also to a canonical name that holds an address, where identifiers are raw",
        identical(open$from_name,
                  c("Canonical A", "Sender hash-b", "carol@example.org", "dave at example.org",
                    "erin\tAT\texample.org"))),
  check("but in a list with hidden identifiers every message keeps its own name instead of such a one",
        identical(hidden$from_name,
                  c("Canonical A", "Sender hash-b", "Sender hash-c", "Sender hash-d", "Sender hash-e",
                    "Sender hash-c"))),
  check("every file the build writes is compressed with zstd",
        length(built) > 0 &&
          all(vapply(built, \(f) all(read_parquet_metadata(f)$column_chunks$codec == "ZSTD"), logical(1)))),
  check("at level 9, by the one helper that writes every file",
        sum(grepl("write_parquet(", script, fixed = TRUE)) == 1 &&
          sum(grepl("^ZSTD_LEVEL <- 9L$", script)) == 1 &&
          sum(grepl("compression_level = ZSTD_LEVEL", script, fixed = TRUE)) == 1)
)

cat("\n", sum(results), " passed, ", sum(!results), " failed\n", sep = "")
quit(status = if (all(results)) 0 else 1)
