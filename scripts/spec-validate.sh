#!/bin/sh
# spec-validate.sh — the planwright status-aware spec validator.
#
# Enforces doctrine/spec-format.md's validator-enforceable invariants
# (REQ-A2.1, REQ-A2.2, REQ-A1.8, REQ-A3.2; D-25, D-34), keyed off the
# bundle's declared format-version (this implementation: format-version 1):
#
#   1. Four-file presence.
#   2. Header block: Status declared (missing warns, defaults to Draft);
#      one of the five statuses; Superseded requires `Superseded-by:`;
#      Format-version declared; Status mirrors kept in sync.
#   3. Spec-identifier charset and length; underscore-accumulator name
#      screening (accumulators are skipped, not validated as bundles).
#   4. REQ-ID convention: ID-bearing bullets, citation per live REQ
#      (superseded records exempt), no duplicate IDs.
#   5. D-ID structure: Decision / Alternatives considered / Chosen because.
#   6. Task structure: well-formed stable ID plus the five definition fields.
#   7. REQ↔test-spec coverage (exact-id matching, never substring).
#   8. Stable-ID discipline: duplicates rejected; against the baseline ref,
#      a vanished (renumbered/removed) ID is flagged; a supersede passes.
#   9. Terminal-state discipline: no transition out of Retired/Superseded
#      relative to the baseline ref.
#
# Severity (status-aware, D-25): findings are warnings on Draft, errors on
# Active and Done (signed-off live content), warnings on Retired/Superseded
# (frozen records do not block CI). Integrity violations are errors
# regardless of status: an unknown status, an unsupported format-version,
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
  en=$(printf '%s' "$1" | tr -d '\000-\037\177')
  [ -n "$en" ] || en="(unprintable name)"
  printf 'spec-validate: ERROR %s: %s\n' "$en" "$2"
  err=$((err + 1))
}

# first_header <file> <key> — first "**<key>:** value" header line's value.
# Non-printable characters are stripped: extracted values are echoed in
# findings, and hostile file content must not reach the terminal raw (same
# echo discipline as the REQ-H1.3 gate parser).
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
      if (match($0, /^- \*\*REQ-[A-Z]+[0-9]+\.[0-9]+\*\*/)) {
        id = substr($0, 5, RLENGTH - 6)
        printf "ALL\t%s\n", id
        if (id in seen) printf "F\thard\tduplicate REQ-ID %s\n", id
        seen[id] = 1
        cur = id
        cites = ($0 ~ /\(Cites:/)
        sup = ($0 ~ /\*\*Superseded-by: REQ-/)
      } else {
        printf "F\tgap\tprose-only requirement bullet (no REQ-ID) at requirements.md:%d\n", NR
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
      | grep -oE '^- \*\*REQ-[A-Z]+[0-9]+\.[0-9]+\*\*' \
      | grep -oE 'REQ-[A-Z]+[0-9]+\.[0-9]+') || old_ids=
    printf '%s\n' "$old_ids" | while read -r oid; do
      [ -n "$oid" ] || continue
      set_in "$oid" "$all_req_ids" \
        || printf 'gap\t%s renumbered or removed since %s (stable IDs are never reused; supersede instead)\n' \
          "$oid" "$baseline" >>"$fnd"
    done
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

  if [ ! -f "$bdir/requirements.md" ]; then
    # The authoritative Status home is absent: derive the severity status
    # from the first sibling mirror that declares one, so deleting
    # requirements.md cannot downgrade an Active bundle's errors to
    # warnings (same evasion class as an implicit-Draft mirror).
    for bf in design.md tasks.md test-spec.md; do
      [ -f "$bdir/$bf" ] || continue
      declared_status=$(first_header "$bdir/$bf" Status)
      [ -n "$declared_status" ] && break
    done
  fi

  if [ -f "$bdir/requirements.md" ]; then
    declared_status=$(first_header "$bdir/requirements.md" Status)
    if [ -z "$declared_status" ]; then
      printf 'gap\tmissing Status: header (defaulting to Draft)\n' >>"$fnd"
      # The default participates in everything downstream (mirrors, severity,
      # baseline): an explicit Active mirror must not hide behind an absent
      # authoritative header.
      declared_status=Draft
    fi

    fver=$(first_header "$bdir/requirements.md" Format-version)
    if [ -z "$fver" ]; then
      printf 'gap\tmissing Format-version: header\n' >>"$fnd"
    elif [ "$fver" != "1" ]; then
      # Keyed off the declared version (REQ-A1.7): rules for an undeclared
      # future version are unknown, so fail closed rather than silently
      # applying format-version 1 rules.
      printf 'hard\tunsupported format-version: %s (this validator implements format-version 1)\n' \
        "$fver" >>"$fnd"
    fi

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

  case $declared_status in
    Draft | Active | Done | Retired | Superseded | '') ;;
    *)
      printf 'hard\tunknown status: %s (expected Draft, Active, Done, Retired, or Superseded)\n' \
        "$declared_status" >>"$fnd"
      ;;
  esac

  if [ -f "$bdir/design.md" ]; then
    parse_design "$bdir/design.md" >"$gtmp/tagged"
    awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged" >>"$fnd"
    all_d_ids=$(awk -F'\t' '$1 == "ALLD" { print $2 }' "$gtmp/tagged")
  fi

  if [ -f "$bdir/tasks.md" ]; then
    parse_tasks "$bdir/tasks.md" >"$gtmp/tagged"
    awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged" >>"$fnd"
    all_t_ids=$(awk -F'\t' '$1 == "ALLT" { print $2 }' "$gtmp/tagged")
  fi

  # REQ↔test-spec coverage: every live REQ appears in an H3 entry heading,
  # matched as an exact id (REQ-F1.1 is not covered by REQ-F1.10).
  if [ -f "$bdir/test-spec.md" ] && [ -n "$live_req_ids" ]; then
    heads=$(grep '^### ' "$bdir/test-spec.md" | grep -oE 'REQ-[A-Z]+[0-9]+\.[0-9]+') || heads=
    printf '%s\n' "$live_req_ids" | while read -r rid; do
      [ -n "$rid" ] || continue
      set_in "$rid" "$heads" \
        || printf 'gap\t%s has no test-spec entry\n' "$rid" >>"$fnd"
    done
  fi

  baseline_checks "$bdir"

  # Severity mapping (D-25): warnings on Draft and on the frozen terminal
  # records; errors on the signed-off live statuses; hard findings always
  # error. An unknown status already carries its own hard finding.
  case $declared_status in
    Active | Done) gapsev=ERROR ;;
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
