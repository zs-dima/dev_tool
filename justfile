# Needs `sh` on PATH (Windows: Git for Windows' `Git\bin`); tools: `mise install`.

default:
    @just --list

[group('gate')]
check: format-check analyze test

[group('gate')]
format-check:
    dart format --output=none --set-exit-if-changed .

[group('gate')]
analyze:
    dart analyze --fatal-infos --fatal-warnings

[group('gate')]
test *args:
    dart run dev_tool:test_workspace {{ args }}

# The fixture app through the runner, as the fixture CI jobs run it.
[group('gate')]
[working-directory('fixtures/flutter_app')]
fixture:
    flutter pub get
    dart run dev_tool:test_workspace

[group('gate')]
lint-workflows:
    actionlint -config-file .github/actionlint.yaml .github/workflows/*.yml templates/*/.github/workflows/*.yml
    zizmor --persona=regular .github templates

[group('dev')]
format:
    dart format .

[group('dev')]
get:
    dart pub get

# Operator only: gate, bump, commit, tag vX.Y.Z, move v1, push.
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
    git tag "v{{ version }}"
    major="v$(echo "{{ version }}" | cut -d. -f1)"
    git tag -f "$major"
    git push --quiet origin HEAD "v{{ version }}"
    git push --quiet --force origin "$major"
    echo "released v{{ version }} and moved $major"
