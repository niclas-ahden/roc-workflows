#!/usr/bin/env bash
# Point every app in the checkout at a package bundle rather than at this
# checkout's package.
#
#   point-at-bundle.sh https://.../<hash>.tar.zst
#   point-at-bundle.sh http://127.0.0.1:8788/<hash>.tar.zst examples tests
#
# Makes a run test the artifact people download instead of the source it was
# built from. The localhost form is for a drafted bundle, whose release asset
# needs a token: roc allows http to localhost, and does the download, hash
# check and unbundle itself either way.
#
# Directories that do not exist are skipped, so one caller can name every
# place a package might keep apps. Set PACKAGE when the package module is not
# package/main.roc.
set -euo pipefail

url=${1:?usage: point-at-bundle.sh <bundle-url> [dir...]}
shift
pkg=${PACKAGE:-package/main.roc}

dirs=()
for d in "$@"; do
  if [ -d "$d" ]; then dirs+=("$d"); fi
done
[ "${#dirs[@]}" -gt 0 ] || {
  echo "error: none of the directories to rewrite (${*:-none given}) exist" >&2
  exit 1
}

# Any number of ../ hops, since how deep an app sits varies.
esc=$(printf '%s' "$pkg" | sed 's/[.[\*^$]/\\&/g')
pattern="\"(\.\./)*$esc\""
# & and | mean something to sed on the right hand side of s|||.
repl=$(printf '%s' "$url" | sed 's/[&|\\]/\\&/g')

apps=()
while IFS= read -r app; do
  apps+=("$app")
done < <(grep -rlE "$pattern" "${dirs[@]}" --include='*.roc' || true)

[ "${#apps[@]}" -gt 0 ] || {
  echo "error: nothing under ${dirs[*]} depends on $pkg, so there is no app to test the bundle with" >&2
  exit 1
}

for app in "${apps[@]}"; do
  sed -i.bak -E "s|$pattern|\"$repl\"|g" "$app"
  rm -f "$app.bak"
done

# A rewrite that silently matched nothing would leave the run testing this
# checkout while reporting that it tested the bundle.
leftover=$(grep -rlE "$pattern" "${dirs[@]}" --include='*.roc' || true)
[ -z "$leftover" ] || {
  echo "error: these still depend on $pkg" >&2
  echo "$leftover" >&2
  exit 1
}

echo "pointed ${#apps[@]} app(s) at $url"
