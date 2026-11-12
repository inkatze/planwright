#!/bin/bash
# Tests for scripts/worker-command-guard.sh: reads that expose secrets always
# defer, whatever the reader and however the path is spelled, and `gh api`
# never rides a method override or another host past the read-only arm. The
# allows the worker workflow needs stay beside them. All suites source
# tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

# The harness pins HOME to $SANDBOX/no-home. The directories exist so a path
# the guard resolves (a symlink into them) can be entered.
H=$SANDBOX/no-home
mkdir -p "$H/.ssh" "$H/.gnupg" "$H/.aws" "$H/.config/gh" "$H/.claude" "$SANDBOX/notes"
: >"$H/.ssh/id_rsa"
: >"$H/.claude/.credentials.json"
: >"$SANDBOX/notes/plain.txt"
ln -s "$H/.ssh" "$SANDBOX/sub/sshdir"
ln -s "$H/.ssh/id_rsa" "$SANDBOX/sub/key"
ln -s "$H/.claude/.credentials.json" "$SANDBOX/sub/creds"
ln -s "$SANDBOX/notes" "$SANDBOX/sub/notesdir"
ln -s "$H" "$SANDBOX/sub/homelink"

echo "### Secret-bearing locations in the home directory, every spelling"
for loc in .ssh/id_rsa .ssh/id_ed25519 .gnupg/private-keys-v1.d/k.key .aws/credentials \
  .config/gh/hosts.yml .netrc .git-credentials .npmrc .kube/config .claude/.credentials.json .claude.json \
  .config/git/credentials .cargo/credentials.toml .vault-token .gem/credentials .terraform.d/credentials.tfrc.json \
  .config/glab-cli/config.yml .config/github-copilot/hosts.json; do
  assert_defer "secrets: cat \$HOME/$loc by absolute path" "cat $H/$loc"
  assert_defer "secrets: cat another account's $loc" "cat /home/someone/$loc"
  assert_defer "secrets: cat root's $loc" "cat /root/$loc"
  assert_defer "secrets: cat ~/$loc" "cat ~/$loc"
  assert_defer "secrets: cat \$HOME/$loc" "cat \$HOME/$loc"
  assert_defer "secrets: cat \${HOME}/$loc" "cat \${HOME}/$loc"
  assert_defer "secrets: repeated slashes before $loc" "cat /home//someone///$loc"
  assert_defer "secrets: a dot component before $loc" "cat /home/someone/./$loc"
  assert_defer "secrets: relative to / after a cd, $loc" "cd / && cat home/someone/$loc"
  assert_defer "secrets: a redirect source naming $loc" "wc -c < /home/someone/$loc"
done
assert_defer "secrets: a brace choosing .ssh under ~" "cat ~/{.ssh,x}/id_rsa"
assert_defer "secrets: a brace choosing .gnupg under a home" "cat /home/someone/{.gnupg,x}/private-keys-v1.d/a"
assert_defer "secrets: a brace choosing .ssh under a home" "cat /home/someone/{.ssh,x}/id_rsa"
assert_defer "secrets: a brace listing .ssh second" "cat /home/someone/{x,.ssh}/id_rsa"
echo "### Recursive readers over a directory that holds secrets"
# shellcheck disable=SC2088,SC2016 # the guard reads the words as written
for dir in '~' '~/' '$HOME' '${HOME}' "$H" /home/someone /home/someone/ /home//someone/./ /root /etc /etc/ssh / // /Users/someone /private/etc /proc /dev \
  '~/.claude' '~/.config' /home/someone/.config; do
  assert_defer "secrets: grep -r over $dir" "grep -r BEGIN $dir"
  assert_defer "secrets: grep -R over $dir" "grep -R BEGIN $dir"
  assert_defer "secrets: grep --recursive over $dir" "grep --recursive BEGIN $dir"
  assert_defer "secrets: grep -rn over $dir" "grep -rn BEGIN $dir"
  assert_defer "secrets: rg over $dir" "rg BEGIN $dir"
  assert_defer "secrets: ls -R over $dir" "ls -R $dir"
  assert_defer "secrets: find over $dir" "find $dir -name id_rsa"
  assert_defer "secrets: find -exec cat over $dir" "find $dir -type f -exec cat {} +"
  assert_defer "secrets: fd over $dir" "fd id_rsa $dir"
done
assert_defer "secrets: grep -r with a pattern flag then ~" "grep -r -e BEGIN ~"
assert_defer "secrets: grep -r over two operands, one broad" "grep -r BEGIN sub ~"
assert_defer "secrets: grep -r over a tracked value naming a home" "d=/home/someone; grep -r BEGIN \$d"
assert_defer "secrets: diff -r over home" "diff -r ~ sub"
assert_defer "secrets: tree over home" "tree ~"
assert_defer "secrets: a recursive read over a symlink into .ssh's parent" "grep -r BEGIN sub/homelink"
echo "### Recursive readers: spellings, other tools, globs, parent chains, a cd first"
# shellcheck disable=SC2088,SC2016 # the guard reads the words as written
for dir in '~' '$HOME' /home/someone /etc /; do
  assert_defer "secrets: grep -d recurse over $dir" "grep -d recurse BEGIN $dir"
  assert_defer "secrets: grep -drecurse over $dir" "grep -drecurse BEGIN $dir"
  assert_defer "secrets: grep --directories recurse over $dir" "grep --directories recurse BEGIN $dir"
  assert_defer "secrets: grep --directories=recurse over $dir" "grep --directories=recurse BEGIN $dir"
  assert_defer "secrets: grep --recurs over $dir" "grep --recurs BEGIN $dir"
  assert_defer "secrets: grep --rec over $dir" "grep --rec BEGIN $dir"
  assert_defer "secrets: grep -ri over $dir" "grep -ri BEGIN $dir"
  assert_defer "secrets: grep -Rl over $dir" "grep -Rl BEGIN $dir"
  assert_defer "secrets: grep -r after the operand, $dir" "grep BEGIN $dir -r"
  assert_defer "secrets: rg --files over $dir" "rg --files $dir"
  assert_defer "secrets: rg -l over $dir" "rg -l BEGIN $dir"
  assert_defer "secrets: rg --hidden over $dir" "rg --hidden BEGIN $dir"
  assert_defer "secrets: ls -lR over $dir" "ls -lR $dir"
  assert_defer "secrets: ls -R -a over $dir" "ls -R -a $dir"
  assert_defer "secrets: ls --recursive over $dir" "ls --recursive $dir"
  assert_defer "secrets: tree -a over $dir" "tree -a $dir"
  assert_defer "secrets: du -a over $dir" "du -a $dir"
  assert_defer "secrets: diff -r of $dir against sub" "diff -r $dir sub"
  assert_defer "secrets: diff -rq of sub against $dir" "diff -rq sub $dir"
  assert_defer "secrets: fd -H over $dir" "fd -H . $dir"
  assert_defer "secrets: file -r over $dir" "file -r $dir"
  assert_defer "secrets: find -type f over $dir" "find $dir -type f"
  assert_defer "secrets: find -print over $dir" "find $dir -print"
  assert_defer "secrets: find -name before the path, $dir" "find -L $dir -name x"
done
assert_defer "secrets: a glob under ~ then grep -r" "grep -r BEGIN ~/*"
assert_defer "secrets: a glob of all homes" "grep -r BEGIN /home/*"
assert_defer "secrets: a glob spelling /home" "grep -r BEGIN /ho*/someone"
assert_defer "secrets: a dot glob under ~" "grep -r BEGIN ~/.[a-z]*"
assert_defer "secrets: a glob of /etc" "grep -r BEGIN /et?"
assert_defer "secrets: a brace choosing ~" "grep -r BEGIN {~,sub}"
assert_defer "secrets: a brace choosing /etc" "grep -r BEGIN {/etc,sub}"
assert_defer "secrets: find over a brace choosing /etc" "find {/etc,sub} -name x"
assert_defer "secrets: a parent chain out of the worktree" "grep -r BEGIN ../../../../../../.."
assert_defer "secrets: a parent chain to /, find" "find ../../../../../../.. -name x"
assert_defer "secrets: one parent of the worktree" "grep -r BEGIN .."
assert_defer "secrets: ls -R one parent up" "ls -R .."
assert_defer "secrets: a .. chain back from a subdirectory" "grep -r BEGIN sub/../.."
assert_defer "secrets: grep -r in ~ after a cd" "cd ~ && grep -r BEGIN ."
assert_defer "secrets: rg in ~ after a cd" "cd ~ && rg BEGIN"
assert_defer "secrets: find in / after a cd" "cd / && find . -name x"
assert_defer "secrets: ls -R in /etc after a cd" "cd /etc && ls -R"
assert_defer "secrets: grep -r in /etc after a cd, a bare dot" "cd /etc && grep -r BEGIN ."
assert_defer "secrets: grep -r in the home after a cd with no operand" "cd /home/someone && grep -r BEGIN"
assert_defer "secrets: rg over the home by a tracked value" "d=~; rg BEGIN \$d"
assert_defer "secrets: grep -r over \$HOME with a trailing glob" "grep -r BEGIN \$HOME/*"
assert_defer "secrets: find over \$HOME with an action" "find \$HOME -type f -exec grep BEGIN {} +"
assert_defer "secrets: find -execdir over /etc" "find /etc -execdir cat {} ;"
assert_defer "secrets: find -ok over home" "find ~ -ok cat {} ;"
assert_defer "secrets: find -fprint over home" "find ~ -fprint out"
assert_defer "secrets: find -delete over home" "find ~ -delete"
assert_defer "secrets: grep -r over /etc/ssl" "grep -R x /etc/ssl"
assert_defer "secrets: grep -r over /etc/ssl/private" "grep -r x /etc/ssl/private"
assert_defer "secrets: cat of sudoers" "cat /etc/sudoers"
assert_defer "secrets: cat of a sudoers.d file" "cat /etc/sudoers.d/90-x"
assert_defer "secrets: cat of the TLS private key directory file" "cat /etc/ssl/private/ssl-cert-snakeoil.key"
assert_defer "secrets: a parent chain through the cwd link into /etc" "cat /proc/self/cwd/../../../etc/shadow"
assert_defer "secrets: the worker process's own memory map" "cat /proc/self/maps"
assert_defer "secrets: a process command line" "cat /proc/self/cmdline"
assert_defer "secrets: a process aux vector" "cat /proc/self/auxv"
assert_defer "secrets: every process's command line by glob" "cat /proc/*/cmdline"
assert_defer "secrets: a numbered process's command line" "cat /proc/1/cmdline"
assert_allow "secrets: the load average" "cat /proc/loadavg"
assert_allow "secrets: grep -d recurse over the worktree" "grep -d recurse BEGIN sub"
assert_allow "secrets: rg --files over the worktree" "rg --files sub"
assert_allow "secrets: rg over a worktree directory" "rg BEGIN scripts"
assert_allow "secrets: diff -r inside the worktree" "diff -r sub scripts"
assert_allow "secrets: fd inside the worktree" "fd -H . sub"
assert_allow "secrets: a parent chain that stays inside" "grep -r BEGIN sub/../scripts"
assert_allow "secrets: grep -r over the cwd" "grep -r BEGIN ."
assert_allow "secrets: grep -r over a worktree directory" "grep -r BEGIN sub"
assert_allow "secrets: grep -rn over scripts" "grep -rn BEGIN scripts tests"
assert_allow "secrets: ls -R in the worktree" "ls -R sub"
assert_allow "secrets: find in the worktree" "find scripts -name '*.sh'"
assert_allow "secrets: find over the cwd" "find . -name '*.sh'"
assert_allow "secrets: grep -r over the worktree by absolute path" "grep -r BEGIN $SANDBOX/scripts"
assert_defer "secrets: the .ssh directory listed" "ls /home/someone/.ssh"
assert_defer "secrets: the .ssh directory with a trailing slash" "ls /home/someone/.ssh/"
assert_defer "secrets: a glob over the .ssh directory" "cat /home/someone/.ssh/*"
assert_defer "secrets: a glob naming a dot directory" "cat /home/someone/.ss?/id_rsa"
assert_defer "secrets: a .. component back into .ssh" "cat /home/someone/x/../.ssh/id_rsa"
assert_defer "secrets: an option's attached file operand" "grep --file=/home/someone/.ssh/id_rsa x"
assert_defer "secrets: grep of a key file" "grep -r BEGIN /home/someone/.ssh"
assert_defer "secrets: head of a key file" "head -n 3 /home/someone/.ssh/id_rsa"
assert_defer "secrets: a tracked value naming one" "f=/home/someone/.ssh/id_rsa; cat \$f"
assert_defer "secrets: a symlinked directory resolving into .ssh" "cat sub/sshdir/id_rsa"
assert_defer "secrets: a symlinked key file" "cat sub/key"
assert_defer "secrets: a symlinked credentials file" "cat sub/creds"
echo "### Runtime secrets, backups and mounted volumes"
for dir in /run /run/ /run/user /run/user/1000 /var /var/run /var/lib /var/backups /private/var /mnt /mnt/c /media /media/usb /srv /Volumes /Volumes/x; do
  assert_defer "secrets: grep -r over $dir" "grep -r BEGIN $dir"
  assert_defer "secrets: grep -R over $dir" "grep -R BEGIN $dir"
  assert_defer "secrets: rg over $dir" "rg BEGIN $dir"
  assert_defer "secrets: find over $dir" "find $dir -name x"
done
for f in /run/secrets/db_password /var/run/secrets/kubernetes.io/serviceaccount/token /run/credentials/x.service/token \
  /private/var/run/secrets/token /var/backups/shadow.bak /var/backups/gshadow.bak /run/user/1000/containers/auth.json; do
  assert_defer "secrets: cat $f" "cat $f"
  assert_defer "secrets: a redirect source $f" "wc -c < $f"
done
assert_defer "secrets: a glob over runtime secrets" "cat /run/secrets/*"
assert_defer "secrets: a glob over shadow backups" "cat /var/backups/*shadow*"
assert_defer "secrets: a glob over every account's container auth" "cat /run/user/*/containers/auth.json"
assert_defer "secrets: grep -r over runtime secrets" "grep -r x /run/secrets"
assert_defer "secrets: a relative runtime secret after a cd" "cd /run && cat secrets/db_password"
assert_allow "secrets: grep -r over system docs" "grep -r BEGIN /usr/share/doc"
assert_allow "secrets: a system log read" "cat /var/log/dpkg.log"
assert_allow "secrets: grep -r over a project below a volume's root" "grep -r BEGIN /Volumes/x/proj/src"

echo "### Shapes found in review: patterns, options, other readers"
# shellcheck disable=SC2016 # the guard reads the words as written
for c in 'cat /pro[c]/self/cmdline' 'cat /pro*/[0-9]*/cmdline' 'cat /pro[c]/self/root/etc/shadow' 'cat /pro?/self/fd/3' \
  'cat /e{tc,x}/shadow' 'cat /{etc,x}/gshadow' 'cat /{proc,x}/self/cmdline' 'cat {/etc/shadow,x}' \
  'cat /etc/ssh/ssh_host_*' 'cat /usr/../etc/sh*' 'cat /./etc/sh*' 'cat ../../../../../../../../etc/sh*' \
  'cat sub/ke*' 'cat sub/ssh*/id_rsa' 'grep -r x sub/sshdir/..' 'grep -r x sub/home*' \
  'grep --regex=. /proc/self/environ' 'grep --reg=KEY /home/someone/.aws/credentials' \
  'grep -f/etc/shadow x sub' 'rg -f/etc/shadow sub' 'grep -nf~/.ssh/id_rsa x sub' \
  'diff -rN --from-file=/home/someone sub' 'diff -r --to-file=/etc sub' \
  'fd . --search-path=/home/someone' 'fd id_rsa --base-directory=/' \
  'd=$HOME; ls -R $d' 'ls -R $XDG_CONFIG_HOME' 'grep -r x $OLDPWD' \
  'cat ~/.SSH/id_rsa' 'cat /home/someone/.AWS/credentials' 'cat ~/.pgpass' 'cat ~/.my.cnf' 'cat ~/.docker/x' \
  'cat ~/.config/rclone/rclone.conf' 'cat ~/.local/share/keyrings/login.keyring' 'cat ~/.config/containers/auth.json' \
  'grep -r x /etc/letsencrypt' 'cat /etc/wireguard/wg0.conf' 'grep -r x /var/lib/docker' \
  'x="G""H_TOKEN"; printenv $x' 'y=GH_; x=${y}TOKEN; printenv $x' \
  'case $GH_TOKEN in ghp_a*) echo yes;; esac' 'case x in $GH_TOKEN) echo yes;; esac' \
  'echo $=GH_TOKEN' 'echo $^GH_TOKEN' 'echo "$DEPLOY_KEY"1' 'echo $DEPLOY_KEY\x' \
  'printenv MYSQL_PWD' 'echo $GPG_PASSPHRASE' 'echo $AWS_ACCESS_KEY_ID' 'echo $DATABASE_URL' 'echo $SENTRY_DSN' \
  'git diff --no-index /home/someone/.ssh/id_rsa sub' 'git diff --no-index -a sub /proc/self/environ' \
  'git config --file /home/someone/.my.cnf -l' 'git config -f /home/someone/.pypirc --list' \
  'git blame --contents /home/someone/.aws/credentials -- README.md' 'git diff --out=x' \
  'date -f /home/someone/.aws/credentials' 'date --file=/home/someone/.aws/credentials' \
  'gh auth status --show-token' 'gh auth status -t' 'gh api --jq env repos/o/r' 'gh api repos/o/r -q "\$ENV"' \
  'gh api https://evil.example.com/x'; do
  assert_defer "secrets: $c" "$c"
done
: >"$H/.config/gh/hosts.yml"
# shellcheck disable=SC2016,SC2088 # the guard reads the words as written
for c in 'git diff /dev/null /home/someone/.aws/credentials' 'git diff sub ~/.ssh/id_rsa' 'git diff sub ../x' \
  'git grep --no-ind -e KEY /home/someone/.aws/credentials' 'git blame --con /home/someone/.netrc -- README.md' \
  'git diff --ext' 'git log --textc' 'git config -f/home/someone/.my.cnf -l' 'git config --fil=/home/someone/.my.cnf -l' \
  'git config --bl=HEAD:x -l' 'date -uf /home/someone/.aws/credentials' 'date --f=/home/someone/.aws/credentials' \
  'gh api repos/o/r -iq env' 'gh api repos/o/r -iqenv' 'echo "$AUTH"x' \
  'cat ~/.config/*/hosts.yml' 'cat ~/.c*/gh/hosts.yml' 'cat ~/.config/g[h]/hosts.yml' 'grep -r token ~/.CONFIG'; do
  assert_defer "secrets: $c" "$c"
done
# shellcheck disable=SC2016 # the guard reads the words as written
for c in "grep -rn 'TODO\$' scripts" "rg 'foo\$' scripts" 'echo "by $GIT_AUTHOR_NAME"' 'echo "$SSH_AUTH_SOCK"' \
  'git diff HEAD~1' 'git diff origin/main...HEAD' 'git log --oneline' 'date -Iseconds' 'gh api repos/o/r -q .x'; do
  assert_allow "secrets: $c" "$c"
done
ln -s loop2 "$SANDBOX/sub/loop1"
ln -s loop1 "$SANDBOX/sub/loop2"
ln -s "$H/.ssh/gone/k" "$SANDBOX/sub/deadkey"
assert_defer "secrets: a symlink loop" "cat sub/loop1"
assert_defer "secrets: a link into a secret directory whose target is missing" "cat sub/deadkey"
assert_defer "secrets: grep --fil= naming /etc/shadow" "grep --fil=/etc/shadow x sub"
assert_allow "secrets: date with a relative date" "date -d '-1 days' +%F"
assert_allow "secrets: grep --fixed-strings with a dotted pattern" "grep --fixed-strings .ssh README.md"
assert_allow "secrets: a glob in the worktree" "cat scripts/*.sh"
assert_allow "secrets: a recursive glob in the worktree" "grep -r x scripts/o*"
assert_allow "secrets: an ordinary quoted variable beside text" "echo \"\$USER\"x"
assert_allow "secrets: git describe --contains" "git describe --contains HEAD"
assert_allow "secrets: gh auth status" "gh auth status"
assert_allow "secrets: gh api with --jq over an environments endpoint" "gh api repos/o/r/environments --jq .total_count"
assert_allow "secrets: date with a format" "date +%F"

echo "### System credential files and kernel views of other data"
for f in /etc/shadow /etc/gshadow /etc/shadow- /etc/gshadow- //etc/shadow /etc//shadow /etc///gshadow /./etc/shadow \
  /proc/1234/mem /proc/self/mem /proc/thread-self/mem //proc/self/mem /proc/1234/environ \
  /dev/fd/0 /dev/fd/3 //dev/fd/0 /dev/stdin //dev/stdin /dev/stdin/ /etc/ssh/ssh_host_rsa_key; do
  assert_defer "secrets: cat $f" "cat $f"
  assert_defer "secrets: a redirect source $f" "wc -c < $f"
done
assert_defer "secrets: jq --rawfile of /etc/shadow" "jq --rawfile a /etc/shadow . f"
assert_defer "secrets: jq --slurpfile of /etc/shadow" "jq --slurpfile a /etc/shadow . f"
assert_defer "secrets: grep through /etc/shadow" "grep root /etc/shadow"
assert_defer "secrets: a relative shadow after a cd" "cd /etc && cat shadow"
assert_defer "secrets: a relative ./shadow after a cd" "cd /etc && cat ./shadow"
assert_defer "secrets: relative to / after a cd, etc/shadow" "cd / && cat etc/shadow"
assert_defer "secrets: a glob matching shadow" "cat /etc/sh*"
assert_defer "secrets: a glob matching gshadow" "cat /etc/g?hadow"
assert_defer "secrets: sed over /etc/shadow" "sed -n p /etc/shadow"
assert_defer "secrets: a glob over every fd" "cat /dev/fd/*"
assert_defer "secrets: tr from stdin by name" "tr a b < /dev/stdin"

echo "### The worker's own environment"
assert_defer "secrets: the own environ" "cat /proc/self/environ"
assert_defer "secrets: the own environ with a doubled slash" "cat //proc/self/environ"
assert_defer "secrets: the own environ as a redirect source" "tr '\\0' '\\n' < /proc/self/environ"
assert_defer "secrets: the thread's own environ" "cat /proc/thread-self/environ"
assert_defer "secrets: bare printenv" "printenv"
assert_defer "secrets: printenv with a flag" "printenv -0"
assert_defer "secrets: bare env" "env"
assert_defer "secrets: bare printenv piped into grep" "printenv | grep -i token"
assert_defer "secrets: bare env piped into grep" "env | grep -i token"

echo "### Variables that carry credentials, by name"
for v in GH_TOKEN GITHUB_TOKEN ANTHROPIC_API_KEY OPENROUTER_API_KEY MY_SERVICE_SECRET DB_PASSWORD AWS_SECRET_ACCESS_KEY NPM_TOKEN gh_token \
  AUTH NPM_AUTH DB_PASS BEARER_VALUE; do
  assert_defer "secrets: echo \$$v" "echo \$$v"
  assert_defer "secrets: echo \"\$$v\"" "echo \"\$$v\""
  assert_defer "secrets: echo \${$v}" "echo \${$v}"
  assert_defer "secrets: printf of \$$v" "printf %s \"\$$v\""
  assert_defer "secrets: printenv $v" "printenv $v"
done
assert_defer "secrets: a credential variable inside other text" "echo \"auth: \$GH_TOKEN end\""
assert_defer "secrets: a credential variable with a default" "echo \${GH_TOKEN:-none}"
assert_defer "secrets: a credential variable transformed" "echo \${GH_TOKEN@Q}"
assert_defer "secrets: a credential variable's length" "echo \${#GH_TOKEN}"
assert_defer "secrets: printenv with several names, one a credential" "printenv HOME GH_TOKEN"
assert_defer "secrets: a credential copied into another variable" "t=\$GH_TOKEN; echo \$t"
assert_defer "secrets: a credential copied by braces into another variable" "t=\${GITHUB_TOKEN}; printf %s \"\$t\""
assert_defer "secrets: an indirect expansion" "x=GH_TOKEN; echo \${!x}"
assert_defer "secrets: a credential in a substitution" "echo \$(printenv GH_TOKEN)"
assert_defer "secrets: a credential read through a loop variable" "for v in GH_TOKEN; do printenv \$v; done"
assert_defer "secrets: a credential piped to a reader" "echo \$GH_TOKEN | wc -c"
assert_defer "secrets: a credential inside fish -c" "fish -c 'echo \$GH_TOKEN'"
assert_allow "secrets: an ordinary variable" "echo \$HOME \$PATH \$PWD"
assert_allow "secrets: a variable that only resembles a key" "echo \"\$KEYMAP\""
assert_allow "secrets: a variable that only resembles auth" "echo \"\$AUTHOR\""
assert_allow "secrets: printf of an ordinary variable" "printf '%s\\n' \"\$USER\""
assert_allow "secrets: a dollar amount" "echo 'costs \$5'"

echo "### gh api: no method override, no other host"
assert_defer "secrets: gh api with an X-HTTP-Method-Override header" "gh api repos/o/r -H 'X-HTTP-Method-Override: DELETE'"
assert_defer "secrets: gh api with a lowercase override header" "gh api repos/o/r -H 'x-http-method-override: DELETE'"
assert_defer "secrets: gh api with --header" "gh api repos/o/r --header 'X-HTTP-Method-Override: DELETE'"
assert_defer "secrets: gh api with --header=" "gh api repos/o/r --header='X-HTTP-Method-Override: DELETE'"
assert_defer "secrets: gh api with an attached -H" "gh api repos/o/r -H'X-HTTP-Method-Override: DELETE'"
assert_defer "secrets: gh api with a bundled -iH" "gh api repos/o/r -iH 'X-HTTP-Method-Override: DELETE'"
assert_defer "secrets: gh api with an X-HTTP-Method header" "gh api repos/o/r -H 'X-HTTP-Method: PUT'"
assert_defer "secrets: gh api with an X-Method-Override header" "gh api repos/o/r -H 'X-Method-Override: PATCH'"
assert_defer "secrets: gh api with an unresolved header value" "gh api repos/o/r -H \"\$HDR\""
assert_defer "secrets: gh api --hostname" "gh api repos/o/r --hostname other.example.com"
assert_defer "secrets: gh api --hostname=" "gh api repos/o/r --hostname=other.example.com"
assert_defer "secrets: gh api --hostname before the endpoint" "gh api --hostname other.example.com repos/o/r"

echo "### What the worker workflow needs stays allowed"
assert_allow "secrets: a read in the worktree" "cat scripts/ok.sh"
assert_allow "secrets: a plain note by absolute path" "cat $SANDBOX/notes/plain.txt"
assert_allow "secrets: a plain note through a symlinked directory" "cat sub/notesdir/plain.txt"
assert_allow "secrets: ls of the worktree" "ls $SANDBOX/scripts"
assert_allow "secrets: /etc/hosts" "cat /etc/hosts"
assert_allow "secrets: a grep over the worktree" "grep -rn x scripts"
assert_allow "secrets: a redirect source in the worktree" "wc -l < scripts/ok.sh"
assert_allow "secrets: a file merely named like a secret directory" "cat notes.ssh.md"
assert_allow "secrets: a dotted file that is not a secret" "cat $SANDBOX/.git"
assert_allow "secrets: printenv with a name" "printenv PATH"
assert_allow "secrets: gh api a read" "gh api repos/o/r"
assert_allow "secrets: gh api with an Accept header" "gh api repos/o/r -H 'Accept: application/vnd.github+json'"
assert_allow "secrets: gh api with --jq" "gh api repos/o/r --jq .name"
assert_allow "secrets: environ as a grep pattern" "grep environ README.md"

finish_suite worker-command-guard-secrets
