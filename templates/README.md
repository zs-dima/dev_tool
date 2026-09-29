# Templates

A repository takes these once and then owns them: edit freely, add recipes at the end of the
`justfile`, add jobs to CI. Nothing checks them for byte equality; what must be identical lives in
the `dev_tool` package and the reusable workflows.

Each file starts with `# dev_tool templates/<stack>/<file> @<version>`. To see what a newer template
changed against a repository's copy:

```sh
git diff --no-index path/to/repo/justfile path/to/dev_tool/templates/flutter-app/justfile
```

## The recipes the workflows run

A workflow runs a recipe by the name its input gives; the defaults are these, and a repository
renames one by passing the input.

| Recipe | Input | Run by | Does |
|---|---|---|---|
| `gen` | `codegen-recipe` | the gate with `codegen: committed` or `ignored` | the code generators: `dart run build_runner build --workspace`, then any generator outside build_runner at a pinned version |
| `gate-extra` | `extra-checks` | the gate, after analyze and before the tests | the repository's own checks |
| `build-appbundle` | `build-recipe` | `flutter-release-android.yml` | the signed AAB, from BUILD_NAME and BUILD_NUMBER |
| `build-ios-config` | `build-recipe` | `flutter-release-ios.yml` | `flutter build ios --config-only`, from BUILD_NAME and BUILD_NUMBER; xcodebuild archives |

`just check` runs what the gate runs after codegen, so a local green is CI's green.

## flutter-app

A Flutter app, a pub workspace or a single package.

| File | Note |
|---|---|
| `justfile` | The recipes above plus the everyday ones; per-developer settings (`KIT`, `DEVICE`) come from a gitignored `.env`. The app's own recipes go at the end. |
| `mise.toml` | `just` only: the Flutter version is the pubspec's `flutter: ">=X"` bound, which CI derives. |
| `renovate.json` | Extends `github>zs-dima/dev_tool`. |
| `.github/workflows/*.yml` | Callers of the gate, the releases and the test report. Keep the file name `code-analysis.yml` and the name "Code Analysis": the release probe and the test report key on them. Runner labels (hosted by default; `runs-on`, `mac-runs-on` for self-hosted) and DCM are inputs. |
| `build.yaml` | Builder options shared by the app's packages. |
| `config/keys.env.example` | Copied to the gitignored `config/keys.env`; `just check-keys` allows only `dev_tool.keys`. CI writes the file from the `KEYS_ENV` secret, composed in the caller from the repository's secrets. |
| `.editorconfig`, `.gitattributes`, `.gitignore` | LF everywhere, generated Dart collapsed in reviews, secrets never committed. |

Also in the app: `dev_tool` as a dev dependency (see the package README), `config/production.env`
and `config/development.env` for the defines, and the `dev_tool:` block:

```yaml
dev_tool:
  release:
    size_budget_mb: 90
    android: { build_number_base: 1788816828, build_number_t0: 1788869018 }  # a store history above the default clock
  keys: [SENTRY_DSN]
```

## dart-package

A Dart package (`TOOL := 'flutter'` in the `justfile` and `flutter-gate.yml` in CI for one that needs
the Flutter SDK). `deploy.yml` only for a package published to pub.dev; `.pubignore` keeps the tooling
out of the archive.

## rust

A Cargo workspace. The gate's flags are cargo aliases in `.cargo/config.toml` (`cargo lint`,
`cargo test-all`, `cargo doc-check`, and `cargo ui` for trybuild), so `just`, CI and `my-stack check`
run one definition. MSRV is `rust-version` in `Cargo.toml`, read by CI. `release.toml` makes
cargo-release bump, commit and push; `just release` tags once CI passed, and `publish.yml` (a library
only) publishes the tag through crates.io's trusted publishing. Lints belong in the workspace manifest:

```toml
[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
```

## On every machine

- `sh` on `PATH`: on Windows, Git for Windows' `Git\bin` (not `usr\bin`, which shadows `link.exe` and
  `find.exe`).
- `mise install` once per repository; on a machine whose mise config does not trust the folder,
  `mise trust` once.
- For an agent: `Bash(just *)` and `Bash(dart run dev_tool:*)` in `.claude/settings.json`, and a
  `deny` for the recipes that write to a live service or skip a confirmation (`just --yes`).
  `release` refuses without a terminal, so an agent cannot run it even with `just --yes`.
