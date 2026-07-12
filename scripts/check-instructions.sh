#!/usr/bin/env bash
# check-instructions.sh — the instruction-hygiene size guard and audit tool
# (prompt-hygiene Task 2; D-1, D-2, D-3, D-4, D-5, D-13).
#
# Instruction files (skills/*/SKILL.md bodies the harness injects at invocation,
# doctrine/*.md rule docs skills front-load) grow monotonically and
# instruction-following degrades as that load grows. This guard bounds it. It:
#
#   - counts words (wc -w; wrap-invariant) and lines (informational) for every
#     instruction file, excluding doctrine/README.md (an index, REQ-A1.1);
#   - computes each skill's manifest-derived mandatory-at-start load (SKILL.md
#     body + run-start docs) and reachable closure (+ point-of-use docs),
#     parsing the doctrine manifest defined by doctrine/instruction-hygiene.md.
#     A skill with no manifest is scored body-only, which is not an error
#     (REQ-A1.2); a malformed manifest entry is a fail-loud error (REQ-B1.8);
#   - runs a deterministic resolution check: every manifest doc name must
#     resolve under the doctrine root (REQ-B1.6);
#   - scans hooks.json-registered hooks that emit additionalContext /
#     hookSpecificOutput and measures their STATIC injected prose, reading the
#     hook script but never executing it, and excluding interpolation lines
#     (REQ-A1.4). This injected-context surface is warn-only: it never fails the
#     check (REQ-B1.7);
#   - enforces per-file / start-load / closure budgets (knobs in
#     config/defaults.yml, overlay-tunable, REQ-B1.2) with boundary-inclusive
#     thresholds (>=, REQ-B1.8), honoring two suppression forms from the
#     tracked suppression list: a permanent per-file-floor exemption and a
#     transitional `pending-diet` allowance (REQ-B1.3);
#   - with --audit, emits a ranked report and an offender shortlist (REQ-A1.3).
#
# All input this guard reads (manifest entries, exemption text, rule-doc names,
# hook scripts) is PR-controllable and treated as untrusted DATA: no content is
# passed to a shell for evaluation, doc-name resolution is confined to the
# doctrine root (a name is charset-validated before any path is formed, so no
# `../` traversal escapes), and hook scripts are read, never executed (REQ-B1.9).
#
# Usage: check-instructions.sh [--audit] [--root <dir>]
#   --audit      also emit the ranked report and offender shortlist on stdout.
#   --root <dir> base dir holding skills/, doctrine/, hooks/, config/ (default:
#                the repo root, the script's parent directory). Used by tests.
#
# Exit codes: 0 clean (warnings do not fail), 1 a budget error / malformed
#   input / unresolvable reference, 2 usage error.
#
# Portable bash 3.2 / BSD tooling; POSIX awk, no gawk-only constructs, no eval;
# all input treated as data (REQ-K1.5, REQ-B1.9).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

self_dir="$(cd "$(dirname "$0")" && pwd -P)"

audit=0
root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --audit)
      audit=1
      ;;
    --root)
      shift
      [ "$#" -gt 0 ] || {
        echo "check-instructions: --root needs a directory argument" >&2
        exit 2
      }
      root="$1"
      ;;
    --root=*)
      root="${1#--root=}"
      ;;
    -h | --help)
      sed -n '2,40p' "$0"
      exit 0
      ;;
    *)
      echo "check-instructions: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
  shift
done

fixture_mode=1
if [ -z "$root" ]; then
  root="$(cd "$self_dir/.." && pwd -P)"
  fixture_mode=0
fi
if [ ! -d "$root" ]; then
  echo "check-instructions: root directory not found: $root" >&2
  exit 2
fi

skills_dir="$root/skills"
doctrine_dir="$root/doctrine"
hooks_json="$root/hooks/hooks.json"
config_defaults="$root/config/defaults.yml"
exemptions_file="$root/config/instruction-budget-exemptions.txt"
config_get="$self_dir/config-get.sh"

status=0
err() {
  echo "check-instructions: ERROR: $1" >&2
  status=1
}
warn() {
  echo "check-instructions: WARN: $1" >&2
}

# Scratch space for the ranked per-file list (sorted at report time).
work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT
perfile_list="$work/perfile"
skill_list="$work/skills"
injected_list="$work/injected"
shortlist="$work/shortlist"
: >"$perfile_list"
: >"$skill_list"
: >"$injected_list"
: >"$shortlist"

########################################################################
# Thresholds — read every knob through config-get so overlay layering
# applies; fail loud on a missing or non-numeric knob (REQ-B1.8).
########################################################################
getknob() {
  # getknob <key> -> echoes the integer value, or errors and echoes nothing.
  key="$1"
  if [ ! -x "$config_get" ]; then
    err "config-get.sh missing or not executable at $config_get"
    return 1
  fi
  # config-get resolves core defaults + overlay layers. Root them at $root so a
  # fixture (or the repo) reads its own config; in fixture mode also neutralize
  # ambient plugin/adopter env so the read is hermetic.
  if [ "$fixture_mode" -eq 1 ]; then
    val="$(
      PLANWRIGHT_CONFIG_DEFAULTS="$config_defaults" \
        PLANWRIGHT_REPO_ROOT="$root" \
        CLAUDE_PLUGIN_ROOT="" CLAUDE_PLUGIN_DATA="" \
        PLANWRIGHT_ADOPTER_OVERLAY="$root/.no-adopter-overlay" \
        PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_ROOT="" \
        "$config_get" "$key" 2>/dev/null
    )"
    rc=$?
  else
    val="$(
      PLANWRIGHT_CONFIG_DEFAULTS="$config_defaults" \
        PLANWRIGHT_REPO_ROOT="$root" \
        "$config_get" "$key" 2>/dev/null
    )"
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    # getknob runs in a command substitution, so it cannot set the parent's
    # status; it prints the diagnostic (stderr is shared) and returns non-zero,
    # and the caller records the failure via `|| knob_ok=0`.
    echo "check-instructions: ERROR: threshold knob '$key' is absent (config-get exit $rc); cannot measure fail-loud" >&2
    return 1
  fi
  case "$val" in
    '' | *[!0-9]*)
      echo "check-instructions: ERROR: threshold knob '$key' is not a non-negative integer: '$val'" >&2
      return 1
      ;;
  esac
  printf '%s' "$val"
}

knob_ok=1
t_skill_warn="$(getknob instruction_budget_skill_warn)" || knob_ok=0
t_skill_error="$(getknob instruction_budget_skill_error)" || knob_ok=0
t_doc_warn="$(getknob instruction_budget_doctrine_warn)" || knob_ok=0
t_doc_error="$(getknob instruction_budget_doctrine_error)" || knob_ok=0
t_sl_warn="$(getknob instruction_budget_startload_warn)" || knob_ok=0
t_sl_error="$(getknob instruction_budget_startload_error)" || knob_ok=0
t_cl_warn="$(getknob instruction_budget_closure_warn)" || knob_ok=0
t_cl_error="$(getknob instruction_budget_closure_error)" || knob_ok=0
t_inj_warn="$(getknob instruction_budget_injected_warn)" || knob_ok=0

# A missing/non-numeric knob is fail-loud: without the thresholds no honest
# measurement is possible, so stop here (an input that cannot be measured is
# never counted as under budget, REQ-B1.8).
if [ "$knob_ok" -ne 1 ]; then
  echo "check-instructions: aborting — threshold knobs could not be read" >&2
  exit 1
fi

########################################################################
# Suppression list — permanent exemptions and transitional allowances.
# Grammar (pipe-delimited, one entry per non-blank/non-comment line):
#   exempt|<path>|<reason>
#       permanent per-file-floor exemption ONLY (never start-load/closure).
#   pending-diet|<budget>|<target>|Task <N>|<reason>
#       transitional allowance; <budget> = file | start-load | closure;
#       <target> = a file path (file) or a skill name (start-load/closure).
# A reason-less entry of either form is an error; an unparseable line is an
# error (REQ-B1.3, REQ-B1.8). Content is data, never evaluated (REQ-B1.9).
########################################################################
exempt_paths=""   # permanent per-file exemptions (newline-separated paths)
exempt_reasons="" # "path\treason" records for echoing
pd_file_paths=""  # transitional per-file allowances (paths)
pd_startload=""   # transitional start-load allowances (skill names)
pd_closure=""     # transitional closure allowances (skill names)

in_list() {
  # in_list <needle> <newline-list> -> 0 if present
  needle="$1"
  list="$2"
  case "
$list
" in
    *"
$needle
"*) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -f "$exemptions_file" ]; then
  # Read as data; IFS='|' splits fields, read -r never interprets backslashes,
  # and no field is ever expanded or executed.
  while IFS= read -r raw || [ -n "$raw" ]; do
    case "$raw" in
      '' | '#'*) continue ;;
    esac
    form="${raw%%|*}"
    rest="${raw#*|}"
    case "$form" in
      exempt)
        path="${rest%%|*}"
        reason="${rest#*|}"
        if [ "$path" = "$rest" ] || [ -z "$path" ]; then
          err "malformed exemption entry (expected exempt|<path>|<reason>): $raw"
          continue
        fi
        if [ -z "$reason" ] || [ "$reason" = "$rest" ]; then
          err "exemption for '$path' has no reason (a recorded reason is required)"
          continue
        fi
        exempt_paths="$exempt_paths
$path"
        exempt_reasons="$exempt_reasons
$path	$reason"
        ;;
      pending-diet)
        budget="${rest%%|*}"
        rest2="${rest#*|}"
        target="${rest2%%|*}"
        rest3="${rest2#*|}"
        task="${rest3%%|*}"
        reason="${rest3#*|}"
        if [ "$budget" = "$rest" ] || [ "$target" = "$rest2" ] \
          || [ "$task" = "$rest3" ] || [ -z "$budget" ] || [ -z "$target" ] \
          || [ -z "$task" ]; then
          err "malformed pending-diet entry (expected pending-diet|<budget>|<target>|Task N|<reason>): $raw"
          continue
        fi
        if [ -z "$reason" ] || [ "$reason" = "$rest3" ]; then
          err "pending-diet allowance for '$target' has no reason (a recorded reason is required)"
          continue
        fi
        case "$budget" in
          file) pd_file_paths="$pd_file_paths
$target" ;;
          start-load) pd_startload="$pd_startload
$target" ;;
          closure) pd_closure="$pd_closure
$target" ;;
          *)
            err "unknown pending-diet budget class '$budget' (expected file|start-load|closure): $raw"
            continue
            ;;
        esac
        ;;
      *)
        err "unknown suppression form '$form' (expected exempt|pending-diet): $raw"
        continue
        ;;
    esac
  done <"$exemptions_file"
fi

########################################################################
# Per-file walk + per-skill start-load / closure, in a single pass per file so
# each file's word/line count is taken exactly once (guard-performance risk R10:
# memoized counts, no O(skills*docs) re-reads). Skills use the skill thresholds
# and additionally get their manifest-derived start-load/closure; doctrine files
# use the doctrine thresholds. doctrine/README.md is excluded (REQ-A1.1).
########################################################################
# Measure EVERY instruction file in ONE awk pass (guard-performance risk R10: no
# per-file fork chain), caching the word/line counts in parallel arrays keyed by
# repo-relative path. Every later lookup — per-file floors, a skill's body, a
# manifest doc's contribution to start-load/closure — is a fork-free array scan.
mpaths=()
mwords=()
mlines=()
files_to_measure=()
if [ -d "$skills_dir" ]; then
  for skill_md in "$skills_dir"/*/SKILL.md; do
    [ -f "$skill_md" ] && files_to_measure+=("$skill_md")
  done
fi
if [ -d "$doctrine_dir" ]; then
  for doc in "$doctrine_dir"/*.md; do
    [ -f "$doc" ] || continue
    [ "${doc##*/}" = "README.md" ] && continue
    files_to_measure+=("$doc")
  done
fi
if [ "${#files_to_measure[@]}" -gt 0 ]; then
  measured="$(awk '
    FNR == 1 { if (f != "") print f "\t" w "\t" l; f = FILENAME; w = 0; l = 0 }
    { w += NF; l++ }
    END { if (f != "") print f "\t" w "\t" l }
  ' "${files_to_measure[@]}")"
  while IFS="$(printf '\t')" read -r mp mw ml; do
    [ -n "$mp" ] || continue
    mpaths+=("$mp")
    mwords+=("$mw")
    mlines+=("$ml")
  done <<EOF
$measured
EOF
fi

# mget <abs-path> -> sets MW and ML from the cache; returns 1 if not measured.
mget() {
  _i=0
  _n="${#mpaths[@]}"
  while [ "$_i" -lt "$_n" ]; do
    if [ "${mpaths[$_i]}" = "$1" ]; then
      MW="${mwords[$_i]}"
      ML="${mlines[$_i]}"
      return 0
    fi
    _i=$((_i + 1))
  done
  return 1
}

# classify <words> <warn> <error> -> sets _STATE to ok|WARN|ERROR (boundary >=).
# A global write, not an echo, to avoid a subshell fork per file.
classify() {
  if [ "$1" -ge "$3" ]; then
    _STATE=ERROR
  elif [ "$1" -ge "$2" ]; then
    _STATE=WARN
  else
    _STATE=ok
  fi
}

record_perfile() {
  # record_perfile <relpath> <words> <lines> <warn> <error> <kind>
  rel="$1"
  words="$2"
  lines="$3"
  wt="$4"
  et="$5"
  classify "$words" "$wt" "$et"
  state="$_STATE"
  suppress=""
  if in_list "$rel" "$exempt_paths"; then
    suppress="exempt"
  elif in_list "$rel" "$pd_file_paths"; then
    suppress="pending-diet"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$words" "$rel" "$lines" "$state" "$suppress" "$6" >>"$perfile_list"

  if [ "$state" = ERROR ]; then
    # Every over-floor file is an offender and goes on the shortlist (it needs a
    # diet plan, REQ-A1.3), whether or not a suppression currently keeps CI
    # green; suppression governs only the exit code, not offender status.
    printf 'per-file\t%s\t%s\t%s\t%s\n' "$rel" "$words" "$et" "${suppress:-unsuppressed}" >>"$shortlist"
    if [ "$suppress" = exempt ]; then
      # echo the standing rationale so a reviewer sees why the floor is waived.
      ereason=""
      case "
$exempt_reasons
" in
        *"
$rel	"*)
          ereason="${exempt_reasons#*"
$rel	"}"
          ereason="${ereason%%
*}"
          ;;
      esac
      warn "per-file floor over budget but permanently exempt: $rel ($words words) [floor $et] — reason: $ereason"
    elif [ "$suppress" = pending-diet ]; then
      warn "per-file floor over budget, pending-diet allowance in place: $rel ($words words) [floor $et]"
    else
      err "per-file floor over budget: $rel ($words words >= $et)"
    fi
  elif [ "$state" = WARN ]; then
    warn "per-file floor warn: $rel ($words words >= $wt)"
  fi
}

# resolve_doc: charset-validate the name BEFORE any path is formed (REQ-B1.9),
# then confine resolution to the doctrine root by looking the doc up in the
# measured-file cache (every doctrine/*.md was measured above). On success sets
# DOC_W to the doc's word count and returns 0; returns 1 unresolvable; returns 2
# invalid name (traversal-safe — the name never reaches a path unless it matched
# the strict kebab-case identifier charset).
resolve_doc() {
  name="$1"
  case "$name" in
    [a-z0-9]*) ;;
    *) return 2 ;;
  esac
  case "$name" in
    *[!a-z0-9-]*) return 2 ;;
  esac
  if mget "$doctrine_dir/$name.md"; then
    DOC_W="$MW"
    return 0
  fi
  # An empty (zero-line) doc exists but is absent from the measure cache; it
  # resolves and contributes zero words.
  if [ -f "$doctrine_dir/$name.md" ]; then
    DOC_W=0
    return 0
  fi
  return 1
}

# The manifest parser: emit one record per column-zero Doctrine: line outside a
# fenced block. Class and name are validated here so a malformed entry is caught
# fail-loud (REQ-B1.8) and a bad name never reaches a path (REQ-B1.9). Output:
#   OK <class> <name>
#   BAD <verbatim line>
# shellcheck disable=SC2016 # a single-quoted awk program; $0/$fields are awk's
parse_manifest='
  BEGIN { fence = 0 }
  {
    line = $0
    # fenced-code tracking: a ``` or ~~~ marker at column zero toggles.
    if (line ~ /^```/ || line ~ /^~~~/) { fence = 1 - fence; next }
    if (fence) next
    # only column-zero lines are entries; indented/quoted lines never are.
    if (line ~ /^[ \t]/) next
    if (line ~ /^Doctrine:/) {
      rest = line
      sub(/^Doctrine:/, "", rest)
      # class
      n = split(rest, tok, /[ \t]+/)
      # tok[1] is empty (leading space); class is first non-empty token.
      ci = 1
      while (ci <= n && tok[ci] == "") ci++
      cls = (ci <= n) ? tok[ci] : ""
      ni = ci + 1
      while (ni <= n && tok[ni] == "") ni++
      nm = (ni <= n) ? tok[ni] : ""
      # after the name, only an optional (parenthesized note) may follow.
      # rebuild the tail after the name token.
      tail = ""
      for (k = ni + 1; k <= n; k++) if (tok[k] != "") tail = tail " " tok[k]
      gsub(/^[ \t]+|[ \t]+$/, "", tail)
      okclass = (cls == "run-start" || cls == "point-of-use")
      okname = (nm ~ /^[a-z0-9][a-z0-9-]*$/)
      oktail = (tail == "" || tail ~ /^\(.*\)$/)
      if (okclass && okname && oktail) {
        print "OK " cls " " nm
      } else {
        print "BAD " line
      }
      next
    }
    # a column-zero case-variant near-miss (doctrine:, DOCTRINE:) is malformed,
    # never silently dropped (it would under-report the start-load).
    if (tolower(line) ~ /^doctrine:/) { print "BAD " line }
  }
'

if [ -d "$skills_dir" ]; then
  for skill_md in "$skills_dir"/*/SKILL.md; do
    [ -f "$skill_md" ] || continue
    sname="${skill_md%/SKILL.md}"
    sname="${sname##*/}"
    # A zero-line (empty) file never reaches the measure awk's FNR==1 flush, so
    # it is absent from the cache; score it 0/0 rather than reuse a stale value.
    MW=0
    ML=0
    mget "$skill_md" || true
    body_words="$MW"
    record_perfile "skills/$sname/SKILL.md" "$MW" "$ML" \
      "$t_skill_warn" "$t_skill_error" skill
    startload="$body_words"
    closure="$body_words"
    seen_docs=""
    malformed=0
    unresolved=0

    while IFS= read -r rec; do
      [ -n "$rec" ] || continue
      tag="${rec%% *}"
      if [ "$tag" = BAD ]; then
        err "malformed doctrine manifest entry in skills/$sname/SKILL.md: ${rec#BAD }"
        malformed=1
        continue
      fi
      # rec = "OK <class> <name>"
      body="${rec#OK }"
      cls="${body%% *}"
      name="${body#* }"
      if in_list "$name" "$seen_docs"; then
        err "duplicate doctrine manifest doc '$name' in skills/$sname/SKILL.md"
        malformed=1
        continue
      fi
      seen_docs="$seen_docs
$name"
      resolve_doc "$name"
      rc=$?
      if [ "$rc" -eq 2 ]; then
        err "invalid doctrine manifest doc name in skills/$sname/SKILL.md: '$name'"
        malformed=1
        continue
      fi
      if [ "$rc" -eq 1 ]; then
        err "unresolvable doctrine reference '$name' in skills/$sname/SKILL.md (no doctrine/$name.md)"
        unresolved=1
        continue
      fi
      dw="$DOC_W"
      if [ "$cls" = run-start ]; then
        startload=$((startload + dw))
        closure=$((closure + dw))
      else
        closure=$((closure + dw))
      fi
    done <<EOF
$(awk "$parse_manifest" "$skill_md")
EOF

    if [ "$malformed" -eq 1 ] || [ "$unresolved" -eq 1 ]; then
      # A skill whose manifest cannot be trusted is not scored under budget.
      printf '%s\t%s\t%s\t%s\t%s\n' "$sname" "$startload" "$closure" \
        "unmeasured" "unmeasured" >>"$skill_list"
      continue
    fi

    classify "$startload" "$t_sl_warn" "$t_sl_error"
    sl_state="$_STATE"
    classify "$closure" "$t_cl_warn" "$t_cl_error"
    cl_state="$_STATE"
    printf '%s\t%s\t%s\t%s\t%s\n' "$sname" "$startload" "$closure" \
      "$sl_state" "$cl_state" >>"$skill_list"

    if [ "$sl_state" = ERROR ]; then
      if in_list "$sname" "$pd_startload"; then
        printf 'start-load\t%s\t%s\t%s\t%s\n' "$sname" "$startload" "$t_sl_error" "pending-diet" >>"$shortlist"
        warn "start-load over budget, pending-diet allowance in place: $sname ($startload >= $t_sl_error)"
      else
        printf 'start-load\t%s\t%s\t%s\t%s\n' "$sname" "$startload" "$t_sl_error" "unsuppressed" >>"$shortlist"
        err "start-load over budget: $sname ($startload words >= $t_sl_error)"
      fi
    elif [ "$sl_state" = WARN ]; then
      warn "start-load warn: $sname ($startload words >= $t_sl_warn)"
    fi

    if [ "$cl_state" = ERROR ]; then
      if in_list "$sname" "$pd_closure"; then
        printf 'closure\t%s\t%s\t%s\t%s\n' "$sname" "$closure" "$t_cl_error" "pending-diet" >>"$shortlist"
        warn "closure over budget, pending-diet allowance in place: $sname ($closure >= $t_cl_error)"
      else
        printf 'closure\t%s\t%s\t%s\t%s\n' "$sname" "$closure" "$t_cl_error" "unsuppressed" >>"$shortlist"
        err "closure over budget: $sname ($closure words >= $t_cl_error)"
      fi
    elif [ "$cl_state" = WARN ]; then
      warn "closure warn: $sname ($closure words >= $t_cl_warn)"
    fi
  done
fi

# Doctrine rule docs: per-file floor only (they carry no manifest of their own;
# their contribution to a skill's start-load/closure is counted above via that
# skill's manifest). doctrine/README.md is excluded (REQ-A1.1).
if [ -d "$doctrine_dir" ]; then
  for doc in "$doctrine_dir"/*.md; do
    [ -f "$doc" ] || continue
    base="${doc##*/}"
    [ "$base" = "README.md" ] && continue
    mget "$doc" || continue
    record_perfile "doctrine/$base" "$MW" "$ML" \
      "$t_doc_warn" "$t_doc_error" doctrine
  done
fi

########################################################################
# Injected-context hooks (REQ-A1.4, REQ-B1.7). Discovery is over hooks.json
# registered commands; a hook is injected-context iff its script emits
# additionalContext / hookSpecificOutput. Static prose is extracted from
# heredoc bodies and multi-line quoted-string assignments, excluding
# interpolation lines. The script is read, never executed. This surface never
# fails the check: over-floor -> warning; unextractable -> parse-failure
# warning.
########################################################################
# Extract static injected prose. Emits two lines: "WORDS <n>" and "BLOCK <0|1>"
# (BLOCK 1 iff at least one heredoc/multi-line-quote body was found). An
# interpolation line ($(...), ${...}, or a $name reference) is noted, not
# counted.
# shellcheck disable=SC2016 # a single-quoted awk program; the $-forms are awk's
extract_injected='
  function is_interp(s) { return (s ~ /\$\(/ || s ~ /\$\{/ || s ~ /\$[A-Za-z_]/) }
  function count_words(s,   m, a) {
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    if (s == "") return 0
    m = split(s, a, /[ \t]+/)
    return m
  }
  BEGIN { mode = 0; total = 0; block = 0; delim = ""; qchar = "" }
  {
    line = $0
    if (mode == 1) {                       # in heredoc
      t = line
      gsub(/^[ \t]+/, "", t)               # <<- strips leading tabs on term
      if (t == delim || line == delim) { mode = 0; next }
      if (!is_interp(line)) total += count_words(line)
      next
    }
    if (mode == 2) {                       # in multi-line quoted string
      idx = index(line, qchar)
      if (idx > 0) {
        prose = substr(line, 1, idx - 1)
        if (!is_interp(prose)) total += count_words(prose)
        mode = 0
        next
      }
      if (!is_interp(line)) total += count_words(line)
      next
    }
    # NORMAL: heredoc opener wins over quoted-assignment detection.
    if (match(line, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_]*/)) {
      d = substr(line, RSTART, RLENGTH)
      sub(/^<<-?[ \t]*[\047"]?/, "", d)
      delim = d
      mode = 1
      block = 1
      next
    }
    # multi-line double- or single-quoted assignment at column zero:
    # name="...    (no closing quote on this line)
    if (line ~ /^[A-Za-z_][A-Za-z0-9_]*="[^"]*$/) {
      qchar = "\""
      prose = line
      sub(/^[A-Za-z_][A-Za-z0-9_]*="/, "", prose)
      if (!is_interp(prose)) total += count_words(prose)
      mode = 2
      block = 1
      next
    }
    if (line ~ /^[A-Za-z_][A-Za-z0-9_]*=\047[^\047]*$/) {
      qchar = "\047"
      prose = line
      sub(/^[A-Za-z_][A-Za-z0-9_]*=\047/, "", prose)
      if (!is_interp(prose)) total += count_words(prose)
      mode = 2
      block = 1
      next
    }
  }
  END { print "WORDS " total; print "BLOCK " block }
'

scan_injected() {
  [ -f "$hooks_json" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq unavailable; injected-context scan skipped (surface is warn-only)"
    return 0
  fi
  cmds="$(jq -r '.hooks // {} | to_entries[]? | .value[]? | .hooks[]? | select(.type=="command") | .command' "$hooks_json" 2>/dev/null)" || {
    warn "hooks.json could not be parsed; injected-context scan skipped (warn-only surface)"
    return 0
  }
  [ -n "$cmds" ] || return 0
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    # Map the command to a script path under $root. Strip quotes, then take the
    # tail after the last brace-close of a ${...} plugin-root reference. Pure
    # string surgery on data — the command is never executed (REQ-B1.9).
    c="${cmd//\"/}"
    c="${c//\'/}"
    case "$c" in
      *'}'*) rel="${c##*\}}" ;;
      *) rel="$c" ;;
    esac
    rel="${rel#/}"
    case "$rel" in
      *..*)
        warn "hook path contains '..' traversal; skipped: $cmd"
        continue
        ;;
    esac
    hook_path="$root/$rel"
    [ -f "$hook_path" ] || continue
    [ -r "$hook_path" ] || continue
    # injected-context iff the script emits additionalContext/hookSpecificOutput.
    grep -q 'additionalContext\|hookSpecificOutput' "$hook_path" 2>/dev/null || continue

    ex="$(awk "$extract_injected" "$hook_path")"
    iwords="$(printf '%s\n' "$ex" | sed -n 's/^WORDS //p')"
    iblock="$(printf '%s\n' "$ex" | sed -n 's/^BLOCK //p')"
    [ -n "$iwords" ] || iwords=0

    if [ "$iblock" = 0 ]; then
      printf '%s\t%s\t%s\n' "$rel" "$iwords" "parse-failure" >>"$injected_list"
      warn "injected-context hook static prose could not be extracted (parse-failure, warn-only): $rel"
      continue
    fi
    istate=ok
    if [ "$iwords" -ge "$t_inj_warn" ]; then
      istate=WARN
      warn "injected-context static prose over floor: $rel (static=$iwords >= $t_inj_warn)"
    fi
    printf '%s\t%s\t%s\n' "$rel" "$iwords" "$istate" >>"$injected_list"
  done <<EOF
$cmds
EOF
}
scan_injected

########################################################################
# --audit report.
########################################################################
if [ "$audit" -eq 1 ]; then
  echo "== Instruction hygiene audit =="
  echo
  echo "Per-file (ranked by words):"
  sort -rn "$perfile_list" | while IFS="$(printf '\t')" read -r w rel l st sup _; do
    tag=""
    [ -n "$sup" ] && tag=" [$sup]"
    printf '  words=%s lines=%s %s %s%s\n' "$w" "$l" "$rel" "$st" "$tag"
  done
  echo
  echo "Per-skill load:"
  while IFS="$(printf '\t')" read -r name sl cl sls cls; do
    printf '  %s start-load=%s (%s) closure=%s (%s)\n' "$name" "$sl" "$sls" "$cl" "$cls"
  done <"$skill_list"
  echo
  echo "Injected-context hooks:"
  if [ -s "$injected_list" ]; then
    while IFS="$(printf '\t')" read -r rel iw ist; do
      printf '  %s static=%s %s\n' "$rel" "$iw" "$ist"
    done <"$injected_list"
  else
    echo "  none"
  fi
  echo
  echo "Offender shortlist:"
  if [ -s "$shortlist" ]; then
    while IFS="$(printf '\t')" read -r cls tgt w th sup; do
      printf '  %s %s (%s words >= %s %s budget) [%s]\n' \
        "$cls" "$tgt" "$w" "$th" "$cls" "$sup"
    done <"$shortlist"
  else
    echo "  none"
  fi
fi

exit "$status"
