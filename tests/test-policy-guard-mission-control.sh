#!/bin/bash
# The mission-control tier of scripts/policy-guard.sh: the tower tier's
# denials, every git mutation, settings and repository writes, and a ready
# flip only inside ready_flip_policy (mission-control REQ-A1.3, REQ-G1.4,
# REQ-I1.1, REQ-I1.2, REQ-I1.4). The rows live in
# tests/fixtures/mission-control-guard-acts.tsv; the harness is the policy
# guard suites' own.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

ROWS="$REPO_ROOT/tests/fixtures/mission-control-guard-acts.tsv"
SCRATCH="$SANDBOX/scratch"
FIXHOME="$SANDBOX/fixhome"
mkdir -p "$SCRATCH/proj/.claude" "$FIXHOME/.claude"
gitq init --bare "$SCRATCH/bare.git"
# A link to a .claude directory whose hooks directory does not exist yet.
ln -s "$FIXHOME/.claude" "$SCRATCH/cl"
TAB=$(printf '\t')

# pg_file <tier> <tool> <path> — run the guard on a file-tool payload.
pg_file() {
  local key=file_path payload
  [ "$2" != NotebookEdit ] || key=notebook_path
  payload=$(jq -n --arg t "$2" --arg k "$key" --arg p "$3" --arg w "$UNIT" \
    '{tool_name:$t, tool_input:{($k):$p, content:"x"}, cwd:$w}')
  pg_payload "$1" file "$payload"
}

pg_mcp() { # <tier> <tool_input json>
  pg_payload "$1" mcp "$(jq -n --argjson i "$2" --arg w "$UNIT" '{tool_name:"mcp__github__update_pull_request", tool_input:$i, cwd:$w}')"
}

fill() { # <input> — the row with its placeholders filled
  local s=$1
  s=${s//@UNIT@/$UNIT}
  s=${s//@SCRATCH@/$SCRATCH}
  s=${s//@HOME@/$FIXHOME}
  printf '%s' "$s"
}

echo "# the fixture rows"
rows=0
denies=0
defers=0
classes=' '
while IFS="$TAB" read -r want class surface knob reason input; do
  case $want in '' | '#'*) continue ;; esac
  rows=$((rows + 1))
  case " $classes " in *" $class "*) ;; *) classes="$classes$class " ;; esac
  if [ "$knob" = - ]; then
    set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'
  else
    set_knobs "$knob"
  fi
  input=$(fill "$input")
  case $surface in
    bash) pg mission-control "$input" ;;
    file) pg_file mission-control "${input%% *}" "${input#* }" ;;
    mcp) pg_mcp mission-control "$input" ;;
    *)
      fail "row $rows names an unknown surface '$surface'"
      continue
      ;;
  esac
  expect "$want" "[mission-control] $class: $input"
  [ "$want" != deny ] || [ "$reason" = - ] || reason_has "$reason" "[mission-control] $class refused for its own reason: $input"
  case $want in
    deny) denies=$((denies + 1)) ;;
    defer) defers=$((defers + 1)) ;;
  esac
done <"$ROWS"

for c in git-mutation merge mcp-flip gh-write settings-write repo-write flip-outside flip-other-repo rewrite protected-push remote-delete flip-inside read; do
  case "$classes" in
    *" $c "*) pass "the table carries a $c row" ;;
    *) fail "the table carries no $c row" ;;
  esac
done
if [ "$denies" -gt 0 ] && [ "$defers" -gt 0 ]; then
  pass "the table holds $denies refused and $defers permitted rows"
else
  fail "the table must hold both refused and permitted rows (refused $denies, permitted $defers)"
fi

echo "# what each refusal reads"
pg mission-control 'git commit -m wip'
reads none "a git mutation is refused with no policy read"
reason_has 'mission control runs no git mutation' "the git-mutation refusal names the rule"
pg mission-control 'gh api -X DELETE repos/acme/widgets/git/refs/heads/planwright/demo/task-2'
reads none "a host ref write is refused with no protected-set read"
set_knobs 'ready_flip_policy: unit-owner'
pg mission-control 'gh pr ready 42'
reads ready_flip_policy "a flip reads only ready_flip_policy"
set_knobs 'ready_flip_policy: human'
pg mission-control 'gh pr ready 42'
reason_has 'ready_flip_policy is human' "the out-of-policy flip names the knob"
pg_file mission-control Write "$FIXHOME/.claude/settings.json"
reason_has 'settings' "the settings refusal names settings"
pg_file mission-control Write "$UNIT/README.md"
reason_has 'repository' "the repository-write refusal names the repository"

echo "# the file surface at the other tiers, and malformed file payloads"
for tier in worker tower ''; do
  pg_file "$tier" Write "$FIXHOME/.claude/settings.json"
  expect defer "[${tier:-none}] the file surface is the mission-control tier's alone"
done
pg_payload mission-control file '{"tool_name":"Write","tool_input":{"content":"x"}}'
expect deny "[mission-control] a file payload with no path is refused"
pg_payload mission-control file '{"tool_name":"Write","tool_input":{"file_path":"relative/x.md"}}'
expect deny "[mission-control] a relative path is refused"
pg_file mission-control Write "$SCRATCH/../repo-escape/x/../../unit/README.md"
expect deny "[mission-control] a path with a dot-dot component is refused"
pg_file mission-control NotebookEdit "$UNIT/nb.ipynb"
expect deny "[mission-control] a notebook edit inside a repository is refused"
pg_payload mission-control file "$(jq -n --arg s "$SCRATCH/ok.txt" --arg r "$UNIT/nb.ipynb" \
  '{tool_name:"NotebookEdit", tool_input:{file_path:$s, notebook_path:$r}}')"
expect deny "[mission-control] every path field is checked, not only the first"
long=$(printf 'x%.0s' $(seq 1 17000))
pg mission-control "cat ~/.claude/settings.json $long"
expect deny "[mission-control] an over-long command naming a settings file is refused without parsing"

no_gh_calls
finish
