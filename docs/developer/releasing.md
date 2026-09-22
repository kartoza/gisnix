# Releasing

A release is: bump the version, record it in `CHANGELOG.md`, tag the
commit, push the tag. Pushing a `v*` tag is the trigger — CI takes it from
there. There is no separate "publish" step and no dry-run mode on a normal
push: the moment a `v*` tag lands on GitHub, a public release is being
built.

## Steps

1. **Bump `VERSION`.** One line, no trailing newline content beyond the
   version itself — `0.13.1`, following semver. Patch for fixes, minor for
   features, major for breaking changes (same rule as everywhere else in
   this project).

2. **Add a `CHANGELOG.md` section.** Keep a Changelog format, newest on
   top:

   ```markdown
   ## [0.13.1] - 2026-09-22

   ### Fixed

   - What changed, in the past tense, one bullet per notable change.
   ```

   The heading must read exactly `## [X.Y.Z] - date` — CI's release-notes
   extraction is an `awk` script matching `^## \[VERSION\]` literally
   against the tag (minus its `v`). A mismatched or missing heading means
   the GitHub Release ships with a placeholder body instead of real notes.

3. **Commit.** Conventional Commits, matching this project's normal
   convention: `chore: cut 0.13.1 — <short summary>`.

4. **Tag.** An annotated tag, `vX.Y.Z`, message following the same
   `X.Y.Z — <short summary>` shape as the commit:

   ```bash
   git tag -a v0.13.1 -m "0.13.1 — <short summary>"
   ```

5. **Push both.**

   ```bash
   git push origin main
   git push origin v0.13.1
   ```

   The tag push is what matters — `.github/workflows/release.yml` triggers
   on any `v*` tag, whether or not `main` was pushed first (though push
   `main` too; a tag whose commit never reaches the default branch is
   confusing to browse later).

## What CI does

Once the tag lands, `.github/workflows/release.yml` runs unattended:

1. Checks out the tag.
2. Builds `nixosConfigurations.installer.config.system.build.isoImage` — a
   full ISO build, so this takes a while.
3. Copies the result to two filenames (each with a `.sha256` alongside it),
   the same bytes both times:
   - `gisnix-installer.iso` — always this name, never one with the version
     baked in. That is what makes
     `https://github.com/kartoza/gisnix/releases/latest/download/gisnix-installer.iso`
     a permanent link, which is what the docs site's download button points
     at.
   - `gisnix-installer-vX.Y.Z.iso` — a hard link to the same file, named for
     this specific release, for grabbing an exact version rather than
     whatever "latest" currently means (testing a fix, pinning to a
     known-good ISO, browsing several versions on the Releases page).
4. Extracts this version's section out of `CHANGELOG.md` (step 2 above) as
   the release body.
5. Publishes a GitHub Release named `gisnix vX.Y.Z`, tag `vX.Y.Z`, with both
   ISOs and both checksums attached.

No manual "are you sure" gate exists beyond the tag push itself — treat
`git push origin vX.Y.Z` as the point of no return, not the commit before
it.

If a release build needs re-running without a new tag (a fixed CI script,
say), trigger it by hand: **Actions → Release → Run workflow**, supplying
the existing tag name. This re-runs the same build/publish steps against
that tag without requiring a new version.

## Downstream: bump the pin

Cutting a gisnix release does not, by itself, change what any consumer
(nix-config, or any other downstream flake) actually builds — a consumer
pins gisnix to a specific tag in its own `flake.nix` (`url =
"github:kartoza/gisnix/vX.Y.Z"`) and has to bump that explicitly, then
relock:

```bash
# in the consumer flake
nix flake lock --update-input gisnix
```

Bumping the pin string in `flake.nix` *before* the tag actually exists on
GitHub leaves the flake unable to lock at all — `nix flake lock`/`nix
develop`/anything that touches the lock file fails outright until either
the tag is pushed or the pin is reverted. Land the gisnix release first,
confirm the tag is actually on GitHub (`git ls-remote --tags
git@github.com:kartoza/gisnix.git`), then bump the downstream pin.
