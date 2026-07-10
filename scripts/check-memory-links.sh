#!/usr/bin/env bash
# check-memory-links.sh — standing machine-local reference guard
# (output-hygiene Task 6, REQ-D1.1, REQ-D1.2, D-4).
#
# A committed spec file must not carry a `[[name]]` memory-link token. Those
# links resolve only against the authoring session's private memory store, so
# a reader of the committed bundle — a human, a plugin adopter, a downstream
# tool — cannot follow them. /spec-draft neutralizes them into plain prose plus
# a `## Sources` pointer before commit (REQ-D1.2); this guard is the CI backstop
# that catches a future writer who skips that step, so the prohibition has a
# standing mechanical reader rather than relying on a one-shot grep.
#
# Scope — the four spec files of every non-terminal bundle:
#   - Files: requirements.md, design.md, tasks.md, test-spec.md. Already-signed
#     kickoff-brief bodies are append-only and out of scope (REQ-D1.1): their
#     historical `[[…]]` are a bounded, named carve-out, reconciled only where
#     the amendment ritual reaches spec files (REQ-D1.4).
#   - Bundles: every specs/<name>/ whose name does not start with `_`
#     (underscore-prefixed dirs are accumulators, not bundles). A bundle's
#     Status is read from requirements.md; terminal bundles (Done, Retired,
#     Superseded) are frozen — changing them requires a Done->Draft reopen plus
#     a scoped kickoff (doctrine/spec-format.md) — so the guard skips them and
#     re-engages automatically the moment such a bundle reopens to Draft. This
#     keeps the guard green over frozen historical bundles (e.g. a Done bundle
#     whose `[[…]]` reconcile is deferred to its future reopen) without
#     excluding any live authoring surface.
#
# Matching — code-span-aware. Inline code spans (backtick-delimited runs) are
# stripped from each line before the token search, so a documentation mention
# of the syntax itself — `[[name]]`, `[[foo]]` inside backticks — is not a live
# link and passes, while a bare `[[slug]]` is flagged. A spec that is *about*
# the `[[name]]` rule (this very bundle) can therefore discuss it in code spans
# and still pass. Parser constraint (documented, like check-doc-links.sh): only
# paired same-line backtick spans are recognized; a `[[slug]]` inside a fenced
# code block on its own line is still flagged (a fenced example should use an
# inline span or a placeholder to opt out).
#
# Usage: check-memory-links.sh [<spec-dir>...]
#   With no arguments, scans every non-accumulator bundle under specs/.
#   Each argument is a single spec bundle directory.
#
# Exit codes: 0 no live memory link found (or only skipped bundles), 1 a
# `[[name]]` token found in a scanned spec file, 2 usage error (a path argument
# that does not exist or is not a directory, or a spec file that exists but
# cannot be read — fail-closed, never reported as clean).
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale so bracket expressions mean exactly their ASCII range on
# every host (defensive; mirrors check-doc-links.sh).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitutions below.
unset CDPATH

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Collect the bundle directories to scan.
dirs=()
if [ "$#" -gt 0 ]; then
  for d in "$@"; do
    if [ ! -d "$d" ]; then
      echo "check-memory-links: not a bundle directory: $d" >&2
      exit 2
    fi
    dirs+=("$d")
  done
else
  for d in "$repo_root"/specs/*/; do
    [ -d "$d" ] || continue
    base="$(basename "$d")"
    case "$base" in
      _*) continue ;; # accumulators (specs/_observations, specs/_pending) are not bundles
    esac
    dirs+=("$d")
  done
fi

# No bundles to scan (e.g. an empty specs/) is a clean pass, not an error.
if [ "${#dirs[@]}" -eq 0 ]; then
  echo "check-memory-links: no spec bundles to scan"
  exit 0
fi

# bundle_status <dir> — echo the bundle's Status from requirements.md, or the
# empty string when requirements.md is absent or carries no Status line.
bundle_status() {
  local req="$1/requirements.md"
  { [ -f "$req" ] && [ -r "$req" ]; } || return 0
  sed -n 's/^\*\*Status:\*\*[[:space:]]*\([A-Za-z]*\).*/\1/p' "$req" | head -n 1
}

# scan_file <file> — emit one "<line>:<token>" record per bare [[...]] token in
# the file, after stripping inline (paired, same-line) code spans. Silent when
# clean.
scan_file() {
  awk '
    {
      line = $0
      gsub(/`[^`]*`/, "", line)          # drop inline code spans (documentation mentions)
      while (match(line, /\[\[[^]]*\]\]/)) {
        tok = substr(line, RSTART, RLENGTH)
        print FNR ":" tok
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$1"
}

status=0
scanned=0
skipped=0

for d in "${dirs[@]}"; do
  d="${d%/}"
  if [ ! -f "$d/requirements.md" ]; then
    echo "check-memory-links: $d has no requirements.md — skipped (validator owns structure)" >&2
    skipped=$((skipped + 1))
    continue
  fi
  st="$(bundle_status "$d")"
  case "$st" in
    Done | Retired | Superseded)
      echo "check-memory-links: $d is $st (frozen) — skipped; re-engages on Done->Draft reopen" >&2
      skipped=$((skipped + 1))
      continue
      ;;
  esac
  for f in requirements.md design.md tasks.md test-spec.md; do
    file="$d/$f"
    [ -f "$file" ] || continue
    # A file the guard cannot scan must not be reported as free of memory links
    # (fail-closed, mirroring check-doc-links.sh).
    if [ ! -r "$file" ]; then
      echo "check-memory-links: spec file not readable: $file" >&2
      exit 2
    fi
    scanned=$((scanned + 1))
    hits="$(scan_file "$file")"
    [ -z "$hits" ] && continue
    while IFS= read -r hit; do
      lineno="${hit%%:*}"
      tok="${hit#*:}"
      echo "check-memory-links: $file:$lineno carries a machine-local memory link $tok (neutralize to prose + a ## Sources pointer — REQ-D1.2; use an inline \`code span\` for a documentation mention)" >&2
      status=1
    done <<EOF
$hits
EOF
  done
done

if [ "$status" -eq 0 ]; then
  echo "check-memory-links: no machine-local memory links in $scanned scanned spec file(s) ($skipped bundle(s) skipped)"
fi
exit "$status"
