#!/usr/bin/env bash
#
# Publish the Parquet files as assets of a rolling GitHub release.
#
# The files used to be committed. A list that receives one message gets its
# whole file rewritten, so the repository grew by every changed file every day
# and reached about 60 GB for under half a gigabyte of data. As release assets
# they are simply replaced, and the repository holds only the code.
#
# A file is uploaded only if it differs from the asset already published
# (compared by SHA-256), so on an ordinary day a handful of files move and the
# rest are never unavailable. Assets the build no longer produces are removed.
#
# usage: publish-parquet.sh <data-dir> [tag]
#   <data-dir>  holds messages/*.parquet, threads.parquet and contributors.parquet
#   [tag]       release to publish to (default: parquet)
#
# Needs an authenticated gh, and GH_REPO or GITHUB_REPOSITORY naming the repository.

set -euo pipefail

DATA="${1:?usage: publish-parquet.sh <data-dir> [tag]}"
TAG="${2:-parquet}"
REPO="${GH_REPO:-${GITHUB_REPOSITORY:?set GH_REPO or GITHUB_REPOSITORY}}"

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
else
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi

files=()
for f in "$DATA"/messages/*.parquet "$DATA"/*.parquet; do
  [ -f "$f" ] && files+=("$f")
done
# An empty build must never be read as "every published file is stale".
if [ ${#files[@]} -eq 0 ]; then
  echo "No Parquet files under $DATA; refusing to publish an empty set" >&2
  exit 1
fi

if ! gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" -R "$REPO" --latest --title "Parquet files" \
    --notes "Every list as a Parquet file, rebuilt daily. See the README for how to read them."
fi

# name<TAB>sha256:<hex> for every asset already published
published="$(gh api "repos/$REPO/releases/tags/$TAG" --jq '.assets[] | [.name, (.digest // "")] | @tsv')"

changed=()
unchanged=0
for f in "${files[@]}"; do
  have="$(awk -F'\t' -v name="$(basename "$f")" '$1 == name {print $2}' <<<"$published")"
  if [ "$have" = "sha256:$(sha256 "$f")" ]; then
    unchanged=$((unchanged + 1))
  else
    changed+=("$f")
  fi
done
if [ ${#changed[@]} -gt 0 ]; then
  gh release upload "$TAG" "${changed[@]}" --clobber -R "$REPO"
fi

removed=0
while IFS=$'\t' read -r name _; do
  [ -n "$name" ] || continue
  keep=false
  for f in "${files[@]}"; do
    if [ "$(basename "$f")" = "$name" ]; then keep=true; break; fi
  done
  if [ "$keep" = false ]; then
    gh release delete-asset "$TAG" "$name" --yes -R "$REPO"
    removed=$((removed + 1))
  fi
done <<<"$published"

echo "Published to $REPO@$TAG: ${#changed[@]} uploaded, $unchanged unchanged, $removed removed"
