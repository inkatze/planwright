#!/usr/bin/env bash
# check-backend-capability-drift.sh — the backend-capability triangle tether
# (guard-coverage Task 9; REQ-F1.2, REQ-H1.3, D-10).
#
# Three surfaces restate the same capability facts:
#
#   1. doctrine/backend-capability-contract.md — the prose table. This is the
#      **direction of truth**: a registry change requires the doc edit first
#      (guard-coverage kickoff brief, §3 F).
#   2. scripts/orchestrate-backends.sh — the `caps_for()` registry the
#      orchestrator actually reads.
#   3. docs/fleet.md — the operator-facing backend table.
#
# A doc restating a machine-readable fact drifts silently, so this check
# asserts all three agree, on the same backend set and on every field the
# surface carries. It is exercised by tests/test-backend-capability-drift.sh,
# which the `test` task runs inside the `check` aggregate.
#
# ## The normalization contract
#
# The three surfaces spell the same value differently; the check compares
# meaning, not bytes, so it fires only on real divergence.
#
#   * **Decoration stripped.** Backticks and `*` emphasis are removed and the
#     cell is trimmed, so `` `no` `` and `*no*` are both `no`.
#   * **Annotations stripped.** A value is its first token: everything from the
#     first space, `(`, `,`, or `;` onward is dropped. So "yes (recoverable via
#     `--resume`)" is `yes`, "deferred to you" is `deferred`, and
#     "`beta` (manual)" names the backend `beta`.
#   * **Boolean synonyms.** `true`/`yes` compare equal, `false`/`no` compare
#     equal — the prose and registry say true/false where the operator doc says
#     yes/no.
#   * **`n/a` equals `na`.** The prose spells the not-applicable value `n/a`;
#     the registry's space-separated field string cannot, and spells it `na`.
#   * **`overhead` is compared literally** (after decoration stripping), since
#     its values are identifiers (`full-session+supervisor`, `light`, `none`),
#     not an enum of synonyms.
#   * **One observe/steer cell covers both fields.** docs/fleet.md merges
#     `can_observe` and `can_steer_inflight` into a single "Observe / steer"
#     column; `yes / no` maps to the pair, and a single value (`n/a`) applies
#     to both.
#
# A value that normalizes to none of the recognized tokens is a **parse error**
# (exit 2), never a silent mismatch: an unreadable surface must not be able to
# masquerade as either agreement or divergence.
#
# ## Fail-closed posture (REQ-H1.3)
#
# Any of the three surfaces parsing to zero rows exits 2, as does a missing
# input file, a capability table whose header does not carry the expected
# columns, a `caps_for()` arm that does not emit exactly the eight contract
# fields, a backend name outside the identifier grammar
# `scripts/orchestrate-backends.sh` enforces in `valid_name()`, and a second
# row for a backend a surface already named. A vacuous or ambiguous parse must
# never read as agreement.
#
# ## Semantic (non-backend) fleet rows
#
# docs/fleet.md's table opens with `full-session`, which is not a backend but a
# semantic value resolved at dispatch time. It is exempt by name (SEMANTIC_ROWS
# below), so the exemption is a declaration rather than an accident; any other
# fleet row naming a backend the contract does not define is an error.
#
# Usage: check-backend-capability-drift.sh [<contract.md> [<backends.sh> [<fleet.md>]]]
#   All three default to the repo's shipped surfaces (the CI entry point).
#
# Exit codes: 0 the three surfaces agree; 1 they diverge; 2 usage error or a
# fail-closed parse degeneracy.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitution below and
# corrupt the repo-root derivation.
unset CDPATH

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Display sanitizer for parsed content (echo discipline,
# doctrine/security-posture.md). A byte-identical inline fallback is defined
# first so a diagnostic is never unable to strip control bytes; the canonical
# shared helper overrides it when the sibling resolves.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -r "$repo_root/scripts/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$repo_root/scripts/echo-safety.sh"
fi

fail_closed() {
  echo "check-backend-capability-drift: $1" >&2
  exit 2
}

# The parsers below carry their diagnostics on `#ERR`-prefixed lines inside
# the fact stream, so a malformed surface needs no scratch file to report
# itself. These two split the stream back apart.
parse_detail() {
  pd_lines="$(printf '%s\n' "$1" | sed -n 's/^#ERR[[:space:]]*//p' | tr '\n' ';')"
  sanitize_printable "$pd_lines" "(unprintable diagnostic)"
}
strip_detail() { printf '%s\n' "$1" | grep -v '^#ERR' || true; }

contract="${1:-$repo_root/doctrine/backend-capability-contract.md}"
registry="${2:-$repo_root/scripts/orchestrate-backends.sh}"
fleet="${3:-$repo_root/docs/fleet.md}"

for path in "$contract" "$registry" "$fleet"; do
  [ -f "$path" ] \
    || fail_closed "input file not found: $(sanitize_printable "$path" "(unprintable path)")"
done

# The eight contract fields, in the order `caps_for()` emits them.
FIELDS="interactive can_observe can_steer_inflight provides_attention_surface supports_parallel session_grade overhead hook_registration"

# Fleet-table rows that name a semantic value rather than a backend.
SEMANTIC_ROWS="full-session"

# ---------------------------------------------------------------------------
# The shared normalization contract, as awk functions. Every surface's parser
# below normalizes through these, so the contract has one implementation.
# ---------------------------------------------------------------------------
awk_lib='
function strip(s) {
  gsub(/`/, "", s); gsub(/\*/, "", s)
  gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s)
  return s
}
function token(s,  t) {
  t = strip(s)
  sub(/[ \t(,;].*$/, "", t)
  return tolower(t)
}
function nbool(v,  t) {
  t = token(v)
  if (t == "true" || t == "yes") return "true"
  if (t == "false" || t == "no") return "false"
  if (t == "n/a" || t == "na") return "na"
  return "!" t
}
function ngrade(v,  t) {
  t = token(v)
  if (t == "yes" || t == "no" || t == "deferred") return t
  if (t == "n/a" || t == "na") return "na"
  return "!" t
}
function nfield(f, v) {
  if (f == "session_grade") return ngrade(v)
  if (f == "overhead") return tolower(strip(v))
  return nbool(v)
}
function emit(b, f, v) { printf "%s\t%s\t%s\n", b, f, v }
# Diagnostics ride the fact stream on a sentinel line rather than stderr, so
# no surface needs a scratch file: a predictable name under TMPDIR would be a
# symlink-following write, and an unwritable TMPDIR would silently cost the
# diagnostic. The bad flag it sets is read by each program END block.
function err(m) { printf "#ERR\t%s\n", m; bad = 1 }
# The backend-name grammar scripts/orchestrate-backends.sh already enforces in
# valid_name(). Validating parsed names here keeps a name carrying a regex
# metacharacter out of the set comparison below, where it would match an
# unrelated backend.
function valid_name(b) { return (b ~ /^[a-z0-9][a-z0-9-]*$/ && length(b) <= 64) }
function accept(b) {
  if (!valid_name(b)) { err("backend name outside the identifier grammar: " b); return 0 }
  if (b in seen_backend) { err("duplicate row for backend " b); return 0 }
  seen_backend[b] = 1
  return 1
}
'

# ---------------------------------------------------------------------------
# Surface 1: the prose capability table. Located by its header row — first cell
# `Backend`, and a column for every one of the eight fields. A header that no
# longer carries them all is not this table, so a renamed column fails closed
# rather than silently parsing a neighbouring table.
# ---------------------------------------------------------------------------
contract_facts="$(awk -v fields="$FIELDS" "$awk_lib"'
  BEGIN {
    nf = split(fields, want, " ")
    for (w = 1; w <= nf; w++) iswant[want[w]] = 1
  }
  {
    line = $0; sub(/^[ \t]+/, "", line)
    # The first non-row line ends the table, and ends the walk: a later table
    # carrying the same header is a neighbouring table (an illustrative one in
    # prose, say), not more registry rows. `exit` still runs the END block, so
    # the no-header, zero-row, and malformed arms keep their exit codes.
    if (line !~ /^\|/) { if (intbl) exit; next }
    n = split(line, c, "|")
    if (!intbl) {
      if (strip(c[2]) != "Backend") next
      for (i in colname) delete colname[i]
      for (i = 3; i < n; i++) {
        key = tolower(strip(c[i]))
        if (key == "session-grade") key = "session_grade"
        colname[i] = key
      }
      ok = 1
      for (w in want) {
        has_col = 0
        for (i in colname) if (colname[i] == want[w]) has_col = 1
        if (!has_col) ok = 0
      }
      if (!ok) next
      intbl = 1; found = 1; next
    }
    if (line ~ /^\|[ \t]*:?-+:?[ \t]*\|/) next
    b = token(c[2])
    if (b == "") next
    if (!accept(b)) next
    # Row arity, the prose-side mirror of the caps_for() field-count check
    # below. A row short of a contract column emits no fact for it, and the
    # comparison loop has nothing to compare — so a truncated row would read
    # as agreement rather than as the partial parse it is. Only cells mapping
    # to a contract field are counted, so a table carrying an extra
    # non-contract column stays readable.
    got = 0
    for (i = 3; i < n; i++) if (colname[i] in iswant) got++
    if (got != nf) {
      err("prose row " b " carries " got " contract cells, expected " nf)
      next
    }
    for (i = 3; i < n; i++) {
      if (colname[i] == "") continue
      emit(b, colname[i], nfield(colname[i], c[i]))
    }
    rows++
  }
  END {
    if (bad) exit 5
    if (!found) exit 3
    if (!rows) exit 4
  }
' "$contract")"
contract_status=$?
safe_contract="$(sanitize_printable "$contract" "(unprintable path)")"
case "$contract_status" in
  3) fail_closed "could not find the backend capability table in $safe_contract (no header row carrying all eight contract columns)" ;;
  4) fail_closed "the backend capability table in $safe_contract parsed to zero rows" ;;
  5) fail_closed "malformed backend capability table in $safe_contract: $(parse_detail "$contract_facts")" ;;
  0) ;;
  *) fail_closed "failed to parse $safe_contract" ;;
esac
contract_facts="$(strip_detail "$contract_facts")"

# ---------------------------------------------------------------------------
# Surface 2: the `caps_for()` registry. Each case arm emits the eight fields as
# a space-separated string, in FIELDS order.
# ---------------------------------------------------------------------------
registry_facts="$(awk -v fields="$FIELDS" "$awk_lib"'
  BEGIN { nf = split(fields, want, " ") }
  /^caps_for\(\)[ \t]*\{/ { infn = 1; next }
  infn && /^\}/ { infn = 0; next }
  infn {
    line = $0; sub(/^[ \t]+/, "", line)
    if (line !~ /^[a-z0-9][a-z0-9-]*\)[ \t]*echo[ \t]+"/) next
    b = line; sub(/\).*/, "", b)
    if (!accept(b)) next
    v = line; sub(/^[^"]*"/, "", v); sub(/".*/, "", v)
    got = split(v, f, /[ \t]+/)
    if (got != nf) {
      err("arm " b " emits " got " fields, expected " nf)
      next
    }
    for (i = 1; i <= nf; i++) emit(b, want[i], nfield(want[i], f[i]))
    rows++
  }
  END {
    if (bad) exit 5
    if (!rows) exit 4
  }
' "$registry")"
registry_status=$?
safe_registry="$(sanitize_printable "$registry" "(unprintable path)")"
case "$registry_status" in
  4) fail_closed "no caps_for() capability arms parsed from $safe_registry" ;;
  5) fail_closed "malformed caps_for() registry in $safe_registry: $(parse_detail "$registry_facts")" ;;
  0) ;;
  *) fail_closed "failed to parse caps_for() in $safe_registry" ;;
esac
registry_facts="$(strip_detail "$registry_facts")"

# ---------------------------------------------------------------------------
# Surface 3: the operator-facing fleet table. Located by a header carrying both
# an "Observe / steer" column and a "Session-grade" column, which is what tells
# it apart from the prose contract's table.
# ---------------------------------------------------------------------------
fleet_facts="$(awk -v semantic="$SEMANTIC_ROWS" "$awk_lib"'
  BEGIN { split(semantic, sem, " ") }
  function is_semantic(b,  k) {
    for (k in sem) if (sem[k] == b) return 1
    return 0
  }
  {
    line = $0; sub(/^[ \t]+/, "", line)
    # First matching table only; see the prose parser above.
    if (line !~ /^\|/) { if (intbl) exit; next }
    n = split(line, c, "|")
    if (!intbl) {
      if (strip(c[2]) != "Backend") next
      obs = 0; grade = 0
      for (i = 3; i < n; i++) {
        key = tolower(strip(c[i]))
        gsub(/[ \t]+/, " ", key)
        if (key == "observe / steer") obs = i
        if (key == "session-grade") grade = i
      }
      if (!obs || !grade) next
      intbl = 1; found = 1; next
    }
    if (line ~ /^\|[ \t]*:?-+:?[ \t]*\|/) next
    b = token(c[2])
    if (b == "" || is_semantic(b)) next
    if (!accept(b)) next
    cell = strip(c[obs])
    low = tolower(cell)
    if (low == "n/a" || low == "na") {
      ov = "na"; sv = "na"
    } else {
      np = split(cell, parts, "/")
      if (np == 1) { ov = nbool(parts[1]); sv = ov }
      else if (np == 2) { ov = nbool(parts[1]); sv = nbool(parts[2]) }
      else {
        err("observe/steer cell for " b " is not one or two values: " cell)
        next
      }
    }
    emit(b, "can_observe", ov)
    emit(b, "can_steer_inflight", sv)
    emit(b, "session_grade", ngrade(c[grade]))
    rows++
  }
  END {
    if (bad) exit 5
    if (!found) exit 3
    if (!rows) exit 4
  }
' "$fleet")"
fleet_status=$?
safe_fleet="$(sanitize_printable "$fleet" "(unprintable path)")"
case "$fleet_status" in
  3) fail_closed "could not find the backend table in $safe_fleet (no header row carrying both an 'Observe / steer' and a 'Session-grade' column)" ;;
  4) fail_closed "the backend table in $safe_fleet parsed to zero backend rows" ;;
  5) fail_closed "malformed backend table in $safe_fleet: $(parse_detail "$fleet_facts")" ;;
  0) ;;
  *) fail_closed "failed to parse the backend table in $safe_fleet" ;;
esac
fleet_facts="$(strip_detail "$fleet_facts")"

# ---------------------------------------------------------------------------
# Unrecognized tokens are a parse error on every surface: an unreadable value
# must not be able to masquerade as agreement or as divergence.
# ---------------------------------------------------------------------------
check_tokens() {
  bad="$(printf '%s\n' "$2" | awk -F'\t' '$3 ~ /^!/ { printf "%s.%s=%s\n", $1, $2, substr($3, 2) }')"
  [ -z "$bad" ] \
    || fail_closed "$1 carries values outside the normalization contract: $(sanitize_printable "$(printf '%s' "$bad" | tr '\n' ' ')" "(unprintable values)")"
}
check_tokens "the prose capability table" "$contract_facts"
check_tokens "the caps_for() registry" "$registry_facts"
check_tokens "the fleet backend table" "$fleet_facts"

# ---------------------------------------------------------------------------
# Comparison.
# ---------------------------------------------------------------------------
backends_of() { printf '%s\n' "$1" | awk -F'\t' '{print $1}' | sort -u; }
fact() {
  printf '%s\n' "$1" | awk -F'\t' -v b="$2" -v f="$3" '
    $1 == b && $2 == f { print $3; found = 1 }
    END { if (!found) exit 1 }'
}

contract_backends="$(backends_of "$contract_facts")"
registry_backends="$(backends_of "$registry_facts")"
fleet_backends="$(backends_of "$fleet_facts")"

status=0
report() {
  echo "check-backend-capability-drift: $1" >&2
  status=1
}

# Basenames for the divergence messages below. Sanitized like the safe_* paths
# above: these come from argv, so a caller-supplied path is caller-controlled
# content reaching a terminal.
safe_registry_base="$(sanitize_printable "${registry##*/}" "(unprintable filename)")"
safe_fleet_base="$(sanitize_printable "${fleet##*/}" "(unprintable filename)")"

# Backend sets: prose vs registry, both directions.
for b in $contract_backends; do
  printf '%s\n' "$registry_backends" | grep -qxF -- "$b" \
    || report "the prose contract defines backend '$b', which caps_for() in $safe_registry_base does not"
done
for b in $registry_backends; do
  printf '%s\n' "$contract_backends" | grep -qxF -- "$b" \
    || report "caps_for() in $safe_registry_base defines backend '$b', which the prose contract does not (the prose table is the direction of truth: edit it first)"
done

# Backend sets: prose vs the fleet table, both directions (semantic rows are
# already excluded by the fleet parser).
for b in $contract_backends; do
  printf '%s\n' "$fleet_backends" | grep -qxF -- "$b" \
    || report "the prose contract defines backend '$b', which the $safe_fleet_base backend table does not document"
done
for b in $fleet_backends; do
  printf '%s\n' "$contract_backends" | grep -qxF -- "$b" \
    || report "the $safe_fleet_base backend table documents '$b', which the prose contract does not define (add it to the contract, or declare it a semantic row)"
done

# Field-by-field agreement for backends every surface carries.
for b in $contract_backends; do
  for f in $FIELDS; do
    cv="$(fact "$contract_facts" "$b" "$f")" || continue
    if rv="$(fact "$registry_facts" "$b" "$f")"; then
      [ "$cv" = "$rv" ] \
        || report "$b.$f: the prose contract says '$cv', caps_for() says '$rv'"
    fi
    if fv="$(fact "$fleet_facts" "$b" "$f")"; then
      [ "$cv" = "$fv" ] \
        || report "$b.$f: the prose contract says '$cv', the $safe_fleet_base backend table says '$fv'"
    fi
  done
done

if [ "$status" -eq 0 ]; then
  count=0
  for b in $contract_backends; do
    count=$((count + 1))
  done
  echo "check-backend-capability-drift: $count backends agree across the prose contract, caps_for(), and the $safe_fleet_base backend table"
fi
exit "$status"
