#!/usr/bin/env bash
# mc-goals.sh — program goals and their done-when checks: a goal is done only
# when its own confirmed check passes, never because its pull requests
# merged.
#
# `mc-goals.sh --help` prints the contract: verbs, outputs, exit codes.
# shellcheck disable=SC2329 # the mutate callbacks below run indirectly
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-goals
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh bounded-run.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

CHECK_TIMEOUT=60
RETRY_AFTER=3600
RECHECK_AFTER=86400
EVIDENCE_MAX=200
tab=$(printf '\t')

usage() {
  mc_usage_fail "usage: mc-goals.sh set|attach|landed|confirm|run|evidence|verify|show|list|watch --program <p> ... (mc-goals.sh --help)"
}

help_text() {
  cat <<'HELP'
mc-goals.sh — program goals and their done-when checks. A goal is a plain
outcome, the check that proves it (a statement, and a command whose exit
status proves it where one fits) and the work it tracks. Mission control
drafts the check, the operator confirms or corrects it, and the goal is
reported done only after the confirmed check passes: the command exits 0, or,
with no command, a read-only session reports evidence that the outcome holds.
Merged pull requests never count as a pass.

The store is <program home>/goals.tsv, opening with `# format: 1`, written
under one lock; a missing or unknown format is refused and nothing is
reported. No repository is written.

Usage (every verb takes --program <p>):
  mc-goals.sh set --outcome <t> --statement <t> [--command <c>] [--work <ref>]...
      add a goal with its drafted check, unconfirmed; prints its id. A
      <ref> is pr:<owner>/<name>#<n>, flight:<handle> or task:<spec>/<id>.
  mc-goals.sh attach <id> --work <ref>
      track more work.
  mc-goals.sh landed <id> --work <ref>
      record a flight or spec task ref as merged (a pull request ref is read
      from the forge by the watcher).
  mc-goals.sh confirm <id> [--statement <t>] [--command <c> | --no-command]
      the operator's confirmation or correction, stored verbatim; prints
      confirmed<TAB><id>. A changed command is a new, unrun check.
  mc-goals.sh run <id> [--now <epoch>] [--timeout <s>]
      run a confirmed command check (refused while unconfirmed or with no
      command); prints passing|failing<TAB><id><TAB><evidence>.
  mc-goals.sh evidence <id> --holds yes|no --text <t> [--now <epoch>]
      record what a verification session reported, for a confirmed goal
      with no command.
  mc-goals.sh verify <id> [--launch]
      prepare the read-only verification session for a confirmed goal with
      no command: writes its brief and prints
      launch<TAB>reviewer<TAB>goal-<id><TAB><brief path>; --launch also
      starts it through mission-control-launch.sh.
  mc-goals.sh show <id>
      id, status, outcome, statement, command (verbatim), state, work,
      evidence.
  mc-goals.sh list
      id<TAB>status<TAB>outcome<TAB>work. Status: unconfirmed, open (its work
      not all merged), merged-not-done (merged, check not passing) or done.
  mc-goals.sh watch [--now <epoch>] [--bring-up] [--timeout <s>]
      the watcher of the goal-check duty: reads each tracked pull request's
      state from the forge; runs a confirmed command check once all its work
      merged; re-checks a done command goal daily, and at --bring-up. A
      failing first check routes one fix (a follow-up) and a failing
      re-check reopens the goal with one goal-reopened event; a passing
      re-check writes nothing. A confirmed goal with no command whose work
      merged raises one goal-verify-due event; a done one is not re-run.
      Prints checked<TAB><id><TAB>passing|failing<TAB><evidence> per run.

A check command is data the operator confirmed: stored and run as written,
from the program home, under a timeout (default 60 s), with no value from a
forge, a session or a record interpolated into it, and no secret stored.

Exit codes: 0 done; 1 a failed read or write, a store of unknown format, a
refused verb or a failed event; 2 usage; 3 the program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
if [ $# -eq 0 ] && [ -n "${PLANWRIGHT_MC_PROGRAM:-}" ]; then
  set -- watch
fi
[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  set | attach | landed | confirm | run | evidence | verify | show | list | watch) ;;
  *) usage ;;
esac

program="" id="" outcome="" statement="" command="" has_command=0 no_command=0
works="" holds="" text="" launch=0 bring_up=0 now_raw="" timeout=$CHECK_TIMEOUT
case $verb in
  attach | landed | confirm | run | evidence | verify | show)
    [ $# -ge 1 ] || usage
    id=$1
    shift
    ;;
esac
while [ $# -gt 0 ]; do
  case $1 in
    --launch)
      launch=1
      shift
      continue
      ;;
    --bring-up)
      bring_up=1
      shift
      continue
      ;;
    --no-command)
      no_command=1
      shift
      continue
      ;;
    --program | --outcome | --statement | --command | --work | --holds | --text | --now | --timeout)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --outcome) outcome=$2 ;;
        --statement) statement=$2 ;;
        --command)
          command=$2
          has_command=1
          ;;
        --work) works="${works:+$works }$2" ;;
        --holds) holds=$2 ;;
        --text) text=$2 ;;
        --now) now_raw=$2 ;;
        --timeout)
          mc_valid_uint "$2" && [ "$2" -ge 1 ] && [ "${#2}" -le 6 ] || mc_usage_fail "--timeout takes a whole number of seconds, at most six digits"
          timeout=$2
          ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
[ -n "$program" ] || usage
mc_now_arg "$now_raw"
mc_require_program "$program"
if [ -n "$id" ]; then
  case $id in
    g-[1-9]*) ;;
    *) mc_usage_fail "invalid goal id '$(sanitize_printable "$id")'" ;;
  esac
  case ${id#g-} in *[!0-9]*) mc_usage_fail "invalid goal id '$(sanitize_printable "$id")'" ;; esac
fi

home=$(mc_program_home "$program")
store="$home/goals.tsv"
trap mc_kb_unlock EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# fld <text>: one store field, tab and newline free; empty is `-`.
fld() {
  mc_valid_text "$1" || mc_fail "text with a control character is refused"
  [ -n "$1" ] || {
    printf '%s\n' "-"
    return 0
  }
  printf '%s\n' "$1"
}
# val <field>: the field's text, `-` being empty.
val() { if [ "$1" = - ]; then printf '\n'; else printf '%s\n' "$1"; fi; }

valid_ref() {
  case $1 in
    pr:*/*#[1-9]*)
      vr_body=${1#pr:}
      vr_slug=${vr_body%%#*}
      vr_n=${vr_body##*#}
      case $vr_slug in "" | /* | */ | *[!A-Za-z0-9._/-]* | -* | */-* | */*/*) return 1 ;; esac
      case $vr_n in *[!0-9]*) return 1 ;; esac
      return 0
      ;;
    flight:*) mc_valid_handle "${1#flight:}" ;;
    task:*/*)
      vr_spec=${1#task:}
      vr_spec=${vr_spec%%/*}
      mc_valid_kebab "$vr_spec" || return 1
      case ${1#task:*/} in "" | *[!0-9.]*) return 1 ;; esac
      return 0
      ;;
    *) return 1 ;;
  esac
}

check_store() {
  [ -f "$store" ] || mc_fail "no goal ${1:-$id}: there are no goals yet"
  mc_store_ok "$store" || mc_fail "the goal store has a missing or unknown format: $store"
}

# load <id>: the goal's fields in G_*.
load() {
  check_store
  l_line=$(I=$1 awk -F '\t' '!/^#/ && $1 == ENVIRON["I"] { print; exit }' "$store") || mc_fail "cannot read $store"
  [ -n "$l_line" ] || mc_fail "no goal $1"
  IFS=$tab read -r G_id G_opened G_outcome G_statement G_command G_state G_work G_merged G_evidence G_ran G_flags <<EOF
$l_line
EOF
}

row_line() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$G_id" "$G_opened" "$G_outcome" "$G_statement" "$G_command" "$G_state" "$G_work" "$G_merged" "$G_evidence" "$G_ran" "$G_flags"
}

# mutate <id> <function> [args]: reload the goal under the store's lock, let
# the function change G_*, write the row back.
mutate() {
  mu_id=$1
  shift
  mc_kb_lock "$program" goals.tsv
  load "$mu_id"
  "$@"
  mu_line=$(row_line)
  mu_all=$(I=$mu_id L=$mu_line awk -F '\t' '!/^#/ && $1 == ENVIRON["I"] { print ENVIRON["L"]; next } { print }' "$store") || mc_fail "cannot read $store"
  printf '%s\n' "$mu_all" | mc_write "$store" || mc_fail "cannot write $store"
  mc_kb_unlock
}

# reset_flags: a new check starts a new episode, so it may route and raise again.
reset_flags() {
  del_flag routed
  del_flag reopened
  del_flag verify
}
has_word() {
  case " $1 " in *" $2 "*) return 0 ;; esac
  return 1
}
add_flag() {
  if [ "$G_flags" = - ]; then G_flags=$1; elif ! has_word "$G_flags" "$1"; then G_flags="$G_flags $1"; fi
}
del_flag() {
  df_out=""
  for df_w in $G_flags; do
    [ "$df_w" = "$1" ] || df_out="${df_out:+$df_out }$df_w"
  done
  G_flags=${df_out:--}
}

# status: the derived status of the loaded goal.
status() {
  if [ "$G_state" = unconfirmed ]; then
    printf 'unconfirmed\n'
  elif [ "$G_state" = passing ]; then
    printf 'done\n'
  elif all_merged; then
    printf 'merged-not-done\n'
  else
    printf 'open\n'
  fi
}

# all_merged: the loaded goal tracks work and every ref of it merged.
all_merged() {
  [ "$G_work" != - ] || return 1
  for am_w in $G_work; do
    has_word "$(printf '%s' "$G_merged" | tr ',' ' ')" "$am_w" || return 1
  done
  return 0
}
merged_add() {
  ma_cur=$(printf '%s' "$G_merged" | tr ',' ' ')
  has_word "$ma_cur" "$1" && return 0
  if [ "$G_merged" = - ]; then G_merged=$1; else G_merged="$G_merged,$1"; fi
}
work_list() { printf '%s' "$G_work" | tr ',' ' '; }

ids() { awk -F '\t' '!/^#/ && $1 != "" { print $1 }' "$store"; }

show_line() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$G_id" "$(status)" "$(val "$G_outcome")" "$(val "$G_statement")" "$(val "$G_command")" "$G_state" "$G_work" "$(val "$G_evidence")"
}

# run_check: the loaded goal's stored command run as written, from the home,
# under the timeout; RUN_RC, RUN_EVIDENCE.
run_check() {
  RUN_CMD=$1
  RUN_STALE=0
  rc_dir=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory"
  rc_script=$(mktemp "$rc_dir/goal-check.XXXXXX") || mc_fail "cannot create the check file"
  rc_out=$(mktemp "$rc_dir/goal-check-out.XXXXXX") || {
    rm -f "$rc_script"
    mc_fail "cannot create the check output file"
  }
  printf '%s' "$1" >"$rc_script" || {
    rm -f "$rc_script" "$rc_out"
    mc_fail "cannot write the check file"
  }
  (cd "$home" && /bin/sh "$script_dir/bounded-run.sh" -k 5 "$timeout" /bin/bash "$rc_script" </dev/null >"$rc_out" 2>&1)
  RUN_RC=$?
  RUN_OUT=$(head -c "$EVIDENCE_MAX" "$rc_out" | tr '\t\n\r' '   ' | mc_clean_text)
  rm -f "$rc_script" "$rc_out"
  if [ "$RUN_RC" -eq 124 ]; then
    RUN_EVIDENCE="timed out after ${timeout}s"
  elif [ -n "$RUN_OUT" ]; then
    RUN_EVIDENCE="exit $RUN_RC: $RUN_OUT"
  else
    RUN_EVIDENCE="exit $RUN_RC"
  fi
  RUN_EVIDENCE="$RUN_EVIDENCE (checked $(mc_iso "$NOW"))"
}

apply_run() {
  # The check was confirmed again while it ran: its result is for the old command.
  RUN_STALE=0
  [ "$G_command" = "$RUN_CMD" ] || {
    RUN_STALE=1
    return 0
  }
  G_ran=$NOW
  G_evidence=$RUN_EVIDENCE
  if [ "$RUN_RC" -eq 0 ]; then
    G_state=passing
    del_flag routed
    del_flag reopened
  else
    G_state=failing
  fi
}

route_fix() {
  rf_day=$(mc_iso "$NOW")
  rf_day=${rf_day%%T*}
  mc_kb followup add --program "$program" --owner mission-control --trigger "date:$rf_day" \
    --text "$1" >/dev/null || mc_fail "cannot route the fix for $G_id"
}

case $verb in
  set)
    [ -n "$outcome" ] && [ -n "$statement" ] || mc_usage_fail "set takes --outcome and --statement"
    for w in $works; do valid_ref "$w" || mc_usage_fail "invalid work ref '$(sanitize_printable "$w")'"; done
    f_outcome=$(fld "$outcome") && f_statement=$(fld "$statement") && f_command=$(fld "$command") || exit 1
    mc_kb_lock "$program" goals.tsv
    mc_store_init "$store"
    n=$(awk -F '\t' '!/^#/ && $1 ~ /^g-[0-9]+$/ { n = substr($1, 3) + 0; if (n > m) m = n } END { print m + 1 }' "$store") || mc_fail "cannot read $store"
    new_id="g-$n"
    work=$(printf '%s' "$works" | tr ' ' ',')
    printf '%s\t%s\t%s\t%s\t%s\tunconfirmed\t%s\t-\t-\t-\t-\n' "$new_id" "$(mc_iso "$NOW")" "$f_outcome" "$f_statement" "$f_command" "${work:--}" >>"$store" || mc_fail "cannot append to $store"
    mc_kb_unlock
    printf '%s\n' "$new_id"
    ;;
  attach | landed)
    [ -n "$works" ] || mc_usage_fail "$verb takes --work <ref>"
    for w in $works; do valid_ref "$w" || mc_usage_fail "invalid work ref '$(sanitize_printable "$w")'"; done
    do_work() {
      for dw in $works; do
        if [ "$verb" = attach ]; then
          has_word "$(work_list)" "$dw" || { if [ "$G_work" = - ]; then G_work=$dw; else G_work="$G_work,$dw"; fi; }
        else
          has_word "$(work_list)" "$dw" || mc_fail "goal $G_id does not track $dw"
          case $dw in pr:*) mc_fail "a pull request ref is read from the forge, not recorded" ;; esac
          merged_add "$dw"
        fi
      done
    }
    mutate "$id" do_work
    printf '%s\t%s\n' "$verb" "$id"
    ;;
  confirm)
    do_confirm() {
      if [ -n "$statement" ]; then
        dc_old=$G_statement
        G_statement=$(fld "$statement") || exit 1
        # With no command the statement is the check, so a new one is a new check.
        if [ "$G_command" = - ] && [ "$G_state" != unconfirmed ] && [ "$dc_old" != "$G_statement" ]; then
          G_state=unrun
          G_evidence=-
          reset_flags
        fi
      fi
      if [ "$no_command" -eq 1 ]; then
        [ "$G_command" = - ] || {
          G_command=-
          G_state=unrun
          G_evidence=-
          reset_flags
        }
      elif [ "$has_command" -eq 1 ]; then
        dc_cmd=$(fld "$command") || exit 1
        [ "$G_command" = "$dc_cmd" ] || {
          G_command=$dc_cmd
          G_state=unrun
          G_evidence=-
          reset_flags
        }
      fi
      [ "$G_state" != unconfirmed ] || G_state=unrun
    }
    mutate "$id" do_confirm
    printf 'confirmed\t%s\n' "$id"
    ;;
  run)
    load "$id"
    [ "$G_state" != unconfirmed ] || mc_fail "the check of $id is unconfirmed; the operator confirms it first"
    [ "$G_command" != - ] || mc_fail "$id has no command; its check is a verification session (verify, evidence)"
    cmd=$G_command
    run_check "$cmd"
    mutate "$id" apply_run
    [ "$RUN_STALE" -eq 0 ] || mc_fail "the check of $id was confirmed again while it ran; run the new one"
    if [ "$RUN_RC" -eq 0 ]; then res=passing; else res=failing; fi
    printf '%s\t%s\t%s\n' "$res" "$id" "$RUN_EVIDENCE"
    ;;
  evidence)
    case $holds in yes | no) ;; *) mc_usage_fail "evidence takes --holds yes|no" ;; esac
    [ -n "$text" ] || mc_usage_fail "evidence takes --text"
    ev=$(fld "$text") || exit 1
    do_evidence() {
      [ "$G_state" != unconfirmed ] || mc_fail "the check of $G_id is unconfirmed"
      [ "$G_command" = - ] || mc_fail "$G_id has a command check; evidence is for a check with no command"
      G_ran=$NOW
      G_evidence="reported $holds: $ev"
      if [ "$holds" = yes ]; then
        G_state=passing
        del_flag routed
      else
        G_state=failing
        if all_merged && ! has_word "$G_flags" routed; then
          route_fix "goal $G_id merged but not done: $(val "$G_outcome"): $G_evidence"
          add_flag routed
        fi
      fi
    }
    mutate "$id" do_evidence
    printf 'recorded\t%s\n' "$id"
    ;;
  verify)
    load "$id"
    [ "$G_state" != unconfirmed ] || mc_fail "the check of $id is unconfirmed; the operator confirms it first"
    [ "$G_command" = - ] || mc_fail "$id has a command check; it needs no session"
    vdir=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory"
    brief="$vdir/goal-$id.brief.md"
    {
      printf '# Verify goal %s (read-only)\n\n' "$id"
      printf 'Outcome: %s\n\n' "$(val "$G_outcome")"
      printf 'Check: %s\n\n' "$(val "$G_statement")"
      printf 'This session is read-only: look and report; change nothing, in any repository, host or file.\n'
      # shellcheck disable=SC2016 # backticks are literal Markdown
      printf 'Finish with one line: `Holds: yes|no - <what you found>`. Mission control records it.\n'
    } | mc_write "$brief" || mc_fail "cannot write $brief"
    printf 'launch\treviewer\tgoal-%s\t%s\n' "$id" "$brief"
    if [ "$launch" -eq 1 ]; then
      /bin/sh "$script_dir/mission-control-launch.sh" launch --program "$program" --kind reviewer --scope "goal-$id" --brief "$brief" || mc_fail "the verification session did not launch"
    fi
    ;;
  show)
    load "$id"
    show_line
    ;;
  list)
    [ -f "$store" ] || exit 0
    check_store
    for gid in $(ids); do
      load "$gid"
      printf '%s\t%s\t%s\t%s\n' "$G_id" "$(status)" "$(val "$G_outcome")" "$G_work"
    done
    ;;
  watch)
    [ -f "$store" ] || exit 0
    check_store
    status_rc=0
    # The runner starts the watcher bare: the first run after its armed time
    # changes is the bring-up.
    if [ "$bring_up" -eq 0 ] && [ "${PLANWRIGHT_MC_DUTY:-}" = goal-check ]; then
      wrt=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory"
      armed=""
      set +f
      for rec in "$wrt"/watchers/*.rec; do
        [ -f "$rec" ] || continue
        armed=$(awk -F '\t' '$3 == "goal-check" { print $2; exit }' "$rec")
        [ -z "$armed" ] || break
      done
      set -f
      if [ -n "$armed" ] && [ "$armed" != "$(cat "$wrt/goal-check.armed" 2>/dev/null)" ]; then
        bring_up=1
        printf '%s\n' "$armed" | mc_write "$wrt/goal-check.armed" || mc_fail "cannot write $wrt/goal-check.armed"
      fi
    fi
    for gid in $(ids); do
      load "$gid"
      [ "$G_state" != unconfirmed ] || continue
      title=""
      # Merge state of the tracked pull requests, read from the forge.
      if ! all_merged; then
        for ref in $(work_list); do
          has_word "$(printf '%s' "$G_merged" | tr ',' ' ')" "$ref" && continue
          case $ref in pr:*) ;; *) continue ;; esac
          body=${ref#pr:}
          gh_out=$(/bin/sh "$script_dir/bounded-run.sh" 30 gh pr view "${body##*#}" --repo "${body%%#*}" --json state,title --jq '[.state,.title]|@tsv' 2>/dev/null) || continue
          if [ "${gh_out%%"$tab"*}" = MERGED ]; then
            title=$(printf '%s' "${gh_out#*"$tab"}" | tr '\t\n\r' '   ' | mc_clean_text | cut -c1-120)
            merge_ref=$ref
            do_merge() { merged_add "$merge_ref"; }
            mutate "$gid" do_merge
            load "$gid"
          fi
        done
      fi
      all_merged || {
        # Only a done command goal is re-checked while its work is open.
        [ "$G_state" = passing ] || continue
      }
      if [ "$G_command" = - ]; then
        # A session check is requested once and never re-run on its own.
        [ "$G_state" != passing ] || continue
        has_word "$G_flags" verify && continue
        do_verify_flag() { add_flag verify; }
        mc_event emit --program "$program" --now "$NOW" -- goal-verify-due "$gid" \
          "goal $gid merged: verify with a read-only session (mc-goals.sh verify $gid): $(val "$G_statement" | cut -c1-200)" >/dev/null || mc_fail "the goal-verify-due event was refused"
        mutate "$gid" do_verify_flag
        continue
      fi
      ran=$G_ran
      mc_valid_uint "$ran" || ran=0
      due=0
      case $G_state in
        passing)
          { [ "$bring_up" -eq 1 ] || [ $((NOW - ran)) -ge "$RECHECK_AFTER" ]; } && due=1
          ;;
        failing)
          { [ "$bring_up" -eq 1 ] || [ $((NOW - ran)) -ge "$RETRY_AFTER" ]; } && due=1
          ;;
        *) due=1 ;;
      esac
      [ "$due" -eq 1 ] || continue
      was=$G_state
      cmd=$G_command
      outcome_text=$(val "$G_outcome")
      run_check "$cmd"
      if [ "$RUN_RC" -eq 0 ]; then res=passing; else res=failing; fi
      if [ "$res" = passing ] && [ "$was" = passing ]; then
        do_quiet() { [ "$G_command" != "$RUN_CMD" ] || G_ran=$NOW; }
        mutate "$gid" do_quiet
        continue
      fi
      mutate "$gid" apply_run
      [ "$RUN_STALE" -eq 0 ] || continue
      printf 'checked\t%s\t%s\t%s\n' "$gid" "$res" "$RUN_EVIDENCE"
      [ "$res" = failing ] || continue
      load "$gid"
      if [ "$was" = passing ]; then
        has_word "$G_flags" reopened && continue
        mc_event emit --program "$program" --now "$NOW" -- goal-reopened "$gid" \
          "goal $gid reopened, its check now fails: $outcome_text: $RUN_EVIDENCE" >/dev/null || mc_fail "the goal-reopened event was refused"
        do_reopen_flag() {
          add_flag reopened
          add_flag routed
        }
        route_fix "goal $gid reopened, its check fails: $outcome_text: $RUN_EVIDENCE"
        mutate "$gid" do_reopen_flag
      else
        has_word "$G_flags" routed && continue
        route_fix "goal $gid merged but not done: $outcome_text: $RUN_EVIDENCE${title:+ (work: $title)}"
        do_route_flag() { add_flag routed; }
        mutate "$gid" do_route_flag
      fi
    done
    exit "$status_rc"
    ;;
esac
