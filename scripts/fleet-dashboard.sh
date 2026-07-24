#!/bin/sh
# fleet-dashboard.sh — the rendered status dashboard (execution-backends
# Task 8: D-10 · REQ-D1.2).
#
# WHAT THIS IS. The second renderer over Task 7's source-merging layer: a
# self-contained HTML page of the same merged worker state the CLI table
# shows, shaped for a phone or browser glance when the operator is away from
# the terminal. It reads exactly ONE thing — `fleet-status.sh merge` — and
# never touches the underlying sources (the attention store, the stream-json
# capture, the agents-json oracle, the dispatch registry) a second way. One
# source-reading implementation, two renderers (D-10).
#
# EXPOSURE (REQ-D1.2, decided at this task). This script opens no socket and
# serves nothing. It renders to stdout, or writes an owner-only (0600) file
# the operator points a browser at. There is therefore no unauthenticated
# network surface to secure, because there is no listener at all: reaching
# the page from a phone goes through a channel the operator already
# authenticates — a tailnet (`tailscale serve` over the written file), an SSH
# port-forward or `ssh -L` to a local server, or a synced-file path. A
# built-in listener was rejected: a POSIX-sh HTTP server would be plaintext
# and unauthenticated by construction, which is precisely what REQ-D1.2
# forbids, and every credible remedy (TLS, auth) is a new runtime dependency.
# See docs/fleet.md, "The rendered dashboard".
#
# READ-ONLY BY CONSTRUCTION. The page has no form, no control, no endpoint,
# and no JavaScript — there is nothing on it to submit or invoke. A
# `default-src 'none'` CSP meta and the absence of any script element are
# belt and braces over the output encoding below.
#
# OUTPUT ENCODING (REQ-D1.2). Worker-authored strings arrive already stripped
# of control bytes: the merge layer sanitizes at ingest, which is the right
# altitude for it (the terminal-escape posture belongs to the source reader,
# not to each renderer). This renderer owns the OTHER context — HTML — and
# entity-encodes `& < > " '` on every value it prints, so markup a worker
# authored renders as text. Untrusted values never reach a class attribute:
# the source-state class is chosen from a closed set, everything else is
# escaped element text.
#
# FRESHNESS. Every page carries the UTC instant it was generated and refreshes
# itself on the same interval the writer loop uses, so a page whose writer
# died reads as stale instead of quietly lying (the Task 7 poller
# observation).
#
# Usage:
#   fleet-dashboard.sh render [--interval <sec>]
#       the HTML page on stdout
#   fleet-dashboard.sh write --out <path> [--interval <sec>]
#       render once, atomically, to a 0600 file
#   fleet-dashboard.sh watch --out <path> [--interval <sec>]
#       re-render to <path> every <sec> until interrupted
#
# --interval defaults to 30 seconds (1..86400).
#
# Exit codes: 0 success; 2 usage error, a merge failure, or a filesystem
#   failure (fail closed — a failed render never emits a partial page and
#   never replaces a previously written one).
#
# `watch` stops on such a failure rather than looping blind. The ORDINARY
# degrade path never gets here: an unreadable store or a failed oracle probe
# is a per-source `unavailable` line inside a successful merge, which renders
# fine. A merge that actually fails is exceptional, and a loop that keeps
# running while writing nothing is worse than one that stops — the page's
# generated-at stamp is what tells an away operator it went stale.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): awk,
# mktemp, date. No eval, no jq (REQ-K1.5); every parsed value is data, never
# code. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-dashboard

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md),
# used on the diagnostics this script writes to the operator's terminal.
echo_safety="$script_dir/echo-safety.sh"
if [ ! -r "$echo_safety" ]; then
  echo "$me: missing $echo_safety (echo-discipline sanitizer)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

# The one thing this script reads: the D-10 merge seam.
ST="$script_dir/fleet-status.sh"

usage() {
  cat >&2 <<'EOF'
usage: fleet-dashboard.sh render [--interval <sec>]
       fleet-dashboard.sh write --out <path> [--interval <sec>]
       fleet-dashboard.sh watch --out <path> [--interval <sec>]
EOF
  exit 2
}

die() {
  echo "$me: $1" >&2
  exit 2
}

# --- the page ---------------------------------------------------------------

emit_head() {
  eh_stamp=$1
  eh_interval=$2
  # No untrusted value reaches the head: the stamp is this host's clock and
  # the interval is a validated integer. Only the two lines that need them
  # are interpolated; the stylesheet and the static markup around it come
  # out of QUOTED here-docs, so a future `$`, backtick, or backslash in the
  # CSS (`content:"\201C"` and friends) is emitted verbatim instead of being
  # eaten by the shell.
  cat <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
EOF
  printf '<meta http-equiv="refresh" content="%s">\n' "$eh_interval"
  cat <<'EOF'
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>planwright fleet</title>
<style>
:root{--bg:#f6f7f9;--fg:#1b1d21;--dim:#5d626b;--card:#fff;--line:#dfe2e7;
--ok:#1a7f45;--warn:#9a5b00;--bad:#a32020;--alert:#fdf0e6;--calm:#eef4ee}
@media(prefers-color-scheme:dark){:root{--bg:#14161a;--fg:#e8eaee;--dim:#9aa1ac;
--card:#1d2026;--line:#2c313a;--ok:#4cc07d;--warn:#e0a44a;--bad:#f0736b;
--alert:#2e2115;--calm:#17231b}}
/* min-width:0 lets flex and grid children shrink below their content width;
   without it one long worker-authored path (a session cwd) widens the whole
   page and every block's right edge slides off a phone screen. */
*{box-sizing:border-box;min-width:0}
body{margin:0;padding:1rem;background:var(--bg);color:var(--fg);
overflow-wrap:anywhere;
font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
h1{font-size:1.15rem;margin:0}
h2{font-size:.8rem;letter-spacing:.08em;text-transform:uppercase;
color:var(--dim);margin:1.4rem 0 .5rem}
h3{font-size:.95rem;margin:1rem 0 .5rem}
h4{font-size:1rem;margin:0 0 .2rem}
.stamp{color:var(--dim);font-size:.78rem;margin:.25rem 0 0}
.banner{margin:.9rem 0;padding:.7rem .9rem;border-radius:.5rem;
border:1px solid var(--line);font-weight:600}
.banner.alert{background:var(--alert);border-color:var(--warn);color:var(--warn)}
.banner.clear{background:var(--calm);border-color:var(--ok);color:var(--ok)}
ul{list-style:none;margin:0;padding:0}
.srclist li{display:flex;flex-wrap:wrap;gap:.5rem;align-items:baseline;
padding:.35rem .6rem;border:1px solid var(--line);border-radius:.4rem;
background:var(--card);margin-bottom:.3rem;font-size:.85rem}
.sname{font-weight:600;min-width:7.5rem}
.sstate{font-weight:600}
.src-ok .sstate{color:var(--ok)}
.src-absent .sstate{color:var(--warn)}
.src-unavailable .sstate,.src-other .sstate{color:var(--bad)}
.sdetail{color:var(--dim)}
.cards{display:grid;grid-template-columns:1fr;gap:.6rem}
@media(min-width:40rem){.cards{grid-template-columns:repeat(auto-fit,minmax(19rem,1fr))}}
.card{background:var(--card);border:1px solid var(--line);border-left-width:4px;
border-radius:.5rem;padding:.7rem .8rem}
.c-needs{border-left-color:var(--warn)}
.c-active{border-left-color:var(--ok)}
.c-finished{border-left-color:var(--line)}
.scope{margin:0 0 .5rem;color:var(--dim);font-size:.82rem}
dl{display:grid;grid-template-columns:auto 1fr;gap:.15rem .7rem;margin:0;
font-size:.85rem}
dt{color:var(--dim)}
dd{margin:0}
.sesslist li{display:flex;flex-wrap:wrap;gap:.15rem .6rem;align-items:baseline;
padding:.35rem .6rem;border:1px solid var(--line);border-radius:.4rem;
background:var(--card);margin-bottom:.3rem;font-size:.8rem}
.sessname{font-weight:600}
.sessmeta{color:var(--dim)}
.sesscwd,.sessid{color:var(--dim);font-size:.72rem}
.sessid{flex-basis:100%}
.v-missing,.v-unknown,.v-na{color:var(--dim);font-style:italic}
.age{color:var(--dim)}
.empty{color:var(--dim);font-size:.85rem;margin:.2rem 0 0}
footer{margin-top:1.8rem;padding-top:.7rem;border-top:1px solid var(--line);
color:var(--dim);font-size:.75rem}
footer p{margin:.2rem 0}
</style>
</head>
<body>
<header>
<h1>planwright fleet</h1>
EOF
  printf '<p class="stamp">generated %s &middot; refreshes every %ss</p>\n' \
    "$eh_stamp" "$eh_interval"
  printf '</header>\n'
}

emit_foot() {
  cat <<'EOF'
<footer>
<p>Legend: &#8212; the source that would fill this cell is absent or
unavailable &middot; <em>unknown</em> degraded evidence, never an invented
verdict &middot; <em>n/a</em> a worker with no runtime presence, rendered
from its dispatch record.</p>
<p>Read-only surface: no controls, no endpoints, no JavaScript.</p>
</footer>
</body>
</html>
EOF
}

emit_body() {
  awk -F'\t' -v sq="'" '
    function esc(s) {
      gsub(/&/, "\\&amp;", s)
      gsub(/</, "\\&lt;", s)
      gsub(/>/, "\\&gt;", s)
      gsub(/"/, "\\&quot;", s)
      gsub(sq, "\\&#39;", s)
      return s
    }
    # Source states drive a CSS class, so they come from a closed set: an
    # unrecognized token is classed `other` and only ever printed as escaped
    # text, never interpolated into the attribute.
    function sclass(st) {
      if (st == "ok" || st == "absent" || st == "unavailable") return "src-" st
      return "src-other"
    }
    # `extra` is an optional additional class, so a caller can style the cell
    # in place instead of wrapping it in a second span.
    function cell(v, extra) {
      if (extra != "") extra = " " extra
      if (v == "-" || v == "") return "<span class=\"v v-missing" extra "\">&#8212;</span>"
      if (v == "?") return "<span class=\"v v-unknown" extra "\">unknown</span>"
      return "<span class=\"v" extra "\">" esc(v) "</span>"
    }
    # A worker known only from its dispatch record has no runtime presence to
    # report: a visible not-applicable marker, never a silent omission
    # (REQ-D1.1, carried into the rendered surface).
    function statecell(via, st, age) {
      if (via == "registry") return "<span class=\"v v-na\">n/a</span>"
      if (st == "-" || st == "") return cell("-")
      if (age == "-" || age == "" || age == "?")
        return "<span class=\"v\">" esc(st) "</span> <span class=\"age\">(age unknown)</span>"
      return "<span class=\"v\">" esc(st) "</span> <span class=\"age\">(" esc(age) "s)</span>"
    }
    # 1 needs the operator, 2 active, 3 finished. Everything that could pull
    # the operator back to the terminal sorts first; that is the whole point
    # of a glance surface.
    function bucket(st, pd, orc) {
      if (st == "awaiting-input" || st == "hung") return 1
      if (orc == "waiting") return 1
      if (pd ~ /^[0-9]+$/ && pd + 0 > 0) return 1
      if (st == "pr-ready" || st == "merged" || st == "done" || st == "ended") return 3
      return 2
    }
    function emitbucket(b, title, cls,   i) {
      printf "<h3 class=\"bucket\">%s (%d)</h3>\n", title, cnt[b] + 0
      if ((cnt[b] + 0) == 0) {
        print "<p class=\"empty\">(none)</p>"
        return
      }
      print "<ul class=\"cards\">"
      for (i = 1; i <= nw; i++) {
        if (wb[i] != b) continue
        printf "<li class=\"card %s\">\n", cls
        printf "<h4>%s</h4>\n", esc(wh[i])
        printf "<p class=\"scope\">%s</p>\n", esc(wsc[i] == "-" ? "(scope unknown)" : wsc[i])
        print "<dl>"
        printf "<dt>state</dt><dd>%s</dd>\n", statecell(wvia[i], wst[i], wag[i])
        printf "<dt>stream-json</dt><dd>%s</dd>\n", cell(wsj[i])
        printf "<dt>pending</dt><dd>%s</dd>\n", cell(wpd[i])
        printf "<dt>oracle</dt><dd>%s</dd>\n", cell(wor[i])
        printf "<dt>via</dt><dd>%s</dd>\n", cell(wvia[i])
        print "</dl>"
        print "</li>"
      }
      print "</ul>"
    }
    $1 == "source" {
      ns++
      sn[ns] = $2; ss[ns] = $3; sd[ns] = $4
      next
    }
    $1 == "worker" {
      nw++
      wh[nw] = $2; wsc[nw] = $3; wvia[nw] = $4; wst[nw] = $5
      wag[nw] = $6; wsj[nw] = $7; wpd[nw] = $8; wor[nw] = $9
      wb[nw] = bucket(wst[nw], wpd[nw], wor[nw])
      cnt[wb[nw]]++
      next
    }
    $1 == "session" {
      ng++
      gid[ng] = $2; gst[ng] = $3; gk[ng] = $4; gn[ng] = $5; gc[ng] = $6
      next
    }
    END {
      n = cnt[1] + 0
      if (n == 0)
        print "<p class=\"banner clear\">no worker needs you</p>"
      else if (n == 1)
        print "<p class=\"banner alert\">1 worker needs you</p>"
      else
        printf "<p class=\"banner alert\">%d workers need you</p>\n", n
      # Every source is named with its state, whatever that state is: a
      # missing source is marked, never silently omitted (REQ-D1.1).
      print "<section class=\"sources\">"
      print "<h2>Sources</h2>"
      print "<ul class=\"srclist\">"
      for (i = 1; i <= ns; i++)
        printf "<li class=\"src %s\"><span class=\"sname\">%s</span><span class=\"sstate\">%s</span><span class=\"sdetail\">%s</span></li>\n", \
          sclass(ss[i]), esc(sn[i]), esc(ss[i]), esc(sd[i])
      if (ns == 0)
        print "<li class=\"src src-other\"><span class=\"sname\">(no source line)</span><span class=\"sstate\">unavailable</span><span class=\"sdetail\">empty merge stream</span></li>"
      print "</ul>"
      print "</section>"
      print "<section class=\"workers\">"
      print "<h2>Workers</h2>"
      if (nw == 0) {
        print "<p class=\"empty\">no workers in flight</p>"
      } else {
        emitbucket(1, "Needs you", "c-needs")
        emitbucket(2, "Active", "c-active")
        emitbucket(3, "Finished", "c-finished")
      }
      print "</section>"
      # Oracle sessions no worker claims: visible, never dropped, but never
      # invented into workers either (an interactive session is usually the
      # operator). They routinely outnumber the workers, so they render as a
      # compact list below them rather than competing for the glance.
      if (ng > 0) {
        print "<section class=\"sessions\">"
        print "<h2>Unjoined sessions</h2>"
        print "<ul class=\"sesslist\">"
        for (i = 1; i <= ng; i++) {
          print "<li class=\"sess\">"
          printf "%s", cell(gn[i], "sessname")
          printf "<span class=\"sessmeta\">%s &middot; %s</span>", cell(gst[i]), cell(gk[i])
          printf "%s", cell(gc[i], "sesscwd")
          printf "%s\n", cell(gid[i], "sessid")
          print "</li>"
        }
        print "</ul>"
        print "</section>"
      }
    }
  ' "$1"
}

# render — the whole page on stdout. Fails closed: the merge runs to
# completion into a temp file BEFORE a byte of the page is emitted, so a
# failed merge is exit 2 with no output, never a half-rendered page.
render() {
  if [ ! -r "$ST" ]; then
    echo "$me: missing $ST (the status merge layer)" >&2
    return 2
  fi
  rn_stamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || return 2
  case $rn_stamp in
    ????-??-??T??:??:??Z) ;;
    *) return 2 ;;
  esac
  /bin/sh "$ST" merge >"$WS/merge" 2>"$WS/merge.err" || {
    echo "$me: '$ST merge' failed" >&2
    cat "$WS/merge.err" >&2
    return 2
  }
  emit_head "$rn_stamp" "$INTERVAL" || return 2
  emit_body "$WS/merge" || return 2
  emit_foot || return 2
}

# write_page <path> — atomic, owner-only. The temp lands in the target's own
# directory so the rename is same-filesystem; a failed render removes it and
# leaves any previously written page untouched.
# PENDING_TMP publishes the in-flight temp to the signal traps. `watch` is
# stopped with a signal by design, and a signal that lands mid-render would
# otherwise abandon the temp beside the operator's target — one more file per
# stop, forever.
PENDING_TMP=""

write_page() {
  wp_out=$1
  wp_dir=$(dirname "$wp_out")
  wp_tmp=$(mktemp "$wp_dir/.planwright-dash.XXXXXX") || return 2
  PENDING_TMP=$wp_tmp
  chmod 600 "$wp_tmp" || {
    rm -f "$wp_tmp"
    PENDING_TMP=""
    return 2
  }
  if ! render >"$wp_tmp"; then
    rm -f "$wp_tmp"
    PENDING_TMP=""
    return 2
  fi
  mv "$wp_tmp" "$wp_out" || {
    rm -f "$wp_tmp"
    PENDING_TMP=""
    return 2
  }
  PENDING_TMP=""
}

# --- argument handling ------------------------------------------------------

bad_flag() {
  echo "$me: $CMD: unknown flag '$(sanitize_printable "$1" "(unprintable flag)")'" >&2
  exit 2
}

INTERVAL=30
OUT=""

[ $# -ge 1 ] || usage
CMD=$1
shift
case $CMD in
  render | write | watch) ;;
  *)
    echo "$me: unknown subcommand '$(sanitize_printable "$CMD" "(unprintable subcommand)")'" >&2
    usage
    ;;
esac

while [ $# -gt 0 ]; do
  case $1 in
    --interval)
      [ $# -ge 2 ] || die "$CMD: --interval needs a value"
      INTERVAL=$2
      shift 2
      ;;
    --out)
      [ "$CMD" = render ] && bad_flag "$1"
      [ $# -ge 2 ] || die "$CMD: --out needs a value"
      OUT=$2
      shift 2
      ;;
    *) bad_flag "$1" ;;
  esac
done

case $INTERVAL in
  '' | *[!0-9]*) die "$CMD: --interval must be a whole number of seconds" ;;
esac
# Leading zeros would read as octal in the arithmetic below.
case $INTERVAL in
  0?*) die "$CMD: --interval must not carry a leading zero" ;;
esac
if [ "$INTERVAL" -lt 1 ] || [ "$INTERVAL" -gt 86400 ]; then
  die "$CMD: --interval must be between 1 and 86400 seconds"
fi

if [ "$CMD" != render ]; then
  [ -n "$OUT" ] || die "$CMD: --out <path> is required"
  case $OUT in
    */) die "$CMD: --out must name a file, not a directory path" ;;
  esac
  [ ! -d "$OUT" ] || die "$CMD: --out names an existing directory"
  out_dir=$(dirname "$OUT")
  [ -d "$out_dir" ] || die "$CMD: --out parent directory does not exist"
  [ -w "$out_dir" ] || die "$CMD: --out parent directory is not writable"
fi

WS=$(mktemp -d "${TMPDIR:-/tmp}/planwright-dash.XXXXXX") || exit 2

cleanup() {
  rm -rf "$WS"
  [ -z "$PENDING_TMP" ] || rm -f "$PENDING_TMP"
}

trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

case $CMD in
  render) render || exit 2 ;;
  write) write_page "$OUT" || exit 2 ;;
  watch)
    while :; do
      write_page "$OUT" || exit 2
      sleep "$INTERVAL"
    done
    ;;
esac
