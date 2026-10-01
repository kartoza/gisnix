# Checks and hooks

GISNIX runs the same set of checks in three places — your local git hooks, CI on
every push and pull request, and a gate before each release — all from **one set
of scripts**, so they cannot drift apart. This page is what each check verifies
and where it runs.

The guiding rule is **eval is not build**: `nix eval` (or `nix flake check`, or a
syntax parse) proves a configuration *evaluates*, but some derivations only fail
when *built* — most notably the kanata keyboard config, validated by running
`kanata --check` inside a build. So the checks come in two weights.

## Installing the hooks

The hooks are defined in `.pre-commit-config.yaml`, all local (every tool comes
from the dev shell, nothing is fetched by pre-commit itself). Install them once:

```bash
nix develop        # or let direnv enter it
gisnix hooks
```

That installs both hook stages: the instant checks on `git commit`, the heavy
gates on `git push`.

## On commit — the instant checks

Only two things run on every commit, because only two things are both
instant and must never be wrong in a commit:

| Check | What it verifies |
|---|---|
| **nixfmt** | Nix files are formatted to the RFC style. |
| **gitleaks** | No secret is being committed (scans the staged change, scoped by `.gitleaks.toml`). |

## On demand — `gisnix validate`

The full static bank lives in pre-commit's `manual` stage: it does not run
on commit (its seconds per commit added up, and a slow hook is a hook
people `--no-verify` past), but one command runs the lot, and CI enforces
it on every push and PR regardless:

```bash
gisnix validate            # the whole tree
gisnix validate --staged   # just what is staged right now
```

| Check | What it verifies |
|---|---|
| **shellcheck** | `utils/*.sh` scripts have no shell bugs. |
| **actionlint** | GitHub Actions workflows are valid. |
| **check-bundles.py** | Every module under `software/` is claimed by a `bundle.json` (or explicitly listed unclaimed), and every import resolves. |
| **check-iso-contents.py** | Every relative reference a baked module makes resolves to something also baked onto the ISO. |
| **check-resources.py** | Brand/resource files are named and referenced consistently. |
| **check-locales.py** | Every locale names a charset glibc will actually generate. |
| **check-brand.py** | Brand colour pairings meet WCAG 2.2 AA contrast. |
| **check-duplicates.py** | No package is declared twice for one host. |
| **check-hostconfig.py** | The `config.nix` editor parses, round-trips and stays stable. |
| **check-manifest.py** | `commands.json` and the surfaces it feeds (docs, editor menus) agree, with no duplicate keys. |

## On push — the gates

These build or evaluate real configurations, so they are minutes of work — too
slow for every commit, right for the moment you publish (`pre-push` stage). Each
is a script that CI and the release also call:

| Gate | Script | What it verifies |
|---|---|---|
| **Example host builds** | `check-example-builds.sh` | The example host toplevel **builds** — the same thing a real `sudo setup` install builds. This is the "eval is not build" catch: a kanata `.kdb` that fails `kanata --check`, or any other build-time failure, is caught here. |
| **Bundles evaluate** | `check-bundle-eval.sh` | The example host with **every non-opt-in bundle** enabled *evaluates*. unfree/insecure/assertion errors throw at eval, so this is a cheap, comprehensive net for a package in a bundle the plain example host doesn't build (Google Earth, the AI assistants, Steam — all unfree). |
| **Command apps evaluate** | `check-commands-eval.sh` | Every operator command the flake mints from `commands.json` evaluates — so a row naming a nixpkgs attribute that doesn't exist can't ship as a broken `gisnix <cmd>`. |

Opt-in bundles are excluded from the bundle gate by design — they are the heavy
or deliberately rough ones (QGIS source builds, the vintage QGIS pins whose own
descriptions warn they may no longer evaluate), not what a normal install takes.

## In CI and at release

- **`ci` workflow** (`.github/workflows/build-hosts.yml`) — on every push to
  `main` and every pull request, a `checks` job runs the commit-stage hooks
  AND the manual bank (through `pre-commit`, so it is the exact same hooks
  `gisnix validate` runs) and a `gates` job runs the three gate scripts. A
  PR cannot merge past a formatting slip, a broken bundle, an unallow-listed
  package or a host that won't build, whether or not its author installed
  the local hooks.
- **`release.yml`** — runs the three gates again before it builds the ISOs and
  publishes, so a release can never ship what the gates would reject.

## Running them by hand

```bash
gisnix validate                                  # instant checks + the manual bank
pre-commit run --all-files --hook-stage pre-push # the gates
```

Or call any script directly — for example `./utils/check-bundle-eval.sh` while
working on a bundle that carries an unfree package. For a trivial push where you
want to skip a specific slow gate (CI still enforces it), `SKIP=example-host-builds
git push`.
