#!/usr/bin/env bash
# Point a release's "Compatible with:" line at a Roc nightly.
#
#   .github/scripts/name-nightly.sh <release-tag> <nightly-tag>
#
# Needs GH_TOKEN and GITHUB_REPOSITORY in the environment.
#
# Two workflows call this. The release flow's `claim` job runs it for the
# newest nightly that passed the advisory board's speed legs, from the
# checkout and from the drafted bundle. test-nightly-roc.yml runs it every
# morning, moving the recommendation forward as newer nightlies keep passing.
#
# Only ever call it for a nightly that has actually passed the suite. The line
# is a claim we are making to people who will install what it names.
#
# The whole line is machine owned: it is replaced outright, or inserted under
# the "## Roc compiler version" heading when the notes carry no line yet, as
# with a release that was published before any nightly had gone green.
# Anchoring on the line rather than on the first nightly link anywhere in the
# body keeps a hand written section such as "Known issues" intact: a nightly
# named there is a statement about the past and must survive.
set -euo pipefail

release=${1:?usage: name-nightly.sh <release-tag> <nightly-tag>}
nightly=${2:?usage: name-nightly.sh <release-tag> <nightly-tag>}

notes=$(mktemp)
trap 'rm -f "$notes" "$notes.bak"' EXIT
gh release view "$release" --json body -q .body --repo "$GITHUB_REPOSITORY" > "$notes"

# shellcheck disable=SC2016  # the backticks are markdown, not a subshell
current=$(sed -n 's|^Compatible with: \[`roc \(nightly-[^`]*\)`\].*|\1|p' "$notes" | head -1)

if [ "$current" = "$nightly" ]; then
  echo "$release notes already name $nightly"
  exit 0
fi

line="Compatible with: [\`roc $nightly\`](https://github.com/roc-lang/nightlies/releases/tag/$nightly)."

if grep -q '^Compatible with: ' "$notes"; then
  sed -i.bak "s|^Compatible with: .*|$line|" "$notes"
elif grep -q '^## Roc compiler version' "$notes"; then
  sed -i.bak "/^## Roc compiler version/a\\
\\
$line" "$notes"
else
  # Releases from before the notes carried a compiler section have nothing to
  # update. That is not a reason to redden a green run, so say so and stop.
  echo "::warning::$release notes carry no '## Roc compiler version' section, leaving them alone"
  exit 0
fi

gh release edit "$release" --notes-file "$notes" --repo "$GITHUB_REPOSITORY"
if [ -n "$current" ]; then
  echo "$release now names $nightly (was $current)"
else
  echo "$release now names $nightly"
fi
