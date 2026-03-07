# Helper functions for reading R mailing list parquet data from GitHub
# https://github.com/r-mailing-lists/data
#
# Usage:
#   source("https://raw.githubusercontent.com/r-mailing-lists/data/main/scripts/rml.R")
#   rml_available()
#   msgs <- rml_read("r-devel")

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

#' List available mailing list names
rml_available <- function() {
  index <- .rml_file_index()
  files <- sub("\\.parquet$", "", index$name)
  sort(unique(sub("-\\d{4}-\\d{4}$", "", files)))
}

#' Download and read a mailing list into a data frame
#'
#' @param list_name Name of the list (e.g. "r-devel"). See rml_available().
#' @param col_select Character vector of columns to read, or NULL for all.
#'   Omitting "body" speeds up loading significantly.
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

#' Download and read thread summaries
rml_read_threads <- function(col_select = NULL) {
  dest <- file.path(.rml_ensure_cache(), "threads.parquet")
  .rml_download(paste0(.rml_base_url, "/threads.parquet"), dest)
  nanoparquet::read_parquet(dest, col_select = col_select)
}

#' Download and read contributor statistics
rml_read_contributors <- function(col_select = NULL) {
  dest <- file.path(.rml_ensure_cache(), "contributors.parquet")
  .rml_download(paste0(.rml_base_url, "/contributors.parquet"), dest)
  nanoparquet::read_parquet(dest, col_select = col_select)
}
