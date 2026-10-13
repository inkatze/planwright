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
#                         earlier, its artifact id is on record, and this
#                         machine opted into auto-republish, so the refreshed
#                         page may replace that artifact without asking again.
#            Run it immediately before publishing: the decision describes the
#            state at that moment, and a knob switched off afterwards is not
#            seen by a session acting on an older answer.
#   record   note a publish the operator has just confirmed, with the artifact
#            it landed at. Refuses without --confirmed: a record is what later
#            lets a republish skip the question, so it is never written on a
#            guess. Without --artifact, an id already on record is kept.
#   status   print the decision an offer would make now, without rendering or
#            screening anything: a cheap look at the state before an offer.
#   auto     set the per-venture auto-republish knob, on or off.
#
# State lives in the clone's git directory, as planwright-publish.local beside
# HEAD: whether to publish to the operator's own account is the operator's call
# on this machine, and anything in the work tree arrives with a pull, so a
# stakeholder's commit could otherwise switch on publishing nobody confirmed. A
# file of that name in the work tree is never read. Writes take a lock
# (planwright-publish.lock, through scripts/lock-lib.sh) so two writers cannot
# lose each other's change. The file is read as data, never sourced; a value that does
# not parse reads as unset, which always lands on `offer`. Outside a git
# repository there is no such place: offers still work, as first publishes,
# and record and auto refuse.
#
# Usage:
#   inception-publish.sh offer [--mode dashboard|pitch] <venture-dir>
#   inception-publish.sh status [--mode dashboard|pitch] <venture-dir>
#   inception-publish.sh record --confirmed [--mode dashboard|pitch]
#                               [--artifact <id>] <venture-dir>
#   inception-publish.sh auto on|off <venture-dir>
#
# --mode defaults to dashboard: each call offers one page, so the pitch is
# offered by its own call.
#
# offer prints `<key><TAB><value>` lines on stdout — mode, export (a private
# copy, in a directory of its own the caller removes once the page is
# published or declined), decision,
# reason (first-publish | auto-republish-off | no-artifact-recorded |
# auto-republish-on), artifact (the recorded id, or none) — and the plain-language instruction on stderr.
#
# Environment:
#   PLANWRIGHT_PUBLISH_LOCK_TRIES   attempts a writer makes at the state lock
#                                   before refusing (lock-lib spins about fifty
#                                   a second); a whole number, default 500.
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
STATE_NAME=planwright-publish.local

if [ ! -f "$script_dir/lock-lib.sh" ] || [ ! -r "$script_dir/lock-lib.sh" ]; then
  printf '%s\n' "inception-publish: required helper $script_dir/lock-lib.sh missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2

usage() {
  cat >&2 <<'EOF'
usage: inception-publish.sh offer [--mode dashboard|pitch] <venture-dir>
       inception-publish.sh status [--mode dashboard|pitch] <venture-dir>
       inception-publish.sh record --confirmed [--mode dashboard|pitch] [--artifact <id>] <venture-dir>
       inception-publish.sh auto on|off <venture-dir>
EOF
  exit 2
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  offer | status | record | auto) ;;
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

# The venture's own repository, never one an inherited override names: a
# caller inside a hook runs with GIT_DIR set, and following it would write this
# venture's publish state into another repository and read that one's back.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
git_dir=$(git -C "$target" rev-parse --absolute-git-dir 2>/dev/null) || git_dir=
state=
lock=
if [ -n "$git_dir" ]; then
  state="$git_dir/$STATE_NAME"
  lock="$git_dir/planwright-publish.lock"
fi

# An artifact id is echoed back to the publishing session and written to the
# state file, so it is held to a plain token: nothing a shell, a markdown
# renderer or a terminal would read as anything but text.
# `none` is reserved: it is what status and offer print for "no artifact on
# record", so a recorded `none` would send a republish at nothing.
id_ok() {
  case $1 in
    '' | none | *[!A-Za-z0-9._:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# load_state — read the whole file once into s_auto, s_dash and s_pitch, last
# line winning per key. Data only: the file is never sourced or evaluated.
load_state() {
  s_auto=
  s_dash=
  s_pitch=
  [ -n "$state" ] && [ -f "$state" ] || return 0
  if [ ! -r "$state" ]; then
    printf '%s\n' "inception-publish: cannot read the publish state at $state; fix its permissions rather than lose the record" >&2
    exit 2
  fi
  s_all=$(awk '
    index($0, "auto-republish=") == 1 { a = substr($0, 16) }
    index($0, "published-dashboard=") == 1 { d = substr($0, 21) }
    index($0, "published-pitch=") == 1 { p = substr($0, 17) }
    END { printf "%s\n%s\n%s\n", a, d, p }
  ' "$state") || exit 2
  s_auto=$(printf '%s\n' "$s_all" | sed -n 1p)
  s_dash=$(printf '%s\n' "$s_all" | sed -n 2p)
  s_pitch=$(printf '%s\n' "$s_all" | sed -n 3p)
}

# take_lock — one writer at a time, through the tree's one lock primitive
# (scripts/lock-lib.sh): the lock is a symbolic link whose target is the
# owner's token, so a release can prove the lock is still its own and a lock
# left by a killed writer is recognised as stale.
w_tmp=
# shellcheck disable=SC2329 # invoked from the traps take_lock installs
release() {
  [ -z "$w_tmp" ] || rm -f "$w_tmp"
  w_tmp=
  pw_lock_release_all
}
take_lock() {
  tries=${PLANWRIGHT_PUBLISH_LOCK_TRIES:-500}
  case $tries in
    '' | *[!0-9]*)
      echo "inception-publish: PLANWRIGHT_PUBLISH_LOCK_TRIES must be a whole number" >&2
      exit 2
      ;;
  esac
  trap release EXIT
  trap 'release; exit 129' HUP
  trap 'release; exit 130' INT
  trap 'release; exit 143' TERM
  pw_lock_acquire "$lock" "$tries"
  case $? in
    0) ;;
    1)
      printf '%s\n' "inception-publish: the publish state is busy (another writer holds $lock); try again" >&2
      exit 2
      ;;
    *)
      printf '%s\n' "inception-publish: cannot lock the publish state at $lock" >&2
      exit 2
      ;;
  esac
}

# write_state <key> <value> — under the lock: read once, replace <key>, keep
# every other key, and rewrite through a temp file beside the state, so a crash
# never leaves it half-written. Private to the operator.
write_state() {
  if [ -z "$state" ]; then
    echo "inception-publish: publish state is kept in the venture's git directory, and this venture is not a git repository; nothing is recorded" >&2
    exit 2
  fi
  take_lock
  load_state
  # A published-* write with no value records the publish and keeps any
  # artifact id already on record: the id is what a later republish targets.
  case $1 in
    auto-republish) s_auto=$2 ;;
    published-dashboard) s_dash=${2:-${s_dash:-yes}} ;;
    published-pitch) s_pitch=${2:-${s_pitch:-yes}} ;;
  esac
  w_tmp=$(mktemp "$state.XXXXXX") || exit 2
  {
    echo "# Machine-local publish state for this venture, written by planwright's"
    echo "# inception-publish.sh. Never edit by hand while a publish runs."
    [ -z "$s_auto" ] || printf 'auto-republish=%s\n' "$s_auto"
    [ -z "$s_dash" ] || printf 'published-dashboard=%s\n' "$s_dash"
    [ -z "$s_pitch" ] || printf 'published-pitch=%s\n' "$s_pitch"
  } >"$w_tmp" || {
    rm -f "$w_tmp"
    exit 2
  }
  if ! chmod 600 "$w_tmp" || ! mv "$w_tmp" "$state"; then
    rm -f "$w_tmp"
    exit 2
  fi
  w_tmp=
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
    # `yes` is the record's own marker for a publish with no id on record.
    if [ "$artifact" = yes ]; then
      echo "inception-publish: --artifact yes is reserved; pass the artifact's real id, or none" >&2
      exit 2
    fi
    if [ -n "$artifact" ] && ! id_ok "$artifact"; then
      echo "inception-publish: --artifact must be a plain id (letters, digits, . _ : -; at most 128)" >&2
      exit 2
    fi
    write_state "published-$mode" "$artifact"
    printf 'inception-publish: recorded the confirmed %s publish\n' "$mode" >&2
    exit 0
    ;;
esac

# --- offer and status --------------------------------------------------------

# Rendered fresh, never taken from disk as found: the page published is the
# bundle as it stands now, not whatever the last commit happened to leave. It is
# rendered into a private directory of its own, never the work tree's exports/,
# so the bytes screened below are the bytes the session publishes: a render of
# the work tree (a commit's hook, another offer) cannot swap a page in under it.
if [ "$cmd" = offer ]; then
  if [ "$mode" = pitch ]; then page=pitch; else page=venture; fi
  priv=$(mktemp -d "${TMPDIR:-/tmp}/inception-offer.XXXXXX") || exit 2
  offer_done=0
  trap '[ "$offer_done" -eq 1 ] || rm -rf "$priv"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  chmod 700 "$priv" || exit 2
  export_path="$priv/$page.html"
  # One snapshot of the bundle is both rendered and screened. Rendering the
  # work tree and screening it again later let an edit in between clean the
  # sources the screen reads while the escaped page still carried the
  # credential. A link is refused before the copy, which would follow it.
  snap="$priv/bundle"
  # not-a-lock: a fresh directory inside the private one mktemp just made
  mkdir "$snap" || exit 2
  for f in brief.md disciplines.md assumptions.md decisions.md plan.md; do
    if [ -h "$target/$f" ]; then
      printf '%s\n' "inception-publish: $f is a symbolic link; refusing to offer through it" >&2
      exit 2
    fi
    [ ! -e "$target/$f" ] || cp "$target/$f" "$snap/$f" || exit 2
  done
  rrc=0
  /bin/sh "$script_dir/inception-render.sh" --mode "$mode" --output "$export_path" "$snap" >/dev/null || rrc=$?
  if [ "$rrc" -eq 3 ]; then
    exit 3
  elif [ "$rrc" -ne 0 ]; then
    printf '%s\n' "inception-publish: the $mode export could not be rendered; nothing to offer" >&2
    exit 2
  fi

  # The page leaves the machine, so it gets the same screen a commit does. The
  # screen names the rule it matched and never the matched text. The bundle files
  # it was rendered from are screened alongside it: escaping turns a quoted
  # assignment's quotes into entities no credential pattern matches.
  src=0
  /bin/sh "$script_dir/inception-secret-screen.sh" -- "$export_path" \
    "$snap/brief.md" "$snap/disciplines.md" "$snap/assumptions.md" \
    "$snap/decisions.md" "$snap/plan.md" || src=$?
  if [ "$src" -eq 1 ]; then
    printf '%s\n' "inception-publish: the $mode export looks like it carries a credential; it is not offered for publishing." >&2
    echo "inception-publish: fix the bundle text it came from, then offer again." >&2
    exit 1
  elif [ "$src" -ne 0 ]; then
    printf '%s\n' "inception-publish: the secret screen could not check the $mode export (exit $src); nothing is offered." >&2
    exit 2
  fi
fi

load_state
auto=$s_auto
case $auto in
  '' | off) auto=off ;;
  on) ;;
  *)
    printf '%s\n' "inception-publish: ignoring an unreadable auto-republish value in $STATE_NAME; treating it as off" >&2
    auto=off
    ;;
esac
if [ "$mode" = pitch ]; then published=$s_pitch; else published=$s_dash; fi
if [ -n "$published" ] && [ "$published" != yes ] && ! id_ok "$published"; then
  printf '%s\n' "inception-publish: ignoring an unreadable published-$mode record in $STATE_NAME; treating the page as never published" >&2
  published=
fi

if [ -z "$published" ]; then
  decision=offer
  reason='first-publish'
elif [ "$auto" != on ]; then
  decision=offer
  reason='auto-republish-off'
elif [ "$published" = yes ]; then
  # A republish replaces a recorded artifact; with none on record it would
  # create a new one, which is a first publish by another name.
  decision=offer
  reason='no-artifact-recorded'
else
  decision=republish
  reason='auto-republish-on'
fi
case $published in
  '' | yes) artifact_out=none ;;
  *) artifact_out=$published ;;
esac

printf 'mode\t%s\n' "$mode"
if [ "$cmd" = status ]; then
  printf 'decision\t%s\n' "$decision"
  printf 'reason\t%s\n' "$reason"
  printf 'artifact\t%s\n' "$artifact_out"
  exit 0
fi
offer_done=1
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
