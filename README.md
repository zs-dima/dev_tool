# dev_tool

Shared developer tooling for standalone repositories: one place for what used to be copied into every
repository and drifted there. Three parts, each consumed by reference rather than by copy:

| Part | What | How a repository uses it |
|---|---|---|
| The `dev_tool` Dart package | Executables for Dart and Flutter repositories (below) | a dev dependency by git tag; `dart run dev_tool:<name>` |
| Reusable workflows and composite actions | The Flutter app gate and releases (Android, iOS), the Dart and Flutter package gates (with a publish check: the published set free of secrets, the version in CHANGELOG), the test report | a 10–40 line caller in `.github/workflows/`, `@v1` |
| `templates/<stack>/` | `justfile`, `mise.toml`, CI callers, editor and git config for `flutter-app`, `dart-package`, `rust` | copied once, then the repository's own ([templates/README.md](templates/README.md)) |

Logic that must be identical everywhere lives in the package and the workflows; what each repository
tunes (flags, paths, its own recipes) lives in its `justfile`.

## Executables

| Name | Does | Used by |
|---|---|---|
| `test_workspace` | Runs every package's tests (root, pub workspace members, `dev_tool: test: extra:` directories: a Dart package or an npm project) and fails unless both the exit code and each JSON report say it passed | `just test`, CI, `my-stack check` |
| `kit link --kit <dirs>` / `kit unlink` | Points the direct dependencies that have a local checkout at it through `pubspec_overrides.yaml`; the set is derived from the pubspecs | `just kit-link` |
| `build_number android\|ios` | The release build number: minutes on the app's clock (`release.<platform>` in `tool/newapp/app.json`, else minutes since 2020) | `just build-*`, the release workflows |
| `check_keys` | Refuses a build whose `config/keys.env` holds a key `app.json` `keys` does not allow (default `SENTRY_DSN`) | `just build-*` |
| `size_gate --aab\|--ipa <file>` | The bundle against `app.json` `sizeBudgetMb`, with a step-summary table | `just size-aab`, the release workflows |
| `release_notes [version]` | The CHANGELOG section as GitHub notes and Play "What's new" cards (en-US from the changelog; another locale from a written `store/play/listing/<locale>/whatsnew.txt`) | the Android release workflow |

## Consuming it

```yaml
# pubspec.yaml of a Flutter app (the root of its pub workspace)
dev_dependencies:
  dev_tool: ^1.0.1
```

Before a version is on pub.dev, or to run an unreleased tag, the same package by git tag:

```yaml
dev_dependencies:
  dev_tool:
    git:
      url: https://github.com/zs-dima/dev_tool.git
      tag_pattern: v{{version}}
    version: ^1.0.1
```

```yaml
# .github/workflows/code-analysis.yml
jobs:
  gate:
    uses: zs-dima/dev_tool/.github/workflows/flutter-app-gate.yml@v1
```

Dependabot bumps the hosted dependency; a git dependency is bumped by hand (`dart pub upgrade dev_tool`).
It bumps `@v1` to `@v2` when one exists.

## Versions

A release is a tag `vX.Y.Z`, and `v1` moves to it (`just release X.Y.Z`, operator only). Within `v1`
the workflows call only the executables of `dev_tool` 1.x, and their inputs and secrets are add-only
with defaults; anything else is `v2`, and callers move one at a time. Third-party actions are pinned
by commit SHA and bumped by Dependabot here, once, for every caller.

## Working on it

`just check` (format, analyze, tests), `just lint-workflows` (actionlint, zizmor over the workflows,
actions and templates), and the fixture jobs in CI prove a change; a workflow or action change is
proven by the fixture jobs before it is released, and by the first consumer's build-only rehearsal
before that consumer tags a release.

## Requirements

Dart >= 3.13 (Flutter >= 3.47 for apps), `just` >= 1.56 and `sh` on `PATH` for the recipes; on
Windows that is Git for Windows' `Git\bin` (from PowerShell it is not there by default, and `bash`
there is the WSL launcher). `mise install` in a repository installs the tools its `mise.toml` pins.

The workflows run on GitHub-hosted runners by default. A repository with its own runners passes their
labels: `runs-on: '["self-hosted","Linux"]'` and, for the iOS archive, `mac-runs-on`. On a hosted
runner the Flutter SDK and the pub cache are restored from the Actions cache; a self-hosted runner
keeps them in its tool cache and on disk, so nothing is restored there.
