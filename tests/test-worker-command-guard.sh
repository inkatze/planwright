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
# The cases split across files that share no fixture, so the runner's pool
# can run them side by side: this file holds the -v forms, worktree cd,
# literal assignments, inspection verbs, containment, and fail-safe rows; the
# rest are in tests/test-worker-command-guard-*.sh. All of them source
# tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

echo "### REQ-A1.13 — the -v forms defer in every spelling"
assert_defer "bypass: test -v runs a subscript" "test -v 'a[\$(id)]'"
assert_defer "bypass: [ -v runs a subscript" "[ -v 'a[\$(id)]' ]"
assert_defer "bypass: printf -v runs a subscript" "printf -v 'a[\$(id)]' x"
assert_defer "bypass: printf -v assigns PATH" "printf -v PATH /x"
assert_defer "bypass: bundled printf -vNAME" "printf -vPATH /x"
assert_defer "bypass: an opaque test operand can become -v" "test \$X 'a[\$(id)]'"
assert_defer "an opaque printf format" "printf \"\$F\" x"
assert_defer "an opaque printf format after --" "printf -- \"\$F\" x"
assert_allow "printf -- ends the options" "printf -- '%s\\n' a \"\$X\""
# zsh evaluates an operand a numeric conversion or a `*` consumes as
# arithmetic, which can assign a variable.
assert_defer "bypass: an opaque operand of a numeric printf conversion" "printf %d \"\$HOME\"" Bash "$SANDBOX"
assert_defer "bypass: an opaque operand of a * printf width" "printf '%*s' \"\$HOME\" x" Bash "$SANDBOX"
assert_defer "bypass: an opaque operand of a printf time conversion" "printf '%(%Y)T' \"\$HOME\"" Bash "$SANDBOX"
assert_allow "a numeric printf conversion of literal operands still allows" "printf '%5.2f\\n' 3" Bash "$SANDBOX"
assert_defer "bypass: a literal numeric printf operand assigns a modelled script path" \
  "v=scripts/ok.sh; printf %d v=7; bash \$v" Bash "$SANDBOX"
assert_defer "bypass: a literal non-number operand of a numeric printf conversion" "printf %d v=7" Bash "$SANDBOX"
assert_allow "a literal * outside a conversion keeps a text format inert" "printf 'a * b %s\\n' \"\$HOME\"" Bash "$SANDBOX"
assert_allow "text conversions of an opaque operand still allow" "printf '%-10s|%c %%\\n' \"\$HOME\" x" Bash "$SANDBOX"
assert_allow "test without -v still allows" "[ -f file ] && test -n x"
# A double-quoted opaque operand is one word in a position bash cannot read
# as an operator; anywhere else it could become `-v`.
assert_allow "a quoted opaque operand of a unary test" "[ -n \"\$HOME\" ] && test -d \"\$HOME/.claude\""
assert_allow "quoted opaque operands around a binary test" "[ \"\$a\" = \"\$b\" ]"
assert_allow "a lone quoted opaque test operand" "test \"\$a\""
assert_defer "an unquoted opaque test operand" "[ -n \$X ]"
assert_defer "two adjacent opaque test operands" "[ \"\$a\" \"\$b\" ]"
assert_defer "a quoted \"\$@\" still splits into test operands" "[ -n \"\$@\" ]"
assert_defer "an opaque test operator position" "[ \"\$a\" \"\$op\" b ]"
assert_defer "a four-word test with an opaque operand" "[ \"\$a\" = b -o c ]"

# Run-order analysis: the state a segment sets (the working directory, a
# variable's value) applies to what follows it, carried only across `&&`
# from a segment that runs unconditionally in the current shell. The `cd`
# fixtures run in a real repository at its canonical path, since the hook asks
# git whether a target belongs to the session's own repository and an
# absolute operand must be written canonically.
SANDBOX_P=$(cd "$SANDBOX" && pwd -P)
WT=$SANDBOX_P/cdrepo
mkdir -p "$WT/sub/deep" "$WT/scripts" "$WT/nested/inner"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$WT"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$WT/nested"
: >"$WT/scripts/ok.sh"
: >"$WT/sub/g"
ln -s "$SANDBOX_P/install/outside" "$WT/outlink"
ln -s "$WT/sub" "$WT/inlink"
# The hook's own git calls (the repository check a `cd` makes, the remote
# lookups `git ls-remote` makes) must not read the host's git config, where
# an insteadOf or remote setting could change a verdict.
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
HOOK_ENV=("${GIT_ISO[@]}")
echo "### REQ-A1.12 / REQ-E1.4 — cd into the own worktree, then the rest analysed from there"
assert_allow "REQ-E1.4: cd into an in-worktree directory" "cd sub && ls" Bash "$WT"
assert_allow "REQ-E1.4: cd to the worktree root by absolute path" "cd $WT && grep -n x f" Bash "$WT"
assert_allow "REQ-E1.4: cd by absolute in-worktree path" "cd $WT/sub && grep -n x g" Bash "$WT"
assert_allow "REQ-E1.4: chained cds each carry state" "cd sub && cd deep && ls" Bash "$WT"
assert_allow "REQ-E1.4: a ./ component is harmless" "cd ./sub/ && ls" Bash "$WT"
assert_allow "REQ-E1.4: an assignment then a cd, both carried" "d=sub && cd \$d && ls" Bash "$WT"
assert_allow "REQ-E1.4: a lone trailing cd" "ls; cd sub" Bash "$WT"
assert_allow "REQ-A1.12: a later script path resolves from the new directory" "cd sub && ../scripts/ok.sh" Bash "$WT"
assert_defer "REQ-A1.12: a later script path no longer resolves from the old directory" "cd sub && scripts/ok.sh" Bash "$WT"
assert_defer "REQ-E1.4: cd out of the worktree" "cd /tmp && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd to an existing directory outside the worktree" "cd $SANDBOX_P/install/outside && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd with a non-literal operand" "cd \$X && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd .. from the worktree root" "cd .. && ls" Bash "$WT"
assert_defer "REQ-E1.4: a .. component anywhere" "cd sub/.. && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd into a missing directory" "cd missing && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd through a symlink leaving the worktree" "cd outlink && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd through a symlink, even one staying inside" "cd inlink && ls" Bash "$WT"
assert_allow "REQ-E1.4: cd within the own repository, then git" "cd scripts && git status" Bash "$WT"
assert_defer "REQ-E1.4: cd into a nested repository, then git" "cd nested && git status" Bash "$WT"
assert_defer "REQ-E1.4: cd into a nested repository" "cd nested && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd below a nested repository's root" "cd nested/inner && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd into the git directory" "cd .git && ls" Bash "$WT"
mkdir -p "$WT/x=~" "$WT/x=" "$WT/+0" "$WT/x^y" "$WT/a~b" "$WT/6-7" "$WT/{6-7}"
assert_defer "REQ-E1.4: bash tilde-expands after = in a cd operand" "cd x=~ && ls" Bash "$WT"
assert_defer "REQ-E1.4: a ~ anywhere in a cd operand" "cd a~b && ls" Bash "$WT"
assert_defer "REQ-E1.4: zsh reads cd +N as the directory stack" "cd +0 && ls" Bash "$WT"
assert_defer "REQ-E1.4: a zsh extended-glob character in a cd operand" "cd x^y && ls" Bash "$WT"
assert_defer "REQ-E1.4: a zsh brace class in a cd operand" "cd {6-7} && ls" Bash "$WT"
assert_defer "REQ-E1.4: an absolute operand not written canonically" "cd $WT//sub/./ && ls" Bash "$WT"
assert_defer "REQ-E1.4: bare cd goes home" "cd && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd - goes to OLDPWD" "cd - && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd with a flag" "cd -P sub && ls" Bash "$WT"
assert_defer "REQ-E1.4: cd with two operands" "cd sub deep && ls" Bash "$WT"
assert_defer "REQ-A1.12: cd followed by ;" "cd sub; ls" Bash "$WT"
assert_defer "REQ-A1.12: a failed cd before ; leaves the old directory" "cd missing; rm -r ../x" Bash "$WT"
assert_defer "REQ-A1.12: cd followed by ||" "cd sub || ls" Bash "$WT"
assert_defer "REQ-A1.12: cd followed by a newline and a reader" "cd sub"$'\n'"ls" Bash "$WT"
assert_defer "REQ-A1.12: a ; while a cd is in force, past an assignment" "cd sub && f=x; ls" Bash "$WT"
assert_defer "REQ-A1.12: cd in a pipeline before a writer" "cd sub | rm -r ../x" Bash "$WT"
assert_defer "REQ-A1.12: cd in a pipeline" "cd sub | cat" Bash "$WT"
assert_defer "REQ-A1.12: cd backgrounded" "cd sub & ls" Bash "$WT"
assert_defer "REQ-A1.12: cd after a real command is conditional" "ls && cd sub && ls" Bash "$WT"
assert_defer "REQ-A1.12: cd after || is conditional" "true || cd sub && ls" Bash "$WT"
assert_defer "REQ-A1.12: cd inside a loop body" "for d in sub; do cd \$d && ls; done" Bash "$WT"
assert_defer "REQ-A1.12: cd inside fish -c" "fish -c 'cd sub && ls'" Bash "$WT"
assert_defer "REQ-A1.12: cd under timeout" "timeout 5 cd sub && ls" Bash "$WT"
assert_defer "REQ-A1.12: cd under time" "time cd sub && ls" Bash "$WT"
assert_defer "REQ-E1.4: CDPATH set in the command" "CDPATH=/ && cd sub && ls" Bash "$WT"
HOOK_ENV=("${GIT_ISO[@]}" "CDPATH=/")
assert_defer "REQ-E1.4: CDPATH exported to the hook" "cd sub && ls" Bash "$WT"
HOOK_ENV=()

echo "### REQ-E1.2 — plain-literal assignments resolve, any literal"
assert_allow "REQ-E1.2: an ordinary literal reaches a later operand" "f=README.md && grep -n x \$f"
assert_allow "REQ-E1.2: a resolved flag still meets the screen it reaches" "X=-name && find . \$X a.sh"
assert_defer "REQ-E1.2: a resolved write flag defers" "X=-delete && find . \$X"
assert_defer "REQ-E1.2: a resolved write flag after ; defers" "x=-delete; find . \$x"
assert_allow "REQ-E1.2: a whole-quoted value resolves" "F='-name' && find . \$F a.sh"
assert_defer "REQ-E1.2: an unquoted value with a space stays unresolved (zsh does not split it)" "F='-name a.sh' && find . \$F"
assert_defer "REQ-E1.2: so a write flag inside it still defers" "F='x -delete' && find . -name \$F"
assert_allow "REQ-E1.2: a quoted value with a space resolves as one word" "F='a b' && find . -name \"\$F\""
# zsh-option characters stay attached to their own word when words move.
assert_allow "a quoted ^ awk program under a prefix" "time awk '/^a/' f"
assert_defer "REQ-A1.13: an unquoted ^ awk program keeps its flag after a prefix shift" "time awk /^a/ f"
assert_defer "REQ-E1.2: an unquoted ^ awk program keeps its flag after an empty word is removed" "E= && awk \$E /^a/ f"
assert_allow "REQ-E1.2: a quoted use stays one word" "F='x -delete' && find . -name \"\$F\""
assert_allow "REQ-E1.2: an empty value removes an unquoted word" "f= && find . \$f -name a"
assert_defer "REQ-E1.2: an empty value leaves joined text" "f= && find . -delete\$f"
assert_allow "REQ-E1.2: literal text before the quoted expansion" "F='a b' && find . -path x\"\$F\""
assert_defer "REQ-E1.2: text adjoined after the quoted expansion stays unresolved" "F='a b' && find . -name \"\$F\"x"
assert_defer "REQ-E1.2: a tab in the value is opaque" "F='a"$'\t'"b' && find . -name \"\$F\""
assert_allow "REQ-E1.2: a lone opaque assignment runs nothing" "f=\$HOME && echo \$f"
assert_defer "REQ-E1.2: a value carrying an expansion is opaque" "f=\$HOME && find \$f"
assert_defer "REQ-E1.2: a value carrying a glob is opaque" "f=*.md && find . \$f"
assert_defer "REQ-E1.2: a value carrying a tilde is opaque" "f=~/x && find \$f"
assert_defer "REQ-E1.2: a partly quoted value is opaque" "f=a\"b\"c && find . \$f"
assert_defer "REQ-E1.2: an extglob pattern in a value is opaque" "X='@(-delete)' && find . \$X"
assert_defer "REQ-E1.2: a backslash in a value is opaque" "X='\\-delete' && find . \$X"
assert_defer "REQ-E1.2: a negated extglob in a value is opaque" "X='!(a)' && find . -name \$X -delete"
assert_defer "REQ-E1.2: an opaque assignment shadows an earlier literal" "f=-name && f=\$X && find . \$f a"
assert_defer "REQ-E1.2: a value whitespace splits inside a mixed word is not modelled" "F='a -delete' && find . -name x\$F\"y\""
assert_defer "REQ-E1.2: a substituted assignment-shaped verb is a command" "A='B=-delete' && \$A && find . \$B"
assert_defer "REQ-E1.2: IFS is refused" "IFS=- && ls"
assert_defer "REQ-E1.2: PATH is refused" "PATH=x && ls"
assert_defer "REQ-E1.2: RANDOM evaluates its value as arithmetic" "RANDOM=1 && ls"
assert_defer "REQ-E1.2: SRANDOM evaluates its value as arithmetic" "SRANDOM=1 && ls"
assert_defer "REQ-E1.2: HISTCMD evaluates its value as arithmetic" "HISTCMD=1 && ls"
assert_defer "REQ-E1.2: SECONDS is a dynamic variable" "SECONDS=1 && ls"
assert_defer "REQ-E1.2: a zsh read-only ZSH_ special is refused" "ZSH_NAME=scripts/ok.sh && bash \$ZSH_NAME"
assert_defer "REQ-E1.2: zsh's funcstack is refused" "funcstack=scripts/ok.sh && bash \$funcstack"
assert_defer "REQ-E1.2: zsh's options hash is refused" "options=scripts/ok.sh && bash \$options"
assert_defer "REQ-E1.2: zsh's argv is refused" "argv=scripts/ok.sh && bash \$argv"
# Each against the control: the same carry through an ordinary name allows.
assert_allow "REQ-E1.2: control, an ordinary name carries a flag across ;" "f=-name; find . \$f a.sh"
assert_defer "REQ-E1.2: zsh's read-only history is refused" "history=-name; find . \$history a.sh"
# A few names through the hook, each unset for it: an exported name (TERM,
# LOGNAME) is refused through the environment snapshot anyway.
for n in TERM mapfile signals PROMPT; do
  HOOK_ENV=(/usr/bin/env -u "$n")
  assert_defer "REQ-E1.2: zsh's $n is refused" "$n=-name; find . \$$n a.sh"
done
HOOK_ENV=()
# The whole list in-process against an empty environment snapshot, so no
# host export can answer for a missing name.
zsh_missed=$(
  eval "$(sed -n '/^assign_name_ok() {$/,/^}$/p' "$HOOK")"
  NL=$'\n'
  # shellcheck disable=SC2034 # read by the eval'd assign_name_ok
  HOOK_ENV_NAMES=$NL
  for n in TERM TERMINFO TERMINFO_DIRS WORDCHARS KEYBOARD_HACK ZLE_RPROMPT_INDENT POSTEDIT RPS1 \
    RPS2 RPROMPT RPROMPT2 SPROMPT prompt PROMPT PROMPT2 PROMPT3 PROMPT4 PSVAR psvar fignore \
    mailpath TIMEFMT HOST LOGNAME CPUTYPE MACHTYPE OSTYPE TTY VENDOR signals dis_functions \
    functions_source dis_functions_source funcsourcetrace builtins dis_builtins reswords \
    dis_reswords patchars dis_patchars modules dirstack history historywords jobtexts jobdirs \
    jobstates nameddirs userdirs usergroups dis_aliases galiases dis_galiases saliases \
    dis_saliases epochtime zgdbm_tied langinfo mapfile errnos sysparams termcap terminfo WATCH \
    watch widgets keymaps zsh_scheduled_events; do
    assign_name_ok "$n" && printf '%s ' "$n"
  done
  assign_name_ok f || printf 'control:f '
)
if [ -z "$zsh_missed" ]; then
  pass "REQ-E1.2: every zsh special, startup-set, and module name is refused"
else
  fail "REQ-E1.2: assign_name_ok admits zsh names: $zsh_missed"
fi
# zsh expands a bare = leading the value, or after a :, as =cmd.
assert_allow "REQ-E1.2: control, a value with no zsh = expansion" "f=a.sh && find . -name \$f"
assert_defer "REQ-E1.2: a leading = is expanded by zsh" "f==a.sh && find . -name \$f"
assert_defer "REQ-E1.2: = after a : is expanded by zsh" "f=a:=b && find . -name \$f"
assert_allow "REQ-E1.2: a quoted leading = stays literal" "f='=a.sh' && find . -name \$f"
assert_allow "REQ-E1.2: = inside the value elsewhere stays literal" "f=a=b && find . -name \$f"
assert_defer "REQ-E1.2: UID is readonly, so the model would be wrong" "UID=-delete && find . \$UID"
assert_defer "REQ-E1.2: a conditional assignment before a use" "false && f=x; grep -n x \$f"
assert_defer "REQ-E1.2: an assignment after a real command is conditional" "ls && f=-delete && find . \$f"
assert_defer "REQ-A1.12: an assignment in a pipeline" "x=a | grep \$x"
assert_defer "REQ-A1.12: an assignment in a pipeline reaching a screen" "x=-delete | find . \$x"
assert_defer "REQ-A1.12: an assignment backgrounded" "x=a & grep \$x"
assert_defer "REQ-A1.12: an assignment inside a loop body" "for d in a; do x=\$d; grep -n y \$x; done"
CHAIN32=''
for n in $(seq 32); do CHAIN32="${CHAIN32}v$n=x && "; done
assert_allow "REQ-E1.2: tracked assignments up to the bound" "${CHAIN32}find . -name \$v32"
assert_defer "REQ-E1.2: tracked assignments past the bound defer" "${CHAIN32}v33=x && find . -name \$v33"
assert_defer "REQ-E1.2: fish -c has no NAME=value statement" "fish -c 'X=README.md; cat \$X'"
# Each opacity row against its control: the same shape with no rewrite
# resolves, so only the rewriting form can be what defers it.
assert_allow "REQ-A1.12: control, a tracked flag reaching find" "f=-name && find . \$f a.sh"
assert_defer "REQ-A1.12: read after a tracked assignment makes it opaque" "f=-name && read f && find . \$f a.sh"
assert_defer "REQ-A1.12: printf -v after a tracked assignment" "f=-name && printf -v f x && find . \$f a.sh"
assert_defer "REQ-A1.12: mapfile after a tracked assignment" "f=-name && mapfile f < g && find . \$f a.sh"
assert_defer "REQ-A1.12: declare after a tracked assignment" "f=-name && declare f=-delete && find . \$f"
assert_defer "REQ-A1.12: typeset after a tracked assignment" "f=-name && typeset f=-delete && find . \$f"
assert_defer "REQ-A1.12: local after a tracked assignment" "f=-name && local f=-delete && find . \$f"
assert_defer "REQ-A1.12: export after a tracked assignment" "f=-name && export f=-delete && find . \$f"
assert_defer "REQ-A1.12: readarray after a tracked assignment" "f=-name && readarray f < g && find . \$f a.sh"
assert_defer "REQ-A1.12: let after a tracked assignment" "n=1 && let n=2 && sed -n \${n}p f"
assert_defer "REQ-A1.12: arithmetic after a tracked assignment" "n=1 && ((n++)) && sed -n \${n}p f"
assert_defer "REQ-A1.12: read makes the variable opaque" "read f; find . \$f"
assert_defer "REQ-A1.12: printf -v makes the variable opaque" "printf -v f x && find . \$f"
assert_defer "REQ-A1.12: mapfile makes the variable opaque" "mapfile -t a < f; find . \${a[0]}"
# The carry rows use a flag that allows only when its value carries.
assert_defer "REQ-A1.12: control, the flag alone is unresolved" "find . \$f a.sh"
assert_allow "REQ-A1.12: an assignment carries across ;" "f=-name; find . \$f a.sh"
assert_allow "REQ-A1.12: an assignment carries across a newline" "f=-name"$'\n'"find . \$f a.sh"
assert_allow "REQ-A1.12: an assignment carries across ||" "f=-name || find . \$f a.sh"
assert_allow "REQ-A1.12: an assignment opened by && after a carrying one" "f=-name && g=a.sh; find . \$f \$g"
assert_allow "REQ-A1.12: control, both assignments unconditional" "f=a; g=-name; find . \$g a.sh"
assert_defer "REQ-A1.12: an assignment after || is conditional" "f=a || g=-name; find . \$g a.sh"
assert_defer "REQ-A1.12: an assignment after a real command's && is conditional" "true && f=-name; find . \$f a.sh"

echo "### REQ-A1.13 — time and timeout are transparent prefixes"
assert_allow "REQ-A1.13: time" "time git status"
assert_allow "REQ-A1.13: time -p" "time -p git status"
assert_allow "REQ-A1.13: timeout <seconds>" "timeout 30 git status"
assert_allow "REQ-A1.13: timeout <minutes>" "timeout 5m git log --oneline -3"
assert_allow "REQ-A1.13: timeout <fraction>" "timeout 1.5 grep -n x f"
assert_allow "REQ-A1.13: time around timeout" "time timeout 30 git status"
assert_allow "REQ-A1.13: the wrapped command is verified as if alone" "timeout 30 echo \$X"
assert_defer "REQ-A1.13: timeout around a writer" "timeout 30 rm -rf x"
assert_defer "REQ-A1.13: timeout with a flag" "timeout -k 5 30 git status"
assert_defer "REQ-A1.13: time around bash -c" "time bash -c x"
assert_defer "REQ-A1.13: a malformed duration" "timeout 5x ls"
assert_defer "REQ-A1.13: an opaque duration" "timeout \$T ls"
assert_defer "REQ-A1.13: time with another flag" "time -v ls"
# bash reads `-p` as time's option only when it is written bare; quoted, it
# is the command time runs.
assert_defer "REQ-A1.13: a double-quoted -p is the command time runs" "time \"-p\" git status"
assert_defer "REQ-A1.13: a single-quoted -p is the command time runs" "time '-p' git status"
assert_defer "REQ-A1.13: a quoted timeout duration" "timeout \"30\" git status"
assert_defer "REQ-A1.13: time with nothing to run" "time"
assert_defer "REQ-A1.13: timeout with nothing to run" "timeout 30"
assert_defer "REQ-A1.13: nested timeout" "timeout 30 timeout 5 ls"
assert_defer "REQ-A1.13: the time program under timeout" "timeout 30 time ls"
assert_defer "REQ-A1.13: an opaque operand the wrapped screen reads" "timeout 30 find . \$X"
assert_defer "REQ-A1.13: an assignment under a prefix" "time f=x"

echo "### REQ-E1.5 — timing and inspection verbs"
assert_allow "REQ-E1.5: sleep" "sleep 5"
assert_allow "REQ-E1.5: sleep with a fraction and a unit" "sleep 0.5; sleep 1m"
assert_allow "REQ-E1.5: sleep then a read" "sleep 20; gh pr checks 5"
# `-e` prints process environments on macOS and the BSDs (operator
# decision 2026-10-09), so every form carrying it defers.
assert_defer "REQ-E1.5: ps -ef prints environments on macOS" "ps -ef"
assert_defer "REQ-E1.5: ps -e" "ps -e"
assert_defer "REQ-E1.5: ps -eo" "ps -eo pid,args"
assert_allow "REQ-E1.5: ps -A selects every process" "ps -A"
assert_allow "REQ-E1.5: ps -o pid,args" "ps -o pid,args"
assert_allow "REQ-E1.5: ps with a format and a pid" "ps -o etimes= -p 1"
assert_allow "REQ-E1.5: uptime" "uptime"
assert_allow "REQ-E1.5: which" "which git"
assert_allow "REQ-E1.5: command -v" "command -v jq"
assert_allow "REQ-E1.5: git check-ignore" "git check-ignore x"
assert_allow "REQ-E1.5: git check-ignore -q" "git check-ignore -q .claude/x && echo ignored"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$WT" remote add origin https://example.invalid/r.git
HOOK_ENV=("${GIT_ISO[@]}")
assert_allow "REQ-E1.5: git ls-remote <remote>" "git ls-remote origin" Bash "$WT"
assert_allow "REQ-E1.5: git ls-remote <remote> <pattern>" "git ls-remote --heads origin refs/heads/main" Bash "$WT"
assert_defer "REQ-E1.5: git ls-remote to a name no remote is configured as" "git ls-remote foo" Bash "$WT"
# Only a built-in transport: any other URL, as configured or after an
# insteadOf rewrite, makes git run a git-remote-<transport> helper.
wtgit() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$WT" "$@"; }
wtgit remote add viassh ssh://git@example.invalid/r.git
wtgit remote add viascp git@example.invalid:r.git
wtgit remote add viagit git://example.invalid/r.git
wtgit remote add viafile "$SANDBOX_P/install/outside"
wtgit remote add helper 'evil::anything'
wtgit remote add rewritten https://rewritten.invalid/r.git
wtgit config url.evil::y.insteadOf https://rewritten.invalid/
wtgit remote add withvcs https://example.invalid/v.git
wtgit config remote.withvcs.vcs evil
wtgit remote add withpack https://example.invalid/p.git
wtgit config remote.withpack.uploadpack 'sh -c id'
assert_allow "REQ-E1.5: git ls-remote to an ssh:// remote" "git ls-remote viassh" Bash "$WT"
assert_allow "REQ-E1.5: git ls-remote to an scp-style remote" "git ls-remote viascp" Bash "$WT"
assert_allow "REQ-E1.5: git ls-remote to a git:// remote" "git ls-remote viagit" Bash "$WT"
assert_allow "REQ-E1.5: git ls-remote to a local-path remote" "git ls-remote viafile" Bash "$WT"
assert_defer "REQ-E1.5: git ls-remote to a custom-transport remote" "git ls-remote helper" Bash "$WT"
assert_defer "REQ-E1.5: git ls-remote to a URL insteadOf rewrites to a helper" "git ls-remote rewritten" Bash "$WT"
assert_defer "REQ-E1.5: git ls-remote to a remote naming a vcs helper" "git ls-remote withvcs" Bash "$WT"
assert_defer "REQ-E1.5: git ls-remote to a remote with its own upload-pack" "git ls-remote withpack" Bash "$WT"
HOOK_ENV=()
assert_allow "REQ-E1.5: jq --version" "jq --version"
assert_allow "REQ-E1.5: shellcheck --version" "shellcheck --version"
assert_allow "REQ-E1.5: git --version" "git --version"
for tool in git gh jq yq rg fd sed awk find grep sort uniq date file bash sh fish bats mise lefthook \
  shellcheck shfmt yamllint markdownlint markdownlint-cli2 cat head tail wc ls diff stat od tr seq \
  cut comm cmp basename dirname realpath readlink nl paste column md5sum sha1sum sha256sum \
  sha512sum cksum env printenv sleep ps uptime which; do
  assert_allow "REQ-E1.5: $tool --version" "$tool --version"
done
for f in -p --pretty -s --since; do
  assert_allow "REQ-E1.5: uptime $f" "uptime $f"
done
for f in -q --quiet -v --verbose -n --non-matching --no-index -z; do
  assert_allow "REQ-E1.5: git check-ignore $f" "git check-ignore $f x"
done
HOOK_ENV=("${GIT_ISO[@]}")
for f in -h --heads -b --branches -t --tags --refs -q --quiet --exit-code --get-url --symref --sort=refname; do
  assert_allow "REQ-E1.5: git ls-remote $f" "git ls-remote $f origin" Bash "$WT"
done
HOOK_ENV=()
for f in -A -a -d -f -F -H -j -l -L -M -m -T -w -x -y -Z --no-headers --forest; do
  assert_allow "REQ-E1.5: ps $f" "ps $f"
done
for f in "-p 1" "-u root" "-o pid,etime" "--sort pid" "--pid=1" "ax" "axwww" "1,2"; do
  assert_allow "REQ-E1.5: ps $f" "ps $f"
done
assert_allow "REQ-E1.5: which -a and -s" "which -a -s git"
assert_defer "REQ-E1.5: sleep with an opaque operand" "sleep \$X"
# Approved waits are capped at two hours, so a typo cannot park a worker.
assert_allow "REQ-E1.5: sleep at the cap" "sleep 2h"
assert_allow "REQ-E1.5: sleep at the cap in minutes" "sleep 120m"
assert_allow "REQ-E1.5: sleep at the cap in seconds" "sleep 7200"
assert_allow "REQ-E1.5: sleep with leading zeros" "sleep 0099"
assert_defer "REQ-E1.5: sleep past the cap" "sleep 7201"
assert_defer "REQ-E1.5: sleep past the cap in minutes" "sleep 121m"
assert_defer "REQ-E1.5: sleep past the cap by a fraction" "sleep 7200.5"
assert_defer "REQ-E1.5: sleep for a year" "sleep 365d"
assert_defer "REQ-E1.5: sleep operands summing past the cap" "sleep 2h 1s"
assert_allow "REQ-A1.13: timeout at the cap" "timeout 2h git status"
assert_defer "REQ-A1.13: timeout past the cap" "timeout 3h git status"
assert_defer "REQ-E1.5: sleep with a non-numeric operand" "sleep forever"
assert_defer "REQ-E1.5: sleep with no operand" "sleep"
assert_defer "REQ-E1.5: ps with an unrecognized flag" "ps --bogus"
assert_allow "REQ-E1.5: ps aux" "ps aux"
assert_defer "REQ-E1.5: BSD e prints other processes' environments" "ps auxe"
assert_defer "REQ-E1.5: ps eww" "ps eww"
assert_defer "REQ-E1.5: ps e" "ps e"
assert_defer "REQ-E1.5: a format naming env" "ps -o pid,env"
assert_defer "REQ-E1.5: a format naming environ" "ps --format=pid,environ"
assert_defer "REQ-E1.5: an -O format naming env" "ps -O env"
assert_defer "REQ-E1.5: e inside a dash cluster" "ps -Ae"
assert_defer "REQ-E1.5: -e after another flag" "ps -A -e"
assert_defer "REQ-E1.5: -e after a format" "ps -o pid,args -e"
assert_defer "REQ-E1.5: BSD e after a dash flag" "ps -A e"
assert_defer "REQ-E1.5: -o env" "ps -o env"
assert_defer "REQ-E1.5: -o environ" "ps -o environ"
assert_defer "REQ-E1.5: uptime with an unrecognized flag" "uptime --bogus"
assert_defer "REQ-E1.5: command runs its operand" "command ls"
assert_defer "REQ-E1.5: command -p runs its operand" "command -p ls"
assert_defer "REQ-E1.5: which with an unrecognized flag" "which --read-functions git"
assert_defer "REQ-E1.5: git check-ignore with an unrecognized flag" "git check-ignore --bogus x"
assert_defer "REQ-E1.5: git ls-remote to a URL" "git ls-remote https://example.invalid/x"
assert_defer "REQ-E1.5: git ls-remote to a relative path" "git ls-remote ./path"
assert_defer "REQ-E1.5: git ls-remote to a parent path" "git ls-remote ../other"
assert_defer "REQ-E1.5: git ls-remote to an scp-style address" "git ls-remote h:r"
assert_defer "REQ-E1.5: git ls-remote --upload-pack" "git ls-remote --upload-pack=x origin"
assert_defer "REQ-E1.5: git ls-remote -u" "git ls-remote -u x origin"
assert_defer "REQ-E1.5: git ls-remote naming an existing path" "git ls-remote sub"
assert_defer "REQ-E1.5: git ls-remote with no remote" "git ls-remote"
assert_defer "REQ-E1.5: --version of a verb outside the allowlist" "rm --version"
assert_defer "REQ-E1.5: --version with another operand" "git --version x"

echo "### REQ-E1.6 — other processes' environments stay unread"
assert_defer "REQ-E1.6: another process's environ" "cat /proc/1234/environ"
assert_defer "REQ-E1.6: a redirect source naming one" "grep -a x < /proc/1234/environ"
assert_defer "REQ-E1.6: a thread's environ" "cat /proc/1234/task/1234/environ"
assert_defer "REQ-E1.6: a glob over every process" "cat /proc/*/environ"
assert_defer "REQ-E1.6: a glob in the last component" "cat /proc/1234/env*"
assert_defer "REQ-E1.6: a doubled leading slash" "cat //proc/1234/env*"
assert_defer "REQ-E1.6: a doubled leading slash on a redirect source" "wc -c < //proc/1234/env*"
assert_defer "REQ-E1.6: a . component before proc" "cat /./proc/1234/env*"
assert_defer "REQ-E1.6: a relative path through proc" "cat ../../../../../../../../proc/1234/env*"
assert_allow "REQ-E1.6: the own environ with a doubled slash" "cat //proc/self/environ"
assert_defer "REQ-E1.6: /dev/fd/0 into a process directory on a loop's stdin" "for f in a; do cat /dev/fd/0/env*; done </proc/1"
assert_defer "REQ-E1.6: /dev/fd/0 into a process directory on stdin" "cat /dev/fd/0/env* < /proc/1"
assert_defer "REQ-E1.6: a glob directory the guard cannot enter" "cat nodir/envir?n"
assert_defer "REQ-E1.6: any other /proc redirect source" "wc -l < /proc/cpuinfo"
assert_defer "REQ-E1.6: fish's recursive ** matching environ" "fish -c 'cat **environ'"
assert_defer "REQ-E1.6: a ** glob matching environ" "cat **env*"
assert_allow "REQ-E1.6: a ** glob that cannot match environ" "cat **.md"
assert_defer "REQ-E1.6: another process's memory" "od -N 8 /proc/1/mem"
assert_defer "REQ-E1.6: a thread's memory" "cat /proc/1234/task/1234/mem"
assert_defer "REQ-E1.6: a glob matching mem" "cat /proc/1234/me?"
assert_allow "REQ-E1.6: a name only starting with mem" "cat memo.md"
# A loop re-walks its body per head word, so each glob directory is
# resolved once per hook run: counted in-process, not timed.
rm -f "$SANDBOX/cd-calls"
if (
  eval "$(sed -n '/^canon_dir_cached() {$/,/^}$/p' "$HOOK")"
  want=$(cd -P "$SANDBOX" && pwd)
  # shellcheck disable=SC2329 # called by the eval'd canon_dir_cached
  cd() {
    echo x >>"$SANDBOX/cd-calls"
    builtin cd "$@"
  }
  canon_dir_cached "$SANDBOX" && canon_dir_cached "$SANDBOX" && canon_dir_cached "$SANDBOX"
  [ "$CANON" = "$want" ] || exit 1
  canon_dir_cached "$SANDBOX/missing" && canon_dir_cached "$SANDBOX/missing"
  [ -z "$CANON" ] && [ "$(wc -l <"$SANDBOX/cd-calls")" -eq 2 ]
); then
  pass "REQ-E1.6: each glob directory is resolved once per hook run"
else
  fail "REQ-E1.6: canon_dir_cached resolved a directory more than once, or wrongly"
fi
assert_defer "REQ-E1.6: every file of a process" "head /proc/1234/*"
assert_defer "REQ-E1.6: a bracket glob matching environ" "cat /proc/1234/[e]nviron"
assert_defer "REQ-E1.6: a brace expansion in the last component" "cat /proc/1234/{environ,status}"
assert_defer "REQ-E1.6: reached through .. from /proc/self" "cat /proc/self/../1234/environ"
assert_defer "REQ-E1.6: reached through /dev/fd" "cat /dev/fd/../../1234/environ"
assert_defer "REQ-E1.6: reached by a relative path" "cat ../../../../../../../../proc/1234/environ"
assert_defer "REQ-E1.6: an option's attached file operand" "grep --file=/proc/1234/environ x"
assert_defer "REQ-E1.6: a tracked value naming one" "f=/proc/1234/environ; cat \$f"
assert_defer "REQ-E1.6: a loop head naming one" "for f in /proc/1234/environ; do cat \$f; done"
assert_defer "REQ-E1.6: \$_ after an echo of the path" "echo /proc/1234/environ; cat \$_"
assert_defer "REQ-E1.6: \$_ alone" "echo a; cat \$_"
assert_defer "REQ-E1.6: a double-quoted opaque operand of a reader" "cat \"\$X\""
assert_allow "REQ-E1.6: a known spaced value reaching a reader unquoted" "F='a b' && grep -n \$F README.md"
assert_defer "REQ-E1.6: a known spaced value bash splits into a path" "F='/proc/1234/environ x' && cat \$F"
assert_defer "REQ-E1.6: a known spaced value joined to a path" "F='environ x' && cat /proc/1234/\$F"
assert_defer "REQ-E1.6: a known spaced value joined to a glob" "F='a /proc/1234/env'; cat \$F*"
assert_allow "REQ-E1.6: a known spaced value joined to a glob that cannot match" "F='a b' && grep -n x \$F*.md"
assert_defer "REQ-E1.6: an opaque operand of a reader" "cat \$X"
assert_defer "REQ-E1.6: an opaque word in a reader's path" "grep -n x src/\$X"
assert_defer "REQ-E1.6: an unexpanded redirect source" "grep x < \$f"
assert_defer "REQ-E1.6: a redirect source glob" "grep x < /proc/1234/env*"
if [ -d /proc/1 ]; then
  assert_defer "REQ-E1.6: a glob whose directory resolves into /proc" "cat /dev/fd/../../1/env*"
fi
for v in tail wc cut od nl paste column md5sum sha1sum sha256sum sha512sum cksum shellcheck yamllint; do
  assert_defer "REQ-E1.6: an opaque operand of $v" "$v \$X"
done
for v in comm cmp diff; do
  assert_defer "REQ-E1.6: an opaque second operand of $v" "$v a \$X"
done
assert_defer "REQ-E1.6: a glob directory with a matching last component" "cat */*"
assert_defer "REQ-E1.6: inside fish -c" "fish -c 'cat /proc/1234/environ'"
assert_defer "REQ-E1.6: past a time prefix" "time cat /proc/1234/environ"
assert_allow "REQ-E1.6: the reading process's own environ" "cat /proc/self/environ"
assert_allow "REQ-E1.6: the reading thread's own environ" "cat /proc/thread-self/environ"
assert_allow "REQ-E1.6: its own environ as a redirect source" "tr '\\0' '\\n' < /proc/self/environ"
assert_allow "REQ-E1.6: env" "env"
assert_allow "REQ-E1.6: printenv" "printenv"
assert_allow "REQ-E1.6: an opaque operand of a non-reader" "echo \$X; ls \$X"
assert_allow "REQ-E1.6: a glob in the worktree" "cat *.md; grep -n x scripts/*"
assert_allow "REQ-E1.6: a last component only starting with environ" "cat environment.md"
assert_allow "REQ-E1.6: a plain redirect source" "wc -l < README.md"
# Only a verb that opens its operands meets the environ test.
assert_allow "REQ-E1.6: environ as a grep pattern" "grep environ README.md"
assert_allow "REQ-E1.6: environ as a grep pattern after flags and --" "grep -n -- environ README.md"
assert_defer "REQ-E1.6: a grep pattern before the environ file" "grep environ /proc/1234/environ"
assert_defer "REQ-E1.6: grep -e makes the first operand a file" "grep -e x /proc/1234/environ"
assert_defer "REQ-E1.6: a later -e makes the first operand a file" "grep environ -e x"
assert_defer "REQ-E1.6: -f in a cluster makes the first operand a file" "grep -nf p environ"
assert_defer "REQ-E1.6: --regexp makes the first operand a file" "rg --regexp=x environ"
assert_defer "REQ-E1.6: a glob pattern operand expands into files grep reads" "grep /proc/*/environ"
assert_defer "REQ-E1.6: a brace pattern operand expands into files" "grep {x,/proc/1234/environ}"
assert_allow "REQ-E1.6: a quoted glob pattern stays one word" "grep -n 'env*ron' README.md"
# zsh's EXTENDED_GLOB makes `#`, `^` and a mid-word `~` pattern operators.
assert_defer "REQ-E1.6: zsh's # operator matching environ" "cat /proc/1234/environ#"
assert_defer "REQ-E1.6: zsh's ^ negation matching environ" "cat /proc/1234/^status"
assert_defer "REQ-E1.6: zsh's ~ exclusion matching environ" "cat /proc/1234/environ~x"
assert_defer "REQ-E1.6: zsh's # operator on a redirect source" "wc -c < /dev/fd/../../1234/environ#"
assert_allow "REQ-E1.6: zsh pattern characters that cannot match environ" "cat README.md#"
assert_allow "REQ-E1.6: environ as an echo operand" "echo environ"
assert_allow "REQ-E1.6: environ as a git log pattern" "git log --grep environ"
for v in "sed -n p" sort uniq file "jq -R ." "rg x" "awk 1" shfmt; do
  assert_defer "REQ-E1.6: $v reads another process's environ" "$v /proc/1234/environ"
done

echo "### REQ-A1.9 — grammar-conservative deferral"
assert_defer "env-assignment prefix BASH_ENV" "BASH_ENV=/tmp/x bash scripts/ok.sh"
assert_defer "env-assignment LD_PRELOAD" "LD_PRELOAD=/tmp/x cat f"
assert_defer "env-assignment GIT_PAGER" "GIT_PAGER='!cmd' git log"
assert_allow "REQ-E1.2: a lone plain assignment runs nothing" "FOO=bar"
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

assert_defer "shell comment defers: trailing comment" "cat README.md #note"
assert_defer "shell comment defers: comment after an operator" "cat README.md;#note"
assert_defer "shell comment defers: comment-only command" "# note"
assert_defer "shell comment defers: comment after a redirect" "cat README.md 2>#note"
assert_defer "shell comment defers: inside fish -c" "fish -c 'cat README.md #note'"
assert_defer "shell comment defers: multi-line command" "cat README.md # '
rm -rf x # '"
assert_defer "shell comment defers: multi-line command after a pipe" "cat README.md |# '
rm -rf x # '"
assert_allow "mid-word # is not a comment" "cat a#b"
assert_allow "single-quoted # is not a comment" "grep -n '#' README.md"
assert_allow "double-quoted # is not a comment" "grep -n \"#x\" README.md"
assert_allow "escaped # is not a comment" "grep -n \\#x README.md"
assert_defer "defer form: a brace word before an output redirect" "cat README.md {fd}>/dev/null"
assert_defer "defer form: a brace word before an input redirect" "cat README.md {fd}<README.md"
assert_defer "defer form: a brace word before an fd duplication" "git status {fd}>&2"
assert_defer "defer form: a brace word before an fd close" "git status {fd}>&-"
assert_defer "defer form: a brace word before a combined-output redirect" "git status {fd}&>/dev/null"
assert_defer "defer form: a brace word before a redirect, then a later command" "printf x {fd}>/dev/null; git status"
assert_allow "parity: a brace word spaced from its redirect is an operand" "cat {a} >/dev/null"
assert_allow "parity: a brace mid-word before a redirect is an operand" "cat a{b}>/dev/null"
assert_allow "parity: an fd-number redirect still allows" "git status 2>&1"

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
malformed_run '{"tool_name":"Bash","tool_input":{"command":"git status\u0000"}}'
if [ "$CODE" -eq 0 ] && is_empty; then
  pass "defer form: a NUL byte in the command"
elif is_allow; then
  fail "defer form: a NUL byte in the command — FALSE-ALLOW: expected DEFER"
  false_allows=$((false_allows + 1))
else
  fail "defer form: a NUL byte in the command — expected defer exit 0 (got $CODE)"
fi
malformed_run "$(jq -n --arg w "$SANDBOX" '{tool_name:"Bash",tool_input:{command:"git status"},cwd:($w+"\u0000x")}')"
if [ "$CODE" -eq 0 ] && is_empty; then
  pass "defer form: a malformed cwd"
elif is_allow; then
  fail "defer form: a malformed cwd — FALSE-ALLOW: expected DEFER"
  false_allows=$((false_allows + 1))
else
  fail "defer form: a malformed cwd — expected defer exit 0 (got $CODE)"
fi
malformed_run "$(jq -n --arg w "$SANDBOX" '{tool_name:"Bash",tool_input:{command:"git status"},cwd:$w}')"
if [ "$CODE" -eq 0 ] && is_allow; then
  pass "parity: a well-formed cwd still allows"
else
  fail "parity: a well-formed cwd — expected allow (got $CODE)"
fi
malformed_run ''
if [ "$CODE" -eq 0 ] && is_empty; then pass "empty stdin defers"; else fail "empty stdin — expected defer exit 0 (got $CODE)"; fi
malformed_run '{"tool_name":"Bash","tool_input":{}}'
if [ "$CODE" -eq 0 ] && is_empty; then pass "missing command field defers"; else fail "missing command — expected defer exit 0 (got $CODE)"; fi
malformed_run '{"tool_name":"Bash","tool_input":{"command":""}}'
if [ "$CODE" -eq 0 ] && is_empty; then pass "empty-string command defers"; else fail "empty command — expected defer exit 0 (got $CODE)"; fi
malformed_run '{"tool_name":"Bash","tool_input":{"command":["not","a","string"]}}'
if [ "$CODE" -eq 0 ] && is_empty; then pass "non-string command defers"; else fail "non-string command — expected defer exit 0 (got $CODE)"; fi
# `cwd` carries the same type discipline as `command`: a PRESENT non-string value
# is a payload that does not match the PreToolUse contract and defers, rather than
# being containment-checked against whatever `jq -r` renders it as. ABSENT and
# null keep their documented $PWD fallback. Panel finding (codex backend, lens 10:
# a sibling consumed field lacking the guard its neighbour has).
for bad_cwd in '{"a":1}' '["/tmp"]' '5' 'true'; do
  malformed_run "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git status\"},\"cwd\":$bad_cwd}"
  if [ "$CODE" -eq 0 ] && is_empty; then
    pass "non-string cwd ($bad_cwd) defers"
  else
    if is_allow; then
      fail "non-string cwd ($bad_cwd) — FALSE-ALLOW: approved on a malformed payload"
      false_allows=$((false_allows + 1))
    else
      fail "non-string cwd ($bad_cwd) — expected defer exit 0 (got $CODE)"
    fi
  fi
done
malformed_run '{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":null}'
if [ "$CODE" -eq 0 ] && is_allow; then pass "null cwd keeps the \$PWD fallback"; else fail "null cwd — expected the \$PWD fallback to still allow (got $CODE)"; fi
malformed_run '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
if [ "$CODE" -eq 0 ] && is_allow; then pass "absent cwd keeps the \$PWD fallback"; else fail "absent cwd — expected the \$PWD fallback to still allow (got $CODE)"; fi

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

finish_suite worker-command-guard
