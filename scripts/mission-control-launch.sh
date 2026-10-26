#!/bin/sh
# mission-control-launch.sh — the one launcher for every session kind mission
# control starts, and the verb that retires them. A launch delivers the brief,
# the rules in scope, the kind's settings profile, its model tier and its name,
# then registers owner, kind and scope. `--help` prints the usage, the output
# shapes and the exit codes.
#
# POSIX sh; no eval; every input is data. Pathname expansion is disabled.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=mission-control-launch
FORMAT=1

script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$me: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

die() {
  printf '%s\n' "$me: $1" >&2
  exit "${2:-2}"
}

help_text() {
  cat <<'EOF'
usage:
  mission-control-launch.sh launch --program <p> --kind <kind> --scope <s>
      --brief <file> [--rules <rule-scope>]... [--backend stream-json|tmux]
      [--cwd <abs-dir>]
  mission-control-launch.sh name --program <p> --kind <kind> --scope <s>
  mission-control-launch.sh retire <name>
  mission-control-launch.sh list
  mission-control-launch.sh kinds

<kind> is one of `kinds`; <scope> holds letters, digits and . _ = @ : - only,
at most 128. --rules adds a rule-store scope (duty:<id> or repo:<name>);
program rules ride every launch. The rung is --backend, else the
mission_control_launch_backend knob.

The name is derived from program, kind and scope alone, so the same inputs
always name the same session, and a name with a registry row is held until
it is retired. No output names a pane, window or attach hint.

Output, tab separated:
  launch   launch <field> <value> for name, kind, program, owner, scope,
           backend, profile, tier, brief
  name     the name alone
  retire   retire <name> released|partial released=<classes> held=<classes>,
           over the classes process, pane, registry, attention and row
  list     <name> <program> <kind> <scope> <backend> <launched epoch>
  kinds    <kind> <profile> <allocation key>

Exit codes: 0 done; 1 the rung failed to start the session, or a retire
released only part of it; 2 usage or an invalid value; 3 the name is held
(launch) or has no row (retire); 4 a launch refused before it started: no
readable profile, no resolvable tier, a program that is not configured, or
rules that would not render.
EOF
}

usage() {
  help_text >&2
  exit 2
}

# kind_row <kind> — set K_PROFILE and K_KEY, or return 1 for an unknown kind.
kind_row() {
  case $1 in
    tower) K_PROFILE=tower K_KEY=orchestrate_dispatch ;;
    orchestrator) K_PROFILE=tower K_KEY=bookkeeping ;;
    worker) K_PROFILE=worker K_KEY=execution ;;
    reviewer) K_PROFILE=worker K_KEY=execute_step ;;
    ad-hoc) K_PROFILE=worker K_KEY=offload ;;
    mission-control) K_PROFILE=mission-control K_KEY=orchestrate_dispatch ;;
    *) return 1 ;;
  esac
}
KINDS="tower orchestrator worker reviewer ad-hoc mission-control"

valid_program() {
  case $1 in
    [a-z]*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9-]* | *--* | *-) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

valid_scope() {
  case $1 in
    '' | *[!A-Za-z0-9._=@:-]* | . | ..) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

valid_name() {
  case $1 in
    mc-*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    return 1
  fi
}

# session_name <program> <kind> <scope> — the brief is left out on purpose:
# a relaunch with a reworded brief must find the name its predecessor holds.
# A program name too long for the readable form falls back to a longer hash.
session_name() {
  sn_h=$(printf '%s\t%s\t%s' "$1" "$2" "$3" | sha256_hex) || die "no SHA-256 tool (sha256sum or shasum) to derive the session name"
  sn_name="mc-$1-$2-$(printf '%s' "$sn_h" | cut -c1-10)"
  [ "${#sn_name}" -le 64 ] || sn_name="mc-$2-$(printf '%s' "$sn_h" | cut -c1-16)"
  printf '%s\n' "$sn_name"
}

# The registry and the composed briefs are runtime state, so they live under
# the fleet home beside the fleet registry, never in the program home.
fleet_home() {
  FH=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null </dev/null) || die "cannot resolve the fleet home for the launcher's registry"
  case $FH in
    /*) ;;
    *) die "the fleet home is not an absolute path" ;;
  esac
  REG="$FH/mission-control/sessions"
  LAUNCHES="$FH/mission-control/launch"
}

# private_dir <dir> — create it owner-only; refuse a symbolic link.
private_dir() {
  [ ! -L "$1" ] || die "refusing $(sanitize_printable "$1"): a symbolic link"
  (umask 077 && mkdir -p "$1") 2>/dev/null || die "cannot create $(sanitize_printable "$1")"
  chmod 700 "$1" 2>/dev/null || :
}

# row_get <file> <key> — print the value of <key> in a registry row.
row_get() {
  awk -F '\t' -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }' "$1"
}

# row_check <file> — refuse a row whose format this launcher does not know.
row_check() {
  rc_fmt=$(row_get "$1" format)
  [ "$rc_fmt" = "$FORMAT" ] \
    || die "refusing the registry row $(sanitize_printable "$1"): its format field is $(sanitize_printable "${rc_fmt:-missing}"), not $FORMAT" 2
}

resolve_backend() {
  if [ -n "$backend" ]; then
    return 0
  fi
  backend=$(/bin/sh "$script_dir/resolve-config-knob.sh" --key mission_control_launch_backend \
    --type enum --values 'stream-json tmux' --fallback stream-json </dev/null) \
    || die "cannot resolve mission_control_launch_backend" 4
}

# --------------------------------------------------------------------------

cmd_launch() {
  program='' kind='' scope='' brief='' backend='' cwd='' rules=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --program | --kind | --scope | --brief | --backend | --cwd | --rules)
        [ "$#" -ge 2 ] || usage
        case $1 in
          --program) program=$2 ;;
          --kind) kind=$2 ;;
          --scope) scope=$2 ;;
          --brief) brief=$2 ;;
          --backend) backend=$2 ;;
          --cwd) cwd=$2 ;;
          --rules)
            case $2 in
              duty:* | repo:*) ;;
              *) die "--rules takes a duty:<id> or repo:<name> rule scope" ;;
            esac
            valid_scope "$2" || die "refusing the rule scope '$(sanitize_printable "$2")'"
            rules="$rules $2"
            ;;
        esac
        shift 2
        ;;
      *) usage ;;
    esac
  done
  valid_program "$program" || die "refusing the program name '$(sanitize_printable "$program")'"
  kind_row "$kind" || die "unknown session kind '$(sanitize_printable "$kind")' (one of: $KINDS)"
  valid_scope "$scope" || die "refusing the scope '$(sanitize_printable "$scope")': letters, digits and . _ = @ : - only, at most 128"
  [ -n "$brief" ] && [ -f "$brief" ] && [ -r "$brief" ] && [ -s "$brief" ] \
    || die "--brief must name a readable, non-empty regular file"
  case $backend in
    '' | stream-json | tmux) ;;
    *) die "--backend is stream-json or tmux" ;;
  esac
  if [ -z "$cwd" ]; then
    cwd=$(pwd -P) || die "cannot resolve the current directory"
  fi
  case $cwd in
    /*) ;;
    *) die "--cwd must be an absolute path" ;;
  esac
  cwd=$(cd "$cwd" 2>/dev/null && pwd -P) || die "--cwd is not an existing directory"

  name=$(session_name "$program" "$kind" "$scope") || exit 2
  valid_name "$name" || die "the derived session name is outside the launcher's grammar"
  /bin/sh "$script_dir/orchestrate-relay.sh" validate-handle stream-json-persistent "$name" 2>/dev/null \
    || die "the derived session name is outside the relay's session-name grammar"

  profile=$(/bin/sh "$script_dir/fleet-launch-profile.sh" "$K_PROFILE" </dev/null) \
    || die "refusing to launch $name without its $K_PROFILE settings profile" 4

  set --
  for r in $rules; do set -- "$@" --scope "$r"; done
  [ "$#" -gt 0 ] || set -- --scope program
  rendered=$(/bin/bash "$script_dir/mc-rules.sh" render "$program" "$@" </dev/null)
  rr=$?
  case $rr in
    0) ;;
    3) die "refusing to launch $name: the program $(sanitize_printable "$program") is not configured" 4 ;;
    *) die "refusing to launch $name: the rules in scope did not render (mc-rules.sh exit $rr)" 4 ;;
  esac

  resolve_backend
  fleet_home
  private_dir "$FH/mission-control"
  private_dir "$REG"
  private_dir "$LAUNCHES"
  row="$REG/$name"
  # The reservation: a row created exclusively, so two launches of one name
  # never both proceed. A held name is reported, never replaced.
  if ! (umask 077 && set -C && printf 'format\t%s\nname\t%s\nstate\tlaunching\n' "$FORMAT" "$name" >"$row") 2>/dev/null; then
    die "the session name $name is held by a registered session; retire it before launching again" 3
  fi
  ldir="$LAUNCHES/$name"
  release_reservation() {
    rm -f "$row"
    rm -rf "$ldir"
  }
  if [ -e "$ldir" ] || [ -L "$ldir" ]; then
    rm -f "$row"
    die "a launch directory for $name already exists with no registry row; remove $(sanitize_printable "$ldir") after checking it" 3
  fi
  # not-a-lock: the reservation is the row above; this only creates the directory it owns
  (umask 077 && mkdir "$ldir") 2>/dev/null || {
    rm -f "$row"
    die "cannot create the launch directory for $name"
  }
  composed="$ldir/brief.md"
  if ! {
    printf '<!-- mission-control launch: %s (kind %s, scope %s, program %s) -->\n\n' "$name" "$kind" "$scope" "$program"
    cat "$brief"
    printf '\n'
    printf '%s\n' "$rendered"
  } >"$composed"; then
    release_reservation
    die "cannot write the composed brief for $name"
  fi
  chmod 600 "$composed" 2>/dev/null || :

  # Each rung is an existing primitive. The stream-json supervisor resolves
  # no tier itself, so the plan is resolved here; offload-dispatch resolves
  # its own at the kind's key, and --strict-tier stops it from launching at
  # the ambient tier when the allocation store is unreachable.
  unit="mission-control:$name"
  case $backend in
    stream-json)
      plan=$(/bin/sh "$script_dir/allocation-apply.sh" plan --key "$K_KEY" --backend stream-json-persistent --unit "$unit" </dev/null)
      pr=$?
      if [ "$pr" -ne 0 ]; then
        release_reservation
        die "refusing to launch $name: no launch tier resolves at the $K_KEY key (allocation-apply exit $pr)" 4
      fi
      model=$(printf '%s\n' "$plan" | awk -F '\t' '$1 == "model" { print $2 }')
      effort=$(printf '%s\n' "$plan" | awk -F '\t' '$1 == "effort" { print $2 }')
      if [ -z "$model" ] || [ -z "$effort" ]; then
        release_reservation
        die "refusing to launch $name: the tier plan carries no model or effort row (broken install)" 4
      fi
      set -- launch "$name" "$scope" --prompt-file "$composed" --profile "$K_PROFILE" --cwd "$cwd" --
      [ "$model" = inherit ] || set -- "$@" --model "$model"
      [ "$effort" = inherit ] || set -- "$@" --effort "$effort"
      tier="$model/$effort"
      handle=$name
      if ! out=$(/bin/sh "$script_dir/fleet-streamjson.sh" "$@" </dev/null); then
        release_reservation
        die "the stream-json rung did not start $name" 1
      fi
      ;;
    tmux)
      out=$(cd "$cwd" && /bin/sh "$script_dir/offload-dispatch.sh" dispatch tmux "$composed" --unit "$unit" \
        --key "$K_KEY" --strict-tier --profile "$K_PROFILE" --name "$name" </dev/null)
      dr=$?
      case $dr in
        0) ;;
        1)
          release_reservation
          die "the tmux rung did not start $name" 1
          ;;
        3 | 4 | 5 | 6)
          release_reservation
          die "refusing to launch $name: no launch tier resolves at the $K_KEY key (offload-dispatch exit $dr)" 4
          ;;
        *)
          release_reservation
          die "the tmux rung refused $name (offload-dispatch exit $dr)" 4
          ;;
      esac
      handle=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "handle" { print $2; exit }')
      case $handle in
        @[0-9]*) ;;
        *)
          release_reservation
          die "the tmux rung reported no usable window for $name" 1
          ;;
      esac
      tier=rung
      ;;
  esac

  now=$(date +%s)
  owner="mission-control:$program"
  tmp_row="$row.tmp.$$"
  if ! (umask 077 && {
    printf 'format\t%s\n' "$FORMAT"
    printf 'name\t%s\n' "$name"
    printf 'state\tlaunched\n'
    printf 'program\t%s\n' "$program"
    printf 'owner\t%s\n' "$owner"
    printf 'kind\t%s\n' "$kind"
    printf 'scope\t%s\n' "$scope"
    printf 'backend\t%s\n' "$backend"
    printf 'handle\t%s\n' "$handle"
    printf 'profile\t%s\n' "$profile"
    printf 'tier\t%s\n' "$tier"
    printf 'brief\t%s\n' "$composed"
    printf 'launched\t%s\n' "$now"
  } >"$tmp_row") || ! mv -f "$tmp_row" "$row"; then
    rm -f "$tmp_row"
    printf '%s\n' "$me: $name started but its registry row could not be completed; retire it by name" >&2
    exit 1
  fi
  report() { printf 'launch\t%s\t%s\n' "$1" "$(sanitize_printable "$2")"; }
  report name "$name"
  report kind "$kind"
  report program "$program"
  report owner "$owner"
  report scope "$scope"
  report backend "$backend"
  report profile "$profile"
  report tier "$tier"
  report brief "$composed"
}

cmd_name() {
  program='' kind='' scope=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --program | --kind | --scope)
        [ "$#" -ge 2 ] || usage
        case $1 in
          --program) program=$2 ;;
          --kind) kind=$2 ;;
          --scope) scope=$2 ;;
        esac
        shift 2
        ;;
      *) usage ;;
    esac
  done
  valid_program "$program" || die "refusing the program name '$(sanitize_printable "$program")'"
  kind_row "$kind" || die "unknown session kind '$(sanitize_printable "$kind")' (one of: $KINDS)"
  valid_scope "$scope" || die "refusing the scope '$(sanitize_printable "$scope")'"
  session_name "$program" "$kind" "$scope"
}

# pane_gone <window-id> — 0 when tmux no longer knows the window.
pane_gone() {
  ! tmux display-message -p -t "$1" '#{window_id}' >/dev/null 2>&1
}

cmd_retire() {
  [ "$#" -eq 1 ] || usage
  name=$1
  valid_name "$name" || die "refusing the session name '$(sanitize_printable "$name")'"
  fleet_home
  row="$REG/$name"
  [ ! -L "$row" ] || die "refusing the registry row for $name: a symbolic link"
  [ -f "$row" ] || die "no registered session is named $name" 3
  row_check "$row"
  backend=$(row_get "$row" backend)
  handle=$(row_get "$row" handle)
  released='' held=''
  add_released() { released="$released,$1"; }
  add_held() { held="$held,$1"; }

  case $backend in
    stream-json)
      st=$(/bin/sh "$script_dir/fleet-streamjson.sh" stop "$name" --final </dev/null 2>/dev/null)
      case $st in
        "stop $name stopped "* | "stop $name already-closed") add_released process ;;
        *) add_held process ;;
      esac
      ;;
    tmux)
      case $handle in
        @[0-9]*) ;;
        *) die "the registry row for $name names no usable window" 2 ;;
      esac
      if [ -n "${TMUX_PANE:-}" ]; then
        self=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null) || self=''
        [ "$self" != "$handle" ] || die "refusing to retire $name from inside its own window" 3
      fi
      if pane_gone "$handle"; then
        add_released pane
      else
        tmux kill-window -t "$handle" >/dev/null 2>&1 || :
        if pane_gone "$handle"; then add_released pane; else add_held pane; fi
      fi
      ;;
    '')
      # A reservation whose launch never finished: nothing was started.
      :
      ;;
    *) die "the registry row for $name names an unknown backend" 2 ;;
  esac

  # The rung registered the session in the fleet registry under its own
  # handle: the session name on stream-json, the window id on tmux.
  marker="$FH/dispatch-markers/${handle:-$name}"
  if [ -f "$marker" ] && [ ! -L "$marker" ]; then
    fields=$(cat "$marker" 2>/dev/null) || fields=''
    mr=0
    /bin/sh "$script_dir/fleet-register.sh" --retire-marker "$marker" --expect "$fields" >/dev/null 2>&1 </dev/null || mr=$?
    case $mr in
      0 | 3) add_released registry ;;
      *) add_held registry ;;
    esac
  else
    add_released registry
  fi

  if /bin/sh "$script_dir/fleet-attention.sh" clear "$name" >/dev/null 2>&1 </dev/null; then
    add_released attention
  else
    add_held attention
  fi

  if [ -z "$held" ]; then
    rm -f "$row" && rm -rf "${LAUNCHES:?}/$name"
    if [ -e "$row" ]; then add_held row; else add_released row; fi
  else
    add_held row
  fi
  released=${released#,}
  held=${held#,}
  if [ -z "$held" ]; then
    printf 'retire\t%s\treleased\treleased=%s\theld=-\n' "$name" "$released"
    return 0
  fi
  printf 'retire\t%s\tpartial\treleased=%s\theld=%s\n' "$name" "${released:--}" "$held"
  return 1
}

cmd_list() {
  [ "$#" -eq 0 ] || usage
  fleet_home
  [ -d "$REG" ] || return 0
  set +f
  set -- "$REG"/mc-*
  set -f
  for f in "$@"; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    case ${f##*/} in *.tmp.*) continue ;; esac
    row_check "$f"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${f##*/}" "$(row_get "$f" program)" "$(row_get "$f" kind)" \
      "$(row_get "$f" scope)" "$(row_get "$f" backend)" "$(row_get "$f" launched)"
  done
}

cmd_kinds() {
  [ "$#" -eq 0 ] || usage
  for k in $KINDS; do
    kind_row "$k"
    printf '%s\t%s\t%s\n' "$k" "$K_PROFILE" "$K_KEY"
  done
}

[ "$#" -ge 1 ] || usage
verb=$1
shift
case $verb in
  -h | --help) help_text ;;
  launch) cmd_launch "$@" ;;
  name) cmd_name "$@" ;;
  retire) cmd_retire "$@" ;;
  list) cmd_list "$@" ;;
  kinds) cmd_kinds "$@" ;;
  *) usage ;;
esac
