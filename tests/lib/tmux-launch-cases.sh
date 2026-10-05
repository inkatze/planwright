# shellcheck shell=bash
# shellcheck disable=SC2034 # PRIM, FLIGHT, and PP are read by the sourcing suite
# tmux-launch-cases.sh — case setup shared by the tmux rung's launch fixture
# files (sourced after tests/lib/tmux-launch-harness.sh, never executed). Every
# launch a sourcing file makes goes through tlh_run_bounded.
#
# Interface:
#   PRIM FLIGHT ROOT                the dispatch primitive, the flight dispatch,
#                                   the checkout under test
#   new_case [<repo-dir-name>]      a bare origin and a primary clone carrying
#                                   the `demo` spec, under its own case dir $C,
#                                   with its own fleet home, marker dir, and
#                                   fetch state. Sets P (the primary as the
#                                   suite reaches it, through the harness's
#                                   symlinked sandbox) and PP (its physical
#                                   path).
#   expect_session <primary-physical> <suffix>
#                                   the session name the launch must create
#   launch_field <key>              the value of a `launch<TAB><key>` report line
#   report_field <key>              the value of a `<key><TAB>` report line
#   calls_matching <word>           the stub tmux calls whose first word is
#                                   <word>
#   registry_col <n>                column <n> of the case's registry records
#   seam_root                       a copy of the planwright scripts whose
#                                   orchestrate-marker.sh and
#                                   fleet-dispatch-env.sh obey SEAM_MODE (see
#                                   below); prints its scripts directory
unset CDPATH
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
PRIM="$ROOT/scripts/fleet-dispatch-worktree.sh"
FLIGHT="$ROOT/scripts/flight-dispatch.sh"
TAB=$(printf '\t')

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
# The dispatcher's root is pinned, so the worker's can be compared with it; the
# stub server's environment holds decoys for every pinned value instead.
PLANWRIGHT_ROOT=$ROOT
export PLANWRIGHT_ROOT
unset CLAUDE_PLUGIN_ROOT PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX PLANWRIGHT_REPO_ROOT
PLANWRIGHT_TOWER_ID=p1.t1.c1
export PLANWRIGHT_TOWER_ID
tlh_server_env PLANWRIGHT_ROOT=/decoy-root CLAUDE_PLUGIN_ROOT=/decoy-root \
  PLANWRIGHT_FLEET_STATE_DIR=/decoy-fleet
tlh_knob worker-confirm off

gitc() {
  local r=$1
  shift
  git -C "$r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

_case_n=0
new_case() {
  local name=${1:-primary}
  _case_n=$((_case_n + 1))
  C="$TLH_SANDBOX/c$_case_n"
  mkdir -p "$C/fleet"
  # Private, as the flight dispatch requires, whatever the host's umask.
  chmod 700 "$C/fleet"
  git -c init.defaultBranch=main init -q --bare "$C/origin.git"
  P="$C/$name"
  mkdir -p "$(dirname "$P")"
  git clone -q "$C/origin.git" "$P" 2>/dev/null
  mkdir -p "$P/specs/demo"
  printf 'x\n' >"$P/specs/demo/requirements.md"
  gitc "$P" add -A
  gitc "$P" commit -q -m init
  gitc "$P" branch -M main
  gitc "$P" push -q origin main
  PP=$(cd "$P" && pwd -P)
  export PLANWRIGHT_FLEET_STATE_DIR="$C/fleet"
  export PLANWRIGHT_ORCH_STATE_DIR="$C/markers"
  export PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$C/fstate"
}

expect_session() {
  local base hash
  base=$(printf '%s' "${1##*/}" | tr -c 'A-Za-z0-9@-' '-' | sed 's/^[^A-Za-z0-9]*//' | cut -c1-32)
  [ -n "$base" ] || base=repo
  hash=$(printf '%08x' "$(printf '%s' "$1" | cksum | awk '{print $1}')" | cut -c1-6)
  printf '%s-%s_%s\n' "$base" "$hash" "$(printf '%s' "$2" | tr . _)"
}

launch_field() {
  printf '%s\n' "$TLH_OUT" | awk -F"$TAB" -v k="$1" '$1 == "launch" && $2 == k { print $3; exit }'
}

report_field() {
  printf '%s\n' "$TLH_OUT" | awk -F"$TAB" -v k="$1" '$1 == k { print $2; exit }'
}

calls_matching() {
  tlh_tmux_calls | awk -F"$TAB" -v w="$1" '$1 == w'
}

registry_col() {
  [ -f "$C/fleet/registry" ] || return 0
  cut -f"$1" "$C/fleet/registry"
}

# The seam copy: every top-level entry of the checkout linked, scripts/ copied,
# and two scripts wrapped. SEAM_MODE, read when they run:
#   remove-worktree   the marker write removes the worktree it is told about
#                     (SEAM_WT) before writing the marker
#   swap-worktree     the marker write replaces SEAM_WT with a symlink to a
#                     directory beside it
#   decoy-pane        the marker write opens a decoy session whose pane sits in
#                     SEAM_WT
#   fail-clear        the marker clear fails
#   refuse-check      the env wrapper's --check refuses
# Callers take the path through $(seam_root), a subshell, so the copy is
# keyed on its directory existing rather than on a variable; and -n, so a link
# that already exists is never followed into the checkout it points at.
seam_root() {
  local e _seam="$TLH_SANDBOX/seam"
  if [ ! -d "$_seam" ]; then
    mkdir -p "$_seam"
    for e in "$ROOT"/* "$ROOT"/.claude-plugin; do
      [ -e "$e" ] || continue
      [ "${e##*/}" = scripts ] && continue
      ln -sn "$e" "$_seam/${e##*/}"
    done
    cp -R "$ROOT/scripts" "$_seam/scripts"
    cat >"$_seam/scripts/orchestrate-marker.sh" <<EOF
#!/bin/sh
case "\${SEAM_MODE:-}/\$1" in
  remove-worktree/write) rm -rf "\$SEAM_WT" ;;
  swap-worktree/write)
    mkdir -p "\$SEAM_WT.elsewhere"
    rm -rf "\$SEAM_WT"
    ln -sn "\$SEAM_WT.elsewhere" "\$SEAM_WT"
    ;;
  decoy-pane/write) tmux new-session -d -s decoy-pane -c "\$SEAM_WT" >/dev/null 2>&1 ;;
  fail-clear/clear) exit 1 ;;
esac
exec /bin/sh '$ROOT/scripts/orchestrate-marker.sh' "\$@"
EOF
    cat >"$_seam/scripts/fleet-dispatch-env.sh" <<EOF
#!/bin/sh
if [ "\${SEAM_MODE:-}" = refuse-check ] && [ "\${1:-}" = --check ]; then
  echo "fleet-dispatch-env.sh: --identity refused by the seam" >&2
  exit 2
fi
exec /bin/sh '$ROOT/scripts/fleet-dispatch-env.sh' "\$@"
EOF
    chmod +x "$_seam/scripts/orchestrate-marker.sh" "$_seam/scripts/fleet-dispatch-env.sh"
  fi
  printf '%s\n' "$_seam/scripts"
}
