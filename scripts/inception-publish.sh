#!/bin/sh
# inception-publish.sh — the offered Artifact publish step for a venture's
# HTML exports (inception REQ-G1.4, REQ-G1.9 · D-9).
#
# This helper DECIDES and never publishes. Publishing sends a page off this
# machine, so the act itself belongs to the session that holds the publishing
# tool and the operator's confirmation; what lives here is the part that has to
# be the same every time: render the page fresh, screen it, and say whether the
# operator must be asked.
#
#   offer    render the chosen export, screen it, then print the decision:
#              offer      ask the operator before publishing. Always the answer
#                         for a first publish, and whenever the venture's
#                         auto-republish knob is off (its default).
#              republish  the operator confirmed a first publish of this page
#                         earlier and opted this venture into auto-republish,
#                         so the refreshed page may replace the published one
#                         without asking again.
#   record   note a publish the operator has just confirmed, with the artifact
#            it landed at. Refuses without --confirmed: a record is what later
#            lets a republish skip the question, so it is never written on a
#            guess.
#   auto     set the per-venture auto-republish knob, on or off.
#
# State lives in <venture>/.planwright-publish.local, gitignored by the venture
# scaffold: whether to publish to the operator's own account is the operator's
# call on this machine, and a tracked knob would let any commit (a stakeholder's
# web-UI edit included) switch on publishing that nobody confirmed. The file is
# read as data, never sourced; a value that does not parse reads as unset, which
# always lands on `offer`.
#
# Usage:
#   inception-publish.sh offer [--mode dashboard|pitch] <venture-dir>
#   inception-publish.sh record --confirmed [--mode dashboard|pitch]
#                               [--artifact <id>] <venture-dir>
#   inception-publish.sh auto on|off <venture-dir>
#
# --mode defaults to dashboard: each call offers one page, so the pitch is
# offered by its own call.
#
# offer prints `<key><TAB><value>` lines on stdout — mode, export, decision,
# reason (first-publish | auto-republish-off | auto-republish-on), artifact (the
# recorded id, or none) — and the plain-language instruction on stderr.
#
# Exit: 0 done · 1 the rendered page looks like it carries a credential, so it
#   is not offered at all · 2 usage or environment error · 3 the renderer
#   refused the bundle (passed through).
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
STATE_NAME=.planwright-publish.local

usage() {
  cat >&2 <<'EOF'
usage: inception-publish.sh offer [--mode dashboard|pitch] <venture-dir>
       inception-publish.sh record --confirmed [--mode dashboard|pitch] [--artifact <id>] <venture-dir>
       inception-publish.sh auto on|off <venture-dir>
EOF
  exit 2
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  offer | record | auto) ;;
  *) usage ;;
esac

mode=dashboard
artifact=
confirmed=0
knob=
target=
if [ "$cmd" = auto ]; then
  [ $# -ge 1 ] || usage
  knob=$1
  shift
  case $knob in
    on | off) ;;
    *)
      echo "inception-publish: auto takes on or off" >&2
      exit 2
      ;;
  esac
fi
while [ $# -gt 0 ]; do
  case $1 in
    --mode)
      [ "$cmd" != auto ] && [ $# -ge 2 ] || usage
      mode=$2
      shift 2
      ;;
    --artifact)
      [ "$cmd" = record ] && [ $# -ge 2 ] || usage
      artifact=$2
      shift 2
      ;;
    --confirmed)
      [ "$cmd" = record ] || usage
      confirmed=1
      shift
      ;;
    -*) usage ;;
    *)
      [ -z "$target" ] || usage
      target=$1
      shift
      ;;
  esac
done

case $mode in
  dashboard | pitch) ;;
  *)
    echo "inception-publish: --mode must be dashboard or pitch" >&2
    exit 2
    ;;
esac
[ -n "$target" ] || usage
while [ "$target" != "${target%/}" ]; do target=${target%/}; done
[ -n "$target" ] || target=/
[ -d "$target" ] || {
  printf '%s\n' "inception-publish: not a directory: $target" >&2
  exit 2
}

state="$target/$STATE_NAME"

# An artifact id is echoed back to the publishing session and written to the
# state file, so it is held to a plain token: nothing a shell, a markdown
# renderer or a terminal would read as anything but text.
id_ok() {
  case $1 in
    '' | *[!A-Za-z0-9._:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# read_state <key> — the value recorded for <key>, last line winning, or empty.
# Data only: the file is never sourced or evaluated.
read_state() {
  [ -f "$state" ] || return 0
  awk -v k="$1" '
    index($0, k "=") == 1 { v = substr($0, length(k) + 2) }
    END { if (v != "") print v }
  ' "$state"
}

# write_state <key> <value> — replace <key>, keep every other known key. The
# file is rewritten through a temp file beside it, so a crash never leaves it
# half-written, and is private to the operator.
write_state() {
  w_auto=$(read_state auto-republish)
  w_dash=$(read_state published-dashboard)
  w_pitch=$(read_state published-pitch)
  case $1 in
    auto-republish) w_auto=$2 ;;
    published-dashboard) w_dash=$2 ;;
    published-pitch) w_pitch=$2 ;;
  esac
  w_tmp=$(mktemp "$target/.planwright-publish.XXXXXX") || exit 2
  {
    echo "# Machine-local publish state for this venture, written by planwright's"
    echo "# inception-publish.sh. Not tracked; never edit by hand while a publish runs."
    [ -z "$w_auto" ] || printf 'auto-republish=%s\n' "$w_auto"
    [ -z "$w_dash" ] || printf 'published-dashboard=%s\n' "$w_dash"
    [ -z "$w_pitch" ] || printf 'published-pitch=%s\n' "$w_pitch"
  } >"$w_tmp" || {
    rm -f "$w_tmp"
    exit 2
  }
  if ! chmod 600 "$w_tmp" || ! mv "$w_tmp" "$state"; then
    rm -f "$w_tmp"
    exit 2
  fi
}

case $cmd in
  auto)
    write_state auto-republish "$knob"
    printf 'inception-publish: auto-republish is %s for this venture\n' "$knob" >&2
    exit 0
    ;;
  record)
    if [ "$confirmed" -ne 1 ]; then
      echo "inception-publish: record only a publish the operator confirmed; pass --confirmed once they have" >&2
      exit 2
    fi
    if [ -n "$artifact" ] && ! id_ok "$artifact"; then
      echo "inception-publish: --artifact must be a plain id (letters, digits, . _ : -; at most 128)" >&2
      exit 2
    fi
    write_state "published-$mode" "${artifact:-yes}"
    printf 'inception-publish: recorded the confirmed %s publish\n' "$mode" >&2
    exit 0
    ;;
esac

# --- offer ------------------------------------------------------------------

# Rendered fresh, never taken from disk as found: the page published is the
# bundle as it stands now, not whatever the last commit happened to leave.
rrc=0
/bin/sh "$script_dir/inception-render.sh" --mode "$mode" "$target" >/dev/null || rrc=$?
if [ "$rrc" -eq 3 ]; then
  exit 3
elif [ "$rrc" -ne 0 ]; then
  printf '%s\n' "inception-publish: the $mode export could not be rendered; nothing to offer" >&2
  exit 2
fi
if [ "$mode" = pitch ]; then
  export_path="$target/exports/pitch.html"
else
  export_path="$target/exports/venture.html"
fi

# The page leaves the machine, so it gets the same screen a commit does. The
# screen names the rule it matched and never the matched text.
src=0
/bin/sh "$script_dir/inception-secret-screen.sh" -- "$export_path" || src=$?
if [ "$src" -eq 1 ]; then
  printf '%s\n' "inception-publish: the $mode export looks like it carries a credential; it is not offered for publishing." >&2
  echo "inception-publish: fix the bundle text it came from, then offer again." >&2
  exit 1
elif [ "$src" -ne 0 ]; then
  printf '%s\n' "inception-publish: the secret screen could not check the $mode export (exit $src); nothing is offered." >&2
  exit 2
fi

auto=$(read_state auto-republish)
case $auto in
  '' | off) auto=off ;;
  on) ;;
  *)
    printf '%s\n' "inception-publish: ignoring an unreadable auto-republish value in $STATE_NAME; treating it as off" >&2
    auto=off
    ;;
esac
published=$(read_state "published-$mode")
if [ -n "$published" ] && [ "$published" != yes ] && ! id_ok "$published"; then
  printf '%s\n' "inception-publish: ignoring an unreadable published-$mode record in $STATE_NAME; treating the page as never published" >&2
  published=
fi

if [ -z "$published" ]; then
  decision=offer
  reason='first-publish'
elif [ "$auto" = on ]; then
  decision=republish
  reason='auto-republish-on'
else
  decision=offer
  reason='auto-republish-off'
fi
case $published in
  '' | yes) artifact_out=none ;;
  *) artifact_out=$published ;;
esac

printf 'mode\t%s\n' "$mode"
printf 'export\t%s\n' "$export_path"
printf 'decision\t%s\n' "$decision"
printf 'reason\t%s\n' "$reason"
printf 'artifact\t%s\n' "$artifact_out"

if [ "$decision" = offer ]; then
  echo "inception-publish: publishing sends this page off this machine; ask the operator before publishing, and check its audience matches the venture repo's visibility." >&2
  if [ "$reason" = first-publish ]; then
    echo "inception-publish: this would be its first publish, which is always confirmed." >&2
  fi
else
  echo "inception-publish: auto-republish is on and the first publish was confirmed; the refreshed page may replace the published one." >&2
fi
exit 0
