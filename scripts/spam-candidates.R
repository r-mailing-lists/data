#!/usr/bin/env Rscript

# Propose messages for a person to confirm as spam. Nothing is flagged here:
# the helper reads the published Parquet files and prints, and a person adds
# the messages they confirm to scripts/spam.tsv.
#
# A candidate is a message that
#   - has a spam word in its subject (strong) or in the first 3,000
#     characters of its body (weaker),
#   - comes from a sender with at most two messages in all the files,
#   - sits alone in its thread, and is not a reply,
#   - is not in the spam file already.
#
# Usage: Rscript scripts/spam-candidates.R <messages_dir> [spam.tsv]
#   messages_dir: the directory of list Parquet files (every *.parquet is read)
#   spam.tsv:     the messages already confirmed (default: scripts/spam.tsv)
#
# Output is tab-separated: strength, list, id, date, word, subject. An address
# in a subject is printed as <address>, whether it is written with "@" or, as
# archives that hid addresses wrote it, with "at" (jane.doe at uni.example.org).
# The second form also takes in a phrase such as "look at data.frame": the
# subject is only for a person to read, and hiding too much is the safe side.

library(nanoparquet)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript scripts/spam-candidates.R <messages_dir> [spam.tsv]", call. = FALSE)
}
messages_dir <- args[1]
spam_file <- if (length(args) >= 2) args[2] else "scripts/spam.tsv"

BODY_CHARS <- 3000
MAX_SENDER_MESSAGES <- 2
SUBJECT_CHARS <- 90

# Whole words, case-insensitive. The stems (refinanc,
# enlarg) also match their endings: refinance, refinancing, enlargement.
WORDS <- c(
  "viagra", "cialis", "levitra", "pharmacy", "pharmaceutical", "replica watch",
  "rolex", "casino", "poker", "lottery", "jackpot", "payday loan", "loan offer",
  "cash loan", "mortgage", "refinanc", "porn", "xxx", "sex", "dating",
  "weight loss", "diet pill", "enlarg", "work from home", "make money",
  "bitcoin", "crypto", "forex", "seo services", "backlinks", "essay writing",
  "buy cheap", "discount", "cheap meds", "inheritance", "beneficiary",
  "next of kin", "wire transfer", "western union", "bank account"
)
STEMS <- c("refinanc", "enlarg")
word_pattern <- function(word) {
  paste0("\\b", gsub(" ", "\\\\s+", word), if (word %in% STEMS) "\\w*" else "\\b")
}
PATTERNS <- vapply(WORDS, word_pattern, "")

# The first spam word found in each text, or NA. Words are tried in order.
first_word <- function(text) {
  found <- rep(NA_character_, length(text))
  text[is.na(text)] <- ""
  for (i in seq_along(WORDS)) {
    todo <- is.na(found)
    if (!any(todo)) break
    hit <- grepl(PATTERNS[i], text[todo], ignore.case = TRUE, perl = TRUE)
    found[which(todo)[hit]] <- WORDS[i]
  }
  found
}

# What a person sees of a subject: one line, no address, not too long.
show_subject <- function(subject) {
  subject[is.na(subject)] <- ""
  subject <- gsub("[[:alnum:]._%+-]+@[[:alnum:].-]+", "<address>", subject)
  subject <- gsub("\\S+\\s+at\\s+\\S+\\.[A-Za-z]{2,}", "<address>", subject,
                  ignore.case = TRUE, perl = TRUE)
  subject <- gsub("[[:space:]]+", " ", subject)
  too_long <- nchar(subject) > SUBJECT_CHARS
  subject[too_long] <- paste0(substr(subject[too_long], 1, SUBJECT_CHARS - 3), "...")
  trimws(subject)
}

# The messages already confirmed, as "list id". The format is that of
# scripts/spam.tsv: lines starting with # are comments, then a header.
read_flagged <- function(path) {
  if (!file.exists(path)) return(character())
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines)) & !startsWith(lines, "#")]
  if (length(lines) <= 1) return(character())
  fields <- strsplit(lines[-1], "\t", fixed = TRUE)
  vapply(fields, \(f) paste(f[1], f[2]), "")
}

files <- sort(list.files(messages_dir, pattern = "\\.parquet$", full.names = TRUE))
if (length(files) == 0) stop("no Parquet files in ", messages_dir, call. = FALSE)

# Only the columns needed, and only the start of each body: the text of all
# the lists is far larger than what is needed to propose candidates.
columns <- c("list", "id", "thread_id", "from_email_hash", "in_reply_to", "subject", "body", "date")
frames <- lapply(files, \(f) {
  d <- read_parquet(f, col_select = columns)
  d$body <- substr(d$body, 1, BODY_CHARS)
  d
})
msgs <- do.call(rbind, frames)
rm(frames)

sender_total <- table(msgs$from_email_hash)
thread_key <- paste(msgs$list, msgs$thread_id)
thread_total <- table(thread_key)

quiet <- !is.na(msgs$from_email_hash) &
  as.vector(sender_total[msgs$from_email_hash]) <= MAX_SENDER_MESSAGES &
  as.vector(thread_total[thread_key]) == 1 &
  is.na(msgs$in_reply_to) &
  !(paste(msgs$list, msgs$id) %in% read_flagged(spam_file))
msgs <- msgs[quiet, ]

subject_word <- first_word(msgs$subject)
body_word <- first_word(msgs$body)
msgs$strength <- ifelse(!is.na(subject_word), "strong", "weaker")
msgs$word <- ifelse(!is.na(subject_word), subject_word, body_word)
msgs <- msgs[!is.na(msgs$word), ]
msgs <- msgs[order(msgs$strength != "strong", msgs$date, msgs$id), ]

cat("strength\tlist\tid\tdate\tword\tsubject\n")
if (nrow(msgs) > 0) {
  cat(paste(msgs$strength, msgs$list, msgs$id, format(msgs$date, "%Y-%m-%d", tz = "UTC"),
            msgs$word, show_subject(msgs$subject), sep = "\t"), sep = "\n")
}
