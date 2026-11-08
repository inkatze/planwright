#!/bin/bash
# Tests for scripts/mc-pane-answer.sh — the one relay that delivers an
# operator's recorded choice to a dialog a mission control is stuck on: a
# single digit, into that program's own mission-control pane, against the
# hub's record of the operator's answer about that very dialog, recorded
# after the dialog appeared. Every refusal has its case here.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-pane-answer.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
unset PLANWRIGHT_STREAMJSON_PENDING_AGE

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-pane-answer.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
cp "$repo_root/config/duties.yaml" "$core/config/duties.yaml"
write_programs() { # write_programs <hub>
  {
    printf 'mission_control_programs: [alpha, beta, hub]\n'
    for p in alpha beta hub; do
      printf 'program_%s_repositories: [%s]\n' "$p" "$repo"
      printf 'program_%s_spec_root: %s/specs\n' "$p" "$repo"
      printf 'program_%s_home: %s/mchome-%s\n' "$p" "$tmp" "$p"
    done
    printf 'mission_control_escalation_hub: %s\n' "$1"
  } >"$tracked"
}
write_programs hub

# Stubs. ps: for the session lookup's own flags, the fixture table, then this
# host's real pid and parent columns (so the caller's own ancestry is real,
# while no real process can read as a session); any other flags reach the
# real ps. busybox ps takes neither -ww nor -A, hence the fallback. tmux:
# panes and captures from files, a capture moving $tmp/pane-<p>.next into
# place for the next one, and the first capture after $tmp/capture-sets
# appears standing in for a watcher pass that rewrites the dialog record to
# it (`remove`: drops it), or after $tmp/capture-releases for one that ends
# a second later, releasing the pass lock; send-keys recorded to $tmp/keys (failing when
# $tmp/send-fails exists, and making the answers log read-only when
# $tmp/send-locks-log does).
esc_self="$fleet/mission-control/alpha/escalate/self"
real_ps=$(command -v ps)
mkdir -p "$tmp/bin"
cat >"$tmp/bin/ps" <<EOF
#!/bin/sh
case "\$*" in
  '-ww -A -o pid= -o ppid= -o uid= -o args=')
    cat "$tmp/ps.out" 2>/dev/null
    "$real_ps" -A -o pid,ppid 2>/dev/null || "$real_ps" -o pid,ppid 2>/dev/null || true
    ;;
  *) exec "$real_ps" "\$@" ;;
esac
EOF
cat >"$tmp/bin/tmux" <<EOF
#!/bin/sh
case "\$1" in
  list-panes) cat "$tmp/panes" 2>/dev/null ;;
  capture-pane)
    t=''
    while [ \$# -gt 0 ]; do [ "\$1" = -t ] && t=\$2; shift; done
    cat "$tmp/pane-\$t" 2>/dev/null || exit 1
    [ ! -e "$tmp/pane-\$t.next" ] || mv "$tmp/pane-\$t.next" "$tmp/pane-\$t"
    if [ -e "$tmp/capture-sets" ]; then
      if [ "\$(cat "$tmp/capture-sets")" = remove ]; then rm -f "$esc_self"; else cp "$tmp/capture-sets" "$esc_self"; fi
      rm -f "$tmp/capture-sets"
    fi
    if [ -e "$tmp/capture-releases" ]; then
      rm -f "$tmp/capture-releases"
      (
        sleep 1
        [ ! -s "$tmp/keys" ] || touch "$tmp/sent-early"
        rm -f "${esc_self%/self}/pass.lock"
        touch "$tmp/released"
      ) >/dev/null 2>&1 &
    fi
    ;;
  send-keys)
    shift
    printf '%s\n' "\$*" >>"$tmp/keys"
    [ ! -e "$tmp/send-locks-log" ] || chmod 444 "${esc_self%/self}/answers.log"
    [ ! -e "$tmp/send-fails" ]
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/ps" "$tmp/bin/tmux"
PATH="$tmp/bin:$PATH"
export PATH

# Fixture pids sit above any pid Linux (at most 4194303) or macOS assigns,
# so none is a real process.
SP=4194401
PP=4194400
uid=$(id -u)
cat >"$tmp/dialog.txt" <<'EOF'
────────────────────────────────────────────────────────────────
 Bash command
 │ /plugin/scripts/fleet-streamjson.sh answer mc-alpha-worker-aaaaaaaaaa r1 --allow
 │ Auto mode needs your confirmation for this command.
 │ 4 consecutive actions were blocked. Please review the transcript before continuing.

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for: /plugin/scripts/fleet-streamjson.sh answer *
   3. No

 Esc to cancel · Tab to amend
EOF
session_row() { printf '  %s  %s %s claude --name alpha-mission-control /planwright:mission-control alpha\n' "$1" "$2" "$uid"; }
session_row "$SP" "$PP" >"$tmp/ps.out"
printf '%%7\t%s\n' "$PP" >"$tmp/panes"

esc_dir="$fleet/mission-control/alpha/escalate"
answer() {
  OUT=$(mc_env env TMUX_PANE=%99 /bin/bash "$repo_root/scripts/mc-pane-answer.sh" "$@" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
print_of() { awk -F '\t' '$1 == "dialog" { print $4; exit }' "$esc_dir/self" 2>/dev/null; }
# shown <pane file>: the pane shows it, and the watcher records it afresh;
# PRINT is its digest.
shown() {
  cp "$1" "$tmp/pane-%7"
  rm -f "$esc_dir/self"
  mc_run mc-escalate.sh scan --program alpha
  PRINT=$(print_of)
  [ -n "$PRINT" ] || fail "the watcher recorded no dialog for $1: $OUT $ERR"
}
# note <program> <shape> <target> [<subject>]: an operator note; prints its id.
note() {
  mc_env /bin/bash "$repo_root/scripts/mc-decide.sh" note --program "$1" --shape "$2" \
    --subject "${4:-alpha dialog $PRINT}" --text "the operator chose $3" --target "$3" 2>"$tmp/note.err" | awk -F '\t' '{ print $2 }'
}
keys() { cat "$tmp/keys" 2>/dev/null; }
refused() { # refused <label> <stderr needle>
  expect_rc "$1" 4
  expect_err "$1: named" "$2"
  [ -z "$(keys)" ] || fail "$1: a key was sent: $(keys)"
}

mc_run mc-kb.sh init --program hub
expect_rc "the hub's knowledge base" 0

shown "$tmp/dialog.txt"
expect_out "the watcher records the open dialog in pane %7" "self${tab}auto-mode${tab}0${tab}owner${tab}%7"
D1=$(note hub answer 1)
if [ -n "$D1" ]; then ok "an operator answer is recorded ($D1)"; else fail "no decision id from mc-decide.sh note: $(cat "$tmp/note.err")"; fi
cp "$esc_dir/self" "$tmp/self.first"

# --- the arguments ----------------------------------------------------------
for bad in 0 10 "1 " ""; do
  answer --program alpha --choice "$bad" --decision "$D1" --decided-in hub
  if [ "$bad" = "" ]; then expect_rc "an empty choice is usage" 2; else refused "choice '$bad'" "one digit"; fi
done
answer --program alpha --choice 1 --decision "../decisions-1" --decided-in hub
refused "a malformed decision id" "decisions-log entry id"
answer --program alpha --choice 1 --decided-in hub
expect_rc "a missing decision is usage" 2
answer --program alpha --choice 1 --decision decisions-209901-9999 --decided-in hub
refused "an unknown decision" "not in the decisions log"
answer --program nosuch --choice 1 --decision "$D1" --decided-in hub
expect_rc "an unconfigured target program" 3
answer --program alpha --choice 1 --decision "$D1" --decided-in nosuch
expect_rc "an unconfigured deciding program" 3

# --- where the decision lives -------------------------------------------------
answer --program alpha --choice 1 --decision "$D1" --decided-in beta
refused "a decision outside the configured hub" "are the hub's (hub), not beta's"
write_programs alpha
answer --program alpha --choice 1 --decision "$D1" --decided-in alpha
refused "a program answering its own dialog" "never answers its own"
write_programs hub

# --- the decision -------------------------------------------------------------
NQ=$(mc_env /bin/bash "$repo_root/scripts/mc-decide.sh" decide --program hub --subject "alpha dialog $PRINT" --act 'operator: "1"' --target 1 --grounds "routine" --class hygiene 2>/dev/null | awk -F '\t' '{ print $2 }')
answer --program alpha --choice 1 --decision "$NQ" --decided-in hub
refused "a decision that is not the operator's" "not the operator's answer"
DC=$(note hub correction 1)
answer --program alpha --choice 1 --decision "$DC" --decided-in hub
refused "an operator correction is not an answer" "not the operator's answer"
DO=$(note hub answer 1 "alpha dialog 0123456789abcdef")
answer --program alpha --choice 1 --decision "$DO" --decided-in hub
refused "an answer about another dialog" "about another dialog"
D3=$(note hub answer 3)
answer --program alpha --choice 1 --decision "$D3" --decided-in hub
refused "a choice other than the answer recorded" "an answer other than 1"
cp "$esc_dir/self" "$tmp/self.saved"
IFS="$tab" read -r _ first sess print kind <"$esc_dir/self"
printf 'dialog\t%s\t%s\t%s\t%s\n' $((first + 86400)) "$sess" "$print" "$kind" >"$esc_dir/self"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a decision older than the dialog" "predates the dialog"
printf 'dialog\t%s\t%s\tnot-a-digest\t%s\n' "$first" "$sess" "$kind" >"$esc_dir/self"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "an unreadable dialog record" "unreadable"
rm -f "$esc_dir/self"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "no dialog on record" "no dialog of alpha is on record"
ln -s "$tmp/self.saved" "$esc_dir/self"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a linked dialog record" "no dialog of alpha is on record"
rm -f "$esc_dir/self"
cp "$tmp/self.saved" "$esc_dir/self"

# --- the session and its pane -------------------------------------------------
cp "$tmp/ps.out" "$tmp/ps.saved"
: >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "no session running" "no mission-control session of alpha is running"
{
  session_row "$SP" "$PP"
  session_row $((SP + 1)) "$PP"
} >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "two sessions running" "more than one"
session_row $((SP + 2)) "$PP" >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a session other than the one on record" "not the one whose dialog is on record"
printf '  %s  %s 4242424 claude /planwright:mission-control alpha\n' "$SP" "$PP" >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "another account's process is never the session" "no mission-control session of alpha is running"
cp "$tmp/ps.saved" "$tmp/ps.out"
: >"$tmp/panes"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a session with no pane" "has no tmux pane"
printf '%%7\t%s\n' "$PP" >"$tmp/panes"
OUT=$(mc_env env TMUX_PANE=%7 /bin/bash "$repo_root/scripts/mc-pane-answer.sh" --program alpha --choice 1 --decision "$D1" --decided-in hub 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
refused "the caller's own pane" "the caller's own"
# The caller runs under the pane: the pane's process is this test's shell.
printf '%%7\t%s\n' "$$" >"$tmp/panes"
session_row "$SP" "$$" >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a pane the caller runs under" "one the caller runs under"
cp "$tmp/ps.saved" "$tmp/ps.out"
printf '%%7\t%s\n' "$PP" >"$tmp/panes"

# --- the dialog -------------------------------------------------------------
printf '  ? for shortcuts\n> \n' >"$tmp/pane-%7"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "no open dialog" "shows no open dialog"
sed 's/4 consecutive/9 consecutive/' "$tmp/dialog.txt" >"$tmp/pane-%7"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a different dialog from the one on record" "a different dialog"
cp "$tmp/dialog.txt" "$tmp/pane-%7"
sed 's/4 consecutive/9 consecutive/' "$tmp/dialog.txt" >"$tmp/pane-%7.next"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a dialog that changed before the keystroke" "a different dialog"
cp "$tmp/dialog.txt" "$tmp/pane-%7"
answer --program alpha --choice 4 --decision "$(note hub answer 4)" --decided-in hub
refused "an option the dialog does not offer" "offers no option 4"
answer --program alpha --choice 2 --decision "$(note hub answer 2)" --decided-in hub
refused "an option that adds a standing permission" "does more than answer this dialog"
sed 's/^   2\. Yes, and don.*$/   2. Yes, auto-accept edits/' "$tmp/dialog.txt" >"$tmp/modes.txt"
shown "$tmp/modes.txt"
answer --program alpha --choice 2 --decision "$(note hub answer 2)" --decided-in hub
refused "an option that switches a mode" "does more than answer this dialog"
sed 's/^   3\. No$/   2. No/' "$tmp/dialog.txt" >"$tmp/repeat.txt"
shown "$tmp/repeat.txt"
answer --program alpha --choice 1 --decision "$(note hub answer 1)" --decided-in hub
refused "a run that repeats a digit" "wrap or repeat"
awk '{ print } /^   2\. Yes, and/ { print "      and every later call" }' "$tmp/dialog.txt" >"$tmp/wrap.txt"
shown "$tmp/wrap.txt"
answer --program alpha --choice 1 --decision "$(note hub answer 1)" --decided-in hub
refused "a run whose labels wrap" "wrap or repeat"
sed '/^ ❯ 1\./d; /^   [23]\./d' "$tmp/dialog.txt" >"$tmp/noopts.txt"
shown "$tmp/noopts.txt"
answer --program alpha --choice 1 --decision "$(note hub answer 1)" --decided-in hub
refused "a dialog with no numbered options" "has no numbered options"
sed 1d "$tmp/dialog.txt" >"$tmp/norule.txt"
shown "$tmp/norule.txt"
answer --program alpha --choice 1 --decision "$(note hub answer 1)" --decided-in hub
refused "a dialog with no opening rule on screen" "cannot cover whole"
pad='                                                  '
sed "s|^ Do you want to proceed?\$| Do you want to proceed?$pad│ and rm -rf ~/|" "$tmp/dialog.txt" >"$tmp/cut.txt"
shown "$tmp/cut.txt"
answer --program alpha --choice 1 --decision "$(note hub answer 1)" --decided-in hub
refused "a dialog with a line cut as side-panel text" "cannot cover whole"
cp "$tmp/dialog.txt" "$tmp/pane-%7"
cp "$tmp/self.first" "$esc_dir/self"
cp "$tmp/self.first" "$tmp/self.saved"
PRINT=$(print_of)

# --- delivery -----------------------------------------------------------------
ln -s "$tmp/elsewhere" "$esc_dir/answers.log"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
expect_rc "a linked answers log" 1
expect_err "is refused" "not a regular file"
[ -z "$(keys)" ] && [ ! -e "$tmp/elsewhere" ] || fail "a linked answers log was used"
rm -f "$esc_dir/answers.log"
ln -s "$$-1-1" "$esc_dir/answer.lock"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
expect_rc "another answer in flight" 1
expect_err "is named" "in flight"
[ -z "$(keys)" ] || fail "a key was sent beside a live answer: $(keys)"
rm -f "$esc_dir/answer.lock"

IFS="$tab" read -r _ first sess print kind <"$tmp/self.saved"
# moved <file> <label> <needle>: the watcher's record becomes <file> (or is
# removed, for `-`) between the first pane read and the final check.
moved() {
  if [ "$1" = - ]; then echo remove >"$tmp/capture-sets"; else cp "$1" "$tmp/capture-sets"; fi
  cp "$tmp/self.saved" "$esc_dir/self"
  answer --program alpha --choice 1 --decision "$D1" --decided-in hub
  rm -f "$tmp/capture-sets"
  refused "$2" "$3"
}
printf 'dialog\t%s\t%s\t%s\t%s\n' $((first + 86400)) "$sess" "$print" "$kind" >"$tmp/later"
moved "$tmp/later" "a dialog reopened after the decision, before the keystroke" "predates the dialog"
printf 'dialog\t%s\t%s\t0123456789abcdef\t%s\n' "$first" "$sess" "$kind" >"$tmp/other"
moved "$tmp/other" "a record that changed before the keystroke" "changed while the answer was checked"
moved - "a record gone before the keystroke" "left the record"
printf 'dialog\tx\t%s\t%s\t%s\n' "$sess" "$print" "$kind" >"$tmp/badfirst"
moved "$tmp/badfirst" "a record whose first sight became unreadable before the keystroke" "is unreadable"
cp "$tmp/self.saved" "$esc_dir/self"
: >"$esc_dir/pass.lock"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
rm -f "$esc_dir/pass.lock"
expect_rc "a watcher lock that cannot be taken" 1
expect_err "sends nothing" "nothing was sent"
[ -z "$(keys)" ] || fail "a key was sent without the watcher's lock: $(keys)"
ln -s "$$-1-1" "$esc_dir/pass.lock"
touch "$tmp/capture-releases"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
expect_rc "a decided choice is delivered once the watcher's pass ends" 0
n=0
while [ ! -e "$tmp/released" ] && [ "$n" -lt 100 ]; do
  sleep 0.1 2>/dev/null || sleep 1
  n=$((n + 1))
done
[ -e "$tmp/released" ] || fail "the stand-in watcher pass never released its lock"
[ ! -e "$tmp/sent-early" ] || fail "a key was sent while the watcher's pass held its lock"
expect_out "naming the pane, digit and option" "answered${tab}alpha${tab}%7${tab}1${tab}Yes"
if [ "$(keys)" = "-t %7 1" ]; then ok "exactly one digit is sent to that pane"; else fail "keys sent: '$(keys)'"; fi
if grep "${tab}${D1}${tab}hub${tab}1${tab}%7${tab}${SP}${tab}" "$esc_dir/answers.log" | awk -F '\t' '{ printf "%s ", $7 }' | grep -q '^pending sent $'; then
  ok "the answer is logged against the decision, pending before the keystroke and sent after"
else
  fail "answers.log: $(cat "$esc_dir/answers.log" 2>/dev/null)"
fi
if [ ! -e "$esc_dir/self" ]; then ok "the answered dialog's record is dropped"; else fail "the dialog record survived its answer"; fi
: >"$tmp/keys"
cp "$tmp/self.saved" "$esc_dir/self"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a decision already used" "already used by an answer attempt"
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$esc_dir/answers.log"
  answer --program alpha --choice 1 --decision "$D1" --decided-in hub
  chmod 644 "$esc_dir/answers.log"
  expect_rc "an answers log that cannot be read" 1
  expect_err "fails the replay check" "was not used before"
  [ -z "$(keys)" ] || fail "a key was sent past an unreadable answers log: $(keys)"
fi
D2=$(note hub answer 3)
touch "$tmp/send-fails"
answer --program alpha --choice 3 --decision "$D2" --decided-in hub
expect_rc "a failed send" 1
expect_err "says the decision is used" "decision $D2 is used"
expect_no_out "and reports no answer" "answered"
rm -f "$tmp/send-fails"
if grep -q "${tab}${D2}${tab}hub${tab}3${tab}%7${tab}${SP}${tab}failed$" "$esc_dir/answers.log"; then
  ok "a failed send is logged and uses the decision"
else
  fail "answers.log after a failed send: $(cat "$esc_dir/answers.log")"
fi
if [ -e "$esc_dir/self" ]; then ok "a failed send keeps the dialog's record"; else fail "a failed send dropped the dialog record"; fi
: >"$tmp/keys"
answer --program alpha --choice 3 --decision "$D2" --decided-in hub
refused "a decision a failed send used" "already used by an answer attempt"
if [ "$(id -u)" != 0 ]; then
  D4=$(note hub answer 1)
  chmod 444 "$esc_dir/answers.log"
  answer --program alpha --choice 1 --decision "$D4" --decided-in hub
  chmod 644 "$esc_dir/answers.log"
  expect_rc "an answer that cannot be logged before the keystroke" 1
  expect_err "sends nothing" "nothing was sent"
  [ -z "$(keys)" ] || fail "a key was sent with no pending line: $(keys)"
  touch "$tmp/send-locks-log"
  answer --program alpha --choice 1 --decision "$D4" --decided-in hub
  rm -f "$tmp/send-locks-log"
  chmod 644 "$esc_dir/answers.log"
  expect_rc "a sent answer whose outcome cannot be logged" 1
  expect_out "still reports the send" "answered${tab}alpha${tab}%7${tab}1"
  expect_err "and says its pending line keeps the decision used" "pending line still marks decision $D4 used"
  if [ "$(keys)" = "-t %7 1" ]; then ok "the one digit was sent"; else fail "keys sent: '$(keys)'"; fi
  : >"$tmp/keys"
  cp "$tmp/self.saved" "$esc_dir/self"
  answer --program alpha --choice 1 --decision "$D4" --decided-in hub
  refused "a decision only a pending line used" "already used by an answer attempt"
else
  echo "skip: the unwritable answers log cases, as root"
fi
cp "$tmp/self.saved" "$esc_dir/self"
: >"$tmp/keys"

# --- the dialog parser, in process ----------------------------------------------
if (
  pfail=0
  fail() {
    echo "FAIL: $1" >&2
    pfail=1
  }
  script_dir="$repo_root/scripts"
  [ -r "$repo_root/scripts/echo-safety.sh" ] || exit 1
  . "$repo_root/scripts/echo-safety.sh"
  . "$repo_root/scripts/mc-lib.sh"
  . "$repo_root/scripts/fleet-pane-vocabulary.sh"
  . "$repo_root/scripts/mc-session-pane.sh"
  parse() { msp_dialog "$(printf '%s\n' "$1" | msp_trim)"; }
  base=$(cat "$tmp/dialog.txt")
  parse "$(printf '%s\n' "$base" | awk '$0 == "   3. No" { print "   3. No, and tell Claude what to do"; print "      differently"; next } { print }')" || :
  [ -z "$MSP_OPTIONS" ] || fail "a wrapped last label left options: $MSP_OPTIONS"
  parse "$(
    printf '%s\n' "$base" | sed '/^ Esc to cancel/d'
    printf ' Enter to select\n Esc to cancel\n'
  )"
  case $MSP_OPTIONS in "1${tab}Yes"*) ;; *) fail "a footer between the options and the end dropped them: '$MSP_OPTIONS'" ;; esac
  parse "$(
    printf 'chat one\n────────────────\n'
    printf '%s\n' "$base"
  )"
  p1=$MSP_PRINT
  parse "$(
    printf 'chat two, scrolled\n────────────────\n'
    printf '%s\n' "$base"
  )"
  [ "$p1" = "$MSP_PRINT" ] || fail "text above the opening rule changed the digest"
  pad='                                                  '
  parse "$(printf '%s\n' "$base" | sed "s/^ Do you want to proceed?\$/ Do you want to proceed?$pad│ 12:00/")"
  p2=$MSP_PRINT
  parse "$(printf '%s\n' "$base" | sed "s/^ Do you want to proceed?\$/ Do you want to proceed?$pad│ 12:01/")"
  [ "$p2" = "$MSP_PRINT" ] || fail "the side panel's text changed the digest"
  [ "$MSP_BINDABLE" = 0 ] || fail "a dialog with a line cut as side-panel text reads bindable"
  parse "$base"
  [ "$MSP_BINDABLE" = 1 ] || fail "a whole dialog under its opening rule reads unbindable"
  [ "$p2" != "$MSP_PRINT" ] || fail "an unbindable view shares the digest of the whole dialog"
  parse "$(printf '────────────────│ hidden\n' && printf '%s\n' "$base" | sed 1d)"
  [ "$MSP_BINDABLE" = 0 ] || fail "a dialog whose opening rule was cut reads bindable"
  # long <first command line>: a dialog whose command runs well past a dozen
  # lines, differing only in its first line.
  long() {
    printf '────────────────\n Bash command\n │ %s\n' "$1"
    i=0
    while [ "$i" -lt 14 ]; do
      printf ' │ echo line %s\n' "$i"
      i=$((i + 1))
    done
    printf '%s\n' "$base" | sed '1,2d'
  }
  parse "$(long 'cd /tmp')"
  p3=$MSP_PRINT
  parse "$(long 'cd / && rm -rf ~')"
  [ "$p3" != "$MSP_PRINT" ] || fail "a command differing above a dozen lines kept the digest"
  [ "$MSP_BINDABLE" = 1 ] || fail "a long dialog under its opening rule reads unbindable"
  # mimic <first command line>: a command that echoes a rule-like line.
  mimic() {
    printf '────────────────\n Bash command\n │ %s\n │ echo ──────────────── done\n' "$1"
    printf '%s\n' "$base" | sed '1,2d'
  }
  parse "$(mimic 'cd /tmp')" || fail "the rule-like dialog did not parse"
  p4=$MSP_PRINT
  parse "$(mimic 'cd / && rm -rf ~')" || fail "the rule-like dialog did not parse"
  [ "$p4" != "$MSP_PRINT" ] || fail "a rule-like line inside the command ended the dialog"
  [ "$MSP_BINDABLE" = 1 ] || fail "a dialog with a rule-like command line reads unbindable"
  # edit <old> <new>: an edit dialog whose diff sits between dashed lines.
  edit() {
    printf '────────────────\n Edit file config.sh\n ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌\n   1 -%s\n   1 +%s\n ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌\n' "$1" "$2"
    printf '%s\n' "$base" | sed '1,5d'
  }
  parse "$(edit x=1 x=2)" || fail "the edit dialog did not parse"
  p5=$MSP_PRINT
  parse "$(edit PATH=/usr/bin PATH=/tmp/evil)" || fail "the edit dialog did not parse"
  [ "$p5" != "$MSP_PRINT" ] || fail "a dashed line inside an edit dialog ended the dialog"
  [ "$MSP_BINDABLE" = 1 ] || fail "an edit dialog under its opening rule reads unbindable"
  # indent <spaces>: a script whose last line differs only in indentation.
  indent() {
    printf '────────────────\n Bash command\n   python3 -c "\n   if False:\n%swipe()"\n' "$1"
    printf '%s\n' "$base" | sed '1,5d'
  }
  parse "$(indent '       ')"
  p6=$MSP_PRINT
  parse "$(indent '   ')"
  [ "$p6" != "$MSP_PRINT" ] || fail "commands differing only in indentation share a digest"
  parse "$(indent '   ❯')"
  p7=$MSP_PRINT
  parse "$(indent '    ')"
  [ "$p7" != "$MSP_PRINT" ] || fail "a command line led by the cursor glyph shares a digest with one led by a space"
  # bare <cursor digit>: two options, no footer below them.
  bare() {
    printf '────────────────\n Bash command\n   ls\n\n Do you want to proceed?\n'
    if [ "$1" = 1 ]; then printf ' ❯ 1. Yes\n   2. No\n'; else printf '   1. Yes\n ❯ 2. No\n'; fi
  }
  parse "$(bare 1)"
  p8=$MSP_PRINT o8=$MSP_OPTIONS
  parse "$(bare 2)"
  [ "$p8" = "$MSP_PRINT" ] || fail "moving the cursor with no footer below changed the digest"
  [ "$o8" = "$MSP_OPTIONS" ] && [ "$(printf '%s\n' "$o8" | wc -l | tr -d ' ')" = 2 ] || fail "options with no footer below read '$o8' then '$MSP_OPTIONS'"
  parse "$(
    bare 1 | sed '$d'
    printf '   2. Yes, and do not ask again for these\n      commands\n   3. No\n'
  )"
  [ "$MSP_RUN" = broken ] || fail "a wrapped label with no footer below read as run '$MSP_RUN': '$MSP_OPTIONS'"
  parse "$(
    bare 1 | sed '$d'
    printf "   2. Yes, allow\n      and don't ask again for ls\n   3. No\n"
  )"
  [ "$MSP_RUN" = broken ] || fail "a label wrapping onto a signature line read as run '$MSP_RUN': '$MSP_OPTIONS'"
  parse "$(indent '   ❯ 1. ')"
  p10=$MSP_PRINT
  parse "$(indent '     1. ')"
  [ "$p10" != "$MSP_PRINT" ] || fail "a command line that looks like a cursor option shares a digest with its uncursored twin"
  # fetch <body line>: a dialog whose question carries no signature, its
  # body right above it.
  fetch() {
    printf '────────────────\n Fetch\n%s\n Do you want to allow Claude to fetch this content?\n ❯ 1. Yes\n   2. No\n\n Esc to cancel\n' "$1"
  }
  parse "$(fetch '   ❯ 1. run it')"
  p11=$MSP_PRINT
  parse "$(fetch '     1. run it')"
  [ "$p11" != "$MSP_PRINT" ] || fail "a body line above an unsigned question shares a digest with its uncursored twin"
  wrapped=$(awk '{ print } /^   2\. Yes, and/ { print "      and every later call" }' "$tmp/dialog.txt")
  parse "$wrapped"
  p9=$MSP_PRINT
  parse "$(printf '%s\n' "$wrapped" | sed 's/^ ❯ 1\. Yes$/   1. Yes/; s/^   2\. Yes, and/ ❯ 2. Yes, and/')"
  [ "$p9" = "$MSP_PRINT" ] || fail "moving the cursor over a wrapped run changed the digest"
  rec="$tmp/rec"
  printf 'dialog\t11\t22\t0123456789abcdef\tdialog\n' >"$rec"
  msp_record "$rec" && [ "$MSP_REC_FIRST/$MSP_REC_SESS/$MSP_REC_PRINT" = 11/22/0123456789abcdef ] \
    || fail "the dialog record read as '$MSP_REC_FIRST/$MSP_REC_SESS/$MSP_REC_PRINT'"
  if [ "$(id -u)" != 0 ]; then
    chmod 000 "$rec"
    msp_record "$rec"
    r=$?
    chmod 644 "$rec"
    [ "$r" = 1 ] || fail "an unreadable dialog record read as $r"
  fi
  awk() {
    rm -f "$rec"
    command awk "$@"
  }
  msp_record "$rec"
  r=$?
  unset -f awk
  [ "$r" = 2 ] || fail "a dialog record that vanished mid-read read as $r"
  # busybox ps: no -ww, and the user column cut to 8 characters. This
  # shell's pid and a sleep's are this user's; the fixture pid is no process.
  mkdir -p "$tmp/bb"
  cat >"$tmp/bb/ps" <<EOF
#!/bin/sh
case "\$*" in
  '-o pid,ppid,user,args') cat "$tmp/bb.out" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$tmp/bb/ps"
  id() { case $1 in -u) command id -u ;; -un) echo averylongusername ;; *) command id "$@" ;; esac }
  bb_find() {
    {
      printf '  PID  PPID USER     COMMAND\n'
      for p in "$@"; do printf '%s 1 averylon claude --name x /planwright:mission-control alpha\n' "$p"; done
    } >"$tmp/bb.out"
    msp_find alpha "$(PATH="$tmp/bb:$PATH" /bin/sh -c "$MSP_PS_CMD")"
  }
  [ "$(bb_find "$SP")" = absent ] || fail "busybox ps: a process this user does not own read as '$(bb_find "$SP")'"
  if [ -d "/proc/$$" ]; then
    sleep 60 >/dev/null 2>&1 &
    bg=$!
    [ "$(bb_find $$ "$SP")" = $$ ] || fail "busybox ps: the session under a long user name read as '$(bb_find $$ "$SP")'"
    [ "$(bb_find $$ "$bg")" = ambiguous ] || fail "busybox ps: two sessions read as '$(bb_find $$ "$bg")'"
    if [ "$(command id -u)" != 0 ] && [ ! -O /proc/1 ]; then
      [ "$(bb_find $$ 1)" = $$ ] || fail "busybox ps: another account's process under the same cut name read as '$(bb_find $$ 1)'"
    fi
    kill "$bg" 2>/dev/null
  fi
  unset -f id
  exit "$pfail"
); then
  ok "the parser cases, the dialog record and busybox ps"
else
  fail "the parser cases above"
fi

answer --help
expect_rc "help" 0
answer --program alpha --choice 1 --decision "$D1" --decided-in hub --pane %3
expect_rc "a caller-named pane is not an argument" 2

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-pane-answer tests passed"
