# Sender names that are email addresses.
#
# A sender who gave no display name is shown by the archives under the
# address itself: "jane.doe at uni.example.org" as Mailman writes it, or
# "jane.doe@uni.example.org" whole. The data and the site then publish the
# address as the person's name, in every message and on a contributor page
# named after it. So each such name is replaced: by a name the same sender
# (the same email hash) gave on other messages, the one they used most, or
# else by the address with its domain left off ("jane.doe"). A name that
# holds an address beside other words ("Jane Doe <jane@example.org>") keeps
# the other words.
#
# Google Groups shows such a sender masked ("ja...@gmail.com"), which is no
# address. It takes the sender's own name in the same way, and is otherwise
# left as it is: cut to "ja..." it would be one name for many people.
#
# Sourced by scripts/build-parquet.R.

# An address: a local part, "@" or the word "at" (any case) with whitespace
# around it, and a domain of at least two labels. A local part that ends in
# "..." is Google's mask, MASKED_PATTERN.
ADDRESS_PATTERN <- "[[:alnum:]._%+-]+(?<!\\.\\.\\.)(@|[[:space:]]+[Aa][Tt][[:space:]]+)[[:alnum:]-]+(\\.[[:alnum:]-]+)+"
MASKED_PATTERN <- "[[:alnum:]._%+-]*\\.\\.\\.@[[:alnum:]-]+(\\.[[:alnum:]-]+)+"

is_address_name <- function(names) grepl(ADDRESS_PATTERN, names, perl = TRUE)
is_masked_name <- function(names) grepl(MASKED_PATTERN, names, perl = TRUE)

# The name without its addresses: an address and the brackets or quotes
# around it are cut, and what is left is trimmed of spaces and stray
# punctuation. A name that was nothing but an address becomes that address's
# local part.
name_without_address <- function(names) {
  out <- names
  hit <- is_address_name(names)
  if (!any(hit)) return(out)
  first <- regmatches(names[hit], regexpr(ADDRESS_PATTERN, names[hit], perl = TRUE))
  local <- sub("(@|[[:space:]]+[Aa][Tt][[:space:]]+).*$", "", first, perl = TRUE)
  rest <- gsub(paste0("[<(\\[\"']*", ADDRESS_PATTERN, "[>)\\]\"']*"), " ", names[hit], perl = TRUE)
  rest <- gsub("[[:space:]]+", " ", rest, perl = TRUE)
  # "jane at example.org (Jane Doe)" leaves "(Jane Doe)": the name in its brackets.
  rest <- sub("^ ?[(<\\[\"'](.*)[)>\\]\"'] ?$", "\\1", rest, perl = TRUE)
  rest <- gsub("^[[:space:][:punct:]]+|[[:space:],;:|/-]+$", "", rest, perl = TRUE)
  out[hit] <- ifelse(nzchar(rest), rest, local)
  out
}

# The name each sender used most, among the names that are not addresses:
# a character vector named by email hash. Ties go to the name that sorts
# first, so the answer does not depend on the order of the messages.
# `counts` is a data frame with columns hash, name and n.
best_sender_names <- function(counts) {
  counts <- counts[nzchar(counts$hash) & nzchar(counts$name) & !is_address_name(counts$name) &
                     !is_masked_name(counts$name), , drop = FALSE]
  if (nrow(counts) == 0) return(character())
  pair <- paste(counts$hash, counts$name, sep = "\r")
  first <- !duplicated(pair)
  totals <- data.frame(hash = counts$hash[first], name = counts$name[first],
                       n = as.vector(tapply(counts$n, factor(pair, levels = pair[first]), sum)),
                       stringsAsFactors = FALSE)
  totals <- totals[order(totals$hash, -totals$n, totals$name), ]
  best <- totals[!duplicated(totals$hash), ]
  setNames(best$name, best$hash)
}

# The names of messages as they are published: an address or masked name is
# replaced by the sender's own name from `best` (best_sender_names()) when
# there is one; an address name is otherwise left without its address, and a
# masked one as it is.
sender_names <- function(names, hashes, best) {
  hit <- is_address_name(names) | is_masked_name(names)
  if (!any(hit)) return(names)
  known <- unname(best[hashes[hit]])
  names[hit] <- ifelse(is.na(known), name_without_address(names[hit]), known)
  names
}

# The contributors table with the same names the messages were given.
# `renames` has columns from and to, one row per message renamed; a
# contributor named after an address, or masked, takes the name its messages
# took most, or else what name_without_address() makes of it. Contributors
# who end up with the
# same name are one row: their counts per list are added up, and their
# first and last messages are the earliest and latest of them.
rename_contributors <- function(contrib, renames) {
  hit <- is_address_name(contrib$name) | is_masked_name(contrib$name)
  if (!any(hit)) return(contrib)
  to <- character()
  if (nrow(renames) > 0) {
    totals <- aggregate(n ~ from + to, data = transform(renames, n = 1L), FUN = sum)
    totals <- totals[order(totals$from, -totals$n, totals$to), ]
    totals <- totals[!duplicated(totals$from), ]
    to <- setNames(totals$to, totals$from)
  }
  known <- unname(to[contrib$name[hit]])
  contrib$name[hit] <- ifelse(is.na(known), name_without_address(contrib$name[hit]), known)

  merged <- lapply(split(contrib, contrib$name), \(rows) {
    if (nrow(rows) == 1) return(rows)
    pairs <- unlist(strsplit(rows$list_counts[nzchar(rows$list_counts)], ",", fixed = TRUE))
    counts <- tapply(as.integer(sub(".*:", "", pairs)), sub(":[^:]*$", "", pairs), sum)
    counts <- counts[order(-counts, names(counts))]
    data.frame(
      name          = rows$name[1],
      message_count = sum(rows$message_count),
      list_count    = length(counts),
      lists         = paste(names(counts), collapse = ","),
      list_counts   = paste(paste0(names(counts), ":", counts), collapse = ","),
      first_message = if (all(is.na(rows$first_message))) NA_character_ else min(rows$first_message, na.rm = TRUE),
      last_message  = if (all(is.na(rows$last_message))) NA_character_ else max(rows$last_message, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, merged)
  rownames(out) <- NULL
  out
}
