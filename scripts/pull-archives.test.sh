#!/usr/bin/env bash
# Tests for pull-archives.sh, run against local git repositories, with a
# stand-in for git so that nothing here can reach a real host.
# Run: bash scripts/pull-archives.test.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

# The fixtures are committed under a fixed identity, and no git configuration
# of the machine the tests run on is read.
export LC_ALL=C HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset XDG_CONFIG_HOME
mkdir -p "$HOME" "$TMP/bin"

# A stand-in git: logs every clone and refuses a web address. For everything
# else it is the real git.
REAL_GIT="$(command -v git)"; export REAL_GIT
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = clone ]; then
  for arg in "$@"; do
    case "$arg" in
      http://*|https://*) echo "clone $arg" >> "$FAKE/log"; exit 128 ;;
      *.git)              echo "clone $arg" >> "$FAKE/log" ;;
    esac
  done
fi
exec "$REAL_GIT" "$@"
GIT
chmod +x "$TMP/bin/git"

PUBLIC="https://stat.ethz.ch/pipermail"
FORGE="https://lists.r-forge.r-project.org/pipermail"
RAW='<4A1B2C3D.5060708@example.org>'
RAW2='<CAF8bMcZ=q1w2e3@mail.example.com>'
# What the old workflow step copied for a list: its months and four summaries.
FILES="2024-01.json 2024-02.json contributors.json index.json message-order.json meta.json "

# scenario NAME -> a fresh working directory, an empty list file, no
# repositories to clone from and a fresh log
scenario() {
  WORK="$TMP/$1/work"; REMOTES="$TMP/$1/remotes"; export FAKE="$TMP/$1/fake"
  mkdir -p "$WORK/scripts" "$REMOTES" "$FAKE"
  printf '# list_name\tbase_url\tarchive_type\tdescription\tarchive_repo\n' > "$WORK/scripts/lists.conf"
  : > "$FAKE/log"
  base="$REMOTES"
}
# conf NAME BASE_URL [REPO] -> one more line of the list file
conf() {
  printf '%s\t%s\tmonthly\tA list' "$1" "$2" >> "$WORK/scripts/lists.conf"
  [ -n "${3:-}" ] && printf '\t%s' "$3" >> "$WORK/scripts/lists.conf"
  echo >> "$WORK/scripts/lists.conf"
}
# month FILE ID... -> a month file with one message for each identifier
month() {
  local file="$1" sep="" id; shift
  { printf '{"messages":['
    for id in "$@"; do printf '%s{"id":"msg","message_id":"%s"}' "$sep" "$id"; sep=","; done
    printf ']}\n'; } > "$file"
}
# archive DIR ID... -> one list's files as an archive repository holds them:
# two months, the four summaries, and files the build never takes. The second
# month has a message for each identifier, the first for the first one and
# for a message that has none.
archive() {
  local dir="$1" f; shift
  mkdir -p "$dir/processed" "$dir/raw"
  month "$dir/processed/2024-01.json" "$1" ""
  month "$dir/processed/2024-02.json" "$@"
  for f in meta index message-order contributors; do echo "{\"file\":\"$f\"}" > "$dir/$f.json"; done
  echo "raw mail" > "$dir/raw/2024-01.mbox"
  echo "about" > "$dir/README.md"
}
# commit DIR -> make a git repository of what was written to DIR
commit() { git -C "$1" init -q >/dev/null 2>&1 && git -C "$1" add -A && git -C "$1" commit -qm fixture; }
# remote NAME ID... -> the archive repository of one list, ready to be cloned
remote() { local name="$1"; shift; archive "$REMOTES/$name.git" "$@" && commit "$REMOTES/$name.git"; }

run() {
  (cd "$WORK" && PATH="$TMP/bin:$PATH" ARCHIVE_BASE="$base" bash "$DIR/pull-archives.sh") > "$FAKE/out" 2>&1
}
# landed NAME -> the files under data/processed/NAME, sorted, on one line
landed() { (cd "$WORK/data/processed/$1" 2>/dev/null && find . -type f | sed 's|^\./||' | sort | tr '\n' ' '); }
# holds DIR -> the names in DIR, on one line
holds() { ls -A "$1" 2>/dev/null | tr '\n' ' '; }
# clones -> the addresses git was asked to clone, in order
clones() { grep '^clone ' "$FAKE/log" | sed "s|$REMOTES/||" | tr '\n' ';'; }
# expect DESC WANTED GOT
expect() {
  if [ "$3" = "$2" ]; then pass "$1"; else bad "$1: wanted '$2' got '$3'"; sed 's/^/        /' "$FAKE/out"; fi
}

scenario public
remote r-help "$RAW" "$RAW2"
conf r-help "$PUBLIC/r-help/"
run; status=$?
expect "a public list lands as its month files and four summaries, and nothing else" "$FILES" "$(landed r-help)"
cmp -s "$REMOTES/r-help.git/processed/2024-02.json" "$WORK/data/processed/r-help/2024-02.json" \
  && pass "byte for byte" || bad "byte for byte"
expect "and its clone is removed" "processed " "$(holds "$WORK/data")"
expect "and the run succeeds" "0" "$status"

scenario pooled
archive "$REMOTES/rforge-archive.git/alpha-list" "$RAW"
archive "$REMOTES/rforge-archive.git/beta-list" "$RAW2"
commit "$REMOTES/rforge-archive.git"
conf alpha-list "$FORGE/alpha-list/" rforge-archive
conf beta-list "$FORGE/beta-list/" rforge-archive
run
expect "both lists of a pooled repository land" "$FILES|$FILES" "$(landed alpha-list)|$(landed beta-list)"
expect "from one clone" "clone rforge-archive.git;" "$(clones)"
expect "which is removed" "processed " "$(holds "$WORK/data")"

scenario missing
remote r-help "$RAW"
conf ghost "$PUBLIC/ghost/"
conf ghost-list "$FORGE/ghost-list/" ghost-pool
conf r-help "$PUBLIC/r-help/"
run; status=$?
expect "a repository that does not exist is passed over" "r-help " "$(holds "$WORK/data/processed")"
expect "and the lists after it still land" "$FILES" "$(landed r-help)"
expect "and the run succeeds" "0" "$status"

scenario web
base=""
conf r-help "$PUBLIC/r-help/"
conf alpha-list "$FORGE/alpha-list/" rforge-archive
run
expect "without ARCHIVE_BASE the repositories are cloned from GitHub" \
  "clone https://github.com/r-mailing-lists/r-help.git;clone https://github.com/r-mailing-lists/rforge-archive.git;" "$(clones)"

# The workflow is read as text: its steps are the "      - " items of its one job.
WORKFLOW="$DIR/../.github/workflows/update-data.yml"
# step TEXT -> the step that holds TEXT, from its "- " line up to the next step's
step() {
  awk -v want="$1" '
    /^      - / { if (found) exit; text = "" }
    { text = text $0 "\n" }
    index($0, want) { found = 1 }
    END { if (found) printf "%s", text }' "$WORKFLOW"
}

scenario workflow
: > "$FAKE/out"
expect "the workflow's pull step runs this script" "        run: bash scripts/pull-archives.sh" \
  "$(step 'name: Pull processed data from archive repos' | grep '^        run:')"

exit "$fail"
