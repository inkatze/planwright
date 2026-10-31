# shellcheck shell=bash
# emitter-lint.sh — lint what a script emits, in the format it emits, from that
# script's own test (sourced; the emitter-output-lint guard,
# doctrine/guard-catalog.md). scripts/check-emitter-lint.sh holds every script
# declaring `# Emits: <format>` to a test calling lint_emitted with its name.

unset CDPATH

# lint_emitted <format> <emitter> <file> [<dialect>]
#   markdown  markdownlint-cli2 under the repository baseline, with the rules
#             a fragment cannot meet off: a first-line heading (MD041), the
#             prose line length (MD013), and the details/summary collapse a
#             PR body uses (MD033); dialect `spec` lints a spec-bundle file
#             under specs/.markdownlint.jsonc instead, MD041 still off
#   yaml      yamllint --strict under the repository baseline, a document
#             start marker not required
#   shell     a parse with the dialect's shell (sh, or bash; default: the
#             shebang's, else sh) and shellcheck in that dialect
# An sh caller sets EMITTER_LINT_ROOT to the repository before calling.
# Status 0 clean; 1 a lint finding or a tool missing in CI; 0 with a skip line
# when the tool is missing outside CI. <emitter> names the script whose output
# this is; the guard reads it, the lint does not.
lint_emitted() {
  le_fmt=$1 le_emitter=$2 le_file=$3 le_dialect=${4:-}
  le_repo=${EMITTER_LINT_ROOT:-}
  if [ -z "$le_repo" ]; then
    # shellcheck disable=SC3028,SC3054 # bash only; an sh caller sets EMITTER_LINT_ROOT
    le_repo=$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/../.." && pwd -P) || return 1
  fi
  [ -f "$le_repo/.markdownlint.jsonc" ] || {
    printf '%s\n' "lint_emitted: cannot locate the repository (set EMITTER_LINT_ROOT)" >&2
    return 1
  }
  [ -f "$le_file" ] || {
    printf '%s\n' "lint_emitted: $le_emitter: no emitted file at $le_file" >&2
    return 1
  }
  le_dir=$(mktemp -d "${TMPDIR:-/tmp}/emitter-lint.XXXXXX") || {
    printf '%s\n' "lint_emitted: $le_emitter: could not create a temporary directory" >&2
    return 1
  }
  le_rc=0
  case $le_fmt in
    markdown)
      if le_need markdownlint-cli2 "$le_emitter"; then
        if [ "$le_dialect" = spec ]; then
          printf '{ "extends": "%s/specs/.markdownlint.jsonc", "MD041": false }\n' "$le_repo"
        else
          printf '{ "extends": "%s/.markdownlint.jsonc", "MD041": false, "MD013": false, %s }\n' \
            "$le_repo" '"MD033": { "allowed_elements": ["details", "summary"] }'
        fi >"$le_dir/.markdownlint.jsonc"
        cp -- "$le_file" "$le_dir/emitted.md" || le_rc=1
        [ "$le_rc" -ne 0 ] || (cd "$le_dir" && markdownlint-cli2 emitted.md >"$le_dir/out" 2>&1) || {
          le_rc=1
          sed "s|^|lint_emitted: $le_emitter: |" "$le_dir/out" >&2
        }
      else
        [ $? -eq 2 ] || le_rc=1
      fi
      ;;
    yaml)
      if le_need yamllint "$le_emitter"; then
        printf 'extends: %s/.yamllint\nrules:\n  document-start: disable\n' "$le_repo" >"$le_dir/config"
        yamllint --strict -c "$le_dir/config" "$le_file" >"$le_dir/out" 2>&1 || {
          le_rc=1
          sed "s|^|lint_emitted: $le_emitter: |" "$le_dir/out" >&2
        }
      else
        [ $? -eq 2 ] || le_rc=1
      fi
      ;;
    shell)
      if [ -z "$le_dialect" ]; then
        case $(head -n 1 "$le_file") in
          '#!'*bash*) le_dialect=bash ;;
          *) le_dialect="sh" ;;
        esac
      fi
      "$le_dialect" -n "$le_file" 2>"$le_dir/out" || {
        le_rc=1
        sed "s|^|lint_emitted: $le_emitter: |" "$le_dir/out" >&2
      }
      if le_need shellcheck "$le_emitter"; then
        shellcheck -s "$le_dialect" "$le_file" >"$le_dir/out" 2>&1 || {
          le_rc=1
          sed "s|^|lint_emitted: $le_emitter: |" "$le_dir/out" >&2
        }
      else
        [ $? -eq 2 ] || le_rc=1
      fi
      ;;
    *)
      printf '%s\n' "lint_emitted: unknown format '$le_fmt' (markdown, yaml or shell)" >&2
      le_rc=1
      ;;
  esac
  rm -rf -- "$le_dir"
  return "$le_rc"
}

# le_need <tool> <emitter>: 0 the tool is on PATH; otherwise a skip line and
# status 2 outside CI, a failure line and status 1 in it.
le_need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  if [ -n "${CI:-}" ]; then
    printf '%s\n' "lint_emitted: $2: $1 is not on PATH in CI" >&2
    return 1
  fi
  printf '%s\n' "skip: lint_emitted: $2: $1 is not on PATH"
  return 2
}
