# dev_tool

Shared developer tooling for Flutter, Dart and Rust repositories: one versioned source for what used
to be copied into every repository and drifted there. Three parts, each consumed by reference rather
than by copy:

| Part | What | How a repository uses it |
|---|---|---|
| The `dev_tool` Dart package | Executables for Dart and Flutter repositories (below) | a dev dependency by git tag; `dart run dev_tool:<name>` |
| Reusable workflows and composite actions | Gates for Flutter, Dart and Rust; Flutter releases to Play and App Store Connect; pub.dev and crates.io publishing; the test report; the workflow lint | a short caller in `.github/workflows/`, `@v2` |
| `templates/<stack>/` | `justfile`, `mise.toml`, `renovate.json`, CI callers, editor and git config for `flutter-app`, `dart-package`, `rust` | copied once, then the repository's own ([templates/README.md](templates/README.md)) |

What must be identical everywhere lives in the package and the workflows. What a repository tunes
lives in its `justfile`: the workflows run its recipes by name for codegen (`gen`), its own checks
(`gate-extra`) and its release builds (`build-appbundle`, `build-ios-config`), so a local run and CI
are one definition.

## Configuration

The executables read one block of the repository's `pubspec.yaml`. Every key is optional; a key they
do not know is an error, so a typo cannot pass as a default.

```yaml
dev_tool:
  test:
    extra: [example, worker]   # directories outside the workspace the runner also tests
  release:
    size_budget_mb: 90         # the ceiling of a release bundle, MiB
    android:                   # a clock per platform; absent: minutes since 2020-01-01
      build_number_base: 1788816828
      build_number_t0: 1788869018
  keys: [SENTRY_DSN]           # what config/keys.env may hold; absent: nothing
```

## Executables

| Name | Does |
|---|---|
| `test_workspace` | Runs the tests of the root, every pub workspace member and each `dev_tool.test.extra` (a Dart package or an npm project); fails unless both the exit code and each JSON report say it passed |
| `coverage_summary` | Each tested package's line coverage as a Markdown table, generated files left out |
| `kit link --kit <dirs>` / `kit unlink` | Points the dependencies that have a local checkout at it through `pubspec_overrides.yaml` |
| `build_number <platform>` | The release build number: minutes on the platform's clock |
| `check_keys` | Refuses a keys file that holds a key `dev_tool.keys` does not allow |
| `size_gate --file <bundle>` | The bundle's size as a table, gated by `dev_tool.release.size_budget_mb` when it is set |
| `release_notes [version]` | The CHANGELOG section as GitHub notes and Play "What's new" cards |

Each takes `--root` and `--help`; a usage error exits 2.

## Workflows and actions

| Workflow | For | What it runs |
|---|---|---|
| `flutter-gate.yml` | anything that needs the Flutter SDK | format, codegen (`none`, `committed` or `ignored`), analyze, DCM, the `extra-checks` recipe, tests, Android JVM tests, coverage, example builds, publish check |
| `dart-gate.yml` | pure-Dart packages | format, analyze, the `extra-checks` recipe, tests, publish check; a job per runner in `os` |
| `flutter-release-android.yml`, `flutter-release-ios.yml` | Flutter apps | the gate unless the commit already passed it, the repository's build recipe, signing, size, Sentry symbols, Play or App Store Connect |
| `pub-publish.yml` | Dart and Flutter packages | the publish check, then pub.dev through OIDC |
| `rust-ci.yml` | Cargo workspaces | fmt, the `lint`, `test-all` and `doc-check` aliases, MSRV, cargo-deny, semver-checks, trybuild `ui` |
| `test-report.yml` | every stack | the JSON reports as a check, from a `workflow_run` caller |
| `actions-lint.yml` | every repository | actionlint and zizmor at the repository's pinned versions |

The `rust-publish` action publishes a Cargo workspace to crates.io through trusted publishing, from
the repository's own `publish.yml`, the file crates.io's trusted publisher names.

## Consuming it

```yaml
# pubspec.yaml
dev_dependencies:
  dev_tool:
    git:
      url: https://github.com/zs-dima/dev_tool.git
      tag_pattern: v{{version}}
    version: ^2.0.0
```

```yaml
# .github/workflows/code-analysis.yml
jobs:
  gate:
    uses: zs-dima/dev_tool/.github/workflows/flutter-gate.yml@v2
    with:
      codegen: committed
      extra-checks: gate-extra
```

Not on pub.dev: it refuses the name as too similar to `devtools`. A repository's `renovate.json`
extends `github>zs-dima/dev_tool`; Renovate's lock-file maintenance moves the git dependency within
`^2`, and a new major tag of the workflows arrives as its own pull request.

## Versions

A release is a tag `vX.Y.Z`, and the major tag moves to it once CI passed on that commit
(`just release X.Y.Z`, operator only). A `v2` workflow uses only the command-line surface of
dev_tool 2.0.0, and its inputs and secrets are add-only with defaults; anything else is `v3`, and
callers move one at a time. `v1` stays at 1.0.1. Third-party actions are pinned by commit SHA and
bumped here, once, for every caller.

## Working on it

`just check` (format, analyze, tests), `just fixture` and `just fixture-rust` (the fixtures as CI
runs them), `just lint-workflows` (actionlint, zizmor pedantic). A workflow or action change is
proven by CI's fixture jobs before it is released, and by the first consumer's build-only rehearsal
before that consumer tags a release.

## Requirements

Dart >= 3.13 (Flutter >= 3.47 for apps), `just` >= 1.56 and `sh` on `PATH` for the recipes; on
Windows that is Git for Windows' `Git\bin` (from PowerShell it is not there by default, and `bash`
there is the WSL launcher). `mise install` in a repository installs the tools its `mise.toml` pins.

The workflows run on GitHub-hosted runners unless the caller passes runner labels (`runs-on`, and
`mac-runs-on` for the iOS archive). A self-hosted runner keeps the Flutter SDK and the pub cache on
disk, so nothing is restored there, and needs GitHub's runner 2.336.0 or newer for `uses: $/...`.
