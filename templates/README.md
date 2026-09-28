# Templates

A repository takes these once and then owns them: edit freely, add recipes at the end of the
`justfile`, add jobs to CI. Nothing checks them for byte equality; what must be identical lives in
the `dev_tool` package and the reusable workflows.

Each file starts with `# dev_tool templates/<stack>/<file> @<version>`. To see what a newer template
changed against a repository's copy:

```sh
git diff --no-index path/to/repo/justfile path/to/dev_tool/templates/flutter-app/justfile
```

## flutter-app

A Flutter app of the line (a pub workspace with `tool/newapp/app.json`).

| File | Note |
|---|---|
| `justfile` | The former make targets as recipes (`stats` and `dependencies` dropped, `doctor` is `flutter-doctor`); per-developer paths (`KIT`, `DESIGN`, `DEVICE`, `DATA`) come from a gitignored `.env`. The app's own recipes go at the end. |
| `mise.toml` | `just` only: the Flutter version is the pubspec's `flutter: ">=X"` bound, which CI derives. |
| `.github/workflows/*.yml` | Callers of the reusable gate, releases and test report. Keep the file names and the name "Code Analysis": the release probe and the test report key on them. Per-app checks and runner labels (hosted by default; `runs-on`, `mac-runs-on` for self-hosted) are the `with:` inputs. |
| `.github/dependabot.yml` | Root only (a pub workspace has one lock). |
| `build.yaml` | The app's builders. `pubspec_generator` is not among them: as a dependency it breaks the app's resolution, so `just gen-ci` and CI run it as a global tool at its latest version. |
| `config/keys.env.example` | Copied to the gitignored `config/keys.env`; `just check-keys` allows only `app.json` `keys`. |
| `.editorconfig`, `.gitattributes`, `.gitignore` | LF everywhere, generated Dart collapsed in reviews, secrets never committed. |

Also in the app: `dev_tool` as a dev dependency (see the package README), and in
`tool/newapp/app.json` the release clock when the app's Play history already holds numbers above the
line clock:

```json
"release": { "android": { "versionCodeBase": 1788816828, "versionCodeT0": 1788869018 } },
"keys": ["SENTRY_DSN"]
```

## dart-package

A Dart or Flutter package (`TOOL := 'flutter'` in the `justfile` and `flutter-package.yml` in CI for
the latter). `deploy.yml` only for a package published to pub.dev; `.pubignore` keeps the tooling out
of the archive; `dart_test.yaml` writes the JSON report CI's verdict reads.

## rust

A Cargo workspace. The gate's flags are cargo aliases in `.cargo/config.toml` (`cargo lint`,
`cargo test-all`, `cargo doc-check`), so `just`, CI and `my-stack check` run one definition. MSRV is
`rust-version` in `Cargo.toml`, read by CI. Lints belong in the workspace manifest:

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
  `deny` for the recipes that write to a live service or skip a confirmation (`l10n-seed`,
  `l10n-translate`, `screenshots-upload`, `new-app`, `just --yes`). `release` refuses without a
  terminal, so an agent cannot run it even with `just --yes`.
