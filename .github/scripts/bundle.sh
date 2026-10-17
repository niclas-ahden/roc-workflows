#!/usr/bin/env bash
# Bundle a Roc package and prove the tarball holds every one of its modules.
#
#   bundle.sh package/main.roc dist
#
# `roc bundle` can exit 0 while producing a tarball that is missing modules
# (seen with path dependencies), so bundling alone proves nothing, and a
# bundle that is missing a module is unusable to everyone who downloads it.
#
# Set ROC to use a compiler that is not on the PATH, such as the one nix
# built (./result/bin/roc). Writes `archive=<filename>` to GITHUB_OUTPUT when
# a job is running.
set -euo pipefail

main=${1:?usage: bundle.sh <package-main> <output-dir>}
out=${2:?usage: bundle.sh <package-main> <output-dir>}
roc=${ROC:-roc}

[ -f "$main" ] || {
  echo "error: no package module at $main" >&2
  exit 1
}

# roc bundles the directory the module sits in, so this runs from there, which
# leaves every path it is handed to resolve from somewhere else.
case "$roc" in
  */*) roc=$(cd "$(dirname "$roc")" && pwd)/$(basename "$roc") ;;
esac
mkdir -p "$out"
out=$(cd "$out" && pwd)
pkg_dir=$(dirname "$main")

(cd "$pkg_dir" && "$roc" bundle --output-dir "$out" "$(basename "$main")")

archive=$(find "$out" -name '*.tar.zst' | head -n 1)
[ -n "$archive" ] || {
  echo "::error::roc bundle produced no tarball"
  exit 1
}

contents=$(mktemp)
trap 'rm -f "$contents"' EXIT
tar -tf "$archive" > "$contents"
echo "Bundle contents:"
cat "$contents"

missing=0
for f in "$pkg_dir"/*.roc; do
  name=$(basename "$f")
  # Another package header next to the main module, such as one that exposes
  # internal modules to the repository's tests, is not part of this bundle.
  if [ "$name" != "$(basename "$main")" ] && grep -qE '^package[[:space:]]*\[' "$f"; then
    continue
  fi
  grep -qx "$name" "$contents" || {
    echo "::error::the bundle is missing $name"
    missing=1
  }
done
[ "$missing" -eq 0 ] || exit 1

[ -z "${GITHUB_OUTPUT:-}" ] || echo "archive=$(basename "$archive")" >> "$GITHUB_OUTPUT"
echo "bundled $(basename "$archive")"
