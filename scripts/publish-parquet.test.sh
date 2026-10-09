#!/usr/bin/env bash
# Tests for publish-parquet.sh, run against a stand-in for the gh CLI.
# Run: bash scripts/publish-parquet.test.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

if command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$1" | cut -d' ' -f1; }
else sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi

# A stand-in gh: answers from files under $FAKE and logs every change it is asked to make.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "release view")          [ -f "$FAKE/exists" ] ;;
  "release create")        touch "$FAKE/exists"; echo "create $3" >> "$FAKE/log" ;;
  "api "*)                 cat "$FAKE/assets.tsv" 2>/dev/null || true ;;   # no assets yet: empty, exit 0
  "release upload")        [ -f "$FAKE/fail-upload" ] && exit 1
                           shift 3   # release upload TAG, then the files, then flags
                           for arg in "$@"; do
                             case "$arg" in -*) break ;; esac
                             echo "upload $(basename "$arg")" >> "$FAKE/log"
                           done ;;
  "release delete-asset")  echo "delete $4" >> "$FAKE/log" ;;
  *) echo "unexpected gh call: $*" >&2; exit 64 ;;
esac
GH
chmod +x "$TMP/bin/gh"

# scenario NAME -> a fresh data dir with three files and a fresh fake state
scenario() {
  DATA="$TMP/$1/data"; export FAKE="$TMP/$1/fake"
  mkdir -p "$DATA/messages" "$FAKE"
  echo "r-devel rows"  > "$DATA/messages/r-devel.parquet"
  echo "r-help rows"   > "$DATA/messages/r-help.parquet"
  echo "thread rows"   > "$DATA/threads.parquet"
  : > "$FAKE/log"
}
# published FILE... -> the release already holds these local files, byte for byte
published() {
  touch "$FAKE/exists"
  for f in "$@"; do printf '%s\tsha256:%s\n' "$(basename "$f")" "$(sha256 "$f")" >> "$FAKE/assets.tsv"; done
}
run() { PATH="$TMP/bin:$PATH" GH_REPO=owner/repo bash "$DIR/publish-parquet.sh" "$DATA" > "$FAKE/out" 2>&1; }
# expect DESC WANTED_LOG -> the changes gh was asked to make, sorted
expect() {
  local got; got="$(sort "$FAKE/log" | tr '\n' ';')"
  if [ "$got" = "$2" ]; then pass "$1"; else bad "$1: wanted '$2' got '$got'"; sed 's/^/        /' "$FAKE/out"; fi
}

scenario first-run
run; status=$?
expect "the first run creates the release and uploads every file" "create parquet;upload r-devel.parquet;upload r-help.parquet;upload threads.parquet;"
[ "$status" = "0" ] && pass "and succeeds" || bad "and succeeds: exit $status"

scenario unchanged
published "$DATA/messages/r-devel.parquet" "$DATA/messages/r-help.parquet" "$DATA/threads.parquet"
run
expect "files identical to the published ones are left alone" ""

scenario one-changed
published "$DATA/messages/r-devel.parquet" "$DATA/messages/r-help.parquet" "$DATA/threads.parquet"
echo "one more message" >> "$DATA/messages/r-help.parquet"
run
expect "only the file that changed is uploaded" "upload r-help.parquet;"

scenario stale
published "$DATA/messages/r-devel.parquet" "$DATA/messages/r-help.parquet" "$DATA/threads.parquet"
printf 'r-help-1990-1999.parquet\tsha256:0000\n' >> "$FAKE/assets.tsv"
run
expect "an asset the build no longer produces is removed" "delete r-help-1990-1999.parquet;"

scenario upload-fails
touch "$FAKE/fail-upload"
run; status=$?
[ "$status" != "0" ] && pass "a failed upload fails the run" || bad "a failed upload fails the run: exit 0"

scenario empty
rm -f "$DATA"/messages/*.parquet "$DATA"/*.parquet
published
run; status=$?
[ "$status" != "0" ] && pass "refuses to publish when the build produced no files" || bad "refuses to publish when the build produced no files: exit 0"
expect "and removes nothing in that case" ""

exit "$fail"
