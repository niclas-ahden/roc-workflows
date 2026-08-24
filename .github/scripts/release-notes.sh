#!/usr/bin/env bash
# Give a drafted release its "Roc compiler version" and "Using this release"
# sections.
#
#   release-notes.sh <release-tag> <bundle-url>
#
# Needs GH_TOKEN and GITHUB_REPOSITORY. Set README to read the usage snippet
# from somewhere other than README.md.
#
# Each section is appended only when it is missing, so re-running a release
# neither duplicates them nor undoes an edit someone made to the draft.
#
# The "Compatible with:" line starts out claiming nothing. The bundle is built
# by the flake's compiler, which is not a nightly anyone installs, so the line
# only ever names a nightly that has passed the suite: the release run's
# `claim` job writes the newest one that did, and name-nightly.sh moves it
# forward as newer nightlies keep passing.
set -euo pipefail

release=${1:?usage: release-notes.sh <release-tag> <bundle-url>}
url=${2:?usage: release-notes.sh <release-tag> <bundle-url>}

readme=${README:-README.md}
name=${GITHUB_REPOSITORY#*/}

[ -f "$readme" ] || {
  echo "error: no $readme to read the usage snippet from" >&2
  exit 1
}

# The README already shows how to depend on this package, which is what the
# notes have to show too: the platform it is demonstrated on, and the
# shorthand its import uses.
platform=$(sed -n 's|.*pf: platform "\([^"]*\)".*|\1|p' "$readme" | head -1)
[ -n "$platform" ] || {
  echo "error: no 'pf: platform \"...\"' line in $readme, so the notes cannot show a runnable snippet" >&2
  exit 1
}

shorthand=$(sed -n "s|^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\): \"https://github.com/$GITHUB_REPOSITORY/releases/download/.*|\1|p" "$readme" | head -1)
[ -n "$shorthand" ] || {
  echo "error: no line in $readme depends on a $GITHUB_REPOSITORY release, so the notes cannot tell what to call this package in an import" >&2
  exit 1
}

grep -q "/releases/download/$release/" "$readme" || \
  echo "::warning::$readme still shows an older release. Update its snippet to $release once this one is published."

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
gh release view "$release" --json body -q .body --repo "$GITHUB_REPOSITORY" > "$notes"
edited=

if ! grep -q '^## Roc compiler version' "$notes"; then
  {
    echo ""
    echo "## Roc compiler version"
    echo ""
    echo "Compatible with: nothing verified against this release yet."
    echo ""
    echo "Roc is currently a moving target and which version you're using matters a lot. We test the latest $name release against the latest Roc nightly and update the compatibility line above every day."
    echo ""
    echo "Oftentimes you'll still be able to use $name with other Roc versions than what's listed here, but if you run into any issues, please try the Roc version above."
  } >> "$notes"
  edited=1
fi

if ! grep -q '^## Using this release' "$notes"; then
  {
    echo ""
    echo "## Using this release"
    echo ""
    echo '```roc'
    echo "app [main!] {"
    echo "    pf: platform \"$platform\","
    echo "    $shorthand: \"$url\","
    echo "}"
    echo '```'
  } >> "$notes"
  edited=1
fi

if [ -n "$edited" ]; then
  gh release edit "$release" --notes-file "$notes" --repo "$GITHUB_REPOSITORY"
  echo "wrote the compiler and usage sections into the $release notes"
else
  echo "the $release notes already carry both sections, leaving them alone"
fi
