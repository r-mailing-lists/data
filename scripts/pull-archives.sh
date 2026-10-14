#!/usr/bin/env bash
#
# Pull each list's processed files from its archive repository into
# data/processed/<list>/.
#
# This was a step of update-data.yml. It is a script so that it can be tested
# (scripts/pull-archives.test.sh). A repository that cannot be cloned is
# passed over, and its list is missing from that day's build.
#
# usage: pull-archives.sh   (from the repository root: it reads
#                            scripts/lists.conf and writes under data/)
#   ARCHIVE_BASE  where the repositories are cloned from
#                 (default: https://github.com/r-mailing-lists)

set -euo pipefail

BASE="${ARCHIVE_BASE:-https://github.com/r-mailing-lists}"

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
done < scripts/lists.conf
rm -rf data/tmp-pool-*
