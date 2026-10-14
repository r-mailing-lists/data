#!/usr/bin/env bash
#
# Pull each list's processed files from its archive repository into
# data/processed/<list>/.
#
# This was a step of update-data.yml. It is a script so that it can be tested
# (scripts/pull-archives.test.sh). A public repository that cannot be cloned
# is passed over, and its list is missing from that day's build.
#
# A list whose archive at the source is members-only (its base URL in
# lists.conf holds /mailman/private/) may be published only from files the
# parser wrote with every address hidden. That parser also writes every
# message identifier as <32 hex digits@hidden>, so the identifiers show which
# kind of files these are. When they are not all hidden, an error is printed
# and the script fails.
#
# That list's archive repository is private. It is read with a deploy key:
# when a repository cannot be cloned anonymously and ARCHIVE_DEPLOY_KEY is
# set, the clone is tried over SSH with that key. Without a key the list is
# passed over, and a line in the log says so. With a key, a repository that
# still cannot be cloned after three tries fails the script as well.
#
# The script fails rather than pass such a list over because of what comes
# after it: publish-parquet.sh deletes the published file of a list that is
# missing from a build. Failing stops the run before anything is built, the
# release stays as it was, and the next run tries again.
#
# usage: pull-archives.sh   (from the repository root: it reads
#                            scripts/lists.conf and writes under data/)
#   ARCHIVE_BASE         where the repositories are cloned from
#                        (default: https://github.com/r-mailing-lists)
#   ARCHIVE_DEPLOY_KEY   the private half of a deploy key of a private
#                        archive repository (default: none)
#   ARCHIVE_RETRY_PAUSE  seconds between the tries of a clone over SSH
#                        (default: 5)

set -euo pipefail

BASE="${ARCHIVE_BASE:-https://github.com/r-mailing-lists}"
PAUSE="${ARCHIVE_RETRY_PAUSE:-5}"

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

# With a deploy key, ssh is told to use that key and no other, and to talk
# only to the host that has the key GitHub publishes. The key goes into a
# file because ssh reads it from one. The file is removed when the script
# ends, however it ends, and nothing here prints the key.
key_file=""
if [ -n "${ARCHIVE_DEPLOY_KEY:-}" ]; then
  key_file="$(mktemp)"
  known_hosts="$(mktemp)"
  trap 'rm -f "$key_file" "$known_hosts"' EXIT
  chmod 600 "$key_file"
  printf '%s\n' "$ARCHIVE_DEPLOY_KEY" > "$key_file"
  echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" > "$known_hosts"
  # Exported, not set for the clone alone: a clone with --filter=blob:none
  # leaves the contents of the files to be fetched when they are checked out,
  # and that fetch goes over SSH as well.
  export GIT_SSH_COMMAND="ssh -i $key_file -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
fi

# clone REPO DIR TRIES -> the sparse clone of an archive repository in DIR.
# Every repository but one is public. The private one fails the anonymous
# clone, and when there is a deploy key it is tried over SSH, up to TRIES
# times with a pause in between.
clone() {
  local try
  git clone --depth 1 --filter=blob:none --sparse \
    "$BASE/$1.git" \
    "$2" 2>/dev/null && return
  [ -n "$key_file" ] || return 1
  for ((try = 1; try <= $3; try++)); do
    [ "$try" -gt 1 ] && sleep "$PAUSE"
    git clone --depth 1 --filter=blob:none --sparse \
      "git@github.com:r-mailing-lists/$1.git" \
      "$2" 2>/dev/null && return
  done
  return 1
}

# not_cloned -> what follows when the repository of the list being pulled
# cannot be cloned. A public list is passed over, as it always was. So is a
# members-only list while there is no deploy key, which is the state before
# the list is switched on. With a key its repository ought to be readable,
# and going on without the list would have the publisher delete its
# published file, so the run stops instead and the next one tries again.
not_cloned() {
  [ "$members_only" = true ] || return 0
  if [ -z "$key_file" ]; then
    echo "Skipping $name: a members-only list, and no deploy key is configured"
    return 0
  fi
  echo "::error::$name has a members-only archive and its repository could not be cloned with the deploy key, so nothing is built or published"
  exit 1
}

mkdir -p data/processed

while IFS=$'\t' read -r name url type desc repo; do
  [[ "$name" =~ ^#.*$ ]] && continue
  [ -z "$name" ] && continue
  echo "Pulling data for $name..."
  if [[ "$url" == */mailman/private/* ]]; then
    members_only=true; tries=3
  else
    members_only=false; tries=1
  fi
  if [ -n "$repo" ]; then
    # Pooled archive repo: one <list>/ directory per list, cloned once and reused
    pool="data/tmp-pool-$repo"
    if [ ! -d "$pool" ]; then
      clone "$repo" "$pool" "$tries" || { not_cloned; continue; }
      cd "$pool"
      git sparse-checkout init --no-cone
      git sparse-checkout set '/*/processed' '/*/meta.json' '/*/index.json' '/*/message-order.json' '/*/contributors.json'
      git checkout
      cd ../..
    fi
    src="$pool/$name"
  else
    src="data/tmp-$name"
    clone "$name" "$src" "$tries" || { not_cloned; continue; }
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
  # A members-only list stays only when its files have addresses hidden.
  # Going on without it would have the publisher delete its published file,
  # so the run stops here, before anything is built.
  if [ "$members_only" = true ] && ! hidden_only "data/processed/$name"; then
    rm -rf "data/processed/$name"
    echo "::error::$name has a members-only archive and its files were not written with addresses hidden, so nothing is built or published"
    exit 1
  fi
done < scripts/lists.conf
rm -rf data/tmp-pool-*
