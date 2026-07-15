#!/bin/sh
# spec-validate.sh — the planwright status-aware spec validator.
#
# Enforces doctrine/spec-format.md's validator-enforceable invariants
# (REQ-A2.1, REQ-A2.2, REQ-A1.8, REQ-A3.2; D-25, D-34), keyed off the
# bundle's declared format-version (this implementation: format-versions
# 1 and 2):
#
#   1. Four-file presence.
#   2. Header block: Status declared (missing warns, defaults to Draft);
#      one of the six statuses (Draft, Ready, Active, Done, Retired,
#      Superseded); Superseded requires `Superseded-by:`; Format-version
#      declared; Status mirrors kept in sync.
#   3. Spec-identifier charset and length; underscore-accumulator name
#      screening (accumulators are skipped, not validated as bundles).
#   4. REQ-ID convention: ID-bearing bullets, citation per live REQ
#      (superseded records exempt), no duplicate IDs.
#   5. D-ID structure: Decision / Alternatives considered / Chosen because.
#   6. Task structure: well-formed stable ID plus the five definition fields.
#   7. REQ↔test-spec coverage (exact-id matching, never substring).
#   8. Stable-ID discipline: duplicates rejected; against the baseline ref,
#      a vanished (renumbered/removed) ID is flagged; a supersede passes,
#      and a supersede newly introduced since the baseline must carry a
#      dated Changelog entry naming the superseded ID (REQ-A3.3).
#   9. Terminal-state discipline: no transition out of Retired/Superseded
#      relative to the baseline ref.
#
# Format-version 2 (the invariant ledger; invariant-tasks REQ-C1.5,
# REQ-C1.8, REQ-C1.9, REQ-D1.1 · D-3, D-5, D-7) adds, for v2 bundles only:
#
#   10. No placement sections: `## Forward plan`, `## In progress`, and
#       `## Completed` do not exist (task blocks live in `## Tasks`).
#   11. No state annotation bullets: `Status`, `Last activity`, and
#       `Dispatch` bullets do not exist in task blocks (the three
#       state-annotation tokens the format defines; other bullets are not
#       this check's concern).
#   12. Stored `Status:` restricted to the human-gated set — Draft, Ready,
#       Retired, Superseded; Active and Done are derived, never stored.
#   13. The static pointer line `**Execution:** derived — see the status
#       render` present in every file's header, in its fixed vocabulary.
#   14. Reference-bullet integrity in the human-payload sections: every
#       `**Task <id>**` bullet names an existing task id, ids pass the
#       task-id grammar before any use, and a task is parked by at most
#       one bullet across all three sections.
#
# Version keying is fail-closed (REQ-C1.8): a missing or unparseable
# `Format-version:` is an error at every status — the rules to apply cannot
# be known without a parsed version — and neither version's extra rules are
# applied. v1 bundles keep the v1 rules unchanged (REQ-D1.1).
#
# Severity (status-aware, D-25): findings are warnings on Draft, errors on
# Ready, Active, and Done (signed-off live content — Ready is signed off and
# executable), warnings on Retired/Superseded (frozen records do not block
# CI). Integrity violations are errors regardless of status: an unknown
# status, a missing/unparseable/unsupported format-version,
# Superseded without its pointer, duplicate IDs, identifier-charset
# violations, and a transition out of a terminal state.
#
# Usage:
#   spec-validate.sh [--baseline <ref>] <specs-root | spec-dir>
#   spec-validate.sh --check-id <identifier>
#
# A path containing any of the four spec files is validated as a single
# bundle; any other directory is treated as a specs root and its direct
# children are screened and validated. A symlinked directory in the root is
# a hard error (a silent skip would be a bundle CI never checks); plain
# files, symlinks to files, and hidden entries (tooling artifacts) are
# ignored. The baseline for stable-ID and
# terminal-state checks defaults to origin/main when it resolves (it is
# skipped quietly otherwise: a brand-new repo with no remote degrades
# gracefully per REQ-K1.7); --baseline makes it explicit and fatal when
# unresolvable. --check-id validates a proposed spec identifier string,
# full-string, for skills to call before any path or command is formed
# (REQ-A1.8); the hostile input is never echoed back.
#
# Exit codes: 0 no errors (warnings allowed), 1 errors found (or an invalid
# --check-id identifier), 2 usage or environment error.
#
# Portable: /bin/sh + awk + grep + git as shipped on macOS (bash 3.2, BSD
# userland) and Linux (GNU userland) — the REQ-K1.5 envelope. Two utilities
# used here sit outside strict POSIX but ship on every targeted platform:
# mktemp(1) and grep -o. No eval; input treated as data only.
set -eu

# Pin the C locale: charset checks and awk/grep ranges must not vary by
# host locale collation.
LC_ALL=C
export LC_ALL

# Canonical echo-discipline sanitizer (doctrine/security-posture.md): strip
# non-printables off repo-controlled input before it reaches the terminal.
# shellcheck source=scripts/echo-safety.sh
. "$(dirname "$0")/echo-safety.sh"

usage() {
  echo "usage: spec-validate.sh [--baseline <ref>] <specs-root-or-spec-dir>" >&2
  echo "       spec-validate.sh --check-id <identifier>" >&2
  exit 2
}

# Full-string spec-identifier check (REQ-A1.8): ^[a-z0-9][a-z0-9-]*$, max 64.
check_spec_id() {
  cid=$1
  [ -n "$cid" ] || return 1
  [ "${#cid}" -le 64 ] || return 1
  case $cid in
    [a-z0-9]*) ;;
    *) return 1 ;;
  esac
  case $cid in
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# Accumulator-name screen (REQ-A1.8): ^_[a-z0-9][a-z0-9-]*$, max 64.
check_accumulator_name() {
  anm=$1
  [ "${#anm}" -le 64 ] || return 1
  case $anm in
    _*) ;;
    *) return 1 ;;
  esac
  check_spec_id "${anm#_}"
}

baseline=origin/main
explicit_baseline=0
target=
while [ $# -gt 0 ]; do
  case $1 in
    --check-id)
      [ $# -eq 2 ] || usage
      if check_spec_id "$2"; then
        exit 0
      fi
      # Never echo the candidate back: a hostile identifier must not reach
      # any output a caller might interpolate.
      echo "spec-validate: invalid spec identifier (must match ^[a-z0-9][a-z0-9-]*\$, max length 64)" >&2
      exit 1
      ;;
    --baseline)
      [ $# -ge 2 ] || usage
      baseline=$2
      explicit_baseline=1
      shift 2
      ;;
    -*)
      usage
      ;;
    *)
      [ -z "$target" ] || usage
      target=$1
      shift
      ;;
  esac
done

[ -n "$target" ] || usage
while [ "$target" != "${target%/}" ]; do target=${target%/}; done
if [ ! -d "$target" ]; then
  echo "spec-validate: not a directory: $target" >&2
  exit 2
fi

gtmp=$(mktemp -d)
trap 'rm -rf "$gtmp"' EXIT

err=0
warn=0
tab=$(printf '\t')

# emit_error <name> <msg> — report a root-level screening error and count
# it. The name is repo-controlled input that failed (or never reached) the
# charset screen, so non-printables are stripped before echoing (REQ-H1.3
# echo discipline), with a placeholder when nothing printable remains.
emit_error() {
  en=$(sanitize_printable "$1" "(unprintable name)")
  printf 'spec-validate: ERROR %s: %s\n' "$en" "$2"
  err=$((err + 1))
}

# first_header <file> <key> — first "**<key>:** value" header line's value.
# Non-printable characters are stripped: extracted values are echoed in
# findings, and hostile file content must not reach the terminal raw (same
# echo discipline as the REQ-H1.3 gate parser). The canonical statement of
# this posture lives in scripts/echo-safety.sh; the awk `gsub(/[^[:print:]]/,
# "")` below is its in-awk form (a strict superset — it strips high/UTF-8
# bytes too, and cannot call the sourced shell sanitizer).
first_header() {
  awk -v key="$2" '
    index($0, "**" key ":**") == 1 {
      sub(/^\*\*[^*]*:\*\*[ \t]*/, "")
      gsub(/[^[:print:]]/, "")
      print
      exit
    }
  ' "$1"
}

# Parse requirements.md REQ blocks. Tagged tab-separated output:
#   F <tab> gap|hard <tab> message     — a finding
#   ALL <tab> id                       — every defined REQ-ID
#   LIVE <tab> id                      — REQ-IDs not marked Superseded-by
parse_requirements() {
  awk '
    function flush() {
      if (cur == "") return
      if (sup) {
        printf "SUP\t%s\n", cur
      } else {
        printf "LIVE\t%s\n", cur
        if (!cites)
          printf "F\tgap\t%s has no citation annotation (*(Cites: ...)*)\n", cur
      }
      cur = ""
    }
    /^## / { flush(); ingroup = ($0 ~ /^## REQ-/); next }
    !ingroup { next }
    /^- / {
      flush()
      if (match($0, /^- \*\*REQ-[A-Z][0-9]+\.[0-9]+\*\*/)) {
        id = substr($0, 5, RLENGTH - 6)
        printf "ALL\t%s\n", id
        if (id in seen) printf "F\thard\tduplicate REQ-ID %s\n", id
        seen[id] = 1
        cur = id
        cites = ($0 ~ /\(Cites:/)
        sup = ($0 ~ /\*\*Superseded-by: REQ-/)
      } else {
        printf "F\tgap\tprose-only bullet or non-conforming REQ-ID at requirements.md:%d (expected REQ-<letter><n>.<m>)\n", NR
      }
      next
    }
    cur != "" {
      if ($0 ~ /\(Cites:/) cites = 1
      if ($0 ~ /\*\*Superseded-by: REQ-/) sup = 1
    }
    END { flush() }
  ' "$1"
}

# Parse design.md D-ID sections. Same tagged tab-separated format as
# parse_requirements: F findings, plus every D-ID tagged ALLD.
parse_design() {
  awk '
    function flush() {
      if (cur == "") return
      if (!hd) printf "F\tgap\t%s missing field: Decision\n", cur
      if (!ha) printf "F\tgap\t%s missing field: Alternatives considered\n", cur
      if (!hc) printf "F\tgap\t%s missing field: Chosen because\n", cur
      cur = ""
    }
    /^### D-[0-9]+:/ {
      flush()
      match($0, /^### D-[0-9]+/)
      id = substr($0, 5, RLENGTH - 4)
      printf "ALLD\t%s\n", id
      if (id in seen) printf "F\thard\tduplicate D-ID %s\n", id
      seen[id] = 1
      cur = id
      hd = ha = hc = 0
      next
    }
    /^### D-/ {
      # D- prefix without the <n>: shape: surface it rather than silently
      # treating a typo as ordinary prose (mirror of the malformed-task rule).
      flush()
      printf "F\tgap\tmalformed decision heading at design.md:%d (expected ### D-<n>: <title>)\n", NR
      next
    }
    /^## / || /^### / { flush(); next }
    cur != "" {
      if ($0 ~ /^\*\*Decision:\*\*/) hd = 1
      if ($0 ~ /^\*\*Alternatives considered:\*\*/) ha = 1
      if ($0 ~ /^\*\*Chosen because:\*\*/) hc = 1
    }
    END { flush() }
  ' "$1"
}

# Parse tasks.md task blocks. Same tagged tab-separated format as
# parse_requirements: F findings, plus every well-formed task id tagged ALLT.
parse_tasks() {
  awk '
    function flush() {
      if (cur == "") return
      if (!fdel) printf "F\tgap\tTask %s missing field: Deliverables\n", cur
      if (!fdw) printf "F\tgap\tTask %s missing field: Done when\n", cur
      if (!fdep) printf "F\tgap\tTask %s missing field: Dependencies\n", cur
      if (!fcit) printf "F\tgap\tTask %s missing field: Citations\n", cur
      if (!feff) printf "F\tgap\tTask %s missing field: Estimated effort\n", cur
      cur = ""
    }
    /^## / { flush(); next }
    /^### Task / {
      flush()
      id = $3
      if (id !~ /^[0-9]+(\.[0-9]+)?$/) {
        printf "F\tgap\tmalformed task id at tasks.md:%d (expected <n> or <n>.<m>)\n", NR
        next
      }
      printf "ALLT\t%s\n", id
      if (id in seen) printf "F\thard\tduplicate task id: Task %s\n", id
      seen[id] = 1
      cur = id
      fdel = fdw = fdep = fcit = feff = 0
      next
    }
    /^### / { flush(); next }
    cur == "" { next }
    /^- \*\*Deliverables:\*\*/ { fdel = 1 }
    /^- \*\*Done when:\*\*/ { fdw = 1 }
    /^- \*\*Dependencies:\*\*/ { fdep = 1 }
    /^- \*\*Citations:\*\*/ { fcit = 1 }
    /^- \*\*Estimated effort:\*\*/ { feff = 1 }
    END { flush() }
  ' "$1"
}

# Parse a format-version 2 tasks.md for the invariant-ledger rules
# (REQ-C1.5, D-3): banned placement sections, banned state-annotation
# bullets, and reference-bullet integrity in the human-payload sections.
# Tagged tab-separated output:
#   F <tab> gap <tab> message   — a finding (embedded values are either
#                                 fixed vocabulary or grammar-validated ids)
#   RB <tab> line <tab> raw-id  — a grammar-violating reference-bullet id,
#                                 raw (whitespace-free by construction: a
#                                 lead with inner whitespace is prose, and
#                                 an awk record cannot hold a newline); the
#                                 caller routes it through
#                                 sanitize_printable before echoing
#                                 (REQ-C1.9)
parse_tasks_v2() {
  awk '
    # Headings are matched with trailing-whitespace tolerance: an exact
    # `==` would let a hand-edited "## Completed " escape the placement
    # ban (fail-open) or hide a payload section from the integrity checks.
    # Suffixed variants ("## Completed (legacy)") stay ordinary headings:
    # canonical heading form belongs to the ledger guard, not this parser.
    function banned(nm, ln) {
      printf "F\tgap\tplacement section \"## %s\" at tasks.md:%d does not exist in format-version 2 (task blocks live in \"## Tasks\"; execution state is derived)\n", nm, ln
    }
    /^## Forward plan[ \t]*$/  { section = ""; in_task = 0; banned("Forward plan", NR); next }
    /^## In progress[ \t]*$/   { section = ""; in_task = 0; banned("In progress", NR); next }
    /^## Completed[ \t]*$/     { section = ""; in_task = 0; banned("Completed", NR); next }
    /^## Awaiting input[ \t]*$/ { section = "Awaiting input"; in_task = 0; next }
    /^## Deferred[ \t]*$/       { section = "Deferred"; in_task = 0; next }
    /^## Out of scope[ \t]*$/   { section = "Out of scope"; in_task = 0; next }
    /^## / { section = ""; in_task = 0; next }
    /^### Task / {
      in_task = 1
      curid = ""
      if ($3 ~ /^[0-9]+(\.[0-9]+)?$/) {
        ids[$3] = 1
        curid = $3
      }
      next
    }
    /^### / { in_task = 0; next }
    in_task && /^- \*\*(Status|Last activity|Dispatch):\*\*/ {
      tok = substr($0, 5)
      sub(/:\*\*.*$/, "", tok)
      if (curid != "") loc = "Task " curid; else loc = "tasks.md:" NR
      printf "F\tgap\tstate annotation bullet \"%s\" on %s does not exist in format-version 2 (the Status, Last activity, and Dispatch state annotations are derived state, never stored)\n", tok, loc
      next
    }
    # A reference bullet is a complete bold lead `**Task <token>**` whose
    # token has no inner whitespace (task ids never do). A lead with inner
    # whitespace ("**Task force assembled.**") is a plain prose bullet —
    # the format allows those in Deferred / Out of scope — and an
    # unterminated bold lead is malformed markdown, which markdown lint
    # owns; neither is treated as (or rejected as) a reference.
    section != "" && /^- \*\*Task [^*]*\*\*/ {
      rest = substr($0, 10)
      match(rest, /^[^*]*\*\*/)
      rid = substr(rest, 1, RLENGTH - 2)
      if (rid ~ /[ \t]/) next
      if (rid !~ /^[0-9]+(\.[0-9]+)?$/) {
        printf "RB\t%d\t%s\n", NR, rid
      } else {
        nref++
        refid[nref] = rid
        refsec[nref] = section
        refnr[nref] = NR
      }
      next
    }
    END {
      for (i = 1; i <= nref; i++) {
        rid = refid[i]
        if (!(rid in ids))
          printf "F\tgap\treference bullet at tasks.md:%d names unknown task id %s (%s)\n", refnr[i], rid, refsec[i]
        if (rid in seensec) {
          if (seensec[rid] == refsec[i])
            printf "F\tgap\tTask %s is named by more than one reference bullet (twice in %s; a task is parked in one section at a time)\n", rid, refsec[i]
          else
            printf "F\tgap\tTask %s is named by more than one reference bullet (%s and %s; a task is parked in one section at a time)\n", rid, seensec[rid], refsec[i]
        } else
          seensec[rid] = refsec[i]
      }
    }
  ' "$1"
}

# set_in <needle> <newline-list> — exact-membership test.
set_in() {
  printf '%s\n' "$2" | grep -qxF "$1"
}

# Baseline checks for one bundle: terminal-state discipline and the
# stable-ID never-reused rule, against $baseline. Appends to $fnd. Skipped
# quietly when the bundle is not in a git work tree or the default baseline
# does not resolve; an explicit --baseline that cannot be used is fatal.
baseline_checks() {
  bdir=$1
  if ! git -C "$bdir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ "$explicit_baseline" -eq 1 ]; then
      echo "spec-validate: --baseline given but $bdir is not in a git work tree" >&2
      exit 2
    fi
    return 0
  fi
  # 2>/dev/null as well as --quiet: --quiet silences the missing-ref case
  # but a failed ^{commit} peel (ref exists, wrong object type) still prints
  # "error: ..." — the probe is a yes/no check and must stay quiet on the
  # default-baseline skip path.
  if ! git -C "$bdir" rev-parse --verify --quiet "$baseline^{commit}" >/dev/null 2>&1; then
    if [ "$explicit_baseline" -eq 1 ]; then
      echo "spec-validate: baseline ref does not resolve: $baseline" >&2
      exit 2
    fi
    return 0
  fi

  old_req=$(git -C "$bdir" show "$baseline:./requirements.md" 2>/dev/null) || old_req=
  old_des=$(git -C "$bdir" show "$baseline:./design.md" 2>/dev/null) || old_des=
  old_tsk=$(git -C "$bdir" show "$baseline:./tasks.md" 2>/dev/null) || old_tsk=

  if [ -n "$old_req" ]; then
    old_status=$(printf '%s\n' "$old_req" \
      | awk 'index($0, "**Status:**") == 1 { sub(/^\*\*Status:\*\*[ \t]*/, ""); gsub(/[^[:print:]]/, ""); print; exit }')
    case $old_status in
      Retired | Superseded)
        if [ "$declared_status" != "$old_status" ]; then
          printf 'hard\ttransition out of terminal status (was %s at %s, now %s)\n' \
            "$old_status" "$baseline" "${declared_status:-Draft}" >>"$fnd"
        fi
        ;;
    esac
    old_ids=$(printf '%s\n' "$old_req" \
      | grep -oE '^- \*\*REQ-[A-Z][0-9]+\.[0-9]+\*\*' \
      | grep -oE 'REQ-[A-Z][0-9]+\.[0-9]+') || old_ids=
    printf '%s\n' "$old_ids" | while read -r oid; do
      [ -n "$oid" ] || continue
      set_in "$oid" "$all_req_ids" \
        || printf 'gap\t%s renumbered or removed since %s (stable IDs are never reused; supersede instead)\n' \
          "$oid" "$baseline" >>"$fnd"
    done

    # Changelog-on-supersede (REQ-A3.3, D-20): a REQ newly marked
    # `Superseded-by` since the baseline must be named in a dated Changelog
    # entry — the supersede pointer records the lineage, the changelog records
    # the why-it-changed. The current superseded set is diffed against the
    # baseline's so a supersede already recorded upstream is not re-flagged.
    # Status-scoped like the other stable-ID findings (warn on Draft, error on
    # Ready/Active/Done). REQ supersedes only: that is the parseable, marked case.
    # Guarded on the current file existing: a bundle that deletes
    # requirements.md still has a non-empty baseline `$old_req`, and parsing a
    # now-missing file would leak raw awk errors and abort under set -eu — the
    # missing-file gap already covers that case (REQ-K1.7 graceful degradation).
    if [ -f "$bdir/requirements.md" ]; then
      printf '%s\n' "$old_req" >"$gtmp/old_req"
      old_sup=$(parse_requirements "$gtmp/old_req" | awk -F"$tab" '$1 == "SUP" { print $2 }')
      cur_sup=$(parse_requirements "$bdir/requirements.md" | awk -F"$tab" '$1 == "SUP" { print $2 }')
      clog=$(awk '
        tolower($0) ~ /^## changelog/ { f = 1; next }
        /^## / { f = 0 }
        f
      ' "$bdir/requirements.md")
      printf '%s\n' "$cur_sup" | while read -r sid; do
        [ -n "$sid" ] || continue
        if set_in "$sid" "$old_sup"; then continue; fi
        # Name the bare id (REQ- stripped) as a whole token, inside a dated
        # Changelog entry (REQ-A3.3). awk tracks whether the current line is
        # part of a dated bullet entry — a `- <YYYY-MM-DD> …` bullet, or one of
        # its continuation lines, since entries span multiple lines and the id
        # often sits on a continuation (e.g. "REQ-B2.4 supersedes REQ-B2.1") —
        # and only scans those, so an undated bullet that names the id does not
        # satisfy the check. On a dated line it tokenizes on non-id characters
        # and compares exactly: the bare "X1.2", a prefixed "REQ-X1.2", and a
        # sentence-final "X1.2." match, while a longer id it only prefixes
        # ("X1.20", "X1.2.alpha") does not. awk, not grep -E, because anchors
        # inside an alternation (`(^|…)` / `($|…)`) match unreliably on BSD
        # grep; exact compare, so the id needs no regex-escaping.
        if printf '%s\n' "$clog" | awk -v id="${sid#REQ-}" '
          /^- / { dated = ($0 ~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) }
          dated {
            line = $0
            gsub(/[^A-Za-z0-9.]/, " ", line)
            n = split(line, t, " ")
            for (i = 1; i <= n; i++) {
              tok = t[i]
              sub(/\.$/, "", tok)
              if (tok == id) { found = 1; exit }
            }
          }
          END { exit(found ? 0 : 1) }
        '; then
          :
        else
          printf 'gap\t%s newly superseded since %s without a matching Changelog entry (REQ-A3.3: a supersede needs a dated Changelog entry naming it)\n' \
            "$sid" "$baseline" >>"$fnd"
        fi
      done
    fi
  fi
  if [ -n "$old_des" ]; then
    old_ids=$(printf '%s\n' "$old_des" | grep -oE '^### D-[0-9]+:' | grep -oE 'D-[0-9]+') || old_ids=
    printf '%s\n' "$old_ids" | while read -r oid; do
      [ -n "$oid" ] || continue
      set_in "$oid" "$all_d_ids" \
        || printf 'gap\t%s renumbered or removed since %s (stable IDs are never reused; supersede instead)\n' \
          "$oid" "$baseline" >>"$fnd"
    done
  fi
  if [ -n "$old_tsk" ]; then
    old_ids=$(printf '%s\n' "$old_tsk" \
      | awk '/^### Task / && $3 ~ /^[0-9]+(\.[0-9]+)?$/ { print $3 }') || old_ids=
    printf '%s\n' "$old_ids" | while read -r oid; do
      [ -n "$oid" ] || continue
      set_in "$oid" "$all_t_ids" \
        || printf 'gap\tTask %s renumbered or removed since %s (stable IDs are never reused)\n' \
          "$oid" "$baseline" >>"$fnd"
    done
  fi
}

# validate_bundle <dir> <name> — run every bundle check, print the
# severity-mapped findings, and update the global err/warn counters. Sets
# the globals declared_status / live_req_ids / all_req_ids / all_d_ids /
# all_t_ids (reset here on every call; baseline_checks reads them).
validate_bundle() {
  bdir=$1
  bname=$2
  fnd="$gtmp/findings"
  : >"$fnd"

  for bf in requirements.md design.md tasks.md test-spec.md; do
    [ -f "$bdir/$bf" ] || printf 'gap\tmissing file: %s\n' "$bf" >>"$fnd"
  done

  declared_status=
  live_req_ids=
  all_req_ids=
  all_d_ids=
  all_t_ids=
  fver=
  bundle_ver=

  if [ ! -f "$bdir/requirements.md" ]; then
    # The authoritative Status home is absent: derive the severity status
    # from the first sibling mirror that declares one, so deleting
    # requirements.md cannot downgrade a Ready/Active bundle's errors to
    # warnings (same evasion class as an implicit-Draft mirror).
    for bf in design.md tasks.md test-spec.md; do
      [ -f "$bdir/$bf" ] || continue
      declared_status=$(first_header "$bdir/$bf" Status)
      [ -n "$declared_status" ] && break
    done
    # The format-version follows the same fallback (REQ-C1.8): deleting
    # requirements.md must not skip version keying, or a v2 bundle's
    # invariants would silently fail open while the file is absent.
    for bf in design.md tasks.md test-spec.md; do
      [ -f "$bdir/$bf" ] || continue
      fver=$(first_header "$bdir/$bf" Format-version)
      [ -n "$fver" ] && break
    done
  fi

  if [ -f "$bdir/requirements.md" ]; then
    declared_status=$(first_header "$bdir/requirements.md" Status)
    if [ -z "$declared_status" ]; then
      printf 'gap\tmissing Status: header (defaulting to Draft)\n' >>"$fnd"
      # The default participates in everything downstream (mirrors, severity,
      # baseline): an explicit Ready/Active mirror must not hide behind an absent
      # authoritative header.
      declared_status=Draft
    fi

    fver=$(first_header "$bdir/requirements.md" Format-version)

    if [ "$declared_status" = "Superseded" ]; then
      grep -q '^\*\*Superseded-by:\*\*' "$bdir/requirements.md" \
        || printf 'hard\tSuperseded status requires a **Superseded-by:** pointer\n' >>"$fnd"
    fi

    parse_requirements "$bdir/requirements.md" >"$gtmp/tagged"
    awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged" >>"$fnd"
    live_req_ids=$(awk -F'\t' '$1 == "LIVE" { print $2 }' "$gtmp/tagged")
    all_req_ids=$(awk -F'\t' '$1 == "ALL" { print $2 }' "$gtmp/tagged")

    # Status mirrors, compared against the declared-or-defaulted status.
    # Format-version mirrors likewise (meta-spec: all four files carry the
    # same header block), compared only when requirements.md declares one —
    # unlike Status it has no specified default to mirror against.
    for bf in design.md tasks.md test-spec.md; do
      [ -f "$bdir/$bf" ] || continue
      mst=$(first_header "$bdir/$bf" Status)
      if [ -z "$mst" ]; then
        printf 'gap\t%s: missing Status: header (mirror of requirements.md)\n' "$bf" >>"$fnd"
      elif [ "$mst" != "$declared_status" ]; then
        printf 'gap\t%s: Status mirror mismatch: %s (requirements.md resolves %s)\n' \
          "$bf" "$mst" "$declared_status" >>"$fnd"
      fi
      if [ -n "$fver" ]; then
        mfv=$(first_header "$bdir/$bf" Format-version)
        if [ -z "$mfv" ]; then
          printf 'gap\t%s: missing Format-version: header (mirror of requirements.md)\n' "$bf" >>"$fnd"
        elif [ "$mfv" != "$fver" ]; then
          printf 'gap\t%s: Format-version mirror mismatch: %s (requirements.md declares %s)\n' \
            "$bf" "$mfv" "$fver" >>"$fnd"
        fi
      fi
    done
  fi

  # Version keying is fail-closed (REQ-C1.8, D-7): a missing, empty, or
  # unparseable declaration is a hard error at every status — the rules to
  # apply cannot be known without a parsed version — and neither version's
  # extra rules run ($bundle_ver stays empty; the shared structural checks
  # still do). An undeclared numeric version is the REQ-A1.7 unsupported
  # error, equally hard. $fver comes from requirements.md (the
  # authoritative home) or, only when that file is absent, from the first
  # declaring sibling mirror.
  case $fver in
    1 | 2)
      bundle_ver=$fver
      ;;
    '')
      printf 'hard\tmissing or empty Format-version: declaration (fail-closed: validation rules cannot be selected without a declared version)\n' >>"$fnd"
      ;;
    *[!0-9]*)
      printf 'hard\tunparseable format-version: %s (fail-closed: validation rules cannot be selected without a parsed version)\n' \
        "$(sanitize_printable "$fver" "(unprintable)")" >>"$fnd"
      ;;
    *)
      printf 'hard\tunsupported format-version: %s (this validator implements format-versions 1 and 2)\n' \
        "$(sanitize_printable "$fver" "(unprintable)")" >>"$fnd"
      ;;
  esac

  if [ "$bundle_ver" = "2" ]; then
    # v2 stored status is restricted to the human-gated set (D-4 via
    # REQ-C1.5): Active and Done are derived on demand, never stored. They
    # are gap-class findings, but a bundle declaring them maps to the
    # errors-block severity anyway, so they always block.
    case $declared_status in
      Draft | Ready | Retired | Superseded | '') ;;
      Active | Done)
        printf 'gap\tstored status %s is derived in format-version 2 (stored header restricted to Draft, Ready, Retired, Superseded)\n' \
          "$declared_status" >>"$fnd"
        ;;
      *)
        printf 'hard\tunknown status: %s (format-version 2 stores Draft, Ready, Retired, or Superseded)\n' \
          "$(sanitize_printable "$declared_status" "(unprintable)")" >>"$fnd"
        ;;
    esac
  else
    case $declared_status in
      Draft | Ready | Active | Done | Retired | Superseded | '') ;;
      *)
        printf 'hard\tunknown status: %s (expected Draft, Ready, Active, Done, Retired, or Superseded)\n' \
          "$declared_status" >>"$fnd"
        ;;
    esac
  fi

  # v2 pointer line (D-5 via REQ-C1.5): the constant
  # `**Execution:** derived — see the status render` line in every file's
  # header, in its fixed vocabulary. Matched as an exact full line
  # (grep -xF); the non-canonical echo goes through first_header's
  # non-printable strip plus sanitize_printable (REQ-C1.9).
  if [ "$bundle_ver" = "2" ]; then
    exec_canon='**Execution:** derived — see the status render'
    for bf in requirements.md design.md tasks.md test-spec.md; do
      [ -f "$bdir/$bf" ] || continue
      if grep -qxF "$exec_canon" "$bdir/$bf"; then
        :
      elif grep -q '^\*\*Execution:\*\*' "$bdir/$bf"; then
        pv=$(first_header "$bdir/$bf" Execution)
        printf 'gap\t%s: non-canonical **Execution:** pointer line: %s (fixed vocabulary: derived — see the status render)\n' \
          "$bf" "$(sanitize_printable "$pv" "(unprintable)")" >>"$fnd"
      else
        printf 'gap\t%s: missing **Execution:** pointer line (format-version 2 header)\n' \
          "$bf" >>"$fnd"
      fi
    done
  fi

  if [ -f "$bdir/design.md" ]; then
    parse_design "$bdir/design.md" >"$gtmp/tagged"
    awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged" >>"$fnd"
    all_d_ids=$(awk -F'\t' '$1 == "ALLD" { print $2 }' "$gtmp/tagged")
  fi

  if [ -f "$bdir/tasks.md" ]; then
    parse_tasks "$bdir/tasks.md" >"$gtmp/tagged"
    awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged" >>"$fnd"
    all_t_ids=$(awk -F'\t' '$1 == "ALLT" { print $2 }' "$gtmp/tagged")

    # v2 invariant-ledger rules (REQ-C1.5): the shared task-structure
    # checks above still apply; these are the additional v2-only bans. A
    # grammar-violating reference-bullet id is untrusted content: it is
    # rejected and echoed only through sanitize_printable (REQ-C1.9).
    if [ "$bundle_ver" = "2" ]; then
      parse_tasks_v2 "$bdir/tasks.md" >"$gtmp/tagged2"
      awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged2" >>"$fnd"
      while IFS="$tab" read -r rtag rline rid; do
        [ "$rtag" = "RB" ] || continue
        printf 'gap\treference bullet task id at tasks.md:%s fails the task-id grammar and is rejected: %s\n' \
          "$rline" "$(sanitize_printable "$rid" "(empty or unprintable)")" >>"$fnd"
      done <"$gtmp/tagged2"
    fi
  fi

  # REQ↔test-spec coverage: every live REQ appears in an H3 entry heading,
  # matched as an exact id (REQ-F1.1 is not covered by REQ-F1.10).
  if [ -f "$bdir/test-spec.md" ] && [ -n "$live_req_ids" ]; then
    heads=$(grep '^### ' "$bdir/test-spec.md" | grep -oE 'REQ-[A-Z][0-9]+\.[0-9]+') || heads=
    printf '%s\n' "$live_req_ids" | while read -r rid; do
      [ -n "$rid" ] || continue
      set_in "$rid" "$heads" \
        || printf 'gap\t%s has no test-spec entry\n' "$rid" >>"$fnd"
    done
  fi

  baseline_checks "$bdir"

  # Severity mapping (D-25): warnings on Draft and on the frozen terminal
  # records; errors on the signed-off live statuses (Ready, Active, Done —
  # Ready is signed off and executable, kickoff-lifecycle D-1/REQ-B1.2); hard
  # findings always error. An unknown status already carries its own hard
  # finding.
  case $declared_status in
    Ready | Active | Done) gapsev=ERROR ;;
    *) gapsev=WARN ;;
  esac
  while IFS="$tab" read -r class msg; do
    [ -n "$class" ] || continue
    if [ "$class" = "hard" ]; then
      sev=ERROR
    else
      sev=$gapsev
    fi
    printf 'spec-validate: %s %s: %s\n' "$sev" "$bname" "$msg"
    if [ "$sev" = "ERROR" ]; then
      err=$((err + 1))
    else
      warn=$((warn + 1))
    fi
  done <"$fnd"
}

# screen_and_validate <dir> — name-screen a direct child of the specs root
# and validate it as a bundle when the screen passes.
screen_and_validate() {
  sdir=$1
  snm=$(basename "$sdir")
  case $snm in
    _*)
      # Reserved non-spec accumulator: never validated as a bundle, but the
      # name is still screened (REQ-A1.8).
      check_accumulator_name "$snm" \
        || emit_error "$snm" "accumulator directory name fails ^_[a-z0-9][a-z0-9-]*\$ (max 64)"
      ;;
    *)
      if check_spec_id "$snm"; then
        validate_bundle "$sdir" "$snm"
      else
        emit_error "$snm" "spec identifier fails ^[a-z0-9][a-z0-9-]*\$ (max 64); not validated as a bundle"
      fi
      ;;
  esac
}

if [ -f "$target/requirements.md" ] || [ -f "$target/design.md" ] \
  || [ -f "$target/tasks.md" ] || [ -f "$target/test-spec.md" ]; then
  screen_and_validate "$target"
else
  # Glob iteration, not `find | split`: pathname-expansion results arrive
  # one entry per word, so names containing newlines (or any other
  # splittable byte) cannot fragment into charset-valid phantom entries,
  # and expansion results are never re-expanded, so glob-metacharacter
  # names (e.g. "[g]") are screened literally. Hidden entries are skipped
  # as tooling artifacts (the root's own dotfiles set the precedent).
  # Symlinked directories are a hard error, not a silent skip: an accepted
  # symlink would be a bundle CI never checks (fail closed, REQ-A2.1);
  # symlinks to non-directories stay ignored like any other plain file.
  for d in "$target"/*; do
    { [ -e "$d" ] || [ -L "$d" ]; } || continue # unmatched-glob literal
    if [ -L "$d" ]; then
      if [ -d "$d" ]; then
        emit_error "$(basename "$d")" \
          "symlinked directory under the specs root; bundles must be real directories"
      fi
      continue
    fi
    [ -d "$d" ] || continue
    screen_and_validate "$d"
  done
fi

printf 'spec-validate: %d error(s), %d warning(s)\n' "$err" "$warn"
[ "$err" -eq 0 ]
