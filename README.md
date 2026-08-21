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
    uses: niclas-ahden/roc-workflows/.github/workflows/test.yml@v2
    secrets:
      CACHIX_AUTH_TOKEN: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

### Filling the binary cache

Every run reads niclas-ahden.cachix.org, so the pinned compiler is a download
rather than half an hour of compiling. Something has to put it there, and a dev
machine cannot: the cache needs an `x86_64-linux` build and Nix does not
cross-compile to it from a Mac. So CI does it.

Set a `CACHIX_AUTH_TOKEN` repository secret with write access to the cache and
pass it as above. A run then pushes the compiler and the devShell only when all
of these hold:

- the secret reached the workflow
- the event is a `push` or a `workflow_dispatch`
- the ref is the repo's default branch

A pull request therefore never writes, and one from a fork is handed no secret
at all. The step says which of the three failed, so a run that unexpectedly
only reads is one log line to diagnose.

Leaving the secret out is supported and costs nothing extra: the repo keeps
reading the cache, and whichever repo does hold the token fills it, since the
compiler derivation is the same everywhere the same `roc-src` is pinned. After
a pin bump, the first run to build is the slow one; merge it to the default
branch and the rest are fast. `workflow_dispatch` re-pushes without a commit,
for when the cache has been pruned.

## bundle.yml

Runs on a published release. Builds the pinned compiler, bundles the package,
and attaches two assets to the release:

1. `<package>-<hash>.tar.zst`, the bundle the package's users depend on
2. `docs.tar.gz`, this version's docs, frozen so `deploy-docs.yml` can collect
   it into the versioned docs site

This is for packages, not platforms. A platform needs its host built, its
examples run, and its own release notes, so it keeps a bundle workflow of its
own.

### Usage

Add `.github/workflows/bundle.yaml` to the repo:

```yaml
name: Bundle

on:
  release:
    types:
      - published

jobs:
  bundle:
    permissions:
      contents: write
    uses: niclas-ahden/roc-workflows/.github/workflows/bundle.yml@v2
```

Keep the workflow named `Bundle`, because `deploy-docs.yml` triggers on a
`workflow_run` of that name. The `permissions` block belongs to the caller, as
described under `deploy-docs.yml` below.

## deploy-docs.yml

Builds the versioned docs site and deploys it to GitHub Pages. A version's docs
live on its release as a `docs.tar.gz` asset (uploaded by the repo's own bundle
workflow), not in the repo, so this workflow collects every release's asset,
adds freshly generated docs for `main`, and writes a landing page that redirects
to the newest release that has docs.

The calling repo needs the shared flake layout (a `flake.nix` exposing
`packages.roc`), a `package/main.roc` (override with the `package` input), and a
landing page template containing `LATESTVERSION` (override with the
`landing-page` input, default `docs/index.html`).

Downloads are cached, keyed on the docs asset ids of every release. Keying on
release tags instead would be wrong: a tag exists from the moment a release is
published, but its docs are uploaded ~15 minutes later by the bundle workflow,
so any run in between would save a docs set that is missing that release under
the very key every later run reads.

### Usage

Add `.github/workflows/deploy-docs.yml` to the repo:

```yaml
name: Deploy docs to Pages

on:
  push:
    branches:
      - main
    paths:
      - '**.roc'
      - 'docs/index.html'
      - '.github/workflows/deploy-docs.yml'
  workflow_run:
    workflows: ["Bundle"]
    types:
      - completed

  workflow_dispatch:

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  deploy:
    # A Bundle that failed uploaded no docs, so there is nothing new to publish.
    if: github.event_name != 'workflow_run' || github.event.workflow_run.conclusion == 'success'
    permissions:
      contents: read
      pages: write
      id-token: write
    uses: niclas-ahden/roc-workflows/.github/workflows/deploy-docs.yml@v2
```

The `permissions` block belongs to the caller. A called workflow can never hold
more than the job that calls it, so leaving it out means the Pages deployment
fails on a missing `pages: write`.
