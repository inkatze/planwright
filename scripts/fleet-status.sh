#!/bin/sh
# fleet-status.sh — the backend-agnostic CLI status view (execution-backends
# Task 7: D-10 · REQ-D1.1).
#
# WHAT THIS IS. One view of every in-flight worker regardless of backend,
# merged from three runtime sources plus the dispatch record:
#   attention   the per-worker state store (fleet-attention.sh's rows at
#               <fleet-home>/attention/state) — every heartbeating backend
#   streamjson  the stream-json event-stream capture (fleet-streamjson.sh's
#               per-worker runtime dirs; status consumed via its `status`
#               subcommand, never re-derived)
#   oracle      `claude agents --json`, read through fleet-liveness.sh's
#               hardened `oracle --list` scanner (D-11) — never a second
#               agents-json parser
#   registry    fleet-state.sh's dispatch records, so a worker on a backend
#               with NO runtime presence (`print`) still renders — from its
#               dispatch record, with a visible not-applicable state marker,
#               never a silent omission (REQ-D1.1)
#
# TWO LAYERS, ONE SOURCE-READING IMPLEMENTATION (D-10). `merge` is the
# source-merging layer: a machine-readable tab-separated stream the planned
# Task 8 dashboard reuses instead of reading sources a second time. `render`
# is the human table over that same stream. Nothing else reads the sources.
#
# GRACEFUL PER-SOURCE DEGRADE (REQ-D1.1). Every merge emission starts with
# one `source` line per source — ok, absent (the surface does not exist:
# no store, no runtime dirs, zero oracle rows, no records), or unavailable
# (the surface cannot be read: unreadable store, missing sibling script,
# failed/timed-out/unparseable oracle probe). A missing source is marked,
# never silently omitted; worker cells it would have filled render `-`
# (or `?` for a joinable worker under an unavailable oracle — degraded
# evidence, never an invented verdict). An unresolvable fleet home degrades
# the three home-backed sources to unavailable and still probes the oracle.
#
# MERGE STREAM (tab-separated; the Task 8 contract):
#   source <name> <ok|absent|unavailable> <detail>
#   worker <handle> <scope> <origins> <attn-state> <attn-age> <sj-status>
#          <sj-pending> <oracle-status>
#   session <sessionId> <status> <kind> <name> <cwd>
# `worker` rows are the union of attention rows, streamjson runtime dirs, and
# registry records (origins: comma-joined subset of
# attention,streamjson,registry), oracle evidence joined by the worker's
# persisted stream-json session id; `session` rows are oracle sessions no
# worker claims (visible, never dropped — but never invented into workers:
# an interactive session is usually the operator, not a worker). Rows sort
# by handle / session id (LC_ALL=C) so output is deterministic.
#
# ECHO DISCIPLINE (REQ-D1.1, doctrine/security-posture.md). Worker-authored
# and hand-corruptible strings (store fields, registry fields, session
# names) are stripped through the canonical sanitizer at INGEST, so the
# merge stream's tab-separated fields cannot be forged or carry terminal
# escapes, and `render` sanitizes each cell again before the terminal.
#
# Usage:
#   fleet-status.sh merge     the machine-readable merged stream (above)
#   fleet-status.sh render    the human table over the same merge
#
# Exit codes: 0 success (an empty fleet renders empty, sources marked);
#   2 usage error or an internal filesystem failure (fail closed).
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): awk,
# mktemp, `date +%s`. No eval, no jq (REQ-K1.5); every parsed value is data,
# never code. Pathname expansion is disabled (set -f) except the one marked
# worker-dir glob.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-status

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md),
# required readable and fail-closed when absent.
echo_safety="$script_dir/echo-safety.sh"
if [ ! -r "$echo_safety" ]; then
  echo "$me: missing $echo_safety (echo-discipline sanitizer)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

FS="$script_dir/fleet-state.sh"
SJ="$script_dir/fleet-streamjson.sh"
FL="$script_dir/fleet-liveness.sh"

usage() {
  echo "usage: fleet-status.sh merge|render" >&2
  exit 2
}

# The Task 9 field grammar (shared with fleet-state.sh), applied where a
# disk-read value is USED — a streamjson dir name (a path segment handed to
# the sibling's `status`) or a session id (a join key). Display-only fields
# are sanitized instead, never skipped (see read_attention).
valid_field() {
  case $1 in
    '' | *[!A-Za-z0-9._=@:-]*) return 1 ;;
    . | ..) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

now_epoch() {
  ne=$(date +%s)
  case $ne in
    '' | *[!0-9]*) return 1 ;;
  esac
  printf '%s' "$ne"
}

# --- source readers ---------------------------------------------------------
# Each reader appends to the temp workspace: a `source` availability line
# plus its normalized per-row file. All fields pass sanitize_printable at
# ingest (tabs and control bytes are C0, so stripping also preserves the
# stream's tab-separated field integrity).

# read_attention <root|""> — attn.tsv: worker scope state age
read_attention() {
  ra_root=$1
  if [ -z "$ra_root" ]; then
    printf 'source\tattention\tunavailable\tno-fleet-home\n' >>"$WS/sources"
    return 0
  fi
  ra_store="$ra_root/attention/state"
  if [ ! -e "$ra_store" ]; then
    printf 'source\tattention\tabsent\tno-store\n' >>"$WS/sources"
    return 0
  fi
  if [ ! -r "$ra_store" ]; then
    printf 'source\tattention\tunavailable\tunreadable-store\n' >>"$WS/sources"
    return 0
  fi
  ra_now=$(now_epoch) || ra_now=""
  ra_n=0
  # A trailing record without a newline is still read (|| [ -n ... ]).
  while IFS="$TAB" read -r ra_w ra_scope ra_state ra_ts _ _ _ _ || [ -n "$ra_w" ]; do
    [ -n "$ra_w" ] || continue
    # Sanitize-and-render, never skip (the fleet-attention.sh render
    # precedent): a hand-corrupted handle is display data here, not a path
    # or join key, and dropping the row would be the silent omission
    # REQ-D1.1 forbids. An all-control handle degrades to the placeholder.
    ra_w=$(sanitize_printable "$ra_w" "?")
    ra_age="?"
    case $ra_ts in
      "" | *[!0-9]* | 0?*) ;; # leading-zero ts would read as octal; degrade
      *) [ -n "$ra_now" ] && ra_age=$((ra_now - ra_ts)) ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$ra_w" \
      "$(sanitize_printable "$ra_scope" "-")" \
      "$(sanitize_printable "$ra_state" "-")" "$ra_age" >>"$WS/attn.tsv"
    ra_n=$((ra_n + 1))
  done <"$ra_store"
  if [ "$ra_n" -eq 0 ]; then
    printf 'source\tattention\tabsent\tempty-store\n' >>"$WS/sources"
  else
    printf 'source\tattention\tok\t%s-rows\n' "$ra_n" >>"$WS/sources"
  fi
}

# read_streamjson <root|""> — sj.tsv: worker status pending sid
read_streamjson() {
  rs_root=$1
  if [ -z "$rs_root" ]; then
    printf 'source\tstreamjson\tunavailable\tno-fleet-home\n' >>"$WS/sources"
    return 0
  fi
  if [ ! -r "$SJ" ]; then
    printf 'source\tstreamjson\tunavailable\tmissing-script\n' >>"$WS/sources"
    return 0
  fi
  if [ ! -d "$rs_root/streamjson" ]; then
    printf 'source\tstreamjson\tabsent\tno-runtime-dirs\n' >>"$WS/sources"
    return 0
  fi
  rs_n=0
  # The one intentional glob in this script: enumerate worker runtime dirs
  # (pathname expansion is otherwise disabled by set -f).
  set +f
  for rs_dir in "$rs_root/streamjson"/*; do
    [ -d "$rs_dir" ] || continue
    rs_w=${rs_dir##*/}
    valid_field "$rs_w" || continue
    # Consume the sibling's status surface, never re-derive it (the Task 9
    # discipline). Line shape: `status <worker> <verdict> <detail>`.
    rs_status=$(/bin/sh "$SJ" status "$rs_w" 2>/dev/null \
      | awk '$1 == "status" { print $3; exit }') || rs_status=""
    rs_status=$(sanitize_printable "$rs_status" "-")
    [ -n "$rs_status" ] || rs_status="-"
    rs_pend=0
    if [ -f "$rs_dir/journal" ]; then
      rs_pend=$(awk -F'\t' '$4 == "pending" { n++ } END { print n + 0 }' \
        "$rs_dir/journal" 2>/dev/null) || rs_pend=0
    fi
    rs_sid=""
    if [ -f "$rs_dir/session" ]; then
      rs_sid=$(head -n 1 "$rs_dir/session" 2>/dev/null) || rs_sid=""
      valid_field "$rs_sid" || rs_sid=""
    fi
    printf '%s\t%s\t%s\t%s\n' "$rs_w" "$rs_status" "$rs_pend" \
      "${rs_sid:--}" >>"$WS/sj.tsv"
    rs_n=$((rs_n + 1))
  done
  set -f
  if [ "$rs_n" -eq 0 ]; then
    printf 'source\tstreamjson\tabsent\tno-runtime-dirs\n' >>"$WS/sources"
  else
    printf 'source\tstreamjson\tok\t%s-workers\n' "$rs_n" >>"$WS/sources"
  fi
}

# read_oracle — oracle.tsv: sid status kind name cwd; ORACLE_STATE for the
# `?`-cell decision.
ORACLE_STATE=unavailable
read_oracle() {
  if [ ! -r "$FL" ]; then
    printf 'source\toracle\tunavailable\tmissing-script\n' >>"$WS/sources"
    return 0
  fi
  ro_rc=0
  /bin/sh "$FL" oracle --list >"$WS/oracle.raw" 2>/dev/null || ro_rc=$?
  if [ "$ro_rc" -ne 0 ]; then
    printf 'source\toracle\tunavailable\tprobe-failed\n' >>"$WS/sources"
    return 0
  fi
  ro_n=0
  while IFS="$TAB" read -r ro_tag ro_sid ro_st ro_kind ro_name ro_cwd || [ -n "$ro_tag" ]; do
    [ "$ro_tag" = row ] || continue
    ro_sid=$(sanitize_printable "$ro_sid" "-")
    printf '%s\t%s\t%s\t%s\t%s\n' "$ro_sid" \
      "$(sanitize_printable "$ro_st" "-")" \
      "$(sanitize_printable "$ro_kind" "-")" \
      "$(sanitize_printable "$ro_name" "-")" \
      "$(sanitize_printable "$ro_cwd" "-")" >>"$WS/oracle.tsv"
    ro_n=$((ro_n + 1))
  done <"$WS/oracle.raw"
  if [ "$ro_n" -eq 0 ]; then
    ORACLE_STATE=absent
    printf 'source\toracle\tabsent\t0-rows\n' >>"$WS/sources"
  else
    ORACLE_STATE=ok
    printf 'source\toracle\tok\t%s-rows\n' "$ro_n" >>"$WS/sources"
  fi
}

# read_registry <root|""> — reg.tsv: worker scope (last record wins)
read_registry() {
  rr_root=$1
  if [ -z "$rr_root" ]; then
    printf 'source\tregistry\tunavailable\tno-fleet-home\n' >>"$WS/sources"
    return 0
  fi
  if [ ! -r "$FS" ]; then
    printf 'source\tregistry\tunavailable\tmissing-script\n' >>"$WS/sources"
    return 0
  fi
  rr_n=0
  # Registry rows: ts worker scope (an append log; the last record for a
  # worker is its current dispatch record).
  /bin/sh "$FS" registry 2>/dev/null >"$WS/reg.raw" || : >"$WS/reg.raw"
  while IFS="$TAB" read -r _ rr_w rr_scope || [ -n "$rr_w" ]; do
    [ -n "$rr_w" ] || continue
    # Sanitize-and-render (validated at write by fleet-state.sh; a corrupted
    # read degrades visibly rather than dropping the dispatch record).
    rr_w=$(sanitize_printable "$rr_w" "?")
    printf '%s\t%s\n' "$rr_w" \
      "$(sanitize_printable "$rr_scope" "-")" >>"$WS/reg.tsv"
    rr_n=$((rr_n + 1))
  done <"$WS/reg.raw"
  if [ "$rr_n" -eq 0 ]; then
    printf 'source\tregistry\tabsent\tno-records\n' >>"$WS/sources"
  else
    printf 'source\tregistry\tok\t%s-records\n' "$rr_n" >>"$WS/sources"
  fi
}

# --- the merge (the D-10 seam Task 8 reuses) --------------------------------

emit_merge() {
  : >"$WS/sources"
  : >"$WS/attn.tsv"
  : >"$WS/sj.tsv"
  : >"$WS/oracle.tsv"
  : >"$WS/reg.tsv"
  em_root=$(/bin/sh "$FS" root 2>/dev/null) || em_root=""
  read_attention "$em_root"
  read_streamjson "$em_root"
  read_oracle
  read_registry "$em_root"
  cat "$WS/sources"
  # Worker rows: the union of attention, streamjson, and registry, oracle
  # evidence joined by the persisted session id. Origins keep a fixed order
  # so the column is comparable across rows.
  awk -F'\t' -v ostate="$ORACLE_STATE" '
    FILENAME ~ /attn\.tsv$/ {
      seen[$1] = 1; a[$1] = 1
      scope[$1] = $2; astate[$1] = $3; aage[$1] = $4
      next
    }
    FILENAME ~ /sj\.tsv$/ {
      seen[$1] = 1; s[$1] = 1
      sjst[$1] = $2; sjp[$1] = $3
      if ($4 != "-") sid[$1] = $4
      next
    }
    FILENAME ~ /reg\.tsv$/ {
      seen[$1] = 1; r[$1] = 1
      if (!($1 in scope) || scope[$1] == "-") scope[$1] = $2
      next
    }
    FILENAME ~ /oracle\.tsv$/ {
      if ($1 != "-") ost[$1] = $2
      next
    }
    END {
      for (w in seen) {
        o = ""
        if (a[w]) o = "attention"
        if (s[w]) o = o (o == "" ? "" : ",") "streamjson"
        if (r[w]) o = o (o == "" ? "" : ",") "registry"
        oc = "-"
        if (w in sid) {
          if (sid[w] in ost) oc = ost[sid[w]]
          else if (ostate == "unavailable") oc = "?"
        }
        printf "worker\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", w, \
          (scope[w] == "" ? "-" : scope[w]), o, \
          (astate[w] == "" ? "-" : astate[w]), \
          (aage[w] == "" ? "-" : aage[w]), \
          (sjst[w] == "" ? "-" : sjst[w]), \
          (s[w] ? sjp[w] : "-"), oc
      }
    }
  ' "$WS/attn.tsv" "$WS/sj.tsv" "$WS/reg.tsv" "$WS/oracle.tsv" | sort
  # Session rows: oracle sessions no worker claims — visible, never dropped,
  # never invented into workers.
  awk -F'\t' '
    FILENAME ~ /sj\.tsv$/ {
      if ($4 != "-") claimed[$4] = 1
      next
    }
    FILENAME ~ /oracle\.tsv$/ {
      if (!($1 in claimed)) {
        printf "session\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5
      }
    }
  ' "$WS/sj.tsv" "$WS/oracle.tsv" | sort
}

# --- the human table --------------------------------------------------------

render() {
  emit_merge >"$WS/merged" || return 2
  # The sources line: every source named with its state — a missing source is
  # marked visibly, never silently omitted (REQ-D1.1).
  rd_line="sources:"
  while IFS="$TAB" read -r _ rd_name rd_state rd_detail; do
    rd_line="$rd_line $(sanitize_printable "$rd_name" "?")=$(sanitize_printable "$rd_state" "?")($(sanitize_printable "$rd_detail" "?"))"
  done <<EOF
$(awk -F'\t' '$1 == "source"' "$WS/merged")
EOF
  printf '%s\n' "$rd_line"
  if awk -F'\t' '$1 == "worker" { exit 1 }' "$WS/merged"; then
    printf 'workers: (none)\n'
  else
    printf '%-20s %-26s %-16s %-11s %-5s %-8s %s\n' \
      WORKER SCOPE STATE SJ PEND ORACLE VIA
    while IFS="$TAB" read -r _ rd_w rd_scope rd_via rd_state rd_age rd_sj rd_pend rd_oracle; do
      # A worker known only from its dispatch record has no runtime presence
      # to report: a visible not-applicable state, never a silent omission.
      if [ "$rd_via" = registry ]; then
        rd_cell="n/a"
      elif [ "$rd_state" = "-" ]; then
        rd_cell="-"
      else
        rd_cell="$rd_state(${rd_age}s)"
      fi
      printf '%-20s %-26s %-16s %-11s %-5s %-8s %s\n' \
        "$(sanitize_printable "$rd_w" "?")" \
        "$(sanitize_printable "$rd_scope" "?")" \
        "$(sanitize_printable "$rd_cell" "?")" \
        "$(sanitize_printable "$rd_sj" "?")" \
        "$(sanitize_printable "$rd_pend" "?")" \
        "$(sanitize_printable "$rd_oracle" "?")" \
        "$(sanitize_printable "$rd_via" "?")"
    done <<EOF
$(awk -F'\t' '$1 == "worker"' "$WS/merged")
EOF
  fi
  if ! awk -F'\t' '$1 == "session" { exit 1 }' "$WS/merged"; then
    printf 'sessions (oracle, unjoined):\n'
    while IFS="$TAB" read -r _ rd_sid rd_st rd_kind rd_name rd_cwd; do
      printf '  %s  %s  %s  %s  %s\n' \
        "$(sanitize_printable "$rd_sid" "?")" \
        "$(sanitize_printable "$rd_st" "?")" \
        "$(sanitize_printable "$rd_kind" "?")" \
        "$(sanitize_printable "$rd_name" "?")" \
        "$(sanitize_printable "$rd_cwd" "?")"
    done <<EOF
$(awk -F'\t' '$1 == "session"' "$WS/merged")
EOF
  fi
}

# --- dispatch ---------------------------------------------------------------

TAB=$(printf '\t')

[ $# -ge 1 ] || usage
cmd=$1
shift
[ $# -eq 0 ] || {
  echo "$me: $cmd: unknown flag '$(sanitize_printable "$1" "(unprintable flag)")'" >&2
  exit 2
}

WS=$(mktemp -d "${TMPDIR:-/tmp}/planwright-status.XXXXXX") || exit 2
trap 'rm -rf "$WS"' EXIT
trap 'rm -rf "$WS"; exit 130' INT
trap 'rm -rf "$WS"; exit 143' TERM

case $cmd in
  merge) emit_merge ;;
  render) render ;;
  *) usage ;;
esac
