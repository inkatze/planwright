#!/bin/bash
# Tests for scripts/mc-pane-answer.sh — the one relay that delivers an
# operator's recorded choice to a dialog a mission control is stuck on: a
# single digit, into that program's own mission-control pane, against a
# decision of the operator's recorded after the dialog appeared. Every
# refusal has its case here.
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
{
  printf 'mission_control_programs: [alpha, hub]\n'
  for p in alpha hub; do
    printf 'program_%s_repositories: [%s]\n' "$p" "$repo"
    printf 'program_%s_spec_root: %s/specs\n' "$p" "$repo"
    printf 'program_%s_home: %s/mchome-%s\n' "$p" "$tmp" "$p"
  done
  printf 'mission_control_escalation_hub: none\n'
} >"$tracked"

# Stubs. ps: the fixture table, then this host's real table with every real
# mission-control session left out, so the caller's own ancestry is real;
# any other flags reach the real ps. tmux: panes and captures from files,
# send-keys recorded to $tmp/keys (failing when $tmp/send-fails exists).
real_ps=$(command -v ps)
uid=$(id -u)
mkdir -p "$tmp/bin"
cat >"$tmp/bin/ps" <<EOF
#!/bin/sh
case "\$*" in
  '-ww -A -o pid= -o ppid= -o uid= -o args=')
    cat "$tmp/ps.out" 2>/dev/null
    "$real_ps" "\$@" | grep -v -F '/planwright:mission-control'
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
    ;;
  send-keys)
    shift
    printf '%s\n' "\$*" >>"$tmp/keys"
    [ ! -e "$tmp/send-fails" ]
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/ps" "$tmp/bin/tmux"
PATH="$tmp/bin:$PATH"
export PATH

cat >"$tmp/pane-%7" <<'EOF'
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
printf '  500  400 %s claude --name alpha-mission-control /planwright:mission-control alpha\n' "$uid" >"$tmp/ps.out"
printf '%%7\t400\n' >"$tmp/panes"

esc() { mc_run mc-escalate.sh "$@"; }
answer() {
  OUT=$(mc_env env TMUX_PANE=%99 /bin/bash "$repo_root/scripts/mc-pane-answer.sh" "$@" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
note() { # note <shape> <text>: an operator note in hub's decisions log; prints its id
  mc_env /bin/bash "$repo_root/scripts/mc-decide.sh" note --program hub --shape "$1" --subject "alpha dialog" --text "$2" --target "$2" 2>"$tmp/note.err" | awk -F '\t' '{ print $2 }'
}
keys() { cat "$tmp/keys" 2>/dev/null; }
refused() { # refused <label> <stderr needle>
  expect_rc "$1" 4
  expect_err "$1: named" "$2"
  [ -z "$(keys)" ] || fail "$1: a key was sent: $(keys)"
}

mc_run mc-kb.sh init --program hub
expect_rc "the hub's knowledge base" 0

# The watcher records the dialog (first sight, session, digest) first.
esc scan --program alpha
expect_rc "the watcher records the open dialog" 0
expect_out "as auto mode's confirmation, in pane %7" "self${tab}auto-mode${tab}0${tab}owner${tab}%7"
sleep 1
D1=$(note answer "1")
if [ -n "$D1" ]; then ok "an operator answer is recorded ($D1)"; else fail "no decision id from mc-decide.sh note: $(cat "$tmp/note.err")"; fi

# --- the arguments ----------------------------------------------------------
for bad in 0 10 a "1 " "" "-1"; do
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

# --- the decision -------------------------------------------------------------
NQ=$(mc_env /bin/bash "$repo_root/scripts/mc-decide.sh" decide --program hub --subject "alpha dialog" --act "answer it" --grounds "routine" --class hygiene 2>/dev/null | awk -F '\t' '{ print $2 }')
answer --program alpha --choice 1 --decision "$NQ" --decided-in hub
refused "a decision that is not the operator's words" "operator's words"
esc_dir="$fleet/mission-control/alpha/escalate"
cp "$esc_dir/self" "$tmp/self.saved"
IFS="$tab" read -r _ first sess print _ <"$esc_dir/self"
printf 'dialog\t%s\t%s\t%s\n' $((first + 86400)) "$sess" "$print" >"$esc_dir/self"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a decision older than the dialog" "predates the dialog"
rm -f "$esc_dir/self"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "no dialog on record" "no dialog of alpha is on record"
cp "$tmp/self.saved" "$esc_dir/self"

# --- the session and its pane -------------------------------------------------
cp "$tmp/ps.out" "$tmp/ps.saved"
: >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "no session running" "no mission-control session of alpha is running"
printf '  500  400 %s claude /planwright:mission-control alpha\n  501  400 %s claude /planwright:mission-control alpha\n' "$uid" "$uid" >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "two sessions running" "more than one"
printf '  510  400 %s claude /planwright:mission-control alpha\n' "$uid" >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a session other than the one on record" "not the one whose dialog is on record"
printf '  500  400 4242424 claude /planwright:mission-control alpha\n' >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "another account's process is never the session" "no mission-control session of alpha is running"
cp "$tmp/ps.saved" "$tmp/ps.out"
: >"$tmp/panes"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a session with no pane" "has no tmux pane"
printf '%%7\t400\n' >"$tmp/panes"
OUT=$(mc_env env TMUX_PANE=%7 /bin/bash "$repo_root/scripts/mc-pane-answer.sh" --program alpha --choice 1 --decision "$D1" --decided-in hub 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
refused "the caller's own pane" "the caller's own"
# The caller runs under the pane: the pane's process is this test's shell.
printf '%%7\t%s\n' "$$" >"$tmp/panes"
printf '  500  %s %s claude /planwright:mission-control alpha\n' "$$" "$uid" >"$tmp/ps.out"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a pane the caller runs under" "one the caller runs under"
cp "$tmp/ps.saved" "$tmp/ps.out"
printf '%%7\t400\n' >"$tmp/panes"

# --- the dialog -------------------------------------------------------------
cp "$tmp/pane-%7" "$tmp/pane.saved"
printf '  ? for shortcuts\n> \n' >"$tmp/pane-%7"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "no open dialog" "shows no open dialog"
sed 's/4 consecutive/9 consecutive/; s/answer \*$/steer */' "$tmp/pane.saved" >"$tmp/pane-%7"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a different dialog from the one on record" "a different dialog"
cp "$tmp/pane.saved" "$tmp/pane-%7"
answer --program alpha --choice 4 --decision "$D1" --decided-in hub
refused "an option the dialog does not offer" "offers no option 4"
answer --program alpha --choice 2 --decision "$D1" --decided-in hub
refused "an option that adds a standing permission" "adds a standing permission"

# --- delivery -----------------------------------------------------------------
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
expect_rc "a decided choice is delivered" 0
expect_out "naming the pane, digit and option" "answered${tab}alpha${tab}%7${tab}1${tab}Yes"
if [ "$(keys)" = "-t %7 1" ]; then ok "exactly one digit is sent to that pane"; else fail "keys sent: '$(keys)'"; fi
if grep -q "${tab}${D1}${tab}hub${tab}1${tab}%7${tab}500${tab}sent$" "$esc_dir/answers.log"; then
  ok "the answer is logged against the decision"
else
  fail "answers.log: $(cat "$esc_dir/answers.log" 2>/dev/null)"
fi
: >"$tmp/keys"
answer --program alpha --choice 1 --decision "$D1" --decided-in hub
refused "a decision already used" "already answered a dialog"
D2=$(note correction "pick no")
touch "$tmp/send-fails"
answer --program alpha --choice 3 --decision "$D2" --decided-in hub
expect_rc "a failed send" 1
rm -f "$tmp/send-fails"
if grep -q "${tab}${D2}${tab}hub${tab}3${tab}%7${tab}500${tab}failed$" "$esc_dir/answers.log"; then
  ok "a failed send is logged and uses the decision"
else
  fail "answers.log after a failed send: $(cat "$esc_dir/answers.log")"
fi
: >"$tmp/keys"
answer --program alpha --choice 3 --decision "$D2" --decided-in hub
refused "a decision a failed send used" "already answered a dialog"

answer --help
expect_rc "help" 0
answer --program alpha --choice 1 --decision "$D1" --decided-in hub --pane %3
expect_rc "a caller-named pane is not an argument" 2

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-pane-answer tests passed"
