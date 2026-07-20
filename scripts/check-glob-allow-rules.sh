#!/usr/bin/env bash
# check-glob-allow-rules.sh — correct-glob allow-rule discipline check
# (fleet-hardening Task 6, D-6, REQ-B1.3, REQ-E1.3).
#
# Two guards, both pure shell — no model or API call is in the decision path
# (REQ-E1.3, carrying fleet-autonomy D-18):
#
#   1. Footgun scan. A path-scoped Bash allow/deny rule must use the
#      `Bash(<dir>/*)` glob, never the word-boundary `Bash(<dir>/:*)` form.
#      Claude Code's `:*` is a COMMAND-boundary glob: it matches only when a
#      space or end-of-string follows the prefix, so `Bash(<dir>/:*)` never
#      matches `<dir>/<file>` (a filename, not a space, follows the slash) and
#      the rule silently never fires. Already-bitten: a machine-local
#      `Bash(<scripts-dir>/:*)` rule silently never matched the wrapper path on
#      2026-07-19 and forced a bare launch. The scan flags any shipped config
#      allow/deny entry whose inner text ends in `/:*`, while passing the
#      correct `/*` path form and the legitimate command globs
#      (`Bash(git status:*)`, `Bash(mise run:*)`), whose `:*` is correct.
#      The scan matches one rule token per line (the pretty-printed
#      one-entry-per-line JSON the profiles ship as, which excludes `_about`
#      prose so the pedagogical `:*` examples are not flagged); a compact or
#      minified array with multiple tokens on a line is out of scope.
#
#   2. Doc-presence. The correct-form rule must be documented in the adopter
#      allow-rule guidance (docs/overlays.md) and the worker-settings profile,
#      and cross-referenced from the ghost-text (D-5) doc and — once it exists —
#      the tower-guard (D-8) doc. The tower-settings profile is a Task 7
#      deliverable; until config/tower-settings.json exists its cross-reference
#      requirement is vacuously satisfied (this is what lets Task 6 land
#      independently of Task 7, brief §6), and becomes enforced the moment the
#      profile ships — so a later tower-settings author cannot omit it silently.
#
# Usage:
#   check-glob-allow-rules.sh              full check: footgun scan over
#                                          config/*.json + doc-presence
#   check-glob-allow-rules.sh <file>...    footgun scan of the given files only
#   check-glob-allow-rules.sh --docs       doc-presence check only
#
# Doc-presence paths are overridable via env (defaults resolve under the repo
# root): GLOB_ALLOW_OVERLAYS, GLOB_ALLOW_GHOST_DOC, GLOB_ALLOW_WORKER_SETTINGS,
# GLOB_ALLOW_TOWER_SETTINGS.
#
# Exit codes: 0 clean, 1 a footgun rule or a missing doc/cross-reference, 2
# usage error (an input file that does not exist or cannot be read — fail
# closed, never reported clean).
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale so bracket expressions mean exactly their ASCII range on
# every host (defensive; mirrors check-memory-links.sh).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitution below.
unset CDPATH

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Stable markers the doc-presence check greps for — the single source of truth,
# so the docs must carry these exact strings. GUIDE_ANCHOR is the GitHub
# heading-slug of GUIDE_HEADING (checked by check-doc-links.sh).
GUIDE_HEADING="### Path-scoped allow rules use the slash-star glob"
GUIDE_ANCHOR="overlays.md#path-scoped-allow-rules-use-the-slash-star-glob"
NOTE_MARKER="path-scoped allow entries use the trailing"

status=0

# scan_allow_file <file> — emit each flagged footgun entry as "<lineno>:<token>".
# A rule entry is a standalone JSON array string: a line whose whole trimmed
# content is a quoted "Bash(...)" token (optional trailing comma). This excludes
# prose fields like "_about" (whose line starts with a different key), so a
# documentation mention of the forbidden token is never miscounted as a live
# rule. A token is a footgun when its inner text ends in `/:*`.
scan_allow_file() {
  awk '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line ~ /^"Bash\([^"]*\)",?$/) {
        tok = line
        sub(/^"/, "", tok)
        sub(/",?$/, "", tok)
        inner = tok
        sub(/^Bash\(/, "", inner)
        sub(/\)$/, "", inner)
        if (inner ~ /\/:\*$/) print FNR ":" tok
      }
    }
  ' "$1"
}

# run_footgun_scan <file>... — scan each file; set status=1 on any finding, and
# fail closed (exit 2) on an unreadable input.
run_footgun_scan() {
  local f hits hit lineno tok
  for f in "$@"; do
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
      echo "check-glob-allow-rules: input not found or unreadable: $f" >&2
      exit 2
    fi
    hits="$(scan_allow_file "$f")"
    [ -z "$hits" ] && continue
    while IFS= read -r hit; do
      lineno="${hit%%:*}"
      tok="${hit#*:}"
      echo "check-glob-allow-rules: $f:$lineno path-scoped rule uses the never-match ':*' word-boundary form: $tok — use the '/*' path glob (Bash(<dir>/*)) instead (D-6, REQ-B1.3)" >&2
      status=1
    done <<EOF
$hits
EOF
  done
}

# doc_has <file> <literal-substring> — true iff the file is readable and holds
# the literal substring. An unreadable file is a fail, never a silent pass.
doc_has() {
  { [ -f "$1" ] && [ -r "$1" ]; } || return 1
  grep -Fq -- "$2" "$1"
}

# run_doc_presence — verify the guidance and cross-references exist.
run_doc_presence() {
  local overlays ghost worker tower
  overlays="${GLOB_ALLOW_OVERLAYS:-$repo_root/docs/overlays.md}"
  ghost="${GLOB_ALLOW_GHOST_DOC:-$repo_root/docs/fleet.md}"
  worker="${GLOB_ALLOW_WORKER_SETTINGS:-$repo_root/config/worker-settings.json}"
  tower="${GLOB_ALLOW_TOWER_SETTINGS:-$repo_root/config/tower-settings.json}"

  # 1. Guidance section present in the adopter allow-rule guidance.
  if ! doc_has "$overlays" "$GUIDE_HEADING"; then
    echo "check-glob-allow-rules: allow-rule glob guidance missing from $overlays (expected a '$GUIDE_HEADING' section — D-6, REQ-B1.3)" >&2
    status=1
  fi
  # 2. Worker-settings profile carries the discipline note.
  if ! doc_has "$worker" "$NOTE_MARKER"; then
    echo "check-glob-allow-rules: worker-settings profile $worker lacks the path-scoped allow-rule note ('$NOTE_MARKER …' — D-6)" >&2
    status=1
  fi
  # 3. Ghost-text (D-5) doc cross-references the guidance.
  if ! doc_has "$ghost" "$GUIDE_ANCHOR"; then
    echo "check-glob-allow-rules: ghost-text doc $ghost does not cross-reference the glob guidance (expected a link to $GUIDE_ANCHOR — D-6)" >&2
    status=1
  fi
  # 4. Tower-guard (D-8) doc cross-references it — enforced once it exists
  #    (Task 7 deliverable; deferred, not skipped, until then).
  if [ -f "$tower" ]; then
    if ! doc_has "$tower" "$NOTE_MARKER"; then
      echo "check-glob-allow-rules: tower-settings profile $tower lacks the path-scoped allow-rule note ('$NOTE_MARKER …' — D-6, Task 7 must carry it)" >&2
      status=1
    fi
  else
    echo "check-glob-allow-rules: tower-settings profile not present yet ($tower) — tower-guard cross-reference deferred to Task 7"
  fi
}

case "${1:-}" in
  --docs)
    run_doc_presence
    ;;
  "")
    # Full check: footgun scan over the shipped config JSON profiles, then the
    # doc-presence pass.
    set -- "$repo_root"/config/*.json
    if [ "$1" = "$repo_root/config/*.json" ] && [ ! -e "$1" ]; then
      echo "check-glob-allow-rules: no config/*.json profiles to scan" >&2
    else
      run_footgun_scan "$@"
    fi
    run_doc_presence
    ;;
  *)
    run_footgun_scan "$@"
    ;;
esac

if [ "$status" -eq 0 ]; then
  echo "check-glob-allow-rules: clean"
fi
exit "$status"
