#!/usr/bin/env bash
# check-ledger.sh — structural-corruption + duplicate-Status guards over the
# committed tasks.md snapshot (orchestration-concurrency Task 7; REQ-E1.1,
# REQ-E1.2, REQ-E1.3; D-1).
#
# Progress state is a DERIVED PROJECTION (D-1): the committed tasks.md sections
# are a discardable read-model the reconcile pass owns and refreshes from truth.
# These guards do NOT check freshness — a well-formed snapshot that merely LAGS
# live truth (a not-yet-reconciled in-flight task still shown under Forward plan
# with no Status) is correct, not corrupt (REQ-E1.1). Freshness is the reconcile
# pass's responsibility (REQ-B1.2). What these guards catch is *structural
# corruption*: placement/state signatures the level-triggered reconcile would
# never produce from any evidence, detectable from the snapshot file alone (no
# git, no gh, deterministic in CI):
#
#   (a) Structural-corruption check (REQ-E1.1):
#       - wrong-block placement contradicting the block's OWN Status evidence
#         (e.g. a `merged` block left under Forward plan; an `implementing`
#         block under Completed; a Completed-section block with no completion
#         Status). "Its own evidence" is the block's Status annotation — the
#         reconcile writes the Status when it places the block, so a Status that
#         disagrees with the section is a placement the reconcile never emits;
#       - a mis-sort / duplicated block (the same task id under two sections —
#         the signature of a concurrent move that copied instead of relocating);
#       - a malformed task heading (not `### Task <id> — <title>`);
#       - a task block orphaned outside any recognized state section.
#
#   (b) `>1 Status line` lint (REQ-E1.2): a task block carrying more than one
#       Status line — the residual duplicate-dispatch-metadata signature.
#
# Usage: check-ledger.sh [<tasks.md> ...]
#   With no arguments, scans every spec bundle's tasks.md under the repo's
#   specs/ directory (skipping `_`-prefixed accumulator dirs, which are not task
#   bundles). The no-arg form is the CI / local-check entry point (REQ-E1.3).
#
# Exit codes: 0 clean, 1 corruption found, 2 usage error.
#
# Portable bash 3.2 / BSD tooling; POSIX awk, no gawk-only constructs, no eval;
# all input treated as data (REQ-K1.5, framework-script safety).
set -u

# Pin the C locale so the bracket expressions and byte matching below mean
# exactly their ASCII range on every host (mirrors the sibling guards).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitution below and
# corrupt the repo-root derivation.
unset CDPATH

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Resolve the file list. Explicit arguments win; otherwise default to every
# bundle's tasks.md (the CI / local-check entry point).
files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  for d in "$repo_root"/specs/*/; do
    base="$(basename "$d")"
    case "$base" in
      _*) continue ;; # accumulator dirs (e.g. _observations, _pending)
    esac
    [ -f "$d/tasks.md" ] && files+=("$d/tasks.md")
  done
  if [ "${#files[@]}" -eq 0 ]; then
    echo "check-ledger: no spec bundles found under $repo_root/specs" >&2
    exit 2
  fi
fi

status=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    echo "check-ledger: missing or unreadable file: $f" >&2
    status=2
    continue
  fi

  # Version keying (invariant-tasks Task 4; REQ-C1.4, REQ-C1.8, D-7). The
  # guard's rule set is selected by the file's own `**Format-version:**`
  # declaration (first header line wins; trailing whitespace/CR trimmed so a
  # Markdown hard-break or CRLF checkout cannot make a valid value
  # unrecognizable). v1 keeps every check below; v2 is reduced to the
  # structural checks (heading form, duplicate ids, orphan blocks — with
  # `## Tasks` recognized) because no derived state is committed there:
  # placement/annotation coherence has nothing legitimate to check, and a
  # banned section or annotation is the validator's finding, not this guard's.
  # A missing or unparseable declaration fails closed: the rules to apply
  # cannot be selected, so the file is reported rather than silently checked
  # under either version's rules. Echo discipline (REQ-C1.9): the declared
  # value is untrusted file content — control bytes are stripped before it
  # reaches the diagnostic, C0 + DEL + the C1 range alike (the
  # sanitize_printable posture, scripts/echo-safety.sh: a raw C1 byte such as
  # CSI 0x9B drives the terminal exactly like ESC-[).
  fver=$(awk '/^\*\*Format-version:\*\*/ { sub(/^\*\*Format-version:\*\*[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit }' "$f")
  case "$fver" in
    1 | 2) ;;
    *)
      printf '%s:1: missing or unparseable Format-version (%s): ledger rules cannot be selected (fail closed; REQ-C1.8)\n' \
        "$f" "$(printf '%s' "$fver" | tr -d '\000-\037\177\200-\237')"
      [ "$status" -eq 2 ] || status=1
      continue
      ;;
  esac

  # One awk pass per file. Findings go to stdout as `<file>:<line>: <message>`;
  # the END block exits 1 if any were emitted. The em-dash (U+2014) in the
  # heading separator is matched byte-wise under LC_ALL=C.
  awk -v FILE="$f" -v VER="$fver" '
    function is_state_section(s) {
      # Format-version 2 adds the single ## Tasks section (invariant-tasks
      # REQ-C1.4): every definition block lives there, never moving. The v1
      # names stay recognized under v2 so this guard does not re-implement the
      # validator banned-placement-section finding; structure vs invariants
      # stay separate concerns.
      if (VER == 2 && s == "Tasks") return 1
      return (s == "Forward plan" || s == "In progress" || \
              s == "Awaiting input" || s == "Completed" || \
              s == "Deferred" || s == "Out of scope")
    }
    # Classify a Status value into the claimed lifecycle state. Order matters:
    # a completed Status ("Completed · PR #1 merged") also contains "pr #", so
    # the completed test runs first.
    function classify(s,   t) {
      if (s == "") return "none"
      t = tolower(s)
      # Status is free-form (spec-format): the canonical reconcile writer emits
      # "Completed · PR #N merged", but a bare "done" is equally completion
      # evidence. Match "done" only as a leading word so "abandoned" etc. do not
      # read as completion.
      if (t ~ /merged/ || t ~ /^completed/ || t ~ /^done([^a-z]|$)/) return "completed"
      if (t ~ /^deferred/) return "deferred"
      if (t ~ /implementing|draft|polish iter|in[ -]progress|awaiting[ -]input|open|pr #/) \
        return "in-progress"
      return "other"
    }
    function finding(line, msg) {
      printf "%s:%d: %s\n", FILE, line, msg
      nfind++
    }
    # Echo discipline (REQ-H1.3, mirrored across the sibling guards): tasks.md
    # content is untrusted repo/PR input, so strip control characters before
    # embedding extracted file content in a finding message. Under LC_ALL=C the
    # cntrl class is C0 + DEL only, so legitimate multibyte UTF-8 (the em-dash in
    # a heading) is preserved while a stray BEL/ESC/CR cannot reach CI logs.
    function safe(s) { gsub(/[[:cntrl:]]/, "", s); return s }
    # Evaluate the block that just ended (placement vs its own Status, and the
    # >1-Status lint). Called on each new heading and at END.
    function finalize_block(   c) {
      if (!in_block) return
      # v2 ledger scope (invariant-tasks REQ-C1.4, D-7): structural checks
      # only. The placement/annotation coherence branches and the >1-Status
      # lint below are checks over the v1 derived snapshot; under v2 no
      # derived state is committed, and a stray section or annotation is the
      # validator invariant finding (spec-validate.sh), not a ledger finding —
      # only the orphan-block structural check is retained here. (No
      # apostrophes in this awk program: it is single-quoted in the shell.)
      if (VER == 2) {
        if (!is_state_section(block_section))
          finding(block_line, \
            sprintf("task %s block is outside any recognized state section (under \"%s\")", \
              block_id, block_section == "" ? "(no section)" : safe(block_section)))
        in_block = 0
        return
      }
      if (status_count > 1)
        finding(block_line, \
          sprintf("task %s block has %d Status lines (duplicate-dispatch-metadata signature; REQ-E1.2)", \
            block_id, status_count))
      if (!is_state_section(block_section)) {
        finding(block_line, \
          sprintf("task %s block is outside any recognized state section (under \"%s\")", \
            block_id, block_section == "" ? "(no section)" : safe(block_section)))
        in_block = 0
        return
      }
      c = classify(status_first)
      if (block_section == "Completed") {
        if (c != "completed")
          finding(block_line, \
            sprintf("task %s under Completed lacks a completion Status (its own evidence contradicts the section)", \
              block_id))
      } else if (block_section == "Forward plan") {
        if (c == "completed" || c == "in-progress" || c == "deferred")
          finding(block_line, \
            sprintf("task %s under Forward plan carries a \"%s\" Status (its own evidence contradicts the section)", \
              block_id, c))
      } else if (block_section == "In progress" || block_section == "Awaiting input") {
        if (c == "completed" || c == "deferred")
          finding(block_line, \
            sprintf("task %s under %s carries a \"%s\" Status (its own evidence contradicts the section)", \
              block_id, block_section, c))
      } else if (block_section == "Deferred") {
        if (c == "completed" || c == "in-progress")
          finding(block_line, \
            sprintf("task %s under Deferred carries a \"%s\" Status (its own evidence contradicts the section)", \
              block_id, c))
      } else if (block_section == "Out of scope") {
        if (c == "completed" || c == "in-progress" || c == "deferred")
          finding(block_line, \
            sprintf("task %s under Out of scope carries a \"%s\" Status (its own evidence contradicts the section)", \
              block_id, c))
      }
      in_block = 0
    }

    # Strip a trailing CR first so a CRLF-saved snapshot parses like an LF one
    # (mirrors scripts/drain-gates.sh); otherwise the \r rides into the section
    # name and is_state_section() rejects every block. Runs before every rule
    # below because awk evaluates rules in source order per line.
    { sub(/\r$/, "") }

    # H2 section heading.
    /^## / {
      finalize_block()
      section = $0
      sub(/^## /, "", section)
      sub(/[ \t]+$/, "", section)
      next
    }

    # H3 task heading.
    /^### / {
      finalize_block()
      if ($0 !~ /^### Task / || $0 !~ /^### Task [0-9]+(\.[0-9]+)? — ./) {
        finding(NR, sprintf("malformed task heading (expected \"### Task <id> — <title>\"): %s", safe($0)))
        in_block = 0
        next
      }
      id = $0
      sub(/^### Task /, "", id)
      sub(/ —.*$/, "", id)
      if (id in seen_line) {
        finding(NR, sprintf("duplicate task block: task %s already defined at line %d (mis-sort / duplicated-block signature)", \
          id, seen_line[id]))
      } else {
        seen_line[id] = NR
      }
      in_block = 1
      block_id = id
      block_line = NR
      block_section = section
      status_count = 0
      status_first = ""
      next
    }

    # Status annotation within the current block.
    in_block && /^- \*\*Status:\*\*/ {
      val = $0
      sub(/^- \*\*Status:\*\*[ \t]*/, "", val)
      sub(/[ \t]+$/, "", val)
      status_count++
      if (status_count == 1) status_first = val
      next
    }

    END {
      finalize_block()
      if (nfind > 0) exit 1
    }
  ' "$f" || { [ "$status" -eq 2 ] || status=1; }
done

exit "$status"
