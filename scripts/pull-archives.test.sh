#!/usr/bin/env bash
# Tests for pull-archives.sh, run against local git repositories, with
# stand-ins for git and ssh so that nothing here can reach a real host, and
# one for sleep so that nothing here waits.
# Run: bash scripts/pull-archives.test.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

# The fixtures are committed under a fixed identity, and no git configuration
# of the machine the tests run on is read. Beyond the stand-ins, git itself
# is allowed no transport but local files and ssh, which is the stand-in.
export LC_ALL=C HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file:ssh
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset XDG_CONFIG_HOME GIT_TERMINAL_PROMPT
mkdir -p "$HOME" "$TMP/bin"

# A stand-in git: logs every clone and whether it may prompt for a password,
# refuses a web address, and fails as many checkouts as a scenario asks for.
# For everything else it is the real git.
REAL_GIT="$(command -v git)"; export REAL_GIT
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = clone ]; then
  echo "GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT-unset}" >> "$FAKE/prompt"
  for arg in "$@"; do
    case "$arg" in
      http://*|https://*) echo "clone $arg" >> "$FAKE/log"; exit 128 ;;
      *.git)              echo "clone $arg" >> "$FAKE/log" ;;
    esac
  done
fi
if [ "$1" = checkout ]; then
  failures="$(cat "$FAKE/checkout-failures" 2>/dev/null || echo 0)"
  if [ "$failures" -gt 0 ]; then echo $((failures - 1)) > "$FAKE/checkout-failures"; exit 1; fi
fi
exec "$REAL_GIT" "$@"
GIT

# A stand-in ssh that is github.com. It notes how it was called, and when the
# key it is given is the deploy key it serves the repository of that name
# under $FAKE/github, as git-upload-pack on the host would. A scenario can
# have it refuse its first calls, as a host that is out of reach would. When
# it refuses it says why, as ssh does.
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
[ "$offered" = "the deploy key" ] || { echo "$1: Permission denied (publickey)." >&2; exit 255; }
refusals="$(cat "$FAKE/refusals" 2>/dev/null || echo 0)"
if [ "$refusals" -gt 0 ]; then
  echo $((refusals - 1)) > "$FAKE/refusals"
  echo "ssh: connect to host github.com port 22: Connection timed out" >&2; exit 255
fi
exec "$REAL_GIT" upload-pack "$FAKE/github/$repo"
SSH

# A stand-in sleep: it notes how long the pause was to be, and does not wait.
cat > "$TMP/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
echo "pause $1" >> "$FAKE/log"
SLEEP
chmod +x "$TMP/bin/git" "$TMP/bin/ssh" "$TMP/bin/sleep"
# The script is only ever run with the stand-ins first on PATH.
for tool in git ssh sleep; do
  if [ "$(PATH="$TMP/bin:$PATH" command -v "$tool")" != "$TMP/bin/$tool" ]; then
    echo "FAIL  the stand-in for $tool is not first on PATH; nothing was run"; exit 1
  fi
done

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
# repositories to clone from, no deploy key in the environment, no pause
# between the tries of a clone and fresh logs
scenario() {
  WORK="$TMP/$1/work"; REMOTES="$TMP/$1/remotes"; export FAKE="$TMP/$1/fake"
  mkdir -p "$WORK/scripts" "$REMOTES" "$FAKE/github"
  printf '# list_name\tbase_url\tarchive_type\tdescription\tarchive_repo\n' > "$WORK/scripts/lists.conf"
  : > "$FAKE/log"; : > "$FAKE/ssh"
  printf '%s\n' "$KEY" > "$FAKE/deploy-key"
  base="$REMOTES"; deploy_key=""; pause="0"
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
# for a message that has none. The one contributor has "at" in his name, but
# not as a word.
archive() {
  local dir="$1" f; shift
  mkdir -p "$dir/processed" "$dir/raw"
  month "$dir/processed/2024-01.json" "$1" ""
  month "$dir/processed/2024-02.json" "$@"
  for f in meta index message-order; do echo "{\"file\":\"$f\"}" > "$dir/$f.json"; done
  echo '[{"name":"Pat Atkins","messageCount":3}]' > "$dir/contributors.json"
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
github() { local name="$1"; shift; archive "$FAKE/github/$name.git" "$@" && serve "$name"; }
# serve NAME -> have the stand-in ssh serve what was written to $FAKE/github/NAME.git
serve() {
  commit "$FAKE/github/$1.git"
  git -C "$FAKE/github/$1.git" config uploadpack.allowFilter true
  git -C "$FAKE/github/$1.git" config uploadpack.allowAnySHA1InWant true
}
# monthless DIR -> one list's files as archive writes them, but with no month
# among them
monthless() {
  archive "$1" "$HIDDEN"
  rm "$1/processed"/2024-*.json
  echo "not a month" > "$1/processed/notes.txt"
}

run() {
  (cd "$WORK" && PATH="$TMP/bin:$PATH" ARCHIVE_BASE="$base" ARCHIVE_DEPLOY_KEY="$deploy_key" \
    ARCHIVE_RETRY_PAUSE="$pause" bash "$DIR/pull-archives.sh") > "$FAKE/out" 2>&1
}
# landed NAME -> the files under data/processed/NAME, sorted, on one line
landed() { (cd "$WORK/data/processed/$1" 2>/dev/null && find . -type f | sed 's|^\./||' | sort | tr '\n' ' '); }
# holds DIR -> the names in DIR, on one line
holds() { ls -A "$1" 2>/dev/null | tr '\n' ' '; }
# tries -> the addresses git was asked to clone and the pauses in between, in order
tries() { sed "s|$REMOTES/||" "$FAKE/log" | tr '\n' ';'; }
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
expect "from one clone" "clone rforge-archive.git;" "$(tries)"
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
  "clone https://github.com/r-mailing-lists/r-help.git;clone https://github.com/r-mailing-lists/rforge-archive.git;" "$(tries)"

# errors -> the error annotations the script printed
errors() { grep '^::error::' "$FAKE/out"; }

scenario hidden
remote r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
run
expect "a members-only list whose identifiers are all hidden is taken" "$FILES" "$(landed r-sig-phylo)"
expect "with no error" "|processed " "$(errors)|$(holds "$WORK/data")"

scenario one-raw
remote r-help "$RAW" "$RAW2"
remote r-sig-phylo "$HIDDEN" "$RAW" "$HIDDEN2"
remote r-devel "$RAW2"
conf r-help "$PUBLIC/r-help/"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
conf r-devel "$PUBLIC/r-devel/"
run; status=$?
expect "a members-only list with one raw identifier in one message of one month stops the run" "1" "$status"
expect "its files are gone, and no list after it is pulled" "r-help |processed " "$(holds "$WORK/data/processed")|$(holds "$WORK/data")"
expect "the public list before it was taken, raw identifiers and all" "$FILES" "$(landed r-help)"
case "$(errors)" in
  "::error::"*r-sig-phylo*"not written with addresses hidden"*) pass "an error names the list and says why" ;;
  *) bad "an error names the list and says why: got '$(errors)'" ;;
esac

# unreadable SLUG WHAT CONTENT -> a members-only list stops the run when one
# of its month files holds CONTENT
unreadable() {
  scenario "unreadable-$1"
  archive "$REMOTES/r-sig-phylo.git" "$HIDDEN" "$HIDDEN2"
  printf '%s' "$3" > "$REMOTES/r-sig-phylo.git/processed/2024-02.json"
  commit "$REMOTES/r-sig-phylo.git"
  conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
  run; status=$?
  expect "a members-only list with a month file that $2 stops the run" \
    "|1|1" "$(holds "$WORK/data/processed")|$status|$(errors | grep -c 'r-sig-phylo')"
}
unreadable truncated "is not valid JSON" "{\"messages\":[{\"id\":\"msg\",\"message_id\":\"$HIDDEN\"}"
unreadable empty "is empty" ""
unreadable two "holds two documents" "{\"messages\":[]}{\"messages\":[{\"id\":\"msg\",\"message_id\":\"$RAW\"}]}"
unreadable shapeless "has no list of messages" "{\"threads\":[]}"

# identifier SLUG WHAT WANTED ID -> a members-only list with a message whose
# identifier is ID is taken (WANTED 0) or stops the run (WANTED 1). The parser
# writes a value that held several identifiers as several codes, one blank
# apart, and nothing else may be before, between or after them.
identifier() {
  scenario "identifier-$1"
  remote r-sig-phylo "$HIDDEN" "$4"
  conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
  run; status=$?
  if [ "$3" = 0 ]; then
    expect "a members-only list with an identifier that $2 is taken" "0|$FILES" "$status|$(landed r-sig-phylo)"
  else
    expect "a members-only list with an identifier that $2 stops the run" "1|" "$status|$(holds "$WORK/data/processed")"
  fi
}
identifier several "is two hidden codes, one blank apart" 0 "$HIDDEN $HIDDEN2"
identifier three "is three hidden codes, one blank apart" 0 "$HIDDEN $HIDDEN2 $HIDDEN"
identifier two-blanks "is two hidden codes, two blanks apart" 1 "$HIDDEN  $HIDDEN2"
identifier newline "is a hidden code with a newline after it" 1 "$HIDDEN\\n"
identifier raw-first "is a raw identifier, then a hidden code" 1 "$RAW $HIDDEN"
identifier raw-last "is a hidden code, then a raw identifier" 1 "$HIDDEN $RAW"
identifier capitals "is a hidden code in upper-case hex" 1 "<0123456789ABCDEF0123456789ABCDEF@hidden>"

# The guard is switched on by the base URL, so the real line is tried as it is.
scenario real-line
remote r-sig-phylo "$RAW"
grep '^r-sig-phylo' "$DIR/lists.conf" >> "$WORK/scripts/lists.conf"
run; status=$?
expect "the line lists.conf has for r-sig-phylo puts the list under the guard" \
  "|1|1" "$(holds "$WORK/data/processed")|$status|$(errors | grep -c 'r-sig-phylo')"

scenario deploy-key
deploy_key="$KEY"
remote r-help "$RAW"
github r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-help "$PUBLIC/r-help/"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
conf ghost "$PUBLIC/ghost/"
run; status=$?
expect "with a deploy key, a clone that fails anonymously is tried once more over SSH, and no other is" \
  "clone r-help.git;clone r-sig-phylo.git;clone git@github.com:r-mailing-lists/r-sig-phylo.git;clone ghost.git;clone git@github.com:r-mailing-lists/ghost.git;" "$(tries)"
expect "the private list is taken, the missing one passed over, and the run succeeds" \
  "$FILES|r-help r-sig-phylo |0" "$(landed r-sig-phylo)|$(holds "$WORK/data/processed")|$status"
called="the deploy key, -rw-------, IdentitiesOnly=yes BatchMode=yes ConnectTimeout=20 StrictHostKeyChecking=yes GlobalKnownHostsFile=/dev/null UserKnownHostsFile"
expect "ssh is given the key in a file of mode 600, to use no other key, no host but GitHub, and no prompt" \
  "git@github.com ghost.git: $called;git@github.com r-sig-phylo.git: $called;" "$(sort -u "$FAKE/ssh" | tr '\n' ';')"
[ "$(grep -c ' r-sig-phylo.git: ' "$FAKE/ssh")" -gt 1 ] && pass "also when it fetches the contents of the files after the clone" \
  || bad "also when it fetches the contents of the files after the clone: $(grep -c ' r-sig-phylo.git: ' "$FAKE/ssh") call"
expect "the one known host is GitHub, by its published key" "$KNOWN_HOSTS" "$(cat "$FAKE/known-hosts" 2>/dev/null)"
# gone FILE -> true when the stand-in ssh noted a path in FILE and nothing is there now
gone() { [ -s "$1" ] && [ -n "$(cat "$1")" ] && [ ! -e "$(cat "$1")" ]; }
gone "$FAKE/key-path" && gone "$FAKE/hosts-path" && pass "the key file and the host file are gone afterwards" \
  || bad "the key file and the host file are gone afterwards"
grep -q "not-a-real-key" "$FAKE/out" && bad "nothing of the key is printed" || pass "nothing of the key is printed"
expect "no clone, anonymous or over SSH, may wait for a password" "GIT_TERMINAL_PROMPT=0" "$(sort -u "$FAKE/prompt")"

scenario no-key
remote r-help "$RAW"
github r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
conf ghost "$PUBLIC/ghost/"
conf r-help "$PUBLIC/r-help/"
run; status=$?
expect "without a deploy key SSH is never tried" "clone r-sig-phylo.git;clone ghost.git;clone r-help.git;|" "$(tries)|$(cat "$FAKE/ssh")"
expect "and the private list is passed over, as before" "r-help |0" "$(holds "$WORK/data/processed")|$status"
expect "with one plain line that says a members-only list was skipped for want of a key" \
  "Skipping r-sig-phylo: a members-only list, and no deploy key is configured" "$(grep -e 'Skipping' -e '^::' "$FAKE/out")"

scenario unreachable
deploy_key="$KEY"
remote r-help "$RAW"
remote r-devel "$RAW"
conf r-help "$PUBLIC/r-help/"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
conf r-devel "$PUBLIC/r-devel/"
run; status=$?
again="clone git@github.com:r-mailing-lists/r-sig-phylo.git"
expect "with a deploy key, a members-only list that cannot be cloned is tried three times over SSH" \
  "clone r-help.git;clone r-sig-phylo.git;$again;pause 0;$again;pause 0;$again;" "$(tries)"
expect "then the run stops, before any list after it is pulled" "1|r-help " "$status|$(holds "$WORK/data/processed")"
case "$(errors)" in
  "::error::"*r-sig-phylo*"could not be cloned"*) pass "with an error that names the list" ;;
  *) bad "with an error that names the list: got '$(errors)'" ;;
esac
gone "$FAKE/key-path" && gone "$FAKE/hosts-path" && pass "and the key file is gone" || bad "and the key file is gone"

scenario out-of-reach-twice
deploy_key="$KEY"; pause=""
github r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
echo 2 > "$FAKE/refusals"
run; status=$?
expect "the second try comes 30 seconds after the first, the third 60 after that, unless ARCHIVE_RETRY_PAUSE says otherwise" \
  "clone r-sig-phylo.git;$again;pause 30;$again;pause 60;$again;" "$(tries)"
expect "and a third try that works is as good as a first" "$FILES|0|" "$(landed r-sig-phylo)|$status|$(errors)"
expect "the log says why the SSH tries failed" "2" "$(grep -c 'Connection timed out' "$FAKE/out")"
grep -q "not-a-real-key" "$FAKE/out" && bad "and nothing of the key is in it" || pass "and nothing of the key is in it"

# The contents of the files are fetched after the clone, when the files are
# checked out. A checkout that fails stands for that fetch failing.
scenario checkout-fails-once
deploy_key="$KEY"
github r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
echo 1 > "$FAKE/refusals"; echo 1 > "$FAKE/checkout-failures"
run; status=$?
expect "a try of a members-only list is its clone and its checkout: one fails, then the other, and there is a third" \
  "clone r-sig-phylo.git;$again;pause 0;$again;pause 0;$again;" "$(tries)"
expect "which is as good as a first when it works" "$FILES|0|" "$(landed r-sig-phylo)|$status|$(errors)"

scenario checkout-fails
deploy_key="$KEY"
remote r-devel "$RAW"
github r-sig-phylo "$HIDDEN" "$HIDDEN2"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
conf r-devel "$PUBLIC/r-devel/"
echo 1 > "$FAKE/refusals"; echo 2 > "$FAKE/checkout-failures"
run; status=$?
expect "when the third try fails as well there is no fourth" \
  "clone r-sig-phylo.git;$again;pause 0;$again;pause 0;$again;" "$(tries)"
expect "the run stops, with nothing of the list left and no list after it pulled" \
  "1||processed " "$status|$(holds "$WORK/data/processed")|$(holds "$WORK/data")"
case "$(errors)" in
  "::error::"*r-sig-phylo*"could not be checked out"*) pass "with an error that names the list" ;;
  *) bad "with an error that names the list: got '$(errors)'" ;;
esac
gone "$FAKE/key-path" && gone "$FAKE/hosts-path" && pass "and the key file is gone" || bad "and the key file is gone"

scenario public-checkout-fails
remote r-help "$RAW"
remote r-devel "$RAW"
conf r-help "$PUBLIC/r-help/"
conf r-devel "$PUBLIC/r-devel/"
echo 1 > "$FAKE/checkout-failures"
run; status=$?
expect "a public list that is cloned and cannot be checked out fails the run at once, as it always did" \
  "1|clone r-help.git;|" "$status|$(tries)|$(errors)"

scenario no-months
deploy_key="$KEY"
remote r-devel "$RAW"
monthless "$FAKE/github/r-sig-phylo.git"
serve r-sig-phylo
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
conf r-devel "$PUBLIC/r-devel/"
run; status=$?
expect "with a deploy key, a members-only list that brings no month file stops the run" \
  "1|" "$status|$(holds "$WORK/data/processed")"
case "$(errors)" in
  "::error::"*r-sig-phylo*"no month file"*) pass "with an error that names the list and says why" ;;
  *) bad "with an error that names the list and says why: got '$(errors)'" ;;
esac

# names SLUG WHAT CONTENT -> with a deploy key, a members-only list whose
# contributors.json WHAT stops the run. CONTENT is the file; none when empty.
names() {
  scenario "names-$1"
  deploy_key="$KEY"
  archive "$FAKE/github/r-sig-phylo.git" "$HIDDEN" "$HIDDEN2"
  rm "$FAKE/github/r-sig-phylo.git/contributors.json"
  [ -n "$3" ] && printf '%s' "$3" > "$FAKE/github/r-sig-phylo.git/contributors.json"
  serve r-sig-phylo
  conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
  run; status=$?
  case "$status|$(holds "$WORK/data/processed")|$(errors)" in
    "1||::error::"*r-sig-phylo*contributors.json*) pass "with a deploy key, a members-only list whose contributors.json $2 stops the run" ;;
    *) bad "with a deploy key, a members-only list whose contributors.json $2 stops the run: got '$status|$(errors)'" ;;
  esac
}
names missing "is missing" ""
names truncated "is not valid JSON" '[{"name":"Pat Atkins"}'
names two "holds two documents" '[][{"name":"jane.doe@uni.example.org"}]'
names object "is an object, not an array" '{"pat":{"name":"Pat Atkins"}}'
names at-sign "has a name with an @ in it" '[{"name":"Pat Atkins"},{"name":"jane.doe@uni.example.org"}]'
names at-word "has a name with the word at in it" '[{"name":"jane.doe at uni.example.org"}]'
names at-capitals "has a name with the word AT in it" '[{"name":"jane.doe AT uni.example.org"}]'
names at-tabs "has a name with the word at between tabs" '[{"name":"jane.doe\tat\tuni.example.org"}]'
names null-name "has a name that is null" '[{"name":"Pat Atkins"},{"name":null}]'
names no-name "has an entry without a name" '[{"name":"Pat Atkins"},{"messageCount":3}]'

scenario no-months-no-key
monthless "$REMOTES/r-sig-phylo.git"
echo '[{"name":"jane.doe at uni.example.org"}]' > "$REMOTES/r-sig-phylo.git/contributors.json"
commit "$REMOTES/r-sig-phylo.git"
conf r-sig-phylo "$PRIVATE/r-sig-phylo/"
run; status=$?
expect "without a deploy key the same list is no error, nor is its contributors.json: it is not switched on" \
  "0|" "$status|$(errors)"

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
secret='ARCHIVE_DEPLOY_KEY: ${{ secrets.ARCHIVE_DEPLOY_KEY }}'
expect "the workflow gives the deploy key to the pull step, by env" "          $secret" \
  "$(step 'name: Pull processed data from archive repos' | awk '/^        env:$/ { on = 1; next } on && /^          / { print; next } { on = 0 }')"
expect "and names it nowhere else" "1" "$(grep -c 'ARCHIVE_DEPLOY_KEY' "$WORKFLOW")"
# A members-only list that cannot be vouched for fails the pull step. That
# stops the run before anything is built or published only while no step
# asks to run after a failure.
expect "nothing in the workflow runs after a step has failed" "0" \
  "$(grep -c -e 'always()' -e 'failure()' -e 'cancelled()' -e 'continue-on-error' "$WORKFLOW")"

exit "$fail"
