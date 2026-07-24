#!/bin/sh
# fleet-dashboard.sh — the rendered status dashboard (execution-backends
# Task 8: D-10 · REQ-D1.2).
#
# WHAT THIS IS. The browser/phone-glanceable face of the same merged worker
# state `fleet-status.sh render` puts in a terminal: one self-contained HTML
# document — no external stylesheet, no font, no script, no network fetch of
# any kind — that a non-terminal operator can read at a glance.
#
# ONE SOURCE-READING IMPLEMENTATION (D-10, REQ-D1.2). This script reads
# exactly one thing: `fleet-status.sh merge`, Task 7's machine-readable
# source-merging stream. It never opens the attention store, a stream-json
# runtime dir, the agents-json oracle, or the dispatch registry itself. Two
# renderers, one merge layer — so the dashboard cannot drift out of agreement
# with the CLI view, and a source added there appears here for free.
#
# THE SERVING SEAM (deliberately empty). How the rendered document reaches a
# phone — a local server, a file the operator syncs, something else — is an
# OPEN operator decision, not settled here. This script therefore binds no
# socket, opens no port, and takes no network dependency: it emits the
# document to stdout (`render`) or writes it to a path (`write`), and any
# serving shape later consumes one of those two without changing a line of
# this file. `--refresh` is the one serving-adjacent knob, and it is
# serving-neutral: a browser-level reload hint that works on a file:// page
# exactly as it would behind a server.
#
# READ-ONLY BY CONSTRUCTION (REQ-D1.2). The document is inert: no form, no
# button, no script, no event handler, no endpoint of any kind. There is
# nothing on the page a request could mutate, whatever it is eventually
# served by.
#
# ENCODING (REQ-D1.2). Worker-authored and hand-corruptible strings arrive
# from the merge stream already stripped of control bytes at ingest; this
# script sanitizes again (the values also pass through a terminal when
# `render` writes to one) and then HTML-encodes `& < > " '` on every value it
# emits, so markup in a worker's scope, handle, or session name renders as
# inert text. Attribute values are never interpolated raw: the one class
# derived from data (the per-source state) is mapped through a fixed
# vocabulary, so a surprise value degrades to `unknown` rather than escaping
# the attribute.
#
# GRACEFUL DEGRADE (REQ-D1.2, mirroring REQ-D1.1). Every source is named on
# the page with its state (ok / absent / unavailable) and the detail behind
# it: a missing source is marked, never silently omitted, and the cells it
# would have filled read `-`, `?` (degraded evidence, never an invented
# verdict), or `n/a` (a worker with no runtime presence — the `print` rung,
# rendered from its dispatch record), each carrying a visible marker style
# and explained in the legend.
#
# Usage:
#   fleet-dashboard.sh render [--refresh <seconds>]   the document on stdout
#   fleet-dashboard.sh write <path> [--refresh <seconds>]   atomic file write
#
# Exit codes: 0 success (an empty fleet renders as an empty page, sources
#   marked); 2 usage error, an unusable merge layer, or a write failure —
#   fail closed, never a half-rendered page.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): awk,
# sed, mktemp, date. No jq, no eval, no second language (REQ-K1.5); every
# parsed value is data, never code. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-dashboard

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

# The one source this script reads: Task 7's source-merging layer.
ST="$script_dir/fleet-status.sh"

usage() {
  echo "usage: fleet-dashboard.sh render [--refresh <seconds>]" >&2
  echo "       fleet-dashboard.sh write <path> [--refresh <seconds>]" >&2
  exit 2
}

# html_escape <value> [placeholder] — the single encoding funnel every emitted
# value passes through: strip control bytes (the merge stream already did this
# at ingest; `render` may still write to a terminal, and the second pass is
# idempotent), then encode the five characters that could otherwise close a
# tag, open one, or break out of an attribute.
html_escape() {
  he_v=$(sanitize_printable "$1" "${2-}")
  printf '%s' "$he_v" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&#39;/g"
}

# state_class <state> — the per-source availability state as a CSS class,
# mapped through a fixed vocabulary so nothing from disk lands in an
# attribute unmapped.
state_class() {
  case $1 in
    ok | absent | unavailable) printf '%s' "$1" ;;
    *) printf 'unknown' ;;
  esac
}

# cell <value> — a table cell, marked when it carries a degrade token so a
# missing or degraded reading is visible rather than an empty-looking blank.
cell() {
  case $1 in
    "-" | "?" | "n/a") printf '<td class="cell marker">%s</td>' "$(html_escape "$1" "-")" ;;
    *) printf '<td class="cell">%s</td>' "$(html_escape "$1" "-")" ;;
  esac
}

emit_style() {
  cat <<'CSS'
<style>
:root { --bg: #fbfbfd; --fg: #1c1c1e; --dim: #6b6b70; --line: #dcdce1;
  --card: #ffffff; --warn: #b34700; --warnbg: #fff3e8; --ok: #1a7f45;
  --bad: #b3261e; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #131316; --fg: #ececf1; --dim: #9a9aa2; --line: #2c2c33;
    --card: #1b1b20; --warn: #ffab6b; --warnbg: #2e1e11; --ok: #5fd08a;
    --bad: #ff8a80; }
}
* { box-sizing: border-box; }
body { margin: 0; padding: 1rem 0.9rem 2.5rem; background: var(--bg);
  color: var(--fg); font: 16px/1.45 -apple-system, BlinkMacSystemFont,
  "Segoe UI", Roboto, sans-serif; -webkit-text-size-adjust: 100%; }
h1 { margin: 0; font-size: 1.35rem; letter-spacing: -0.01em; }
h2 { margin: 1.6rem 0 0.5rem; font-size: 0.8rem; text-transform: uppercase;
  letter-spacing: 0.08em; color: var(--dim); font-weight: 600; }
.generated { margin: 0.15rem 0 0.9rem; color: var(--dim); font-size: 0.8rem; }
.summary { display: flex; flex-wrap: wrap; gap: 0.4rem; margin: 0 0 0.2rem; }
.pill { display: inline-block; padding: 0.25rem 0.6rem; border-radius: 999px;
  background: var(--card); border: 1px solid var(--line); font-size: 0.85rem; }
.pill.attention { background: var(--warnbg); border-color: var(--warn);
  color: var(--warn); font-weight: 600; }
.sources { list-style: none; margin: 0; padding: 0; display: flex;
  flex-wrap: wrap; gap: 0.4rem; }
.source { display: flex; align-items: baseline; gap: 0.35rem;
  padding: 0.3rem 0.55rem; border-radius: 0.5rem; background: var(--card);
  border: 1px solid var(--line); font-size: 0.82rem; }
.src-name { font-weight: 600; }
.src-state { font-variant: small-caps; }
.state-ok .src-state { color: var(--ok); }
.state-absent .src-state { color: var(--dim); }
.state-unavailable .src-state { color: var(--bad); font-weight: 700; }
.state-unknown .src-state { color: var(--bad); }
.state-absent, .state-unavailable { border-style: dashed; }
.src-detail { color: var(--dim); }
.scroll { overflow-x: auto; -webkit-overflow-scrolling: touch; }
table { border-collapse: collapse; width: 100%; font-size: 0.85rem;
  background: var(--card); border: 1px solid var(--line);
  border-radius: 0.5rem; }
th { text-align: left; font-size: 0.7rem; text-transform: uppercase;
  letter-spacing: 0.06em; color: var(--dim); font-weight: 600;
  padding: 0.45rem 0.5rem; border-bottom: 1px solid var(--line);
  white-space: nowrap; }
td { padding: 0.45rem 0.5rem; border-bottom: 1px solid var(--line);
  vertical-align: top; word-break: break-word; }
tr:last-child td { border-bottom: 0; }
.handle { font-weight: 600; }
.mono, .handle, .scope, .sid { font-family: ui-monospace, SFMono-Regular,
  Menlo, monospace; font-size: 0.82em; }
.marker { color: var(--dim); font-style: italic; }
.needs-attention td { background: var(--warnbg); }
.needs-attention .handle { color: var(--warn); }
.empty { color: var(--dim); font-style: italic; margin: 0.2rem 0; }
.legend { margin-top: 1.8rem; padding-top: 0.8rem;
  border-top: 1px solid var(--line); color: var(--dim); font-size: 0.78rem; }
.legend dt { font-weight: 600; float: left; clear: left; width: 3.2rem;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.legend dd { margin: 0 0 0.3rem 3.6rem; }
</style>
CSS
}

emit_sources() {
  printf '%s\n' '<h2>sources</h2>'
  printf '%s\n' '<ul class="sources">'
  while IFS="$TAB" read -r _ es_name es_state es_detail || [ -n "${es_name:-}" ]; do
    [ -n "$es_name" ] || continue
    printf '<li class="source state-%s"><span class="src-name">%s</span> <span class="src-state">%s</span> <span class="src-detail">%s</span></li>\n' \
      "$(state_class "$es_state")" \
      "$(html_escape "$es_name" "?")" \
      "$(html_escape "$es_state" "?")" \
      "$(html_escape "$es_detail" "-")"
  done <"$WS/src"
  printf '%s\n' '</ul>'
}

emit_workers() {
  printf '%s\n' '<h2>workers</h2>'
  if [ ! -s "$WS/wrk" ]; then
    printf '%s\n' '<p class="empty">no workers</p>'
    return 0
  fi
  printf '%s\n' '<div class="scroll">'
  printf '%s\n' '<table class="workers">'
  printf '%s' '<thead><tr><th>worker</th><th>scope</th><th>state</th>'
  printf '%s\n' '<th>sj</th><th>pend</th><th>oracle</th><th>via</th></tr></thead>'
  printf '%s\n' '<tbody>'
  while IFS="$TAB" read -r _ ew_w ew_scope ew_via ew_state ew_age ew_sj ew_pend ew_oracle; do
    [ -n "${ew_w:-}" ] || continue
    # The state cell, mirroring the CLI view exactly: a worker known only
    # from its dispatch record has no runtime presence to report (a visible
    # not-applicable marker, never a silent omission); a worker the attention
    # store never covered reads `-`.
    if [ "$ew_via" = registry ]; then
      ew_cell="n/a"
    elif [ "$ew_state" = "-" ]; then
      ew_cell="-"
    else
      ew_cell="$ew_state (${ew_age}s)"
    fi
    # Needs attention: a pending permission/question request, an oracle
    # verdict of waiting, or a worker that pushed a blocked-ish state.
    ew_row="worker"
    case $ew_pend in
      '' | *[!0-9]*) ;;
      *) [ "$ew_pend" -eq 0 ] || ew_row="worker needs-attention" ;;
    esac
    case $ew_oracle in
      waiting) ew_row="worker needs-attention" ;;
    esac
    case $ew_state in
      waiting | blocked | parked) ew_row="worker needs-attention" ;;
    esac
    printf '<tr class="%s">' "$ew_row"
    printf '<td class="cell handle">%s</td>' "$(html_escape "$ew_w" "?")"
    printf '<td class="cell scope">%s</td>' "$(html_escape "$ew_scope" "-")"
    cell "$ew_cell"
    cell "$ew_sj"
    cell "$ew_pend"
    cell "$ew_oracle"
    printf '<td class="cell mono">%s</td>' "$(html_escape "$ew_via" "-")"
    printf '</tr>\n'
  done <"$WS/wrk"
  printf '%s\n' '</tbody>'
  printf '%s\n' '</table>'
  printf '%s\n' '</div>'
}

emit_sessions() {
  [ -s "$WS/ses" ] || return 0
  printf '%s\n' '<h2>sessions (oracle, unjoined)</h2>'
  printf '%s\n' '<div class="scroll">'
  printf '%s\n' '<table class="sessions">'
  printf '%s' '<thead><tr><th>session</th><th>status</th><th>kind</th>'
  printf '%s\n' '<th>name</th><th>cwd</th></tr></thead>'
  printf '%s\n' '<tbody>'
  while IFS="$TAB" read -r _ ex_sid ex_st ex_kind ex_name ex_cwd; do
    [ -n "${ex_sid:-}" ] || continue
    printf '<tr class="session">'
    printf '<td class="cell sid">%s</td>' "$(html_escape "$ex_sid" "?")"
    cell "$ex_st"
    cell "$ex_kind"
    printf '<td class="cell">%s</td>' "$(html_escape "$ex_name" "-")"
    printf '<td class="cell mono">%s</td>' "$(html_escape "$ex_cwd" "-")"
    printf '</tr>\n'
  done <"$WS/ses"
  printf '%s\n' '</tbody>'
  printf '%s\n' '</table>'
  printf '%s\n' '</div>'
}

emit_legend() {
  cat <<'HTML'
<footer class="legend">
<dl>
<dt>-</dt><dd>the source that would fill this cell reported nothing for this worker</dd>
<dt>?</dt><dd>degraded evidence: the source could not be read, so no verdict is claimed</dd>
<dt>n/a</dt><dd>no runtime presence to report — rendered from its dispatch record</dd>
</dl>
<p>Sources are listed above with their state; a missing one is marked, never
dropped. Read-only view of the same merged state the CLI renders.</p>
</footer>
HTML
}

emit_page() {
  ep_total=$(awk 'END { print NR + 0 }' "$WS/wrk") || return 2
  ep_attn=$(awk -F'\t' '
    ($8 ~ /^[0-9]+$/ && $8 + 0 > 0) || $9 == "waiting" \
      || $5 == "waiting" || $5 == "blocked" || $5 == "parked" { n++ }
    END { print n + 0 }
  ' "$WS/wrk") || return 2
  printf '%s\n' '<!doctype html>'
  printf '%s\n' '<html lang="en">'
  printf '%s\n' '<head>'
  printf '%s\n' '<meta charset="utf-8">'
  printf '%s\n' '<meta name="viewport" content="width=device-width, initial-scale=1">'
  printf '%s\n' '<meta name="color-scheme" content="light dark">'
  [ "$REFRESH" -eq 0 ] \
    || printf '<meta http-equiv="refresh" content="%s">\n' "$REFRESH"
  printf '%s\n' '<title>planwright fleet</title>'
  emit_style
  printf '%s\n' '</head>'
  printf '%s\n' '<body>'
  printf '%s\n' '<h1>fleet</h1>'
  printf '<p class="generated">generated %s</p>\n' \
    "$(html_escape "$(date '+%Y-%m-%d %H:%M:%S %Z')" "unknown time")"
  printf '%s' '<p class="summary">'
  if [ "$ep_total" -eq 1 ]; then
    printf '<span class="pill">1 worker</span>'
  else
    printf '<span class="pill">%s workers</span>' "$ep_total"
  fi
  [ "$ep_attn" -eq 0 ] \
    || printf '<span class="pill attention">%s need attention</span>' "$ep_attn"
  printf '%s\n' '</p>'
  emit_sources
  emit_workers
  emit_sessions
  emit_legend
  printf '%s\n' '</body>'
  printf '%s\n' '</html>'
}

# --- dispatch ---------------------------------------------------------------

TAB=$(printf '\t')

[ $# -ge 1 ] || usage
cmd=$1
shift
out_path=""
case $cmd in
  render) ;;
  write)
    [ $# -ge 1 ] || usage
    out_path=$1
    shift
    ;;
  *) usage ;;
esac

REFRESH=0
while [ $# -gt 0 ]; do
  case $1 in
    --refresh)
      [ $# -ge 2 ] || usage
      REFRESH=$2
      case $REFRESH in
        '' | *[!0-9]*) usage ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

if [ ! -r "$ST" ]; then
  echo "$me: missing $ST (the shared source-merging layer)" >&2
  exit 2
fi

WS=$(mktemp -d "${TMPDIR:-/tmp}/planwright-dashboard.XXXXXX") || exit 2
trap 'rm -rf "$WS"' EXIT
trap 'rm -rf "$WS"; exit 130' INT
trap 'rm -rf "$WS"; exit 143' TERM

# The single source read. Buffered before anything is emitted, so a failing
# merge is a clean exit 2 and never a half-rendered page.
if ! /bin/sh "$ST" merge >"$WS/merge"; then
  echo "$me: fleet-status.sh merge failed (fail closed)" >&2
  exit 2
fi
# Each scan writes to a temp first so its exit status is checked (the
# fleet-status.sh discipline: a scan whose status is discarded renders an
# empty section on failure and still exits 0).
awk -F'\t' '$1 == "source"' "$WS/merge" >"$WS/src" || exit 2
awk -F'\t' '$1 == "worker"' "$WS/merge" >"$WS/wrk" || exit 2
awk -F'\t' '$1 == "session"' "$WS/merge" >"$WS/ses" || exit 2

case $cmd in
  render) emit_page || exit 2 ;;
  write)
    out_dir=$(dirname "$out_path")
    if [ ! -d "$out_dir" ] || [ ! -w "$out_dir" ]; then
      echo "$me: cannot write into $out_dir" >&2
      exit 2
    fi
    # Render to a sibling temp, then rename: a reader (or a serving shape
    # layered on later) never observes a partially written document.
    out_tmp=$(mktemp "$out_dir/.fleet-dashboard.XXXXXX") || exit 2
    if ! emit_page >"$out_tmp"; then
      rm -f "$out_tmp"
      echo "$me: render failed" >&2
      exit 2
    fi
    if ! mv "$out_tmp" "$out_path"; then
      rm -f "$out_tmp"
      echo "$me: cannot rename into $out_path" >&2
      exit 2
    fi
    ;;
esac
