# roc-workflows

Reusable GitHub Actions workflows for Roc packages.

## test.yml

Builds the pinned Roc compiler from the repo's flake (`nix build .#roc`), then runs:

1. `roc check` on the package's main module
2. `roc test` on the package's main module
3. A bundle sanity check: `roc bundle` must produce a tarball containing every
   `.roc` module in the package directory. This exists because `roc bundle`
   can exit 0 while silently omitting all modules (seen with path
   dependencies), which would publish an unusable release.

The calling repo needs the shared flake layout: a `flake.nix` exposing
`packages.roc` and a `package/main.roc` (override the location with the
`package` input).

### Usage

Add `.github/workflows/test.yml` to the repo:

```yaml
name: Test

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  test:
    uses: niclas-ahden/roc-workflows/.github/workflows/test.yml@v1
```

Callers pin `@v1` so a change here can't break every repo at once. To ship a
breaking change, tag a `v2` and move callers over one at a time. To ship a fix
within `v1`, move the `v1` tag (`git tag -f v1 && git push -f origin v1`).
