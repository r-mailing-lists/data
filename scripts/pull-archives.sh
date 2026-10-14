#!/usr/bin/env bash
#
# Pull each list's processed files from its archive repository into
# data/processed/<list>/.
#
# This was a step of update-data.yml. It is a script so that it can be tested
# (scripts/pull-archives.test.sh). A repository that cannot be cloned is
# passed over, and its list is missing from that day's build.
#
# A list whose archive at the source is members-only (its base URL in
# lists.conf holds /mailman/private/) may be published only from files the
# parser wrote with every address hidden. That parser also writes every
# message identifier as <32 hex digits@hidden>, so the identifiers show which
# kind of files these are. When they are not all hidden the list is left out,
# an error is printed and data/.archive-guard-failed is left behind. The
# script still succeeds, so the other lists are published, and the last step
# of the workflow fails the run on that file.
#
# usage: pull-archives.sh   (from the repository root: it reads
#                            scripts/lists.conf and writes under data/)
#   ARCHIVE_BASE  where the repositories are cloned from
#                 (default: https://github.com/r-mailing-lists)

set -euo pipefail

BASE="${ARCHIVE_BASE:-https://github.com/r-mailing-lists}"
MARKER="data/.archive-guard-failed"

# hidden_only DIR -> true when every message of every month file in DIR has
# no identifier or a hidden one. The month files are the ones build-parquet.R
# makes rows of. A file that is not one JSON document with a list of messages
# counts as not hidden: what cannot be checked is not published.
hidden_only() {
  local month
  for month in "$1"/[0-9][0-9][0-9][0-9]-[0-9][0-9].json; do
    [ -e "$month" ] || continue
    jq -e -s 'length == 1 and all(.[0].messages[]; (.message_id // "") | . == "" or test("^<[0-9a-f]{32}@hidden>$"))' \
      "$month" >/dev/null 2>&1 || return 1
  done
}

mkdir -p data/processed

while IFS=$'\t' read -r name url type desc repo; do
  [[ "$name" =~ ^#.*$ ]] && continue
  [ -z "$name" ] && continue
  echo "Pulling data for $name..."
  if [ -n "$repo" ]; then
    # Pooled archive repo: one <list>/ directory per list, cloned once and reused
    pool="data/tmp-pool-$repo"
    if [ ! -d "$pool" ]; then
      git clone --depth 1 --filter=blob:none --sparse \
        "$BASE/$repo.git" \
        "$pool" 2>/dev/null || continue
      cd "$pool"
      git sparse-checkout init --no-cone
      git sparse-checkout set '/*/processed' '/*/meta.json' '/*/index.json' '/*/message-order.json' '/*/contributors.json'
      git checkout
      cd ../..
    fi
    src="$pool/$name"
  else
    src="data/tmp-$name"
    git clone --depth 1 --filter=blob:none --sparse \
      "$BASE/$name.git" \
      "$src" 2>/dev/null || continue
    cd "$src"
    git sparse-checkout init --no-cone
    git sparse-checkout set /processed /meta.json /index.json /message-order.json /contributors.json
    git checkout
    cd ../..
  fi
  if [ -d "$src/processed" ]; then
    mv "$src/processed" "data/processed/$name"
  fi
  for f in meta.json index.json message-order.json contributors.json; do
    if [ -f "$src/$f" ]; then
      mkdir -p "data/processed/$name"
      cp "$src/$f" "data/processed/$name/$f"
    fi
  done
  if [ -z "$repo" ]; then
    rm -rf "$src"
  fi
  # A members-only list stays only when its files have addresses hidden. The
  # others are still wanted, so this is reported and the loop goes on.
  if [[ "$url" == */mailman/private/* ]] && ! hidden_only "data/processed/$name"; then
    rm -rf "data/processed/$name"
    echo "::error::$name has a members-only archive and its files were not written with addresses hidden, so it is left out of this build"
    echo "$name" >> "$MARKER"
  fi
done < scripts/lists.conf
rm -rf data/tmp-pool-*
