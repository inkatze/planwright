#!/bin/sh
# Tests for step-record.sh write's head handling: heads default from git when
# omitted, a head recorded by the run's own begin record is preferred for the
# step's start, an omitted start head on a skill step that changed the head is
# refused rather than guessed, and a given sha must be the full id of a commit
# in the worktree's repository.
#
#   ./tests/test-step-record-heads.sh
# shellcheck disable=SC2319,SC2154 # verdicts judge the condition just before; the fixture sets wt and bin
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
RUN="$repo_root/scripts/step-run.sh"
SR="$repo_root/scripts/step-record.sh"
TAB=$(printf '\t')
# shellcheck source=tests/lib/step-run-fixture.sh
. "$here/lib/step-run-fixture.sh"

# Real-looking times: the truth check refuses a skill step window under 30
# seconds, of whole minutes, or starting on seconds :00.
TS=2026-11-14T10:00:13Z
TE=2026-11-14T10:01:20Z
# w <run> <step> <kind> <outcome> [flags...]: one pre-pr step record.
w() {
  _r=$1 _s=$2 _k=$3 _o=$4
  shift 4
  sr write --run "$_r" --point pre-pr --step "$_s" --kind "$_k" --target "$_s" --hosting in-session \
    --backend in-session --start "$TS" --end "$TE" --outcome "$_o" "$@" >"$tmp/out" 2>"$tmp/err"
  WRC=$?
}
field() { # field <run> <key>: the key's value in the run's pre-pr record
  recs "$1" pre-pr | sed -n "s/^$2${TAB}//p" | head -n 1
}
commit() {
  printf '%s\n' "$1" >>"$wt/src/a.txt"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m "chore: $1"
}

fresh
h0=$(head_of)
commit one
h1=$(head_of)

r=$(sr new-run)
w "$r" skill-a skill passed
[ "$WRC" -eq 0 ] && [ "$(field "$r" head)" = "$h1" ] && [ "$(field "$r" end-head)" = "$h1" ]
verdict $? "omitted heads default to HEAD for a step that left it unchanged" "rc $WRC err: $(cat "$tmp/err")"

r=$(sr new-run)
w "$r" skill-a skill passed --head "$(printf '%s' "$h0" | cut -c1-10)"
[ "$WRC" -eq 2 ] && grep -q -- '--head' "$tmp/err" && grep -Fq 'git rev-parse HEAD' "$tmp/err"
verdict $? "a short sha is refused, naming the full-sha fix" "rc $WRC err: $(cat "$tmp/err")"
r=$(sr new-run)
w "$r" skill-a skill passed --head "$h0" --end-head "$(printf '%s' "$h1" | cut -c1-12)"
[ "$WRC" -eq 2 ] && grep -q -- '--end-head' "$tmp/err"
verdict $? "a short end head is refused" "rc $WRC err: $(cat "$tmp/err")"

r=$(sr new-run)
w "$r" skill-a skill passed --head "0000000000000000000000000000000000000000"
[ "$WRC" -eq 2 ] && grep -q "0000000000000000000000000000000000000000" "$tmp/err"
verdict $? "a full sha that is no commit is refused naming it" "rc $WRC err: $(cat "$tmp/err")"

git -C "$wt" checkout -q -b other "$h0"
commit elsewhere
hx=$(head_of)
git -C "$wt" checkout -q -
r=$(sr new-run)
w "$r" skill-a skill applied --head "$h1" --end-head "$hx"
[ "$WRC" -eq 0 ] && [ "$(field "$r" end-head)" = "$hx" ]
verdict $? "a commit of the repository off the current branch is accepted as a head" "rc $WRC err: $(cat "$tmp/err")"

# A skill step that changed the head and has no begin record is not guessed at.
r=$(sr new-run)
w "$r" skill-a skill applied
[ "$WRC" -eq 2 ] && grep -q -- '--head' "$tmp/err" && grep -qi 'begin' "$tmp/err"
verdict $? "an applied skill step with no --head and no begin record is refused" "rc $WRC err: $(cat "$tmp/err")"
r=$(sr new-run)
w "$r" skill-a skill passed --end-head "$h0"
[ "$WRC" -eq 2 ] && grep -q -- '--head' "$tmp/err"
verdict $? "a skill step whose end head is not HEAD, with no --head and no begin record, is refused" "rc $WRC err: $(cat "$tmp/err")"
r=$(sr new-run)
w "$r" skill-a skill applied --head "$h0"
[ "$WRC" -eq 0 ] && [ "$(field "$r" head)" = "$h0" ] && [ "$(field "$r" end-head)" = "$h1" ]
verdict $? "an applied skill step with its start head given records it, and HEAD as the end" "rc $WRC err: $(cat "$tmp/err")"
r=$(sr new-run)
w "$r" prompt-a prompt applied
[ "$WRC" -eq 2 ] && grep -q -- '--head' "$tmp/err" && grep -q 'prompt step changed the head' "$tmp/err"
verdict $? "an applied prompt step with no --head and no begin record is refused" "rc $WRC err: $(cat "$tmp/err")"
r=$(sr new-run)
w "$r" cmd-a command applied --end-head "$h0"
[ "$WRC" -eq 0 ] && [ "$(field "$r" head)" = "$h1" ]
verdict $? "a command step with no --head and no begin record takes HEAD unrefused" "rc $WRC err: $(cat "$tmp/err")"
r=$(sr new-run)
w "$r" skill-a skill skipped --skip-code missing --skip-reason gone --end-head "$h0"
[ "$WRC" -eq 0 ] && [ "$(field "$r" head)" = "$h1" ]
verdict $? "a skipped skill step is not refused for an end head other than HEAD" "rc $WRC err: $(cat "$tmp/err")"

# A begin record's head that names no commit is refused, not recorded.
r=$(sr new-run)
printf 'head\t%s\n' deadbeefdeadbeefdeadbeefdeadbeefdeadbeef >"$wt/.claude/steps/$r/runner-pending-pre-pr-skill-b"
w "$r" skill-b skill passed
[ "$WRC" -eq 2 ] && grep -q deadbeefdeadbeefdeadbeefdeadbeefdeadbeef "$tmp/err" && [ -z "$(recs "$r" pre-pr)" ]
verdict $? "a begin record naming no commit is refused and nothing is stored" "rc $WRC err: $(cat "$tmp/err")"

# The run's own begin record supplies the start head.
fresh
catalog "show|kind: command|target: $bin/show.sh|hosting: in-session"
config 'steps_pre_pr: [show]'
hb=$(head_of)
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >"$tmp/rows" 2>"$tmp/err"
srun begin --run "$r" --point pre-pr --step show --owner "$(owner)" >"$tmp/out" 2>>"$tmp/err"
commit moved
hm=$(head_of)
w "$r" show command applied
[ "$WRC" -eq 0 ] && [ "$(field "$r" head)" = "$hb" ] && [ "$(field "$r" end-head)" = "$hm" ]
verdict $? "the begin record's head is the start head and HEAD the end when --head is omitted" \
  "rc $WRC err: $(cat "$tmp/err") head: $(field "$r" head) end: $(field "$r" end-head) want $hb $hm"

# A branch named like an abbreviation is not mistaken for the commit id.
fresh
commit one
git -C "$wt" branch deadbee "$(git -C "$wt" rev-parse HEAD~1)"
r=$(sr new-run)
w "$r" skill-a skill passed --head deadbee
[ "$WRC" -eq 2 ] && grep -q 'not a full commit id' "$tmp/err"
verdict $? "a hex-looking ref name is refused rather than read as an abbreviation" "rc $WRC err: $(cat "$tmp/err")"

# A command step that rewrites history still records its start head.
fresh
catalog "amend|kind: command|target: $bin/amend.sh"
config 'steps_pre_pr: [amend]'
cat >"$bin/amend.sh" <<'EOF'
#!/bin/sh
git commit -q --amend --allow-empty -m "chore: rewritten"
EOF
chmod +x "$bin/amend.sh"
ha=$(head_of)
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >"$tmp/rows" 2>"$tmp/err"
srun command --run "$r" --point pre-pr --step amend >"$tmp/out" 2>>"$tmp/err"
[ "$(field "$r" head)" = "$ha" ] && [ "$(field "$r" end-head)" = "$(head_of)" ] && [ "$ha" != "$(head_of)" ]
verdict $? "a command step that amends HEAD is recorded with its start head" "err: $(cat "$tmp/err") out: $(cat "$tmp/out")"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all step-record head tests passed"
