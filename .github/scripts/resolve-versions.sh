#!/usr/bin/env bash
# Resolve the versions a run tests, once, so every leg of it tests the same
# set rather than whatever was newest when that leg happened to start.
#
#   resolve-versions.sh          # the nightlies worth testing
#   resolve-versions.sh release  # that, plus this repository's latest release
#
# Needs GH_TOKEN and GITHUB_REPOSITORY. Writes to GITHUB_OUTPUT:
#
#   nightly      the newest Roc nightly
#   sha          its short commit sha
#   prev_sha     the sha of the nightly before it, to name a commit range
#   recommended  the nightly the latest release's notes recommend
#   release      the latest release tag, with `release` only
#   bundle       the bundle URL on that release, with `release` only
#
# recommended is an advisory extra: empty when there is no release or no
# recommendation, and empty when it repeats `nightly`, so a caller can gate
# its legs on non-emptiness and never test the same compiler twice.
set -euo pipefail

with_release=${1:-}

tag=$(gh release view --repo roc-lang/nightlies --json tagName -q .tagName)
[ -n "$tag" ] || {
  echo "error: could not resolve the latest roc nightly" >&2
  exit 1
}

# Tag spellings have changed before, but both end in the short sha, which is
# what names a commit range when a nightly breaks us.
prev=$(gh release list --repo roc-lang/nightlies --limit 2 --json tagName -q '.[1].tagName')

# What the latest release's notes tell people to install today. Testing it
# answers whether this checkout still keeps that promise.
# shellcheck disable=SC2016  # the backticks are markdown, not a subshell
recommended=$(gh release view --repo "$GITHUB_REPOSITORY" --json body -q .body 2>/dev/null \
  | sed -n 's|^Compatible with: \[`roc \(nightly-[^`]*\)`\].*|\1|p' | head -1 || true)
[ "$recommended" != "$tag" ] || recommended=

{
  echo "nightly=$tag"
  echo "sha=${tag##*-}"
  echo "prev_sha=${prev##*-}"
  echo "recommended=$recommended"
} >> "$GITHUB_OUTPUT"
echo "the latest roc nightly is $tag"
[ -z "$recommended" ] || echo "the latest release recommends $recommended"

[ "$with_release" = release ] || exit 0

release=$(gh release view --repo "$GITHUB_REPOSITORY" --json tagName -q .tagName 2>/dev/null || true)
[ -n "$release" ] || {
  echo "error: $GITHUB_REPOSITORY has no published release yet, so there is nothing released to test" >&2
  exit 1
}

bundle=$(gh release view --repo "$GITHUB_REPOSITORY" --json assets \
           -q '.assets[] | select(.name | endswith(".tar.zst")) | .url')
[ -n "$bundle" ] || {
  echo "error: no package bundle on $GITHUB_REPOSITORY $release" >&2
  exit 1
}

{
  echo "release=$release"
  echo "bundle=$bundle"
} >> "$GITHUB_OUTPUT"
echo "the latest release is $release"

[ -z "${GITHUB_STEP_SUMMARY:-}" ] || \
  echo "Testing **$release** against Roc **$tag**" >> "$GITHUB_STEP_SUMMARY"
