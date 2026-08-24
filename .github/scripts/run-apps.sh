#!/usr/bin/env bash
# Run every app in the given directories.
#
#   run-apps.sh examples
#
# The examples are the only part of a package that is compiled and run the way
# a user runs it, so a release that breaks them is a release that breaks its
# own documentation. They must therefore run to completion on their own, with
# no arguments and no input.
#
# Set ROC_OPT to pick the backend (default speed) and ROC to use a compiler
# that is not on the PATH. Directories that do not exist are skipped.
set -euo pipefail

opt=${ROC_OPT:-speed}
roc=${ROC:-roc}
ran=0

for dir in "$@"; do
  [ -d "$dir" ] || continue
  for app in "$dir"/*.roc; do
    [ -f "$app" ] || continue
    echo "--- $app (--opt=$opt)"
    "$roc" --opt="$opt" "$app"
    ran=$((ran + 1))
  done
done

echo "ran $ran app(s) from ${*:-nowhere}"
