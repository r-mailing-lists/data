#!/usr/bin/env Rscript

# The spam helper proposes; a person decides. It lists the messages that look
# like spam and are not in the spam file yet, strongest first, and it neither
# writes anything nor prints a whole address.
#
# Usage: Rscript tests/test-spam-candidates.R   (from the repository root)

library(nanoparquet)

fail <- function(...) {
  cat("FAIL:", ..., "\n")
  quit(status = 1)
}

msg_id <- function(i) sprintf("msg-%012x", i)

row <- function(i, hash, subject, body = "hello", thread = sprintf("thread-%03d", i),
                in_reply_to = NA_character_) {
  data.frame(
    list = "test-list", id = msg_id(i), from_email_hash = hash,
    date = as.POSIXct("2020-01-01 00:00:00", tz = "UTC") + i * 60,
    subject = subject, in_reply_to = in_reply_to, body = body, thread_id = thread,
    stringsAsFactors = FALSE
  )
}

dir <- tempfile("candidates")
dir.create(dir)
msgs <- rbind(
  row(1, "hash-one", "Win the lottery now"),
  row(2, "hash-two", "Hello", body = paste("Dear friend, a", "lottery", "prize")),
  row(3, "hash-three", "Re: lottery", in_reply_to = "<m001@example.org>"),
  row(4, "hash-busy", "Lottery winner"),
  row(5, "hash-busy", "Question"), row(6, "hash-busy", "Another question"),
  row(7, "hash-four", "Mail someone@example.org about a casino"),
  row(8, "hash-five", "A lottery question", thread = "thread-008"),
  row(9, "hash-six", "Answer", thread = "thread-008"),
  row(10, "hash-seven", "Ordinary", body = paste0(strrep("x ", 2000), "lottery")),
  row(11, "hash-eight", "Bioinformatics lotteryish"),
  row(12, "hash-nine", "Write to Jane.Doe AT uni.example.org about the casino")
)
# The first half of the fixture is one file and the rest another: a list may be
# split, and the sender count spans the files.
write_parquet(msgs[1:5, ], file.path(dir, "test-list.parquet"))
write_parquet(msgs[6:12, ], file.path(dir, "test-list-2020.parquet"))

script <- "scripts/spam-candidates.R"
run <- function(...) {
  out <- suppressWarnings(system2("Rscript", c(script, ...), stdout = TRUE, stderr = TRUE))
  list(out = out, status = attr(out, "status") %||% 0L)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

res <- run(dir)
if (res$status != 0) fail("the helper failed:", res$out)
out <- res$out
if (!identical(out[1], "strength\tlist\tid\tdate\tword\tsubject")) fail("header was", out[1])
rows <- strsplit(out[-1], "\t")
ids <- vapply(rows, `[`, "", 3)
strength <- vapply(rows, `[`, "", 1)

if (!identical(ids, c(msg_id(1), msg_id(7), msg_id(12), msg_id(2)))) fail("candidates were", ids)
if (!identical(strength, c("strong", "strong", "strong", "weaker"))) fail("strengths were", strength)
if (any(grepl("someone@example.org", out, fixed = TRUE))) fail("an address was printed")
if (!identical(rows[[2]][6], "Mail <address> about a casino")) fail("the address was not masked:", rows[[2]][6])
# An address written with "at", as archives that hid addresses wrote them.
if (any(grepl("uni.example.org", out, fixed = TRUE))) fail("an address written with 'at' was printed")
if (!identical(rows[[3]][6], "Write to <address> about the casino")) fail("the 'at' address was not masked:", rows[[3]][6])
if (!identical(rows[[1]][5], "lottery")) fail("word was", rows[[1]][5])
if (!identical(rows[[1]][4], "2020-01-01")) fail("date was", rows[[1]][4])

# A message already in the spam file is not proposed again.
spam <- tempfile(fileext = ".tsv")
writeLines(c("# confirmed", "list\tid\treason\tflagged", paste("test-list", msg_id(1), "lottery", "2026-10-19", sep = "\t")), spam)
res <- run(dir, spam)
if (res$status != 0) fail("the helper failed with a spam file:", res$out)
if (any(grepl(msg_id(1), res$out, fixed = TRUE))) fail("a flagged message was proposed")
if (!any(grepl(msg_id(2), res$out, fixed = TRUE))) fail("the others were lost")

# It writes nothing.
if (!identical(sort(list.files(dir)), c("test-list-2020.parquet", "test-list.parquet"))) fail("it wrote into the directory")

cat("OK: spam candidates\n")
