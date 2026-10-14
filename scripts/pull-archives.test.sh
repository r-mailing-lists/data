#!/usr/bin/env bash
# Tests for pull-archives.sh, run against local git repositories, with
# stand-ins for git and ssh so that nothing here can reach a real host.
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

# A stand-in git: logs every clone, refuses a web address, and fails a
# checkout when a scenario asks for that. For everything else it is the real git.
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
[ "$1" = checkout ] && [ -f "$FAKE/fail-checkout" ] && exit 1
exec "$REAL_GIT" "$@"
GIT

# A stand-in ssh that is github.com. It notes how it was called, and when the
# key it is given is the deploy key it serves the repository of that name
# under $FAKE/github, as git-upload-pack on the host would.
cat > "$TMP/bin/ssh" <<'SSH'
#!/usr/bin/env bash
key="" hosts="" options=""
while [ $# -gt 0 ]; do
  case "$1" in
    -i) key="$2"; shift 2 ;;
    -o) case "$2" in
          UserKnownHostsFile=*) hosts="${2#*=}"; options="$options UserKnownHostsFile" ;;
          SendEnv=*) ;;   # git's own, to pass the protocol version on
          *) options="$options $2" ;;
        esac
        shift 2 ;;
    -*) shift ;;
    *)  break ;;
  esac
done
repo="${2#*r-mailing-lists/}"; repo="${repo%\'}"
offered="another key"
[ "$(cat "$key" 2>/dev/null)" = "$(cat "$FAKE/deploy-key")" ] && offered="the deploy key"
echo "$1 $repo: $offered, $(ls -l "$key" 2>/dev/null | cut -c1-10),$options" >> "$FAKE/ssh"
echo "$key" > "$FAKE/key-path"; echo "$hosts" > "$FAKE/hosts-path"; cat "$hosts" > "$FAKE/known-hosts" 2>/dev/null
[ "$offered" = "the deploy key" ] || exit 255
exec "$REAL_GIT" upload-pack "$FAKE/github/$repo"
SSH
chmod +x "$TMP/bin/git" "$TMP/bin/ssh"
# The script is only ever run with the stand-ins first on PATH.
if [ "$(PATH="$TMP/bin:$PATH" command -v git)" != "$TMP/bin/git" ] || [ "$(PATH="$TMP/bin:$PATH" command -v ssh)" != "$TMP/bin/ssh" ]; then
  echo "FAIL  the stand-ins for git and ssh are not first on PATH; nothing was run"; exit 1
fi

PUBLIC="https://stat.ethz.ch/pipermail"
FORGE="https://lists.r-forge.r-project.org/pipermail"
# The base URL of a list whose archive at the source is members-only.
PRIVATE="https://stat.ethz.ch/mailman/private"
RAW='<4A1B2C3D.5060708@example.org>'
RAW2='<CAF8bMcZ=q1w2e3@mail.example.com>'
# Identifiers as the parser writes them when it hides addresses.
HIDDEN='<0123456789abcdef0123456789abcdef@hidden>'
HIDDEN2='<fedcba9876543210fedcba9876543210@hidden>'
# Not a key: two lines of text, which is all the script needs it to be.
KEY=$'not-a-real-key line one\nnot-a-real-key line two'
# GitHub's published host key for ed25519.
KNOWN_HOSTS="github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
# What the old workflow step copied for a list: its months and four summaries.
FILES="2024-01.json 2024-02.json contributors.json index.json message-order.json meta.json "

# scenario NAME -> a fresh working directory, an empty list file, no
# repositories to clone from, no deploy key in the environment and fresh logs
scenario() {
  WORK="$TMP/$1/work"; REMOTES="$TMP/$1/remotes"; export FAKE="$TMP/$1/fake"
  mkdir -p "$WORK/scripts" "$REMOTES" "$FAKE/github"
  printf '# list_name\tbase_url\tarchive_type\tdescription\tarchive_repo\n' > "$WORK/scripts/lists.conf"
  : > "$FAKE/log"; : > "$FAKE/ssh"
  printf '%s\n' "$KEY" > "$FAKE/deploy-key"
  base="$REMOTES"; deploy_key=""
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
# github NAME ID... -> a private archive repository: it cannot be cloned
# anonymously, and the stand-in ssh serves it as GitHub would, leaving the
# contents of the files to be fetched when they are checked out
github() {
  local name="$1"; shift
  archive "$FAKE/github/$name.git" "$@" && commit "$FAKE/github/$name.git"
  git -C "$FAKE/github/$name.git" config uploadpack.allowFilter true
  git -C "$FAKE/github/$name.git" config uploadpack.allowAnySHA1InWant true
}

run() {
  (cd "$WORK" && PATH="$TMP/bin:$PATH" ARCHIVE_BASE="$base" ARCHIVE_DEPLOY_KEY="$deploy_key" \
    bash "$DIR/pull-archives.sh") > "$FAKE/out" 2>&1
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

MARKER="data/.archive-guard-failed"
# errors -> the error annotations the script printed
errors() { grep '^::error::' "$FAKE/out"; }

scenario hidden
remote r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
run
expect "a members-only list whose identifiers are all hidden is taken" "$FILES" "$(landed r-sig-phylo)"
expect "with no error and no marker" "|processed " "$(errors)|$(holds "$WORK/data")"

scenario one-raw
remote r-help "$RAW" "$RAW2"
remote r-sig-phylo "$HIDDEN" "$RAW" "$HIDDEN2"
remote r-devel "$RAW2"
conf r-help "$PUBLIC/r-help/"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
conf r-devel "$PUBLIC/r-devel/"
run; status=$?
expect "a members-only list with one raw identifier in one message of one month is not taken" \
  "r-devel r-help " "$(holds "$WORK/data/processed")"
expect "the public lists around it are taken, raw identifiers and all" "$FILES|$FILES" "$(landed r-help)|$(landed r-devel)"
case "$(errors)" in
  "::error::"*r-sig-phylo*"not written with addresses hidden"*) pass "an error names the list and says why" ;;
  *) bad "an error names the list and says why: got '$(errors)'" ;;
esac
expect "only that list is reported" "1" "$(errors | wc -l | tr -d ' ')"
expect "the marker is left, naming the list" "r-sig-phylo" "$(cat "$WORK/$MARKER" 2>/dev/null)"
expect "and the run still succeeds, so that the other lists are published" "0" "$status"

# unreadable SLUG WHAT CONTENT -> a members-only list is not taken when one of
# its month files holds CONTENT
unreadable() {
  scenario "unreadable-$1"
  archive "$REMOTES/r-sig-phylo.git" "$HIDDEN" "$HIDDEN2"
  printf '%s' "$3" > "$REMOTES/r-sig-phylo.git/processed/2024-02.json"
  commit "$REMOTES/r-sig-phylo.git"
  conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
  run
  expect "a members-only list with a month file that $2 is not taken" \
    "|r-sig-phylo" "$(holds "$WORK/data/processed")|$(cat "$WORK/$MARKER" 2>/dev/null)"
}
unreadable truncated "is not valid JSON" "{\"messages\":[{\"id\":\"msg\",\"message_id\":\"$HIDDEN\"}"
unreadable empty "is empty" ""
unreadable two "holds two documents" "{\"messages\":[{\"id\":\"msg\",\"message_id\":\"$RAW\"}]}{\"messages\":[]}"
unreadable shapeless "has no list of messages" "{\"threads\":[]}"

scenario deploy-key
deploy_key="$KEY"
remote r-help "$RAW"
github r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-help "$PUBLIC/r-help/"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
conf ghost "$PUBLIC/ghost/"
run; status=$?
expect "with a deploy key, a clone that fails anonymously is tried once more over SSH, and no other is" \
  "clone r-help.git;clone r-sig-phylo.git;clone git@github.com:r-mailing-lists/r-sig-phylo.git;clone ghost.git;clone git@github.com:r-mailing-lists/ghost.git;" "$(clones)"
expect "the private list is taken, the missing one passed over, and the run succeeds" \
  "$FILES|r-help r-sig-phylo |0" "$(landed r-sig-phylo)|$(holds "$WORK/data/processed")|$status"
called="the deploy key, -rw-------, IdentitiesOnly=yes StrictHostKeyChecking=yes UserKnownHostsFile"
expect "ssh is given the key in a file of mode 600, to use no other key and no unknown host" \
  "git@github.com ghost.git: $called;git@github.com r-sig-phylo.git: $called;" "$(sort -u "$FAKE/ssh" | tr '\n' ';')"
[ "$(grep -c ' r-sig-phylo.git: ' "$FAKE/ssh")" -gt 1 ] && pass "also when it fetches the contents of the files after the clone" \
  || bad "also when it fetches the contents of the files after the clone: $(grep -c ' r-sig-phylo.git: ' "$FAKE/ssh") call"
expect "the one known host is GitHub, by its published key" "$KNOWN_HOSTS" "$(cat "$FAKE/known-hosts" 2>/dev/null)"
# gone FILE -> true when the stand-in ssh noted a path in FILE and nothing is there now
gone() { [ -s "$1" ] && [ -n "$(cat "$1")" ] && [ ! -e "$(cat "$1")" ]; }
gone "$FAKE/key-path" && gone "$FAKE/hosts-path" && pass "the key file and the host file are gone afterwards" \
  || bad "the key file and the host file are gone afterwards"
grep -q "not-a-real-key" "$FAKE/out" && bad "nothing of the key is printed" || pass "nothing of the key is printed"

scenario no-key
remote r-help "$RAW"
github r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
conf r-help "$PUBLIC/r-help/"
run; status=$?
expect "without a deploy key SSH is never tried" "clone r-sig-phylo.git;clone r-help.git;|" "$(clones)|$(cat "$FAKE/ssh")"
expect "and the private list is passed over, as before" "r-help |0" "$(holds "$WORK/data/processed")|$status"

scenario cut-short
deploy_key="$KEY"
github r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
touch "$FAKE/fail-checkout"
run; status=$?
[ "$status" != "0" ] && gone "$FAKE/key-path" && gone "$FAKE/hosts-path" && pass "the key file is also gone when the script fails half way" \
  || bad "the key file is also gone when the script fails half way: exit $status"

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

# last_step -> the last step of the job
last_step() { awk '/^      - / { text = "" } { text = text $0 "\n" } END { printf "%s", text }' "$WORKFLOW"; }
# commands -> the "run: |" lines of the step on standard input
commands() { awk '/^        run: \|$/ { on = 1; next } on && /^          / { print substr($0, 11); next } { on = 0 }'; }
# last_step_in SCENARIO -> the status of the last step's commands, run where
# that scenario's pull left its files. They are run as the runner does, but
# with nothing on PATH: whatever the step is, here it can only use the shell.
last_step_in() { (cd "$TMP/$1/work" && PATH=/nonexistent "$BASH" -e -c "$(last_step | commands)") > "$FAKE/out" 2>&1; echo $?; }

scenario workflow
: > "$FAKE/out"
expect "the workflow's pull step runs this script" "        run: bash scripts/pull-archives.sh" \
  "$(step 'name: Pull processed data from archive repos' | grep '^        run:')"
secret='ARCHIVE_DEPLOY_KEY: ${{ secrets.ARCHIVE_DEPLOY_KEY }}'
expect "the workflow gives the deploy key to the pull step, by env" "          $secret" \
  "$(step 'name: Pull processed data from archive repos' | awk '/^        env:$/ { on = 1; next } on && /^          / { print; next } { on = 0 }')"
expect "and names it nowhere else" "1" "$(grep -c 'ARCHIVE_DEPLOY_KEY' "$WORKFLOW")"
# Read before it is run: only a step that is about the marker is run here.
case "$(last_step)" in
  *"if: always()"*"$MARKER"*)
    pass "the workflow's last step runs whatever came before it, and looks for the marker"
    expect "it fails where the pull left the marker" "1" "$(last_step_in one-raw)"
    expect "and succeeds where the pull left none" "0" "$(last_step_in hidden)" ;;
  *) bad "the workflow's last step runs whatever came before it, and looks for the marker" ;;
esac

exit "$fail"
