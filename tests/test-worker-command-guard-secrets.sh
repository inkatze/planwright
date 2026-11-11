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

echo "### Secret-bearing locations in the home directory, every spelling"
for loc in .ssh/id_rsa .ssh/id_ed25519 .gnupg/private-keys-v1.d/k.key .aws/credentials \
  .config/gh/hosts.yml .netrc .git-credentials .npmrc .kube/config .claude/.credentials.json .claude.json; do
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
