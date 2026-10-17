#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the enumerated known-safe shapes
# (REQ-A1.1, A1.5), every-segment compound analysis and redirects (REQ-A1.4),
# the explicit defer set (REQ-A1.6), the safe-invocation rule (REQ-A1.8), the
# red-team regressions, the narrowed sed/awk/plugin-root screens, the
# installed-plugin roots (REQ-A1.10), tracked assignments (REQ-A1.9, E1.2),
# and unresolved `$` in a screened position (REQ-E1.1).
# tests/test-worker-command-guard.sh holds the suite's overview; all its files
# source tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

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
assert_defer "the force-push helper is the tower's" "scripts/tower-force-push.sh push --branch b --to a --lease c"
assert_defer "the force-push helper bash-prefixed" "bash scripts/tower-force-push.sh confirm --branch b --to a"
assert_defer "the force-push helper in another casing" "scripts/Tower-Force-Push.sh push --branch b"
assert_defer "the force-push helper through a hardlink" "bash scripts/fph.sh confirm --branch b --to a"
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
# The blanket `|` reject this screen used to carry stalled real workers on
# their first command (2026-09-14), so `|` — and ONLY `|` — is recoverable, in
# the two spellings that can be positively identified: `||`, and a `|` inside a
# regex literal opened where awk cannot mean division. Everything else about
# the blanket screen stands, `>` included. The pairs below are the evidence
# that the separation holds in BOTH directions.
assert_allow "awk logical OR" "awk 'x||y{print}' file"
assert_allow "awk regex alternation" "awk '/a|b/{print}' file"
assert_allow "awk escaped | in a regex is literal" "awk '/a\\|b/{print}' file"
assert_allow "awk regex after ~ (spaced)" "awk '\$0 ~ /a|b/ {print \$2}' file"
assert_allow "awk regex as a function argument" "awk '{n = split(\$0, a, /x|y/); print n}' file"
assert_allow "awk regex opened after && " "awk 'p&&/a|b/{p=0} p{print}' file"
assert_defer "awk line continuation is refused outright" "awk '\$0 ~ \\
/a|b/ {print}' file"
assert_allow "awk character class in a regex" "awk '/[0-9]+/{print}' file"
assert_allow "awk POSIX class in a regex" "awk '\$0~/^[[:alpha:]]+\$/{print}' file"
# The stall this widening exists for, verbatim from the worker that hit it: a
# `||` chain, a regex holding both a `|` and the `#` of a markdown heading.
assert_allow "awk REQ-section filter (the stall that motivated the widening)" \
  "awk -v r=\"REQ-A\" 'index(\$0,\"**\"r\"**\")||index(\$0,\"### \"r)||index(\$0,\"- \"r\" \")||index(\$0,\"**\"r)==1{p=1;print;next} p&&/^- \\*\\*REQ-|^### REQ-|^## /{p=0} p{print}' file"
# Hostile pairs: each blessing must still refuse its dangerous twin.
assert_defer "awk print redirection with no space before >" "awk '{print>\"f\"}' file"
assert_defer "awk print pipe with no spaces" "awk '{print|\"sh\"}' file"
assert_defer "awk || in a string does not license a following pipe" "awk '{print \"a||b\" | \"sh\"}' file"
assert_defer "awk pipe after a real division" "awk '{c = a / 2; print | \"sh\"}' file"
assert_defer "awk pipe after a post-increment (dialects split on / here)" "awk '{a++ / 2; print | \"sh\"}' file"
assert_defer "awk redirection hidden behind a line continuation" "awk '{print \$0 \\
> \"f\"}' file"
assert_defer "awk redirection to a data-derived filename" "awk '{print \$1 > \$2}' file"
assert_defer "awk pipe to a variable command (no quotes needed)" "awk -v c=sh '{print \$1 | c}' file"
assert_defer "awk pipe smuggled behind a bracket/delimiter desync" "awk '/[/{print|\"sh\"}x[1]/{print}' file"
assert_defer "awk pipe inside a regex holding a quote" "awk '/a\"b|c/{print \$1}' file"
# The working bypasses of the lexer this screen replaced (2026-09-14), and the
# two this replacement's own first draft still allowed. Every one of them was
# ALLOWED and every one really ran: they pipe `id` into sh, except bypass 4,
# which writes /tmp/pwn. They are the regression seeds for the rule that a `/`
# the screen cannot place is a defer, never a span scanned on as code.
assert_defer "bypass 1 — regex misread as division opens a comment" "awk '{print /#/; print \"id\" | \"sh\"}' file"
assert_defer "bypass 2 — same, behind an arithmetic operator" "awk '{x = 0 + /#/; print \"id\" | \"sh\"}' file"
assert_defer "bypass 3 — regex holding a quote swallows the pipe" "awk '{ print /\"/ ; print \"id\" | \"sh\" ; print /\"/ }' file"
assert_defer "bypass 4 — regex misread as division hides a redirection" "awk '{print /; 5/ > \"/tmp/pwn\"}' file"
assert_defer "bypass 5 (this draft) — a ; or & inside a STRING must not bless the next /" \
  "awk 'BEGIN{c=\"sh\";s=\"id\"} {x = \"&\" /2; print s | c; y=1/2}' file"
assert_defer "bypass 6 (this draft) — a \\-newline is a continuation, not a statement end" \
  "awk 'BEGIN{c=\"sh\";s=\"id\"}{x = 1 \\
/ 2; print s | c; y = 1/3}' file"
# Outside a string or a regex the only `\` awk accepts is a line continuation,
# so every other `\X` defers rather than being consumed as an inert unit — a
# skip that swallowed `\|` would hide a command pipe from the screen even
# though no awk would run it.
assert_defer "awk backslash-pipe is consumed by nothing" "awk '{print \"id\" \\| \"sh\"}' file"
# Deliberate over-defers, all of them the fail-closed direction. A `>` is
# rejected wherever it appears, because telling a redirecting `>` from a
# relational one needs a real awk parser and this screen does not have one; a
# `|` a string hides is rejected because placing it would mean modelling what
# awk does with the value.
assert_defer "awk relational > outside a print statement (over-defer)" "awk '\$1 > 5' file"
assert_defer "awk relational > with no spaces (over-defer)" "awk 'NR>1{print}' file"
assert_defer "awk relational >= inside a print statement (over-defer)" "awk '{print (\$1 >= 5)}' file"
assert_defer "awk | inside a string literal (over-defer)" "awk '{print \"a|b\"}' file"
assert_defer "awk alternation across bracket expressions (over-defer)" "awk '/[0-9]+|[a-z]+/{print}' file"
assert_defer "awk getline in any form (over-defer)" "awk '{getline x; print x}' file"
# A program with no `|` left after the blanket screen carries no exec or write
# vector AT ALL — no `>`, `|`, `@`, `system`, `close`, `ENVIRON` or `getline` —
# so it is approved without a walk, whatever it would parse to. These three are
# unparseable, dialect-divergent, or both, and none of them can run or write
# anything; deferring them would cost every `/[0-9]+/` filter with it.
assert_allow "awk unterminated string literal, but no pipe to hide" "awk '{print \"unterminated}' file"
assert_allow "awk unterminated regex literal, but no pipe to hide" "awk '/unterminated{print}' file"
assert_allow "awk bracket expression containing the regex delimiter, no pipe" "awk '/[/]/{print}' file"
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
# path carries the plugin version work with zero setup. The env arms are
# emptied explicitly: a mise-run suite inherits this checkout as PLANWRIGHT_ROOT,
# which would otherwise grant the allow before self-location is consulted.
HOOK_ENV=("PLANWRIGHT_ROOT=" "CLAUDE_PLUGIN_ROOT=")
assert_allow "self-location arm — the hook's own sibling scripts/" "$REPO_ROOT/scripts/resolve-rule-doc.sh rigor" Bash "$PLUGIN_CWD"
HOOK_ENV=()
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
assert_defer "the plugin root's force-push helper through a hardlink" "bash $PLUGIN_ROOT/scripts/plug-fph.sh confirm --branch b" Bash "$PLUGIN_CWD"
HOOK_ENV=("PLANWRIGHT_ROOT=$SANDBOX/install/does-not-exist")
assert_defer "unresolvable root arm allows nothing" "$PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=()
assert_defer "plugin path with no root arm resolving to it" "$PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"

# --- Arm 5: the roots Claude Code itself installed the plugin at ---------------
# The 2026-09-12 stall: the launcher exported ITS root (a checkout) as arms 1-2,
# the worker's skill text resolved `${CLAUDE_PLUGIN_ROOT}` to the marketplace
# cache, and every plugin-script call deferred. The hook now also trusts what
# <claude-dir>/plugins/installed_plugins.json records and every version dir
# under <claude-dir>/plugins/cache/*/planwright/, with the same containment
# discipline as the other arms.
echo "### REQ-A1.10 — installed-plugin roots (arm 5)"
CDIR="$SANDBOX/cdir"
INST_JSON_ROOT="$CDIR/inst/planwright/0.40.0"
INST_CACHE_ROOT="$CDIR/plugins/cache/mkt/planwright/0.41.0"
INST_CACHE_DECOY="$CDIR/plugins/cache/mkt/planwright-evil/0.41.0"
INST_CACHE_OTHER="$CDIR/plugins/cache/mkt/otherplugin/0.41.0"
mkdir -p "$INST_JSON_ROOT/scripts" "$INST_CACHE_ROOT/scripts" "$INST_CACHE_ROOT/tests" \
  "$INST_CACHE_DECOY/scripts" "$INST_CACHE_OTHER/scripts" "$CDIR/plugins"
: >"$INST_JSON_ROOT/scripts/plug.sh"
: >"$INST_CACHE_ROOT/scripts/plug.sh"
: >"$INST_CACHE_ROOT/tests/plug.sh"
: >"$INST_CACHE_DECOY/scripts/plug.sh"
: >"$INST_CACHE_OTHER/scripts/plug.sh"
jq -n --arg p "$INST_JSON_ROOT" \
  '{version: 2, plugins: {"planwright@planwright": [{scope: "user", installPath: $p, version: "0.40.0"}], "other@mkt": [{installPath: "/nope"}]}}' \
  >"$CDIR/plugins/installed_plugins.json"
HOOK_ENV=("CLAUDE_DIR=$CDIR" "HOME=$SANDBOX/nohome")
assert_allow "arm 5 — installed_plugins.json installPath" "$INST_JSON_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "arm 5 — marketplace cache version dir" "$INST_CACHE_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "arm 5 — the stalled shape: a loop over a cache-root script" \
  "for d in a b; do printf '%s -> ' \$d; $INST_CACHE_ROOT/scripts/plug.sh \$d; done" Bash "$PLUGIN_CWD"
assert_defer "arm 5 — a cache plugin that is not planwright" "$INST_CACHE_OTHER/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "arm 5 — a name-PREFIX sibling under the cache" "$INST_CACHE_DECOY/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "arm 5 — tests/ under an installed root stays untrusted" "$INST_CACHE_ROOT/tests/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "arm 5 — .. escaping an installed root" "$INST_CACHE_ROOT/scripts/../../../../../inst/planwright/0.40.0/scripts/plug.sh" Bash "$PLUGIN_CWD"
printf '{not json' >"$CDIR/plugins/installed_plugins.json"
assert_defer "arm 5 — a malformed record trusts nothing from it" "$INST_JSON_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "arm 5 — the cache walk survives a malformed record" "$INST_CACHE_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=("CLAUDE_DIR=$SANDBOX/no-such-dir" "HOME=$SANDBOX/nohome")
assert_defer "arm 5 — no claude dir, nothing trusted" "$INST_CACHE_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
# A cache root that is a symlink canonicalizes to wherever it points, which
# would make that target trusted; at either level it defers (REQ-E1.1).
LINKED_TARGET="$SANDBOX/install/linked-target"
mkdir -p "$LINKED_TARGET/scripts" "$CDIR/plugins/cache/linkmkt"
: >"$LINKED_TARGET/scripts/plug.sh"
ln -s "$LINKED_TARGET" "$CDIR/plugins/cache/mkt/planwright/9.9.9"
ln -s "$SANDBOX/install/linked-mkt" "$CDIR/plugins/cache/evilmkt"
mkdir -p "$SANDBOX/install/linked-mkt/planwright/1.0.0/scripts"
: >"$SANDBOX/install/linked-mkt/planwright/1.0.0/scripts/plug.sh"
HOOK_ENV=("CLAUDE_DIR=$CDIR" "HOME=$SANDBOX/nohome")
assert_defer "bypass: a symlinked cache version root" "$CDIR/plugins/cache/mkt/planwright/9.9.9/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "bypass: a symlinked cache marketplace dir" "$CDIR/plugins/cache/evilmkt/planwright/1.0.0/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "a real cache root beside a symlinked one still allows" "$INST_CACHE_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
ln -s "$LINKED_TARGET" "$SANDBOX/install/linked-plugin-root"
HOOK_ENV=("CLAUDE_PLUGIN_ROOT=$SANDBOX/install/linked-plugin-root")
assert_defer "bypass: a symlinked CLAUDE_PLUGIN_ROOT" "$LINKED_TARGET/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=("CLAUDE_PLUGIN_ROOT=$SANDBOX/install/linked-plugin-root/.")
assert_defer "bypass: a symlinked CLAUDE_PLUGIN_ROOT behind a trailing /." "$LINKED_TARGET/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=()

# --- Same-command variable tracking (the raw-command premise) ---------------
# Claude Code hands the hook the command as written: `$P` arrives unexpanded.
# The verifier resolves exactly one class of expansion itself — a standalone,
# unconditional, top-level assignment of a bare absolute path inside a trusted
# root — and every other `$` in a verb still defers.
echo "### REQ-A1.9 / REQ-E1.2 — tracked assignments"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_allow "tracked: the 2026-09-12 stalled command shape" \
  "P=$PLUGIN_ROOT && for d in a b c; do printf '%s -> ' \$d; \$P/scripts/plug.sh \$d; done; echo; grep -n 'Status:' specs/x.md | head" Bash "$PLUGIN_CWD"
assert_allow "tracked: \$P verb" "P=$PLUGIN_ROOT && \$P/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_allow "tracked: \${P} verb" "P=$PLUGIN_ROOT && \${P}/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_allow "tracked: double-quoted \"\$P\" expands" "P=$PLUGIN_ROOT && \"\$P\"/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_allow "tracked: quoted VALUE is still an assignment" "P=\"$PLUGIN_ROOT\" && \$P/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_allow "tracked: semicolon-separated" "P=$PLUGIN_ROOT; \$P/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_allow "tracked: two assignments chained by &&" "A=$PLUGIN_ROOT && B=$PLUGIN_ROOT/scripts && \$A/scripts/plug.sh && \$B/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "tracked: later assignment wins" "P=$PLUGIN_ROOT/scripts && P=$PLUGIN_ROOT && \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "REQ-E1.2: an earlier untrusted value is replaced by the later one" "P=$PLUGIN_DECOY && P=$PLUGIN_ROOT && \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "REQ-E1.2: a later untrusted value replaces the trusted one" "P=$PLUGIN_ROOT && P=$PLUGIN_DECOY && \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "tracked: used inside a later if body" "P=$PLUGIN_ROOT; if true; then \$P/scripts/plug.sh; fi" Bash "$PLUGIN_CWD"
assert_allow "tracked: bash \$P/<script>" "P=$PLUGIN_ROOT && bash \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "tracked: repo root through the cwd's checkout" "R=$SANDBOX && \$R/scripts/ok.sh" Bash "$SANDBOX"
assert_defer "defer form: a tracked assignment to zsh's path" "path=$SANDBOX && cat README.md" Bash "$SANDBOX"
assert_defer "defer form: a modifier on a tracked variable" "P=$SANDBOX && find . -name \$P:t" Bash "$SANDBOX"
assert_defer "defer form: a subscript on a tracked variable" "P=$SANDBOX && find . -name \"\$P[1]\"" Bash "$SANDBOX"
# zsh evaluates an unbraced subscript as arithmetic, so it can re-point a
# variable the guard has modelled before a later script path reads it.
assert_defer "bypass: a zsh subscript re-points a modelled script path" "v=scripts/ok.sh; ls \$q[v=7]; bash \$v" Bash "$SANDBOX"
assert_defer "bypass: a quoted zsh subscript re-points a script operand" "v=scripts/ok.sh; echo \"\$q[v=7]\"; scripts/ok.sh \$v" Bash "$SANDBOX"
assert_defer "defer form: an unbraced subscript on an unknown name" "echo \$q[1]" Bash "$SANDBOX"
assert_defer "bypass: a zsh subscript on \$* re-points a script path" "v=scripts/ok.sh; echo \"\$*[v=7]\"; bash \$v" Bash "$SANDBOX"
assert_defer "defer form: a zsh subscript on \$@" "echo \$@[v=7]" Bash "$SANDBOX"
assert_defer "defer form: a zsh subscript on \$?" "echo \$?[1]" Bash "$SANDBOX"
assert_defer "defer form: a zsh subscript on a positional parameter" "echo \$1[v=7]" Bash "$SANDBOX"
assert_defer "bypass: a zsh flag before a special parameter's subscript" "echo \$=*[v=7]" Bash "$SANDBOX"
assert_defer "defer form: a zsh ^ flag before \$@'s subscript" "echo \$^@[v=7]" Bash "$SANDBOX"
assert_defer "defer form: a zsh + flag before \$?'s subscript" "echo \$+?[1]" Bash "$SANDBOX"
assert_defer "defer form: a zsh = flag before \$#'s subscript" "echo \$=#[1]" Bash "$SANDBOX"
assert_allow "parity: a flagged parameter with no subscript still allows" "echo \$=x \"\$@\" \$*" Bash "$SANDBOX"
assert_defer "defer form: a zsh subscript on \$_" "echo \$_[v=7]" Bash "$SANDBOX"
assert_allow "parity: a special parameter with no subscript still allows" "echo \"\$?:\$!\" \$*" Bash "$SANDBOX"
assert_allow "parity: a braced tracked variable before a colon is still its value" "P=$SANDBOX && cat \${P}/README.md:x" Bash "$SANDBOX"
assert_allow "tracked: a lone assignment runs nothing" "P=$PLUGIN_ROOT" Bash "$PLUGIN_CWD"
# NEGATIVES: every way the substitution could differ from what the shell does,
# or name something the hook does not trust.
assert_defer "defer: single-quoted '\$P' is literal" "P=$PLUGIN_ROOT && '\$P'/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_defer "defer: backslash-escaped \\\$P is literal" "P=$PLUGIN_ROOT && \\\$P/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_defer "defer: whole-word quoted 'P=..' is a command" "'P=$PLUGIN_ROOT' && \$P/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_defer "defer: \${P:-x} modifier" "P=$PLUGIN_ROOT && \${P:-/tmp}/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_defer "defer: unknown variable" "\$Q/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_defer "defer: value outside every trusted root" "P=$SANDBOX/install/outside && \$P/evil.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: name-PREFIX decoy root as value" "P=$PLUGIN_DECOY && \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: value with a glob" "P=$PLUGIN_ROOT/* && \$P/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: value with .. that escapes" "P=$PLUGIN_ROOT/../../.. && \$P/etc/x.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: value carries an expansion" "P=\$Q && \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: tilde value" "P=~ && \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: IFS even with a trusted value" "IFS=$PLUGIN_ROOT && \$IFS/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: PATH even with a trusted value" "PATH=$PLUGIN_ROOT && \$PATH/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: CDPATH" "CDPATH=$PLUGIN_ROOT && \$CDPATH/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: BASH_ENV" "BASH_ENV=$PLUGIN_ROOT && \$BASH_ENV/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: PS4" "PS4=$PLUGIN_ROOT && \$PS4/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: an exported name (HOME)" "HOME=$PLUGIN_ROOT && \$HOME/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "P=/already-exported")
assert_defer "defer: a name present in the hook's environment" "P=$PLUGIN_ROOT && \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_defer "defer: assignment conditional after a command (&&)" "true && P=$PLUGIN_ROOT; \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: assignment conditional after a command (||)" "false || P=$PLUGIN_ROOT; \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: assignment inside a loop body" "for d in a; do P=$PLUGIN_ROOT; done; \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: assignment inside an if body" "if true; then P=$PLUGIN_ROOT; fi; \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: assignment in a pipeline" "P=$PLUGIN_ROOT | cat; \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: assignment backgrounded" "P=$PLUGIN_ROOT & \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: assignment PREFIX still defers" "P=$PLUGIN_ROOT \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: the table does not cross into fish -c" "P=$PLUGIN_ROOT && fish -c '\$P/scripts/plug.sh'" Bash "$PLUGIN_CWD"
assert_defer "defer: substituted verb still needs a trusted script" "P=$PLUGIN_ROOT && \$P/notscripts.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: substituted path with .. escaping" "P=$PLUGIN_ROOT && \$P/scripts/../../outside/evil.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: substitution never widens the verb set" "P=$PLUGIN_ROOT && rm -rf \$P" Bash "$PLUGIN_CWD"
assert_defer "defer: a closer with no opener" "P=$PLUGIN_ROOT; fi; \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
# The boundaries the tracker turns on, each one a verdict a one-token mutant
# flips: a literal `\$` inside double quotes, quoting that starts exactly on
# the `=`, the two expand_word shapes that leave the `$` in place, the newline
# separator, nesting, and the environment-name probe against the names the
# dispatch wrapper actually exports.
assert_defer "defer: double-quoted \"\\\$P\" is literal" "P=$PLUGIN_ROOT && \"\\\$P\"/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_defer "defer: quoting that starts on the = makes a command word" "P\"=\"$PLUGIN_ROOT && \$P/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_defer "defer: unterminated \${P" "P=$PLUGIN_ROOT && \${P/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_defer "defer: \$Pfoo is another name" "P=$PLUGIN_ROOT && \$Pfoo/scripts/plug.sh" Bash "$PLUGIN_CWD"
assert_allow "tracked: newline-separated" "P=$PLUGIN_ROOT
\$P/scripts/plug.sh x" Bash "$PLUGIN_CWD"
assert_allow "tracked: used inside an if nested in a for" "P=$PLUGIN_ROOT; for d in a; do if true; then \$P/scripts/plug.sh x; fi; done" Bash "$PLUGIN_CWD"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "LD_PRELOAD=/already-exported")
assert_defer "defer: an exported LD_PRELOAD is refused as a name" "LD_PRELOAD=$PLUGIN_ROOT && \$LD_PRELOAD/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_defer "defer: PLANWRIGHT_ROOT, exported by the dispatch wrapper" "PLANWRIGHT_ROOT=$PLUGIN_ROOT && \$PLANWRIGHT_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=("CLAUDE_PLUGIN_ROOT=$PLUGIN_ROOT")
assert_defer "defer: CLAUDE_PLUGIN_ROOT, exported by the dispatch wrapper" "CLAUDE_PLUGIN_ROOT=$PLUGIN_ROOT && \$CLAUDE_PLUGIN_ROOT/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=()

# The hook sees the command unexpanded, so a word whose value it cannot see
# must never satisfy a screen that reads that value. Each bypass below was
# approved by the guard before the fix; the regression-only rows already
# deferred and pin that they keep doing so.
echo "### REQ-E1.1 — an unresolved \$ in a screened position defers"
assert_defer "bypass: a loop head word smuggles find flags" \
  "for d in \"-maxdepth 0 -exec id ;\"; do find . \$d; done"
assert_defer "bypass: \$_ carries the previous command's last word into find" \
  "printf '%s' '-maxdepth 0 -exec id ;' >/dev/null; find . \$_"
assert_defer "bypass: a non-literal loop head reaching cat" "for d in \$X; do cat \$d; done"
assert_defer "bypass: a non-literal loop head reaching sed" "for d in \$X; do sed \$d f; done"
assert_defer "bypass: a non-literal loop head reaching awk" "for p in \$X; do awk \$p f; done"
assert_defer "bypass: a positional parameter as a find operand" "find . \$1"
assert_defer "bypass: \"\$@\" as a git operand" "git log \"\$@\""
assert_defer "bypass: a glob in a direct verb path" "scripts/o*.sh"
assert_defer "bypass: a glob in a bash script path" "bash scripts/o*.sh"
assert_defer "bypass: brace expansion assembles a find action" "find . -maxdepth 0 {-exec,id} ';'"
assert_defer "bypass: a loop variable named PATH re-points later verbs" "for PATH in /tmp; do git status; done"
assert_defer "defer form: zsh's path as a loop variable" "for path in scripts; do cat README.md; done"
assert_defer "defer form: zsh's cdpath as a loop variable" "for cdpath in /tmp; do git status; done"
assert_defer "defer form: NULLCMD as a loop variable" "for NULLCMD in /tmp/x; do >/dev/null; done"
assert_defer "defer form: READNULLCMD as a loop variable" "for READNULLCMD in /tmp/x; do <README.md; done"
assert_defer "defer form: module_path as a loop variable" "for module_path in /tmp/x; do for commands in x; do git status; done; done"
assert_defer "defer form: MODULE_PATH as a loop variable" "for MODULE_PATH in /tmp/x; do git status; done"
assert_defer "defer form: a further special name as a loop variable (1)" "for fpath in /tmp/x; do git status; done"
assert_defer "defer form: a further special name as a loop variable (2)" "for FPATH in /tmp/x; do git status; done"
assert_defer "defer form: a further special name as a loop variable (3)" "for manpath in /tmp/x; do git status; done"
assert_defer "defer form: a further special name as a loop variable (4)" "for MANPATH in /tmp/x; do git status; done"
assert_allow "parity: a longer name sharing a special name's prefix still resolves" "for fpaths in scripts; do cat README.md; done"
assert_allow "parity: a longer lowercase loop variable still resolves" "for paths in scripts; do cat README.md; done"
assert_defer "defer form: zsh's \$~ parameter form" "for f in a; do find . \$~f; done"
assert_defer "defer form: zsh's \$= parameter form" "for f in a; do find . \$=f; done"
assert_defer "defer form: zsh's \$^ parameter form" "for f in a; do find . \$^f; done"
assert_defer "defer form: zsh's \$+ parameter form" "for f in a; do find . \$+f; done"
assert_defer "defer form: zsh's \$~ parameter form in double quotes" "for f in a; do find . \"\$~f\"; done"
assert_allow "parity: a plain loop variable still resolves for find" "for f in a; do find . -name \$f; done"
assert_defer "defer form: a zsh subscript on an unbraced loop variable" "for f in abcd; do find . -name \"\$f[2,3]\"; done"
assert_defer "defer form: a zsh modifier on an unbraced loop variable" "for f in a.b; do find . -name \$f:e; done"
assert_defer "defer form: a zsh modifier on a quoted loop variable" "for f in A; do find . -name \"\$f:l\"; done"
assert_defer "defer form: a zsh substitution modifier on a loop variable" "for f in a; do find . -name \$f:s/a/b/; done"
assert_allow "parity: a braced loop variable before a colon is still its value" "for f in README; do cat \${f}:x; done"
assert_allow "parity: a braced loop variable before a bracket is still its value" "for f in a; do find . -name \"\${f}[0-9]\"; done"
assert_defer "defer form: zsh's \$= parameter form reaching jq" "for f in a; do jq -n \$=f; done"
assert_defer "defer form: zsh's \$^ parameter form reaching jq" "for f in a; do jq -n \$^f; done"
assert_defer "defer form: zsh's \$~ parameter form in double quotes reaching jq" "for f in a; do jq -n \"\$~f\"; done"
assert_defer "defer form: a zsh subscript on a quoted loop variable reaching jq" "for f in abcd; do jq -n \"\$f[2,3]\"; done"
assert_defer "defer form: a zsh modifier on a loop variable reaching jq" "for f in a.b; do jq -n \$f:e; done"
assert_defer "defer form: zsh's glob-substitution parameter form after an argument-independent verb" "echo \$~X"
assert_defer "defer form: zsh's glob-substitution parameter form over a value read from a file" "read -r X < README.md; echo \$~X"
assert_defer "defer form: zsh's glob-substitution parameter form past a printf format" "printf '%s' \$~X"
assert_defer "defer form: a non-ASCII letter directly after a loop variable" "for f in x; do cat a\$fé; done"
assert_defer "defer form: a non-ASCII letter after a loop variable inside double quotes reaching jq" "for f in x; do jq -n \".a\$fé\"; done"
assert_defer "defer form: a dollar directly before a non-ASCII letter" "jq -n '.a'\$é'b'"
assert_allow "parity: a braced loop variable before a non-ASCII letter is still its value" "for f in README; do cat \${f}é; done"
assert_defer "bypass: read overwrites a loop variable before a screened use" \
  "for d in -name; do read d; find . \$d; done"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_defer "bypass: read overwrites a tracked variable" \
  "P=$PLUGIN_ROOT && read P && \$P/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=()
assert_defer "regression-only: a loop variable reaching bash" "for d in a; do bash \$d; done"
assert_defer "bypass: an unexpanded operand passes bats containment as a literal name" "bats \$X"
assert_defer "bypass: a loop variable reaching bats containment" "for d in /tmp/evil.bats; do bats \$d; done"
assert_defer "a loop variable outlives its loop as opaque" "for d in -name; do true; done; find . \$d x"
assert_defer "select is not modelled" "select d in a b; do echo \$d; done"
assert_defer "for with no in-list iterates the positionals" "for d; do echo \$d; done"
assert_defer "an arithmetic for header" "for ((i=0;i<3;i++)); do echo \$i; done"
LOOP17='w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12 w13 w14 w15 w16 w17'
LOOP16='w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12 w13 w14 w15 w16'
assert_defer "a loop head past the bound defers whole" "for f in $LOOP17; do echo \$f; done"
assert_allow "a loop head at the bound is verified" "for f in $LOOP16; do grep -n x \$f; done"
assert_allow "a plain-literal loop head behaves as its substituted form" \
  "for f in a b; do grep -n x \$f; done"
assert_allow "a resolved loop variable passes a screened verb" \
  "for f in a.sh b.sh; do find . -name \$f; done"
assert_defer "a resolved loop variable still meets the screen" \
  "for f in -name -delete; do find . \$f; done"
assert_allow "nested loops resolve both variables" \
  "for a in x y; do for b in p q; do find . -name \$a\$b; done; done"
assert_allow "an opaque operand of an argument-independent verb" "ls \$X; echo \"\$Y\"; printf '%s\\n' \"\$Z\""
assert_allow "a quoted glob is a literal" "find . -name '*.sh' -type f"

LOOP9='a b c d e f g h i'
assert_defer "nested loops past the pass bound defer" \
  "for x in $LOOP9; do for y in $LOOP9; do echo \$x\$y; done; done"
MANY=''
for _ in $(seq 520); do MANY="${MANY}true; "; done
assert_defer "a command past the simple-command bound defers" "$MANY"
assert_defer "REQ-A1.14: an unassigned variable in a script path" "bash \$X/scripts/x.sh"
assert_defer "REQ-A1.14: a relative assigned path is not tracked" "X=../../../tmp/evil; bash \$X/scripts/x.sh"
# Expansions that evaluate a value as arithmetic (a subscript, an offset,
# `$[…]`) or indirectly run a `$(…)` the hook never sees, whatever the verb.
assert_defer "bypass: a read value as an array subscript" "read -r b < f; echo \${a[b]}"
assert_defer "bypass: a read value as a substring offset" "read -r b < f; echo \${x:b}"
assert_defer "bypass: a read value in \$[ ] arithmetic" "read -r b < f; echo \$[b]"
assert_defer "bypass: a read value through indirection" "read -r b < f; echo \${!b}"
assert_defer "an environment value as a subscript" "echo \"\${a[X]}\""
assert_allow "a braced bare name stays an opaque operand" "echo \"\${HOME}/x\""

finish_suite worker-command-guard-shapes
