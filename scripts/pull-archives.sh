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
# set, it is tried over SSH with that key. Without a key the list is passed
# over, and a line in the log says so. With a key the script fails as well
# when, after three tries, the repository still cannot be cloned or its files
# cannot be checked out, and when it brings no month file at all.
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
#   ARCHIVE_RETRY_PAUSE  seconds before the second try over SSH, twice as
#                        many before the third (default: 30)

set -euo pipefail

# No clone may wait for a password: the anonymous clone of a private
# repository would ask for one.
export GIT_TERMINAL_PROMPT=0

BASE="${ARCHIVE_BASE:-https://github.com/r-mailing-lists}"
PAUSE="${ARCHIVE_RETRY_PAUSE:-30}"

# The month files of a list: the ones build-parquet.R makes rows of.
MONTHS='[0-9][0-9][0-9][0-9]-[0-9][0-9].json'

# hidden_only DIR -> true when every message of every month file in DIR has
# no identifier or a hidden one. A hidden identifier is one code, or several
# one blank apart where the value held several, and the pattern holds the
# whole value: \A and \z, where $ would let a newline after it through. A
# file that is not one JSON document with a list of messages counts as not
# hidden: what cannot be checked is not published.
hidden_only() {
  local month
  for month in "$1"/$MONTHS; do
    [ -e "$month" ] || continue
    jq -e -s 'length == 1 and all(.[0].messages[]; (.message_id // "") | . == "" or test("\\A<[0-9a-f]{32}@hidden>( <[0-9a-f]{32}@hidden>)*\\z"))' \
      "$month" >/dev/null 2>&1 || return 1
  done
}

# names_hidden FILE -> true when FILE, a list's contributors.json, is one
# JSON array and no name in it holds an address: an "@", or the word "at"
# between blanks in any case. rmail-parser aggregate builds
# contributors.parquet from these files, and a parse that did not hide
# addresses can leave one with names like "jane.doe at uni.example.org"
# beside month files that did.
names_hidden() {
  jq -e -s 'length == 1 and (.[0] | type == "array") and all(.[0][]; (.name // "") | test("@| at "; "i") | not)' \
    "$1" >/dev/null 2>&1
}

# With a deploy key, ssh is told to use that key and no other, to talk only
# to the host that has the key GitHub publishes, never to ask anything, and
# to give up on a host it cannot reach within 20 seconds. The key goes into a
# file because ssh reads it from one. The file is removed when the script
# ends, however it ends, and nothing here prints the key: ssh and git name
# the file in their messages, not what is in it.
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
  export GIT_SSH_COMMAND="ssh -i $key_file -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$known_hosts"
fi

# sparse DIR PATTERN... -> check out, in the clone in DIR, the files the build
# takes and no others. The clone was made with --filter=blob:none, so this is
# also where the contents of those files are fetched.
sparse() {
  local dir="$1"; shift
  (cd "$dir" && git sparse-checkout init --no-cone && git sparse-checkout set "$@" && git checkout)
}

# fetch REPO DIR TRIES PATTERN... -> the sparse clone of an archive repository
# in DIR, with the files of PATTERN checked out. Every repository but one is
# public. The private one fails the anonymous clone, and when there is a
# deploy key it is tried over SSH, up to TRIES times, PAUSE seconds before
# the second try and twice that before the third. A try is the clone and the
# checkout together, as either can fail when the host is out of reach. What
# git and ssh say about a failed try goes to the log. Returns 1 when the
# repository cannot be cloned and 2 when it was cloned and its files cannot
# be checked out.
fetch() {
  local repo="$1" dir="$2" tries="$3" try status=1; shift 3
  if git clone --depth 1 --filter=blob:none --sparse \
    "$BASE/$repo.git" \
    "$dir" 2>/dev/null; then
    sparse "$dir" "$@" || return 2
    return 0
  fi
  [ -n "$key_file" ] || return 1
  for ((try = 1; try <= tries; try++)); do
    [ "$try" -gt 1 ] && sleep $((PAUSE * (try - 1)))
    if git clone --depth 1 --filter=blob:none --sparse \
      "git@github.com:r-mailing-lists/$repo.git" \
      "$dir"; then
      sparse "$dir" "$@" && return 0
      status=2
      rm -rf "$dir"
    fi
  done
  return "$status"
}

# stop REASON -> end the run because of the members-only list being pulled.
# Going on without the list would have the publisher delete its published
# file. Failing here stops the run before anything is built, the release
# stays as it was, and the next run tries again.
stop() {
  echo "::error::$name has a members-only archive and $1, so nothing is built or published"
  exit 1
}

# not_fetched STATUS -> what follows when fetch fails for the list being
# pulled. A public list that cannot be cloned is passed over, as it always
# was, and one that cannot be checked out fails the run, as it always did. A
# members-only list is passed over only while there is no deploy key, which
# is the state before the list is switched on.
not_fetched() {
  if [ "$members_only" != true ]; then
    [ "$1" = 1 ] || exit 1
    return 0
  fi
  [ "$1" = 1 ] || stop "its files could not be checked out of its repository"
  if [ -z "$key_file" ]; then
    echo "Skipping $name: a members-only list, and no deploy key is configured"
    return 0
  fi
  stop "its repository could not be cloned with the deploy key"
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
      fetch "$repo" "$pool" "$tries" '/*/processed' '/*/meta.json' '/*/index.json' '/*/message-order.json' '/*/contributors.json' \
        || { not_fetched $?; continue; }
    fi
    src="$pool/$name"
  else
    src="data/tmp-$name"
    fetch "$name" "$src" "$tries" /processed /meta.json /index.json /message-order.json /contributors.json \
      || { not_fetched $?; continue; }
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
  if [ "$members_only" = true ]; then
    # A members-only list stays only when its files have addresses hidden.
    if ! hidden_only "data/processed/$name"; then
      rm -rf "data/processed/$name"
      stop "its files were not written with addresses hidden"
    fi
    # Once it is switched on it must also bring something to build. With no
    # month file it would be missing from the build like a list passed over.
    if [ -n "$key_file" ] && ! compgen -G "data/processed/$name/$MONTHS" > /dev/null; then
      rm -rf "data/processed/$name"
      stop "its repository holds no month file"
    fi
    if [ -n "$key_file" ] && ! names_hidden "data/processed/$name/contributors.json"; then
      rm -rf "data/processed/$name"
      stop "its contributors.json is missing, is not one JSON array, or has a name that holds an address"
    fi
  fi
done < scripts/lists.conf
rm -rf data/tmp-pool-*
