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
# The installed-root screen reads the plugin cache under the user's home.
export HOME="$FIXHOME"
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
  [ "$want" = defer ] || [ "$reason" = - ] || reason_has "$reason" "[mission-control] $class refused for its own reason: $input"
  case $want in
    deny) denies=$((denies + 1)) ;;
    defer) defers=$((defers + 1)) ;;
  esac
done <"$ROWS"

for c in git-mutation merge mcp-flip gh-write settings-write repo-write flip-human flip-other-repo rewrite protected-push remote-delete flip-inside read; do
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
expect ask "[mission-control] a flip under human asks the operator"
reads ready_flip_policy "the asked flip read only ready_flip_policy"
pg mission-control 'gh pr ready 42 && git commit -m wip'
expect deny "[mission-control] a refusal elsewhere in the command outranks the flip's ask"
pg worker 'gh pr ready 42'
expect deny "[worker] a flip under human still denies at the worker tier"
set_knobs 'ready_flip_policy: unit-owner'
GH_REPO=employer/widgets pg mission-control 'gh pr ready 42'
expect deny "[mission-control] a flip under a GH_REPO the session inherited is refused"
many=''
for _ in $(seq 1 70); do many="$many git status;"; done
start=$SECONDS
pg mission-control "sh -c '$many'"
expect deny "[mission-control] a wrapped text past the git-invocation bound is refused"
if [ $((SECONDS - start)) -lt 10 ]; then
  pass "the bounded wrapped-text screen answers quickly"
else
  fail "the wrapped-text screen took $((SECONDS - start))s"
fi
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
pg mission-control "cat $FIXHOME/.claude/settings.json $long"
expect deny "[mission-control] an over-long command naming a settings file is refused without parsing"

echo "# a flip in another repository the program lists reads that repository's policy"
# A stand-in for the program reader: programs.tsv rows are <program><TAB><path>.
PROGS="$SANDBOX/programs.tsv"
cat >"$S/mc-program.sh" <<EOF
#!/bin/sh
case "\$1" in
  list) cut -f1 "$PROGS" | sort -u ;;
  get) [ "\$3" = repositories ] && awk -F'\t' -v p="\$2" '\$1 == p { print \$2 }' "$PROGS" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$S/mc-program.sh"
WIDGETS="$SANDBOX/widgets"
DUP="$SANDBOX/widgets-dup"
GADGETS="$SANDBOX/gadgets"
for r in "$WIDGETS:acme/widgets" "$DUP:acme/widgets" "$GADGETS:acme/gadgets"; do
  clone_on "${r%%:*}" main 0
  gitq -C "${r%%:*}" remote set-url origin "https://github.com/${r#*:}.git"
done
mkdir -p "$WIDGETS/.claude" "$GADGETS/.claude"
printf 'ready_flip_policy: human\n' >"$WIDGETS/.claude/planwright.yml"
printf 'ready_flip_policy: unit-owner\n' >"$GADGETS/.claude/planwright.yml"
set_knobs ''
printf 'alpha\t%s\nalpha\t%s\n' "$WIDGETS" "$GADGETS" >"$PROGS"

pg mission-control 'gh pr ready 42 --repo acme/widgets'
expect ask "[mission-control] a flip in a listed repository under human asks, as that repository's policy says"
reads ready_flip_policy "the named repository's flip reads only ready_flip_policy"
pg mission-control 'gh pr ready 42 -R acme/widgets'
expect ask "[mission-control] -R names the listed repository too"
pg mission-control 'gh -R acme/widgets pr ready 42'
expect ask "[mission-control] a global -R names the listed repository too"
pg mission-control 'gh pr ready 42 --repo=acme/widgets'
expect ask "[mission-control] --repo= names the listed repository too"
pg mission-control 'gh pr ready 42 --repo ACME/Widgets'
expect ask "[mission-control] the repository name matches regardless of case"
pg mission-control 'gh pr ready 42 --repo acme/gadgets'
expect defer "[mission-control] a listed repository under unit-owner defers to the ready-guard"
pg mission-control 'gh pr ready 42 --repo acme/widgets && git commit -m wip'
expect deny "[mission-control] a refusal elsewhere in the command outranks the other repository's ask"

pg mission-control 'gh pr ready 42 --repo acme/unlisted'
expect deny "[mission-control] a repository no program lists is refused"
reason_has 'names a repository' "the unlisted refusal names the rule"
pg mission-control 'gh pr ready 42 --repo acme/widgets --repo acme/gadgets'
expect deny "[mission-control] two repository selectors are refused"
pg mission-control 'gh pr ready https://github.com/acme/widgets/pull/42'
expect deny "[mission-control] a PR URL is refused"
pg mission-control 'gh pr ready 42 --repo github.example.com/acme/widgets'
expect deny "[mission-control] a host-qualified repository is refused"
# shellcheck disable=SC2016 # the guard must see the expansion literally
pg mission-control 'gh pr ready 42 --repo acme/wid$(id)gets'
expect deny "[mission-control] an expanded repository name is refused"
pg mission-control 'gh pr ready 42 --repo ../widgets'
expect deny "[mission-control] a path as the repository is refused"
GH_HOST=github.example.com pg mission-control 'gh pr ready 42 --repo acme/widgets'
expect deny "[mission-control] a GH_HOST the session inherited is refused"
GH_REPO=acme/widgets pg mission-control 'gh pr ready 42 --repo acme/widgets'
expect deny "[mission-control] a GH_REPO the session inherited is refused"
pg mission-control 'GH_HOST=github.example.com gh pr ready 42 --repo acme/widgets'
expect deny "[mission-control] an inline GH_HOST is refused"
pg mission-control "cd $SCRATCH && gh pr ready 42 --repo acme/widgets"
expect ask "[mission-control] a followable directory change does not move the named repository's policy"
pg mission-control "cd ../x && gh pr ready 42 --repo acme/widgets"
expect deny "[mission-control] a flip after a directory change the guard cannot follow is refused"
pg worker 'gh pr ready 42 --repo acme/widgets'
expect defer "[worker] the worker tier does not read the program list"

printf 'alpha\t%s\nbeta\t%s\n' "$WIDGETS" "$DUP" >"$PROGS"
pg mission-control 'gh pr ready 42 --repo acme/widgets'
expect deny "[mission-control] a repository two different checkouts answer to is refused as ambiguous"
printf 'alpha\t%s\nbeta\t%s\n' "$WIDGETS" "$WIDGETS" >"$PROGS"
pg mission-control 'gh pr ready 42 --repo acme/widgets'
expect ask "[mission-control] one checkout listed by two programs is not ambiguous"
printf 'alpha\t%s\n' "$SANDBOX/not-a-checkout" >"$PROGS"
pg mission-control 'gh pr ready 42 --repo acme/widgets'
expect deny "[mission-control] a listed path that is no checkout is refused"
rm -f "$PROGS"
pg mission-control 'gh pr ready 42 --repo acme/widgets'
expect deny "[mission-control] an unreadable program list is refused"
rm -f "$S/mc-program.sh"
pg mission-control 'gh pr ready 42 --repo acme/widgets'
expect deny "[mission-control] a missing program reader is refused"

no_gh_calls
finish
