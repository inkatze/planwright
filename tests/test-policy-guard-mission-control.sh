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
# Links into posture from a plain directory, the link targets spelled every way
# a target can be, for the table's write-through-a-link rows.
KB="$SCRATCH/kb"
MEM="$FIXHOME/.claude/projects/p/memory"
mkdir -p "$KB" "$MEM" "$FIXHOME/.claude/agents" "$FIXHOME/.config/planwright"
: >"$FIXHOME/.claude/settings.json"
: >"$FIXHOME/.config/planwright/planwright.yml"
: >"$KB/real.md"
ln -s "$FIXHOME/.claude/settings.json" "$KB/lk-file"
ln -s "$FIXHOME//.claude/./settings.json" "$KB/lk-dslash"
ln -s "$FIXHOME/.claude/../.claude/settings.json" "$KB/lk-dotdot"
ln -s ../../fixhome/.claude/settings.json "$KB/lk-rel"
# A literal ~ in a link target is a relative name; this one leads home.
ln -s "$FIXHOME" "$KB/~"
# shellcheck disable=SC2088 # the target is the literal ~ name
ln -s '~/.claude/settings.json' "$KB/lk-tilde"
ln -s lk-file "$KB/lk-chain"
ln -s "$FIXHOME/.config/planwright/planwright.yml" "$KB/lk-overlay"
ln -s "$FIXHOME/.claude/agents/new.md" "$KB/lk-dangling"
ln -s "$FIXHOME/.claude" "$KB/lk-dir"
ln -s "$FIXHOME/.claude/agents" "$KB/lk-agents"
ln -s "$KB/real.md" "$KB/lk-plain"
ln -s "$FIXHOME/.claude/settings.json" "$FIXHOME/notes.md"
ln -s "$FIXHOME/.claude/settings.json" "$MEM/lk-mem"
ln -s "$FIXHOME/.claude/settings.json" "$KB/a b"
ln -s "$FIXHOME/.claude/settings.json" "$KB/lk1"
# A link to a posture directory not made yet, a link to itself, a link into
# the projects folder, and a link to an MCP server list.
ln -s "$FIXHOME/.claude/hooks" "$KB/ld"
ln -s loop "$KB/loop"
ln -s "$FIXHOME/.claude/projects" "$KB/lk-projects"
: >"$FIXHOME/.mcp.json"
ln -s "$FIXHOME/.mcp.json" "$KB/lk-mcp"
mkdir -p "$KB/sub" "$SCRATCH/x"
# A plain file whose name is a link in kb, for a copy into kb.
: >"$SCRATCH/x/lk-file"
# A plain directory holding a link to a work tree, for a write through it.
mkdir -p "$SCRATCH/rl"
ln -s "$UNIT" "$SCRATCH/rl/unit"
TAB=$(printf '\t')
NL=$'\n'

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

echo "# a relative write target, followed from where the command runs"
pg mission-control 'echo x >> lk-file' "$KB"
expect deny "[mission-control] a relative write through a link into posture is refused"
pg mission-control 'echo x >> ./lk-chain' "$KB"
expect deny "[mission-control] a ./ write through a chained link is refused"
pg mission-control 'echo x >> lk-dir/agents/x.md' "$KB"
expect deny "[mission-control] a relative write through a link to a posture directory is refused"
pg mission-control '(echo x > lk-file)' "$KB"
expect deny "[mission-control] a relative write through a link inside a subshell is refused"
pg mission-control 'ln -s lk-agents c && echo x >> c/x.md' "$KB"
expect deny "[mission-control] a relative link source leading into posture is refused"
pg mission-control 'cd kb && echo x >> real.md' "$SCRATCH"
expect deny "[mission-control] a relative write after a directory change the guard cannot place is refused"
pg mission-control 'cd - && echo x >> real.md' "$KB"
expect deny "[mission-control] a relative write after cd - is refused"
pg mission-control 'cd && echo x >> notes.md' "$KB"
expect deny "[mission-control] a bare cd goes home, and a relative write there is followed"
pg mission-control 'echo x >> real.md' "$KB"
expect defer "[mission-control] a relative write to a plain file is permitted"
pg mission-control "cd $KB && echo x >> lk-plain" "$UNIT"
expect defer "[mission-control] a relative write through a link to a plain file is permitted"
pg_payload mission-control bash "$(jq -n '{tool_name:"Bash", tool_input:{command:"echo x >> real.md"}, cwd:7}')"
expect deny "[mission-control] a relative write under a cwd the guard cannot read is refused"

echo "# an in-place editor or write the screen reads only as text, into a repository"
pg mission-control "bash <<'EOF'${NL}perl -pi -e s/a/b/ $SCRATCH/kb/real.md${NL}EOF"
expect deny "[mission-control] an in-place editor in a here-document a shell reads is refused"
reason_has 'edits no repository' "[mission-control] the here-document in-place refusal names the repository rule"
pg mission-control "cd $KB && cat > notes.md <<'EOF'${NL}text${NL}EOF"
expect defer "[mission-control] a store heredoc after the one cd, from a repository cwd, is permitted"
TMPDIR=$UNIT pg mission-control 'S=$(mktemp -d); echo x > "$S/x"'
expect deny "[mission-control] a write under a fresh mktemp -d directory is refused when TMPDIR lies in a repository"
reason_has 'edits no repository' "[mission-control] the mktemp-in-repository refusal names the repository rule"
for c in 'echo x >&2' 'echo x >&-' '(echo x >&2)' 'echo x >&2-' 'echo x 2>&1'; do
  pg mission-control "$c" "$FIXHOME/.claude/agents"
  expect defer "[mission-control] a descriptor duplication opens no file, even from a posture directory: $c"
done
pg mission-control "cd$NL/bin$NL echo x >> notes.md" "$KB"
expect deny "[mission-control] a cd ending its line goes home, never to the next line's word"
pg mission-control "echo x >> $FIXHOME/.claude/settin\\${NL}gs.json"
expect deny "[mission-control] a backslash-newline inside a target is joined as the shell joins it"
pg mission-control "echo x > \\${NL}$KB/lk-file"
expect deny "[mission-control] a backslash-newline before a target hides nothing"
pg mission-control "echo a #\"${NL}echo y >> $FIXHOME/.claude/agents/x.md #\""
expect deny "[mission-control] quotes paired across a comment hide no redirect"
pg mission-control "cat <<'EOF'${NL}\"${NL}EOF${NL}echo y >> $KB/lk-file${NL}cat <<'EOF'${NL}\"${NL}EOF"
expect deny "[mission-control] quotes paired across here-documents hide no redirect"
for c in "echo \"<<A\"${NL}cd $KB${NL}echo x > lk-file${NL}A" "echo \$((1<<2))${NL}cd $KB${NL}echo x > lk-file${NL}2" \
  "echo hi # <<EOF${NL}cd $KB${NL}echo x > lk-file" "cat <<E\"O\"F${NL}x${NL}EOF${NL}cd $KB${NL}echo x > lk-file" \
  "X=cd; \$X $KB${NL}echo x > lk-file" "\$'\\x63d' $KB${NL}echo x > lk-file"; do
  pg mission-control "$c" "$SCRATCH"
  expect deny "[mission-control] a cd the guard cannot see past a here-document look-alike or a spelled command word: ${c//$NL/ / }"
done
for c in "echo a \\<<EOF${NL}cd $KB${NL}echo x > lk-file${NL}EOF" "mksh <<EOF${NL}cd $KB${NL}echo x > lk-file${NL}EOF" \
  "echo hi # <<EOF${NL}cd $KB${NL}echo x > lk-file${NL}EOF" "echo \$[1<<2]${NL}cd $KB${NL}echo x > lk-file${NL}2" \
  "\"\$X\" $KB${NL}echo x > lk-file" "\${X} $KB${NL}echo x > lk-file" "\$(echo cd) $KB${NL}echo x > lk-file" \
  "\`echo cd\` $KB${NL}echo x > lk-file"; do
  pg mission-control "$c" "$SCRATCH"
  expect deny "[mission-control] a cd hidden behind an escaped or run here-document or a spelled command word stays seen: ${c//$NL/ / }"
done
# shellcheck disable=SC2016 # the guard must see the expansion literally
pg mission-control '$HOME/bin/x > out.txt' "$KB"
expect defer "[mission-control] \$HOME/... as the command word names a file, never cd"
for c in "X=\$'c\\x64 '; \$X$KB; echo x > lk-file" "HOME=/x; \$HOME/bin/x > lk-file" \
  "bash <<EOF${NL}cp /x $KB/lk-file${NL}EOF" "xargs <<EOF${NL}cp /x $KB/lk-file${NL}EOF" \
  "cat <<'EOF' | bash${NL}tee $KB/lk-file${NL}EOF"; do
  pg mission-control "$c" "$SCRATCH"
  expect deny "[mission-control] a variable holding cd, or a here-document a shell reads, stays refused: ${c//$NL/ / }"
done
pg mission-control "gh pr create --title t --body \"\$(cat <<'EOF'${NL}Run cd sub then a -> b${NL}EOF${NL})\"" "$SCRATCH"
expect defer "[mission-control] a PR body here-document mentioning cd is data"
pg mission-control 'ln -s .claude/worktrees/x y' "$SANDBOX/repo"
expect defer "[mission-control] a relative .claude/worktrees link source is a checkout"
mkdir -p "$SCRATCH/cdx/dst/src" "$SCRATCH/cdx/src"
pg mission-control 'cd '"$SCRATCH/cdx"' && cp -r src dst' "$UNIT"
expect deny "[mission-control] a recursive copy into a tree already there is looked up from the cd directory"
WT="$SANDBOX/repo/.claude/worktrees/w"
mkdir -p "$WT"
pg mission-control 'ln -s a b' "$WT"
expect defer "[mission-control] a link made inside a .claude/worktrees checkout is permitted"
pg mission-control "ln -s $WT /tmp/wt-link" "$UNIT"
expect defer "[mission-control] a link to a .claude/worktrees checkout is permitted"
for c in "ln -s $WT/.claude/settings.json b" "ln -s $SANDBOX/repo/.claude/worktreesX b" "ln -s $WT/../../agents b" "ln -s $SANDBOX/repo/.claude b"; do
  pg mission-control "$c" "$WT"
  expect deny "[mission-control] a link beside the worktree exemption stays refused: $c"
done
pg mission-control "cat > $KB/note.md <<'EOF'${NL}cd somewhere and run \"x > y\"${NL}EOF" "$SCRATCH"
expect defer "[mission-control] a cd inside a real here-document body is data"
pg_payload mission-control bash "$(jq -n '{tool_name:"Bash", tool_input:{command:"echo x >> lk-file"}}')"
expect deny "[mission-control] a relative write with no cwd in the payload is refused"
echo "# an expanding write target in a data place is followed too"
# shellcheck disable=SC2016 # the guard must see the expansions literally
TMPDIR=$SANDBOX pg mission-control 'echo x > "$TMPDIR/scratch/kb/lk-file"'
expect deny "[mission-control] a \$TMPDIR write through a link into posture is refused"
# shellcheck disable=SC2016 # the guard must see the expansions literally
TMPDIR=$SANDBOX pg mission-control 'echo x > "${TMPDIR}/scratch/kb/lk-agents/x.md"'
expect deny "[mission-control] a \${TMPDIR} write through a link to a posture directory is refused"
# shellcheck disable=SC2016 # the guard must see the expansions literally
TMPDIR=$SANDBOX pg mission-control 'echo x > "$TMPDIR/scratch/kb/real.md"'
expect defer "[mission-control] a \$TMPDIR write to a plain file is permitted"
# shellcheck disable=SC2016 # the guard must see the expansions literally
TMPDIR=$SANDBOX pg mission-control 'echo x > "$TMPDIR/scratch/kb/lk-f"*'
expect deny "[mission-control] a glob under \$TMPDIR cannot be followed and is refused"
# shellcheck disable=SC2016 # the guard must see the expansions literally
TMPDIR=$SANDBOX pg mission-control 'XL=$(mktemp -d); L=$TMPDIR/scratch/kb; echo x > $L/lk-file'
expect deny "[mission-control] another variable's mktemp -d does not make this one fresh"
# shellcheck disable=SC2016 # the guard must see the expansions literally
TMPDIR=$SANDBOX pg mission-control 'L=$(mktemp -d); echo x > $L/out.md'
expect defer "[mission-control] a write into a fresh mktemp -d directory is permitted"
# shellcheck disable=SC2016 # the guard must see the expansions literally
TMPDIR='' pg mission-control 'echo x > "$TMPDIR/out"'
expect defer "[mission-control] a \$TMPDIR write with TMPDIR empty lands where the shell puts it"
# shellcheck disable=SC2016 # the guard must see the expansion literally
TMPDIR='' pg mission-control 'echo x > "$TMPDIR'"$KB"'/lk-file"'
expect deny "[mission-control] a \$TMPDIR write with TMPDIR empty is still followed through a link"
# shellcheck disable=SC2016 # the guard must see the expansions literally
TMPDIR=relative pg mission-control 'echo x > "$TMPDIR/out"'
expect deny "[mission-control] a \$TMPDIR write with a relative TMPDIR is refused"

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
  get) [ "\$2" != broken ] && [ "\$3" = repositories ] && awk -F'\t' -v p="\$2" '\$1 == p { print \$2 }' "$PROGS" ;;
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
printf 'alpha\t%s\nbroken\t%s\n' "$WIDGETS" "$DUP" >"$PROGS"
pg mission-control 'gh pr ready 42 --repo acme/widgets'
expect deny "[mission-control] a program whose repositories cannot be read refuses the flip rather than hiding a second match"
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
