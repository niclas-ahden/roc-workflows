# roc-workflows

Reusable GitHub Actions workflows for our Roc packages. A package that follows
the shared layout gets, from four short caller files:

- every push checked, tested and bundled, on every operating system
- `git push origin 0.1.0` leaving a **draft** release with the bundle, the
  docs and the notes on it, gated only by the flake's compiler, with every
  nightly worth asking about tested as an advisory board
- a daily run that tests the latest published bundle against the newest Roc
  nightly and moves the compatibility line in its release notes forward
- a versioned docs site on GitHub Pages

Jump to [Wiring up a package](#wiring-up-a-package) to set one up.

## What a calling repository needs

| Path | Why |
| --- | --- |
| `flake.nix` exposing `packages.roc` | the compiler `test.yml` and the docs build use |
| `package/main.roc` | the package. Override with the `package` input |
| `README.md` | the release notes read the usage snippet out of it |
| `docs/index.html` containing `LATESTVERSION` | the docs site landing page |
| `examples/*.roc` | optional, run on every operating system |
| `tests.roc` | optional, run on every operating system |

### The two compilers

`test.yml` builds Roc from the flake, because that is the compiler the dev
shell hands you, and a repository whose own dev shell fails should go red. It
is also the only thing a release requires: it gates the draft, and it builds
the bundle and the docs that ship.

Everything nightly is advisory. Nix has no Windows support, and a downloaded
nightly is what a user of the package actually has, so the suite runs on
nightlies across every operating system to tell you which of them work. What
it finds goes into the notes' `Compatible with:` line, never into a gate.

There is no nightly pin. The nightlies a run tests are resolved fresh by
`resolve-versions.yml`, so a nightly leg can go red on Roc's schedule rather
than yours. That is the point: the flake pins the compiler you answer for,
and the nightly legs report on the world.

### The release notes

`release-notes.sh` reads the README to write the notes, so the README has to
show how to depend on this package: a `pf: platform "..."` line, and a line
depending on a release of this repository, whose shorthand becomes the import
name.

```roc
app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/....tar.zst",
    random: "https://github.com/niclas-ahden/joy-random/releases/download/0.1.0/<hash>.tar.zst",
}
```

The release fails loudly when it cannot find both, rather than publishing notes
that tell people the wrong thing.

## The workflows

### suite.yml

The per operating system matrix, called by everything that needs one. It
installs a Roc nightly, then per `opt` and per `os`:

1. `roc check` and `roc test` on the package
2. every `examples/*.roc`, run the way a user runs it
3. `./tests.roc`, if the repository has one

A caller picks the compiler and what is under test: this checkout's package, a
published bundle (`bundle-url`), or a bundle that is still a draft
(`bundle-artifact`). For the two bundle forms, `point-at-bundle.sh` rewrites
every app that depends on the package so it depends on the bundle instead, and
the package's own `roc check` and `roc test` are skipped, since a consumer has
no checkout to check. A draft release's assets need a token and roc fetches
anonymously, so a drafted bundle travels as a workflow artifact and each leg
serves it over `127.0.0.1`, which roc is willing to download from.

| Input | Default | |
| --- | --- | --- |
| `label` | required | prefix for the job names, so a caller's legs are tellable apart |
| `roc` | required | a nightly tag |
| `opts` | `["speed"]` | JSON array of backends, crossed with `os` |
| `os` | ubuntu, macos, windows | JSON array of runner labels |
| `ref` | the caller's ref | what to check out |
| `package` | `package/main.roc` | |
| `examples` | `examples` | directories whose top level `*.roc` files are run |
| `consumers` | `examples tests` | directories rewritten to point at a bundle |
| `bundle-url` | | test this published bundle instead of the checkout |
| `bundle-artifact` | | test this drafted bundle instead of the checkout |
| `setup` | | script in the calling repository, run once Roc is installed |
| `teardown` | | script in the calling repository, run after the checks |
| `node` | `false` | set up Node, implied by `bundle-artifact` |

A red leg reddens the whole call, so `needs.<job>.result` is the truth about
it. That is why callers put informational backends in a call of their own and
gate nothing on it.

`setup` and `teardown` are the escape hatch for a package that needs more than
a compiler present, such as a browser or a database. A package whose per
operating system needs go further than that keeps a `suite.yml` of its own and
calls the other workflows here (roc-playwright does).

### draft-release.yml

Bundles a tagged package with the flake's compiler, proves the tarball holds
every module, and puts it on a **draft** release together with this version's
docs and the notes a user needs. A human presses Publish.

The flake's compiler is the one the release gate proved the package on, so it
is the one that builds what ships. Which nightlies can consume the bundle is
the advisory board's question, and the answer lands in the notes through
name-nightly.yml.

Drafting before the bundle has been tested is deliberate: the drafted bundle is
the artifact the rest of the release run tests, so it has to exist first.
Nothing is public until Publish, so a run that goes red afterwards is thrown
away by deleting the draft.

It outputs `artifact`, which is what a caller hands to `suite.yml`'s
`bundle-artifact`. Inputs: `package`, `readme`. Needs
`permissions: contents: write` from the calling job.

### resolve-versions.yml

Resolves what a run tests, once, so every leg of it tests the same set rather
than whatever happened to be newest when that leg started. Outputs `nightly`,
`sha` and `prev_sha` for the newest nightly, `recommended` for the nightly the
latest release's notes recommend, and with `release: true`, this repository's
latest `release` and the `bundle` URL on it.

`recommended` is empty when there is no release or no recommendation, and
empty when it repeats `nightly`, so a caller can gate its legs on
non-emptiness and never test the same compiler twice.

### name-nightly.yml

Points a release's `Compatible with:` line at a Roc nightly, replacing the
line or inserting it under the "## Roc compiler version" heading when the
notes carry none yet, as with a release published before any nightly had gone
green. Only call it once that nightly has passed the suite against that
release: the line is a claim made to people who will install what it names.

The whole line is machine owned, and it anchors there rather than on the
first nightly link in the body, because the notes are hand edited and a
"Known issues" section may well name the nightly a bug was seen on. That is a
statement about the past and has to survive. Needs
`permissions: contents: write` from the calling job.

### test.yml

The checks every push runs under the flake's compiler at `--opt=speed`:
`roc check`, `roc test`, the examples, a bundle sanity check, and `./tests.roc`
if there is one. In the release flow this is the gate: the only job a release
requires.

The bundle sanity check exists because `roc bundle` can exit 0 while silently
omitting every module (seen with path dependencies), which would otherwise
publish an unusable release.

### deploy-docs.yml

Builds the versioned docs site and deploys it to GitHub Pages. A version's docs
live on its release as a `docs.tar.gz` asset, uploaded while the release was
still a draft, not in the repository. This collects every release's asset, adds
freshly generated docs for `main`, and writes a landing page redirecting to the
newest release that has docs.

Downloads are cached, keyed on the docs asset ids of every release rather than
on the release tags. Keying on tags would be wrong: a tag exists from the
moment a release is published, so a run in between would save a docs set
missing that release under the very key every later run reads.

**The `github-pages` environment only accepts deployments from the default
branch.** A `release` event runs on the tag, so deploying straight from it is
rejected with "Tag ... is not allowed to deploy to github-pages due to
environment protection rules". The caller template below works around it by
dispatching a run on `main` instead, which needs no repository settings. The
alternative is to widen that environment's deployment branch policy by hand.

### bundle.yml

Superseded by `draft-release.yml`, kept for repositories still on the older
publish-then-bundle flow. It runs on a published release and attaches the
bundle and the docs afterwards. New packages should use the tag driven flow.

## Wiring up a package

Four files. Replace `joy-random` with the package's name.

### `.github/workflows/test.yml`

```yaml
name: Test

on:
  push:
    branches:
      - main
  pull_request:
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  # The checks shared by every Roc package of ours, under the compiler the
  # flake pins, which is the one the dev shell hands you: roc check, roc test,
  # the examples and a bundle sanity check.
  test:
    uses: niclas-ahden/roc-workflows/.github/workflows/test.yml@v3
    secrets:
      CACHIX_AUTH_TOKEN: ${{ secrets.CACHIX_AUTH_TOKEN }}

  resolve:
    uses: niclas-ahden/roc-workflows/.github/workflows/resolve-versions.yml@v3

  # What the package has to prove per operating system, on the newest
  # downloaded nightly, because that is the compiler its users have.
  latest:
    needs: resolve
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.nightly }}
      label: Latest nightly

  # Informational and not branch protected. Running the other backends anyway
  # means we see the day one breaks, or the day one goes green.
  latest-opts:
    needs: resolve
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.nightly }}
      label: Latest nightly
      opts: '["dev", "size", "interpreter"]'
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

### `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags:
      - '[0-9]*'
  # Re-run for an existing tag: pick the tag as the ref when dispatching.
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: release-${{ github.ref_name }}
  cancel-in-progress: false

jobs:
  # The release gate, under the same compiler that builds the bundle.
  gate:
    uses: niclas-ahden/roc-workflows/.github/workflows/test.yml@v3

  resolve:
    uses: niclas-ahden/roc-workflows/.github/workflows/resolve-versions.yml@v3

  draft:
    needs: gate
    permissions:
      contents: write
    uses: niclas-ahden/roc-workflows/.github/workflows/draft-release.yml@v3

  # The advisory board. The speed legs feed `claim`, the opts legs are
  # information only, and a leg whose nightly resolves empty is skipped.
  latest:
    needs: resolve
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.nightly }}
      label: Latest nightly

  latest-opts:
    needs: resolve
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.nightly }}
      label: Latest nightly
      opts: '["dev", "size", "interpreter"]'

  recommended:
    needs: resolve
    if: needs.resolve.outputs.recommended != ''
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.recommended }}
      label: Recommended nightly

  recommended-opts:
    needs: resolve
    if: needs.resolve.outputs.recommended != ''
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.recommended }}
      label: Recommended nightly
      opts: '["dev", "size", "interpreter"]'

  # The consumer's path. roc downloads, hash checks and unbundles the drafted
  # bundle, then the suite runs against it. It catches packaging bugs, and it
  # is the half of the compatibility claim that tests what people install.
  bundle-latest:
    needs: [draft, resolve]
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.nightly }}
      label: Drafted bundle, latest nightly
      bundle-artifact: ${{ needs.draft.outputs.artifact }}

  bundle-recommended:
    needs: [draft, resolve]
    if: needs.resolve.outputs.recommended != ''
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.recommended }}
      label: Drafted bundle, recommended nightly
      bundle-artifact: ${{ needs.draft.outputs.artifact }}

  # The newest nightly whose speed legs went green from both angles,
  # preferring latest. A duplicate nightly was resolved to empty, so its
  # verdict lives in the leg above it.
  choose:
    name: Choose the nightly to claim
    needs: [resolve, latest, recommended, bundle-latest, bundle-recommended]
    if: ${{ !cancelled() }}
    runs-on: ubuntu-24.04
    outputs:
      nightly: ${{ steps.pick.outputs.nightly }}
    steps:
      - id: pick
        env:
          LATEST: ${{ needs.resolve.outputs.nightly }}
          RECOMMENDED: ${{ needs.resolve.outputs.recommended }}
          LATEST_OK: ${{ needs.latest.result == 'success' && needs.bundle-latest.result == 'success' }}
          RECOMMENDED_OK: ${{ needs.recommended.result == 'success' && needs.bundle-recommended.result == 'success' }}
        run: |
          nightly=
          if [ "$LATEST_OK" = true ]; then
            nightly=$LATEST
          elif [ "$RECOMMENDED_OK" = true ]; then
            nightly=$RECOMMENDED
          fi
          echo "nightly=$nightly" >> "$GITHUB_OUTPUT"
          if [ -n "$nightly" ]; then
            echo "claiming $nightly"
          else
            echo "::warning::no nightly passed speed from both the checkout and the bundle, so the notes will claim nothing"
          fi

  claim:
    needs: [draft, choose]
    if: ${{ !cancelled() && needs.draft.result == 'success' && needs.choose.outputs.nightly != '' }}
    permissions:
      contents: write
    uses: niclas-ahden/roc-workflows/.github/workflows/name-nightly.yml@v3
    with:
      release: ${{ github.ref_name }}
      nightly: ${{ needs.choose.outputs.nightly }}
```

The shape of it:

1. `gate` is the only requirement: the flake's compiler at speed running
   `roc check`, `roc test`, the examples, the bundle sanity check and
   `./tests.roc`. It gates `draft` and nothing else does.
2. `draft` bundles the package and its docs with that same compiler and
   drafts the release.
3. The advisory board tests each distinct nightly (the newest one and the one
   the previous release recommends) from this checkout at speed, on the other
   backends, and from the drafted bundle the way a consumer will.
4. `claim` writes the newest nightly that passed speed from both the checkout
   and the bundle into the notes' `Compatible with:` line, preferring latest.
   When none passed, the notes say nothing is verified yet, and the daily
   workflow fills the line in on the first green morning.

The advisory board may be red without blocking anything. Read it, decide
whether to publish, and throw a bad run away by deleting its draft.

### `.github/workflows/test-nightly-roc.yml`

```yaml
name: Test latest release on latest nightly Roc

on:
  schedule:
    # Nightlies publish between 10:00 and 13:30 UTC.
    - cron: '0 15 * * *'
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: nightly-roc
  cancel-in-progress: false

jobs:
  resolve:
    uses: niclas-ahden/roc-workflows/.github/workflows/resolve-versions.yml@v3
    with:
      release: true

  # The versions go in the job name, because `run-name` cannot see `needs`.
  test:
    needs: resolve
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.nightly }}
      label: joy-random ${{ needs.resolve.outputs.release }} on ${{ needs.resolve.outputs.nightly }}
      ref: ${{ needs.resolve.outputs.release }}
      bundle-url: ${{ needs.resolve.outputs.bundle }}

  advisory:
    needs: resolve
    uses: niclas-ahden/roc-workflows/.github/workflows/suite.yml@v3
    with:
      roc: ${{ needs.resolve.outputs.nightly }}
      label: Advisory ${{ needs.resolve.outputs.release }} on ${{ needs.resolve.outputs.nightly }}
      opts: '["dev", "size", "interpreter"]'
      ref: ${{ needs.resolve.outputs.release }}
      bundle-url: ${{ needs.resolve.outputs.bundle }}

  recommend:
    needs: [resolve, test]
    permissions:
      contents: write
    uses: niclas-ahden/roc-workflows/.github/workflows/name-nightly.yml@v3
    with:
      release: ${{ needs.resolve.outputs.release }}
      nightly: ${{ needs.resolve.outputs.nightly }}

  name-commit-range:
    name: Name the commit range
    needs: [resolve, test]
    if: needs.test.result == 'failure'
    runs-on: ubuntu-24.04
    steps:
      - run: |
          echo "::error::joy-random ${{ needs.resolve.outputs.release }} fails on roc ${{ needs.resolve.outputs.nightly }}"
          echo "  https://github.com/roc-lang/roc/compare/${{ needs.resolve.outputs.prev_sha }}...${{ needs.resolve.outputs.sha }}"
```

This goes red every morning until the package's first release is published,
since there is nothing released to test yet.

### `.github/workflows/deploy-docs.yml`

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
  release:
    types: [published]

  workflow_dispatch:

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  # A release event runs on the tag, and the github-pages environment only
  # accepts deployments from the default branch, so a deploy from here would be
  # rejected outright. Hand the work to a run on main instead. A
  # workflow_dispatch is one of the two events GITHUB_TOKEN is allowed to
  # raise, so this does start a new run.
  dispatch:
    name: Deploy from main instead
    if: github.event_name == 'release'
    runs-on: ubuntu-24.04
    permissions:
      actions: write
    steps:
      - env:
          GH_TOKEN: ${{ github.token }}
        run: gh workflow run deploy-docs.yml --ref main --repo "$GITHUB_REPOSITORY"

  deploy:
    if: github.event_name != 'release'
    permissions:
      contents: read
      pages: write
      id-token: write
    uses: niclas-ahden/roc-workflows/.github/workflows/deploy-docs.yml@v3
```

Every `permissions` block above belongs to the caller. A called workflow never
holds more than the job that calls it, so leaving one out means the job fails
on a missing scope rather than doing less.

## Releasing a package

```sh
git tag 0.1.0 && git push origin 0.1.0
```

Then watch the run. When the gate is green and the advisory board reads the
way you want, edit the drafted notes if you want to and press Publish.
Publishing deploys the docs. Afterwards, update the README's usage snippet to
the new version and hash, which the release warns about.

## Cutting a new version of roc-workflows

A reusable workflow cannot see which ref it was called at, so the workflows
here name it themselves, in the `TOOLING_REF` variable at the top of each one,
to check their own scripts out at the version the caller asked for.

So: bump every `TOOLING_REF` to the new tag, commit, then tag. One command:

```sh
new=v4
sed -i "s|TOOLING_REF: v[0-9.]*|TOOLING_REF: $new|" .github/workflows/*.yml
git commit -am "$new" && git tag -a "$new" -m "$new" && git push origin main "$new"
```

check-tooling-ref.yml runs on the tag push and goes red if any file names a
different version than the tag, so a forgotten bump is caught within a minute,
before any caller has moved. Callers move over by bumping `@v3` in their four
files.
