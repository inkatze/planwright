#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the widened allowlist verbs and
# the write/exec vectors that kept each off the list, the real-world stall
# commands, and the regression baseline of shapes that must stay allowed.
# tests/test-worker-command-guard.sh holds the suite's overview; all its files
# source tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

echo "### Widened allowlist (2026-09-14) — the verbs measured worker stalls needed"
# Two real dispatched workers stalled within ~30s on their FIRST command, both
# pure read-only exploration, because these verbs were absent from the
# allowlist. Each pair is the positive the worker needed plus the write/exec
# vector that kept the verb off the list until now.
# `env`: bare only. `env <assignment|flag> <command>` EXECUTES the command, and
# `-u`/`-C`/`-S` take values, so an operand cannot be told apart from a command.
assert_allow "env bare prints the environment" "env"
assert_allow "env piped into grep" "env | grep -i planwright"
assert_defer "env with an assignment prefix execs" "env FOO=bar rm -rf x"
assert_defer "env -i execs" "env -i /bin/sh"
assert_defer "env -u execs" "env -u PATH cat file"
assert_defer "env with a bare command operand execs" "env rm -rf x"
assert_allow "printenv one name" "printenv PATH"
assert_allow "printenv bare" "printenv"
# `read` assigns SHELL variables, so each name goes through assign_name_ok —
# `read PATH` would re-point every later command in the same shell.
assert_allow "while read loop over a file" "while read l; do echo \"\$l\"; done < file"
assert_allow "while read -r loop" "while read -r line; do echo \"\$line\"; done"
assert_allow "read bare sets REPLY" "read"
assert_defer "read PATH poisons command resolution" "read PATH"
assert_defer "read IFS changes later word splitting" "read IFS"
assert_defer "defer form: read of zsh's path" "read path"
assert_defer "defer form: read of zsh's module_path" "read -r module_path"
assert_defer "defer form: read of a further special name" "read fpath"
assert_defer "defer form: a tracked assignment to a further special name" "fpath=$SANDBOX && cat README.md" Bash "$SANDBOX"
assert_allow "parity: read of a longer lowercase name" "read paths"
assert_defer "read inside a loop is name-checked too" "while read PATH; do echo x; done"
assert_defer "read -p takes a value operand" "read -p 'x' y"
assert_defer "read -a array form" "read -a arr"
# The guard's OWN shell state must never answer for the name under test. `i` is
# the commonest loop variable there is, `a` is this file's token variable, and
# `name` is assign_name_ok's own parameter: all three deferred while the
# shadowing rule was an indirect expansion, which reads locals as readily as
# the environment it meant to consult (2026-09-14).
assert_allow "read i" "while read i; do echo \"\$i\"; done < file"
assert_allow "read a" "read a"
assert_allow "read name" "read name"
assert_allow "read several names at once" "read i j k"
# jq's language has no exec and no file-write primitive, but it CAN read the
# environment, and the guard cannot see what a filter does with the value. So
# `env` and `$ENV` defer for the same reason awk's `ENVIRON` does, and the
# filter has to be identified before it can be screened: that is why every
# value-taking flag is enumerated and why the `-f`/`-L` forms, whose program
# text the guard never sees, defer.
assert_allow "jq filter" "jq . file.json"
assert_allow "jq raw output" "jq -r '.a[]' file.json"
assert_allow "jq combined short flags" "jq -rc '.a' file.json"
assert_allow "jq in a pipeline" "gh pr view 5 --json title | jq -r .title"
assert_allow "jq .env is a field access, not the builtin" "jq '.env' file.json"
assert_allow "jq nested .a.env field access" "jq '.a.env' file.json"
assert_allow "jq .envelope is a longer name" "jq -r '.envelope' file.json"
assert_allow "jq --indent takes a value, the filter follows it" "jq --indent 4 '.a' file.json"
assert_allow "jq --arg takes two values" "jq --arg x 1 '.a' file.json"
assert_allow "jq --args leaves the filter first" "jq --args '.a' one two"
assert_allow "jq -- ends the flags" "jq -- '.a' file.json"
assert_defer "jq env builtin decants the environment" "jq -n env"
assert_defer "jq \$ENV decants the environment" "jq -n '\$ENV'"
assert_defer "jq env.PATH single-key read" "jq -n 'env.PATH'"
assert_defer "jq \$ENV in a string interpolation" "jq -n '\"\\(\$ENV)\"'"
assert_defer "jq env after a pipe" "jq -n '.|env'"
assert_defer "jq env inside a collection" "jq -n '[env]'"
assert_defer "jq env behind --indent's value" "jq --indent 4 '\$ENV'"
assert_defer "jq env behind --arg's two values" "jq --arg x 1 '\$ENV'"
assert_defer "jq env after --" "jq -- '\$ENV'"
assert_defer "jq -f program file is unscreenable" "jq -f prog.jq file.json"
assert_defer "jq --from-file long form" "jq --from-file prog.jq file.json"
assert_defer "jq -f bundled into a short cluster" "jq -nf prog.jq"
assert_defer "jq -L loads module text the guard never sees" "jq -L /tmp/mods 'include \"m\"; .' file.json"
assert_defer "jq --library-path long form" "jq --library-path /tmp/mods '.' file.json"
assert_defer "jq unknown long flag" "jq --frobnicate '.a' file.json"
assert_defer "jq unknown short flag" "jq -z '.a' file.json"
assert_defer "jq dangling value-flag" "jq --indent"
assert_defer "jq with no filter at all" "jq"
# A filter's module text and its `ENV` spellings defer, and so does every run
# while ~/.jq exists or HOME is not an absolute path.
assert_defer "defer form: jq include with a search path" "jq -n 'include \"m\" {search:\"/tmp/mods\"}; f'"
assert_defer "defer form: jq import with a search path" "jq -n 'import \"m\" as e {search:\"/tmp/mods\"}; .'"
assert_defer "defer form: jq include" "jq -n 'include \"m\"; .'"
assert_defer "defer form: jq import of data" "jq -n 'import \"d\" as \$d; \$d'"
assert_allow "parity: jq .include is a field access" "jq '.include' file.json"
assert_allow "parity: jq .imports is a field access" "jq '.a.imports' file.json"
assert_allow "parity: jq \$import is a variable" "jq --arg import 1 '\$import' file.json"
assert_defer "defer form: jq ENV after a spaced dollar" "jq -n '\$ ENV'"
assert_defer "defer form: jq ENV after a dollar and a comment" "jq -n '\$#c
ENV'"
assert_defer "defer form: jq bare ENV word" "jq -n 'ENV'"
assert_allow "parity: jq .ENV is a field access" "jq '.ENV' file.json"
assert_allow "parity: jq ENVIRONMENT is a longer name" "jq '.a | .ENVIRONMENT' file.json"
assert_defer "defer form: jq import as the last word" "jq -n '. | import'"
assert_defer "defer form: jq ENV right after an opening bracket" "jq -n '[ENV]'"
assert_allow "parity: jq a filter dense in e and i beside a field" "jq '.env | .items[] | select(.line == \"eine\") | .id' file.json"
assert_allow "parity: jq a user function with env as a prefix" "jq 'def envx: .; envx' file.json"
assert_allow "parity: jq a user function with env as a suffix" "jq 'def myenv: .; myenv' file.json"
assert_allow "parity: jq a user function with ENV as a suffix" "jq 'def myENV: .; myENV' file.json"
assert_defer "defer form: a further jq module read" "jq -n '\"m\"|modulemeta'"
assert_defer "defer form: a further jq module read as the whole filter" "jq -n modulemeta"
assert_allow "parity: jq a field named like a module builtin" "jq '.modulemeta' file.json"
assert_allow "parity: jq a longer name starting like a module builtin" "jq 'def modulemetax: .; modulemetax' file.json"
JQ_HOME="$SANDBOX/jq-home"
mkdir -p "$JQ_HOME" && : >"$JQ_HOME/.jq" || exit 1
HOOK_ENV=(HOME="$JQ_HOME")
assert_defer "defer form: jq while a ~/.jq file exists" "jq . file.json"
rm -f "$JQ_HOME/.jq" && mkdir "$JQ_HOME/.jq" || exit 1 # not-a-lock: test fixture directory
assert_defer "defer form: jq while a ~/.jq directory exists" "jq . file.json"
rmdir "$JQ_HOME/.jq" && ln -s "$JQ_HOME/not-yet" "$JQ_HOME/.jq" || exit 1
assert_defer "defer form: jq while ~/.jq is a dangling symlink" "jq . file.json"
rm -f "$JQ_HOME/.jq"
assert_allow "parity: jq once ~/.jq is gone" "jq . file.json"
# The unset case chains a second env, since run_hook's own one sets HOME first.
HOOK_ENV=(/usr/bin/env -u HOME)
assert_defer "defer form: jq with HOME unset" "jq . file.json"
HOOK_ENV=(HOME=)
assert_defer "defer form: jq with HOME empty" "jq . file.json"
HOOK_ENV=(HOME=rel-home)
assert_defer "defer form: jq with a relative HOME" "jq . file.json"
HOOK_ENV=()
# A program word holding an unquoted character that a non-default zsh option
# (extended globbing, brace character classes) would expand defers in the
# screens that read program text; the same characters elsewhere, and inside
# quotes, keep their verdicts.
assert_defer "defer form: an unquoted caret in a jq program word" "jq .a^b file.json"
assert_defer "defer form: an unquoted mid-word tilde in a jq program word" "jq .a~b file.json"
assert_defer "defer form: an unquoted mid-word hash in a jq program word" "jq .a#b file.json"
assert_defer "defer form: an unquoted brace in a jq program word" "jq .a{b} file.json"
assert_defer "defer form: an unquoted caret in an awk program word" "awk /a^b/ file"
assert_defer "defer form: an unquoted brace in an awk program word" "awk {print} file"
assert_defer "defer form: an unquoted caret in a sed script word" "sed s/a^/b/ file"
assert_defer "defer form: an unquoted mid-word tilde in a sed -e script" "sed -e s/a~/b/ file"
assert_defer "defer form: an unquoted brace in a sed --expression script" "sed --expression=1{p} file"
assert_allow "parity: a quoted jq filter with a caret, tilde, hash and brace" "jq '.a | {b} | test(\"^x~#\")' file.json"
assert_allow "parity: a quoted awk program with braces" "awk '{print \$1}' file"
assert_allow "parity: a quoted sed script with a caret" "sed 's/^a/b/' file"
assert_allow "parity: an unquoted jq program word without those characters" "jq .a file.json"
assert_allow "parity: an input file named with a caret after the jq filter" "jq . a^b.json"
assert_allow "parity: a git revision with a parent suffix" "git show HEAD^"
assert_allow "parity: a git revision with an ancestor suffix" "git log --oneline HEAD~2"
assert_allow "parity: a git reflog selector" "git reflog show HEAD@{1}"
assert_allow "parity: a mid-word hash in a read operand" "cat a#b"
# yq EDITS IN PLACE.
assert_allow "yq read" "yq . file.yml"
assert_allow "yq -I indent is not -i inplace" "yq -I4 . file.yml"
assert_defer "yq -i writes the file back" "yq -i '.a=1' file.yml"
assert_defer "yq --inplace long form" "yq --inplace '.a=1' file.yml"
assert_defer "yq bundled -Pi" "yq -Pi '.a=1' file.yml"
assert_defer "yq -s splits into files" "yq -s '.a' file.yml"
assert_defer "yq --split-exp long form" "yq --split-exp '.a' file.yml"

# yq's env()/strenv() is the same capability as awk's ENVIRON and jq's env:
# program text whose use of the value the guard cannot see. It was the one
# member of that family left unscreened (found by the panel pass, 2026-09-14).
assert_defer "yq env() reads the environment" "yq 'env(GH_TOKEN)' f.yml"
assert_defer "yq strenv() reads the environment" "yq 'strenv(GH_TOKEN)' f.yml"
assert_defer "yq env() inside an assignment" "yq '.a = env(HOME)' f.yml"
assert_defer "yq --from-file hides the expression" "yq --from-file e.yq f.yml"
assert_allow "yq plain field access" "yq '.a' f.yml"
assert_allow "yq a longer name containing env" "yq '.environment' f.yml"
assert_defer "REQ-E1.6: yq load_str reads any path" "yq 'load_str(\"/proc/1/environ\")' f.yml"
assert_defer "REQ-E1.6: yq load reads any path" "yq -n 'load(\"x.yml\")'"
assert_defer "REQ-E1.6: yq load_xml after a pipe" "yq '.a | load_xml(\"x\")' f.yml"
assert_allow "REQ-E1.6: yq fields containing load" "yq '.payload, .upload.load' f.yml"
assert_defer "defer form: a yq environment read (1)" "yq -n '\"x\" | envsubst'"
assert_defer "defer form: a yq environment read (2)" "yq '.a | envsubst(nu)' f.yml"
assert_defer "defer form: a yq environment read (3)" "yq -n '\$ENV'"
assert_defer "defer form: a yq environment read (4)" "yq -n '\$ ENV'"
assert_defer "defer form: a yq module form (1)" "yq -n 'include \"m\"; .'"
assert_defer "defer form: a yq module form (2)" "yq -n 'import \"m\" as e; .'"
assert_defer "defer form: a yq module form (3)" "yq -n '\"m\"|modulemeta'"
assert_allow "parity: yq a field named like a screened word" "yq '.include' f.yml"
assert_allow "parity: yq a field sharing an environment read's prefix" "yq '.envs' f.yml"
assert_allow "parity: yq a longer name sharing a screened prefix" "yq '.a.imports' f.yml"
assert_defer "defer form: a yq flag form (1)" "yq -n --security-enable-system-operator 'system(\"id\")'"
assert_defer "defer form: a yq flag form (2)" "yq --split-exp-file e.yq f.yml"
assert_defer "defer form: a yq flag form (3)" "yq -n --expression='env(HOME)'"
assert_allow "parity: yq short flags with an attached value" "yq -n -o=json '.a'"
assert_defer "defer form: a yq operand form (1)" "yq -o json 'env(HOME)' f.yml"
assert_defer "defer form: a yq operand form (2)" "yq e 'env(HOME)' f.yml"
assert_defer "defer form: a yq operand form (3)" "yq -n -- 'env(HOME)'"
assert_allow "parity: yq several file operands" "yq '.a' f.yml g.yml"
assert_allow "parity: yq a short subcommand before the expression" "yq e '.a' f.yml"
assert_allow "parity: yq an expression after the end of flags" "yq -- '.a' f.yml"
assert_defer "defer form: a yq expression form (1)" "yq -n 'eval(\"e\" + \"nv(HOME)\")'"
assert_defer "defer form: a yq expression form (2)" "yq -n 'eval (.a)'"
assert_allow "parity: yq a longer name sharing an expression form's prefix" "yq '.evaluation' f.yml"
assert_allow "parity: yq a field named like an expression form" "yq '.a.eval' f.yml"
assert_allow "parity: yq the long subcommand before the expression" "yq eval '.a' f.yml"
assert_allow "parity: yq the all-documents subcommand before the expression" "yq eval-all '.a' f.yml"
YQ_HOME="$SANDBOX/yq-home"
mkdir -p "$YQ_HOME" && : >"$YQ_HOME/.jq" || exit 1
HOOK_ENV=(HOME="$YQ_HOME")
assert_defer "defer form: yq while a home module file exists" "yq . file.yml"
rm -f "$YQ_HOME/.jq"
assert_allow "parity: yq once the home module file is gone" "yq . file.yml"
HOOK_ENV=(HOME=rel-home)
assert_defer "defer form: yq with a relative HOME" "yq . file.yml"
HOOK_ENV=()
# shfmt: -w formats in place.
assert_allow "shfmt diff mode" "shfmt -d ."
assert_allow "shfmt list mode" "shfmt -l ."
assert_defer "shfmt -w writes" "shfmt -w scripts/x.sh"
assert_defer "shfmt --write long form" "shfmt --write scripts/x.sh"
assert_defer "shfmt bundled -lw" "shfmt -lw ."
# rg / fd: no write vector, but each can RUN a program.
assert_allow "rg search" "rg -n foo src/"
assert_defer "rg --pre runs a program per file" "rg --pre /tmp/evil.sh foo"
assert_defer "rg --pre= attached form" "rg --pre=/tmp/evil.sh foo"
assert_defer "rg --hostname-bin runs a program" "rg --hostname-bin /tmp/evil.sh foo"
assert_defer "rg -z spawns decompressors off PATH" "rg -z foo"
assert_allow "fd search" "fd -tf foo"
assert_defer "fd -x execs per result" "fd -x rm {}"
assert_defer "fd --exec long form" "fd --exec rm {}"
assert_defer "fd -X exec-batch" "fd -X rm"
# A short flag that takes a VALUE swallows the rest of its token, so the
# characters after it are data and screening them as flags is a pure stall.
# Every row here is a command a dispatched worker actually blocked on
# (2026-09-14), or its adversarial twin.
assert_allow "yq -o=json (the 's' in json is a value, not -s)" "yq -o=json . file.yml"
assert_allow "rg -tzsh (the 'z' is the -t type name)" "rg -tzsh foo"
assert_allow "rg -rz (the 'z' is the -r replacement)" "rg -rz foo"
assert_allow "shfmt -filename=workflow.sh (the 'w' is in the value)" "shfmt -filename=workflow.sh -d"
assert_allow "fd -e txt attached extension" "fd -etxt"
assert_allow "sort -to (the 'o' is the -t separator)" "sort -to file"
assert_defer "rg -nz still catches a bundled -z" "rg -nz foo"
assert_defer "yq -Pi still catches a bundled -i" "yq -Pi '.a=1' file.yml"
assert_defer "sort -uo still catches a bundled -o" "sort -uo out file"
assert_defer "fd -Hx still catches a bundled -x" "fd -Hx rm"
# `--` ends the flags: what follows is an operand, however it is spelled.
assert_allow "rg -- -z searches for the literal -z" "rg -- -z"
assert_allow "sort -- -o reads a file named -o" "sort -- -o"
assert_allow "fd -- -x matches the literal -x" "fd -- -x"
assert_defer "rg -z before -- is still a flag" "rg -z -- foo"
# Read-only coreutils with no output-file or filter flag anywhere.
assert_allow "md5sum" "md5sum file"
assert_allow "sha256sum -c" "sha256sum -c sums.txt"
assert_allow "readlink -f" "readlink -f file"
assert_allow "column -t" "column -t file"
assert_allow "paste" "paste a b"
assert_allow "nl" "nl -ba file"
# `lefthook run <job>` sits on the same trust boundary as `mise run <task>`:
# what it runs is the repo's own tracked lefthook.yml. `-c/--config` points it
# at an arbitrary one, which is arbitrary exec.
assert_allow "lefthook run a repo-defined job" "lefthook run pre-commit"
assert_defer "lefthook run -c arbitrary config" "lefthook run -c /tmp/evil.yml pre-commit"
assert_defer "lefthook run --config arbitrary config" "lefthook run --config /tmp/evil.yml pre-commit"
assert_defer "lefthook global -c before the subcommand" "lefthook -c /tmp/evil.yml run pre-commit"
assert_defer "lefthook install writes hook files" "lefthook install"
assert_defer "lefthook uninstall" "lefthook uninstall"
# `gh api` is a GET until a flag makes it a write; gh switches to POST on the
# mere presence of a field flag, with no -X needed.
assert_allow "gh api GET" "gh api repos/o/r"
assert_allow "gh api GET with --jq" "gh api repos/o/r --jq .name"
assert_allow "gh api --paginate" "gh api --paginate repos/o/r/issues"
assert_defer "gh api -X POST" "gh api -X POST repos/o/r/issues"
assert_defer "gh api --method DELETE" "gh api --method DELETE repos/o/r"
assert_defer "gh api -f field implies POST" "gh api repos/o/r -f title=x"
assert_defer "gh api -F field implies POST" "gh api repos/o/r -F body=@x"

# Short-flag bundling. gh uses pflag, which bundles, so a write flag can ride
# behind a boolean one — `-iX POST` is `-i` plus `-X POST`. An anchored `-X*`
# match never sees it, which is how this read as a GET (found by the panel
# pass, 2026-09-14). The value-taking flags end a cluster, so a `F` sitting
# inside `-q`'s jq expression is data and stays allowed.
assert_defer "gh api -X bundled behind a boolean" "gh api -iX POST repos/o/r/issues"
assert_defer "gh api -f bundled behind a boolean" "gh api -if repos/o/r"
assert_defer "gh api -F bundled behind a boolean" "gh api -iF body=x repos/o/r"
assert_allow "gh api -q consumes the rest of its cluster" "gh api -qFkey=val repos/o/r"
assert_allow "gh api -i alone is read-only" "gh api -i repos/o/r"
assert_defer "gh api --input body" "gh api --input body.json repos/o/r"
assert_defer "gh api --raw-field implies POST" "gh api repos/o/r --raw-field title=x"
assert_defer "gh api graphql with a query field" "gh api graphql -f query=xyz"
assert_allow "gh issue view" "gh issue view 5"
assert_allow "gh issue list" "gh issue list"
assert_defer "gh issue create writes" "gh issue create --title x"
assert_allow "gh run list" "gh run list"
assert_allow "gh run view" "gh run view 5 --log"
assert_defer "gh run download writes files" "gh run download 5"
assert_defer "gh run rerun mutates" "gh run rerun 5"
assert_allow "git worktree list" "git worktree list"
assert_allow "git worktree list --porcelain" "git worktree list --porcelain"
assert_defer "git worktree add mutates" "git worktree add /tmp/x"
assert_defer "git worktree remove mutates" "git worktree remove x"
assert_defer "git worktree prune mutates" "git worktree prune"
assert_defer "git worktree bare is a usage error" "git worktree"

echo "### Real-world stalls (2026-09-14) — the acceptance commands"
# Command 1, verbatim: the shape that stalled a worker on its first tool call.
# Every path in it is relative, so it replays unchanged.
assert_allow "stall 1 — grep|head then a for-loop over an awk filter" \
  "grep -n '^## \\|^### ' specs/tower-comms/test-spec.md | head -40; for r in A1.1 A1.2; do echo \"=== \$r\"; awk -v r=\"REQ-\$r\" 'index(\$0,\"**\"r\"**\")||index(\$0,\"### \"r)||index(\$0,\"- \"r\" \")||index(\$0,\"**\"r)==1{p=1;print;next} p&&/^- \\*\\*REQ-|^### REQ-|^## /{p=0} p{print}' specs/tower-comms/test-spec.md; done"
# Command 2: structurally verbatim, with the one absolute path (a real
# machine's plugin cache root) pointed at this suite's sandbox plugin root so
# the fixture is hermetic. Everything the command exercises — the bare `env`
# pipe, a tracked `R=<trusted root>` assignment, `diff` through `$R`, and the
# plugin script invoked through `$R` — is unchanged.
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_allow "stall 2 — env pipe, tracked root assignment, plugin script call" \
  "env | grep -i 'planwright\\|PLUGIN' ; echo ---; R=$PLUGIN_ROOT; diff -rq \$R/scripts scripts | head; echo \"--- dispatch-fetch\"; \$R/scripts/plug.sh --spec specs/x $PLUGIN_CWD; echo \"exit \$?\"" \
  Bash "$PLUGIN_CWD"
HOOK_ENV=()

echo "### Regression baseline — shapes that were already allowed must stay allowed"
assert_allow "regression — grep piped into head" "grep -n foo file | head"
assert_allow "regression — for-loop over an awk filter" "for r in A B; do echo \"\$r\"; awk -v r=\"X\$r\" '{print}' file; done"
assert_allow "regression — sed -n range print" "sed -n '1,5p' file"
assert_allow "regression — git blame" "git blame file"
assert_allow "regression — git cherry" "git cherry main topic"
assert_allow "regression — git merge-base" "git merge-base a b"
assert_allow "regression — gh pr diff" "gh pr diff"
assert_allow "regression — mise run check" "mise run check"
assert_allow "regression — bats on a repo test" "bats tests/ok.bats"
assert_allow "regression — shellcheck" "shellcheck scripts/ok.sh"
assert_allow "regression — yamllint" "yamllint ."
assert_allow "regression — sort piped into uniq -c" "sort file | uniq -c"
assert_allow "regression — comm" "comm a b"
assert_allow "regression — cut" "cut -d, -f1 file"
assert_allow "regression — tr" "tr a b"
assert_allow "regression — stat" "stat file"
assert_allow "regression — realpath" "realpath file"
assert_allow "regression — test && echo" "test -f file && echo yes"
assert_allow "regression — if/then/fi with a verified body" "if [ -f file ]; then cat file; fi"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_allow "regression — tracked trusted-root assignment then a script call" \
  "R=$PLUGIN_ROOT; \$R/scripts/plug.sh --flag" Bash "$PLUGIN_CWD"
HOOK_ENV=()

finish_suite worker-command-guard-widened
