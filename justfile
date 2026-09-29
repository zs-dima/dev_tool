# Needs `sh` on PATH (Windows: Git for Windows' `Git\bin`); tools: `mise install`.

default:
    @just --list

# What CI's `package` job runs.
[group('gate')]
check: format-check analyze test

# Hand-written Dart outside the fixtures, as the format-check action runs it with `format-exclude: ^fixtures/`.
[group('gate')]
format-check:
    git ls-files -z -- '*.dart' ':(exclude,glob)**/*.*.dart' | { grep -zvE '^fixtures/' || true; } | xargs -0 -r dart format --output=none --set-exit-if-changed

[group('gate')]
analyze:
    dart analyze --fatal-infos --fatal-warnings

[group('gate')]
test *args:
    dart run dev_tool:test_workspace {{ args }}

# The Flutter fixture as CI's `fixture-flutter` job runs it; its `gate-extra` needs Chrome.
[group('gate')]
[working-directory('fixtures/flutter_app')]
fixture:
    flutter pub get
    just gen
    git status --porcelain --untracked-files=all -- . ':(exclude,glob)**/*.lock' | { ! grep . ; }
    just check

# The Rust fixture as CI's `fixture-rust` job runs it, without the MSRV toolchain and cargo-deny.
[group('gate')]
[working-directory('fixtures/rust_workspace')]
fixture-rust:
    cargo fmt --all --check
    cargo lint
    cargo test-all
    RUSTDOCFLAGS=-Dwarnings cargo doc-check
    cargo check-all

# What CI's `actions-lint` job runs.
[group('gate')]
lint-workflows:
    actionlint .github/workflows/*.yml templates/*/.github/workflows/*.yml
    zizmor --persona=pedantic .github templates

[group('dev')]
format:
    git ls-files -z -- '*.dart' ':(exclude,glob)**/*.*.dart' | xargs -0 -r dart format

[group('dev')]
get:
    dart pub get

# Operator only: gate, bump, commit, push, wait for CI on that commit, then tag vX.Y.Z and move the
# major tag. Every caller floats on the major tag, so it never moves onto a commit CI has not passed.
[group('operator')]
[script]
release version:
    [ -t 0 ] || { echo "release is an operator command: run it from a terminal"; exit 2; }
    case "{{ version }}" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "usage: just release 1.2.3"; exit 2 ;; esac
    [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "commit or stash first: the tree is dirty"; exit 1; }
    grep -q "^## \[{{ version }}\]" CHANGELOG.md || { echo "CHANGELOG.md has no section for {{ version }}"; exit 1; }
    just check lint-workflows
    sed "s/^version: .*/version: {{ version }}/" pubspec.yaml > pubspec.yaml.tmp && mv pubspec.yaml.tmp pubspec.yaml
    git add pubspec.yaml
    git diff --cached --quiet || git commit --quiet -m "chore: release {{ version }}"
    git push --quiet origin HEAD
    sha="$(git rev-parse HEAD)"
    run=""
    for _ in $(seq 1 30); do
      run="$(gh run list --commit "$sha" --workflow ci.yml --json databaseId --jq '.[0].databaseId')"
      [ -n "$run" ] && break
      sleep 10
    done
    [ -n "$run" ] || { echo "no CI run for $sha within 5 minutes: tag it by hand once it is green"; exit 1; }
    gh run watch "$run" --exit-status || { echo "CI failed on $sha: not tagged"; exit 1; }
    git tag "v{{ version }}"
    major="v$(echo "{{ version }}" | cut -d. -f1)"
    git tag -f "$major"
    git push --quiet origin "v{{ version }}"
    git push --quiet --force origin "$major"
    echo "released v{{ version }} and moved $major"
