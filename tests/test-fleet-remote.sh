#!/bin/bash
# Tests for scripts/fleet-remote.sh, the near-side SSH channel to a remote
# host's stream-json verbs. A fake `ssh` on PATH runs the remote command
# string under a chosen login shell with a sandbox HOME, so the quoting is
# exercised by each real shell present (sh always; bash, zsh, fish when
# installed), and a fake remote root records the argv and stdin each verb
# received. Plain bash 3.2, inline asserts.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/fleet-remote.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/fleet-remote-test.XXXXXX")" || {
  echo "FAIL: mktemp could not create a work dir" >&2
  exit 1
}
tmp=$(cd -P "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

bin="$tmp/bin"
rhome="$tmp/rhome"
rroot="$tmp/rroot"
mkdir -p "$bin" "$rhome/.config/planwright" "$rroot/scripts"

cat >"$bin/ssh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_SSH_LOG"
while :; do
  case $1 in
    -T) shift ;;
    -o) shift 2 ;;
    *) break ;;
  esac
done
[ "$1" = down ] && exit 255
case ${FAKE_FAIL_RUN:-}:$2 in 1:exec*) exit 255 ;; esac
cd "$FAKE_REMOTE_HOME" || exit 255
exec env -i HOME="$FAKE_REMOTE_HOME" PATH="${FAKE_REMOTE_PATH:-$PATH}" "$FAKE_REMOTE_SHELL" -c "$2"
EOF
chmod +x "$bin/ssh"

# The fake remote verbs print their argv, one bracketed word per line, then
# the file a --brief or --message-file named and whether it still exists.
for s in fleet-streamjson mission-control-launch; do
  cat >"$rroot/scripts/$s.sh" <<EOF
#!/bin/sh
echo "$s"
f=''
prev=''
for a in "\$@"; do
  printf '[%s]\n' "\$a"
  case \$prev in --brief | --message-file) f=\$a ;; esac
  prev=\$a
done
if [ -n "\$f" ]; then echo "file:\$f"; cat "\$f"; fi
EOF
done

export FAKE_SSH_LOG="$tmp/ssh.log"
export FAKE_REMOTE_HOME="$rhome"
export FAKE_REMOTE_SHELL=/bin/sh
export PATH="$bin:$PATH"

run() {
  OUT=$(/bin/sh "$script" "$@" 2>"$tmp/err")
  CODE=$?
  ERR=$(cat "$tmp/err")
}

# set_env_root <root>: a remote whose installed-plugin record names <root>,
# with an empty env file.
set_env_root() {
  mkdir -p "$rhome/.claude/plugins/cache/planwright/planwright/9.9.9/scripts"
  # shellcheck disable=SC2016 # the $1 belongs to the fake resolver
  printf '#!/bin/sh\n[ "$1" = --current ] && echo %s\n' "$1" \
    >"$rhome/.claude/plugins/cache/planwright/planwright/9.9.9/scripts/resolve-installed-roots.sh"
  : >"$rhome/.config/planwright/remote-env.sh"
}

# --- usage and refusals, none of which reaches ssh -----------------------------
: >"$FAKE_SSH_LOG"
run --help
assert_eq "--help exits 0" 0 "$CODE"
run status w1
assert_eq "a missing --host is a usage error" 2 "$CODE"
run --host -oProxyCommand=x status w1
assert_eq "an alias with a leading dash is refused" 2 "$CODE"
run --host 'a b' status w1
assert_eq "an alias with a space is refused" 2 "$CODE"
run --host mac status 'w;x'
assert_eq "a worker name outside the grammar is refused" 2 "$CODE"
run --host mac answer w1 'id;x' --allow
assert_eq "a request id outside the grammar is refused" 2 "$CODE"
run --host mac answer w1 r1 --deny --message 'a\b'
assert_eq "a backslash argument is refused" 2 "$CODE"
run --host mac answer w1 r1 --deny --message "$(printf 'a\nb')"
assert_eq "a newline argument is refused" 2 "$CODE"
run --host mac launch --brief /x --program p
assert_eq "launch refuses a caller --brief" 2 "$CODE"
run --host mac --root /x root
assert_eq "no caller can choose the remote root" 2 "$CODE"
run --host mac frobnicate
assert_eq "an unknown verb is a usage error" 2 "$CODE"
assert_eq "no refusal reached ssh" "" "$(cat "$FAKE_SSH_LOG")"

# --- root resolution -----------------------------------------------------------
set_env_root "$rroot"
run --host mac root
assert_eq "root comes from the remote's installed-plugin record" "$rroot" "$OUT"
if grep -q -- '-o BatchMode=yes .*-o ForwardAgent=no .*-o ClearAllForwardings=yes mac ' "$FAKE_SSH_LOG"; then
  ok "ssh runs in batch mode with forwarding off"
else
  fail "ssh runs in batch mode with forwarding off"
fi
run --host mac pending w.1 'x@y:z=1'
assert_eq "worker names in the supervisor's grammar are reachable" "$(printf 'fleet-streamjson\n[pending]\n[w.1]\n[x@y:z=1]')" "$OUT"

printf 'PLANWRIGHT_ROOT=%s\n' "$tmp/other" >"$rhome/.config/planwright/remote-env.sh"
run --host mac root
assert_eq "an env file's PLANWRIGHT_ROOT does not pick the root" "$rroot" "$OUT"

mkdir -p "$rhome/.claude/plugins/cache/planwright/planwright/0.0.1/scripts"
printf '#!/bin/sh\nexit 0\n' >"$rhome/.claude/plugins/cache/planwright/planwright/0.0.1/scripts/resolve-installed-roots.sh"
run --host mac root
assert_eq "root resolution moves past a resolver that prints nothing" "$rroot" "$OUT"
rm -rf "$rhome/.claude"
run --host mac root
assert_eq "no remote root exits 3" 3 "$CODE"
case $ERR in *"no planwright root"*) ok "no remote root names the fix" ;; *) fail "no remote root names the fix ($ERR)" ;; esac

run --host down root
assert_eq "an unreachable host passes ssh's 255 through" 255 "$CODE"

# --- verbs, under every shell present as the remote login shell -----------------
set_env_root "$rroot"
hostile="it's \$(touch $tmp/pwned) \`touch $tmp/pwned\`; & | > \"q\" * ~"
for sh in /bin/sh bash zsh fish; do
  shpath=$(command -v "$sh" 2>/dev/null) || {
    echo "skip: $sh not installed"
    continue
  }
  FAKE_REMOTE_SHELL=$shpath
  export FAKE_REMOTE_SHELL

  run --host mac pending w1 w-2
  assert_eq "[$sh] pending forwards its workers" "$(printf 'fleet-streamjson\n[pending]\n[w1]\n[w-2]')" "$OUT"

  run --host mac answer w1 r-1 --deny --message "$hostile"
  assert_eq "[$sh] a hostile deny message arrives verbatim" \
    "$(printf 'fleet-streamjson\n[answer]\n[w1]\n[r-1]\n[--deny]\n[--message]\n[%s]' "$hostile")" "$OUT"
  if [ -e "$tmp/pwned" ]; then fail "[$sh] the hostile message executed"; else ok "[$sh] the hostile message never executed"; fi

  run --host mac status w1
  assert_eq "[$sh] status forwards" "$(printf 'fleet-streamjson\n[status]\n[w1]')" "$OUT"

  run --host mac retire mc-x-1
  assert_eq "[$sh] retire goes to the launcher" "$(printf 'mission-control-launch\n[retire]\n[mc-x-1]')" "$OUT"

  OUT=$(printf 'line one\n%s\n' "$hostile" | /bin/sh "$script" --host mac steer w1 2>"$tmp/err")
  CODE=$?
  f=$(printf '%s\n' "$OUT" | sed -n 's/^file://p')
  assert_eq "[$sh] steer sends stdin as the message file" \
    "$(printf 'fleet-streamjson\n[steer]\n[w1]\n[--message-file]\n[%s]\nfile:%s\nline one\n%s' "$f" "$f" "$hostile")" "$OUT"
  if [ -n "$f" ] && [ ! -e "$f" ]; then ok "[$sh] steer removes its temp file"; else fail "[$sh] steer removes its temp file ($f)"; fi

  OUT=$(printf 'brief body\n' | /bin/sh "$script" --host mac launch --program p --kind worker --scope 's:a b' 2>"$tmp/err")
  f=$(printf '%s\n' "$OUT" | sed -n 's/^file://p')
  assert_eq "[$sh] launch sends stdin as the brief" \
    "$(printf 'mission-control-launch\n[launch]\n[--program]\n[p]\n[--kind]\n[worker]\n[--scope]\n[s:a b]\n[--brief]\n[%s]\nfile:%s\nbrief body' "$f" "$f")" "$OUT"

  OUT=$(/bin/sh "$script" --host mac steer w1 </dev/null 2>"$tmp/err")
  CODE=$?
  assert_eq "[$sh] steer with empty stdin is refused remotely" 2 "$CODE"
done

# --- compute: ship HEAD, run one command, stream back, clean up ---------------
FAKE_REMOTE_SHELL=/bin/sh
export FAKE_REMOTE_SHELL
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# A fake mise that reports what it was asked to run and where.
# shellcheck disable=SC2016 # expanded by the fake at run time
printf '#!/bin/sh\necho "mise $* in $(pwd -P) PLANWRIGHT_ROOT=${PLANWRIGHT_ROOT:-}"\n' >"$bin/mise"
chmod +x "$bin/mise"
lrepo="$tmp/lrepo"
mkdir -p "$lrepo/tests"
git -C "$lrepo" init -q
git -C "$lrepo" remote add origin https://example.invalid/acct/proj.git
# shellcheck disable=SC2016 # expanded by the suite at run time
printf 'echo "suite ran in $(pwd -P)"\necho "tmp=$TMPDIR"\nexit 0\n' >"$lrepo/tests/test-ok.sh"
printf 'exit 3\n' >"$lrepo/tests/test-fail.sh"
printf 'sleep 60\n' >"$lrepo/tests/test-slow.sh"
printf 'trap "exit 0" TERM\nsleep 60 &\nwait\n' >"$lrepo/tests/test-trap.sh"
git -C "$lrepo" add tests
git -C "$lrepo" commit -q -m one
mkdir -p "$rhome/dev"
git clone -q "$lrepo" "$rhome/dev/proj"
printf 'echo "second commit"\n' >"$lrepo/tests/test-new.sh"
git -C "$lrepo" add tests
git -C "$lrepo" commit -q -m two
head_sha=$(git -C "$lrepo" rev-parse HEAD)

: >"$FAKE_SSH_LOG"
run --host mac compute --worktree "$lrepo" --test ../etc/passwd
assert_eq "compute refuses a test path outside tests/" 2 "$CODE"
run --host mac compute --worktree "$lrepo" --task 'a;b'
assert_eq "compute refuses a task name outside the grammar" 2 "$CODE"
run --host mac compute --worktree "$lrepo"
assert_eq "compute needs a command kind" 2 "$CODE"
run --host mac compute --worktree rel --check
assert_eq "compute refuses a relative worktree" 2 "$CODE"
run --host mac compute --worktree "$lrepo" --check --test tests/test-ok.sh
assert_eq "compute takes one command kind" 2 "$CODE"
run --host mac compute --worktree "$lrepo" --check --timeout 0
assert_eq "compute refuses a zero timeout" 2 "$CODE"
assert_eq "no compute refusal reached ssh" "" "$(cat "$FAKE_SSH_LOG")"

run --host mac compute --worktree "$lrepo" --test tests/test-new.sh
assert_eq "compute runs a file only the shipped commit has" 0 "$CODE"
case $OUT in *"second commit"*) ok "compute streams the command's output" ;; *) fail "compute streams the command's output ($OUT)" ;; esac
case $ERR in *"exit 0 after"*) ok "compute reports exit and duration" ;; *) fail "compute reports exit and duration ($ERR)" ;; esac
case $ERR in *"$head_sha"*) ok "compute names the commit it ran" ;; *) fail "compute names the commit it ran" ;; esac
case $ERR in *Done* | *Killed* | *Terminated*) fail "compute leaks job-control notices ($ERR)" ;; *) ok "compute leaks no job-control notices" ;; esac

run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh
case $OUT in *"suite ran in $rhome/dev/.planwright-compute/run."*"/wt"*) ok "compute runs in a scratch worktree" ;; *) fail "compute runs in a scratch worktree ($OUT)" ;; esac
case $OUT in *"tmp=$rhome/dev/.planwright-compute/run."*"/tmp"*) ok "compute gives the run its own TMPDIR" ;; *) fail "compute gives the run its own TMPDIR ($OUT)" ;; esac

run --host mac compute --worktree "$lrepo" --test tests/test-fail.sh
assert_eq "compute passes the command's exit status through" 3 "$CODE"

started=$(date +%s)
run --host mac compute --worktree "$lrepo" --test tests/test-slow.sh --timeout 1
assert_eq "compute stops a run at its timeout" 143 "$CODE"
if [ $(($(date +%s) - started)) -lt 30 ]; then ok "the timeout fires well before the command ends"; else fail "the timeout fires well before the command ends"; fi

assert_eq "compute leaves no scratch run behind" "" "$(ls -A "$rhome/dev/.planwright-compute")"
assert_eq "compute leaves no extra remote worktree" 1 "$(git -C "$rhome/dev/proj" worktree list | wc -l | tr -d ' ')"
assert_eq "compute removes its hidden ref" "" "$(git -C "$rhome/dev/proj" for-each-ref refs/planwright-compute)"

run --host mac compute --worktree "$lrepo" --test tests/test-slow.sh --timeout 1
case $ERR in *"timeout after 1s"*) ok "compute says the timeout stopped the run" ;; *) fail "compute says the timeout stopped the run ($ERR)" ;; esac

run --host mac compute --worktree "$lrepo" --test tests/test-trap.sh --timeout 1
assert_eq "a command that exits 0 on TERM still reads as timed out" 143 "$CODE"

run --host mac compute --worktree "$lrepo" --task lint:md
assert_eq "compute --task runs mise with the task" 0 "$CODE"
case $OUT in *"mise run lint:md in"*"/wt PLANWRIGHT_ROOT="*) ok "compute --task runs in the scratch worktree without PLANWRIGHT_ROOT" ;; *) fail "compute --task runs in the scratch worktree without PLANWRIGHT_ROOT ($OUT)" ;; esac
run --host mac compute --worktree "$lrepo" --check
case $OUT in *"mise run check in"*) ok "compute --check runs the full check" ;; *) fail "compute --check runs the full check ($OUT)" ;; esac

run --host mac compute --worktree "$lrepo" --test tests/test-absent.sh
assert_eq "a test file missing at the commit is a setup failure" 3 "$CODE"

run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh --timeout 00
assert_eq "an all-zero timeout is refused" 2 "$CODE"
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh --timeout 86401
assert_eq "a timeout over a day is refused" 2 "$CODE"
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh --timeout 0030
assert_eq "a zero-padded timeout is read as its number" 0 "$CODE"

printf 'false\n' >"$rhome/.config/planwright/remote-env.sh"
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh
assert_eq "a failing remote env file is a setup failure" 3 "$CODE"
assert_eq "a setup failure still removes the shipped ref" "" "$(git -C "$rhome/dev/proj" for-each-ref refs/planwright-compute)"
set_env_root "$rroot"

assert_eq "compute leaves no scratch run behind" "" "$(ls -A "$rhome/dev/.planwright-compute")"
assert_eq "compute leaves no extra remote worktree" 1 "$(git -C "$rhome/dev/proj" worktree list | wc -l | tr -d ' ')"
assert_eq "compute removes its hidden ref" "" "$(git -C "$rhome/dev/proj" for-each-ref refs/planwright-compute)"

printf 'echo "dirty edit shipped"\n' >"$lrepo/tests/test-ok.sh"
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh
case $ERR in *"uncommitted changes are not shipped"*) ok "compute warns that uncommitted changes stay behind" ;; *) fail "compute warns that uncommitted changes stay behind" ;; esac
case $OUT in *"dirty edit shipped"*) fail "compute shipped an uncommitted edit" ;; *"suite ran in"*) ok "compute runs the committed file, not the edit" ;; *) fail "compute runs the committed file, not the edit ($OUT)" ;; esac
git -C "$lrepo" checkout -q -- tests/test-ok.sh

mkdir -p "$lrepo/.git/hooks-planted"
printf '#!/bin/sh\ntouch %s/hook-ran\n' "$tmp" >"$lrepo/.git/hooks-planted/pre-push"
chmod +x "$lrepo/.git/hooks-planted/pre-push"
git -C "$lrepo" config core.hooksPath .git/hooks-planted
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh
if [ -e "$tmp/hook-ran" ]; then fail "compute ran the worktree's own push hook on this host"; else ok "compute never runs the worktree's hooks on this host"; fi
git -C "$lrepo" config --unset core.hooksPath

git -C "$lrepo" config protocol.ext.allow always
git -C "$lrepo" config url."ext::touch $tmp/ext-ran ".pushInsteadOf mac:
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh
if [ -e "$tmp/ext-ran" ]; then fail "compute let the worktree's config pick a command transport"; else ok "compute pushes over ssh only, whatever the worktree's config says"; fi
git -C "$lrepo" config --unset protocol.ext.allow
git -C "$lrepo" config --remove-section "url.ext::touch $tmp/ext-ran "

printf 'ref=bogus\nrun=/nonexistent\ncleanup() { :; }\n' >"$rhome/.config/planwright/remote-env.sh"
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh
assert_eq "an env file reusing common names still runs compute" 0 "$CODE"
assert_eq "an env file reusing common names cannot stop the ref cleanup" "" "$(git -C "$rhome/dev/proj" for-each-ref refs/planwright-compute)"
assert_eq "an env file reusing common names cannot stop the run cleanup" "" "$(ls -A "$rhome/dev/.planwright-compute")"
set_env_root "$rroot"

other="$tmp/other-repo"
git init -q "$other"
git -C "$other" commit -q --allow-empty -m other
run_env() {
  OUT=$(env "$@" /bin/sh "$script" --host mac compute --worktree "$lrepo" --test tests/test-new.sh 2>"$tmp/err")
  CODE=$?
  ERR=$(cat "$tmp/err")
}
run_env GIT_DIR="$other/.git"
case $ERR in *"$head_sha"*) ok "an inherited GIT_DIR does not change what compute ships" ;; *) fail "an inherited GIT_DIR does not change what compute ships ($ERR)" ;; esac

: >"$lrepo/untracked-scratch"
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh
case $ERR in *"uncommitted changes are not shipped"*) ok "an untracked file draws the warning too" ;; *) fail "an untracked file draws the warning too" ;; esac
rm -f "$lrepo/untracked-scratch"

# A remote whose PATH holds what compute needs except mise.
minbin="$tmp/minbin"
mkdir -p "$minbin"
for t in git git-receive-pack perl mkdir mktemp rm cat date sed env tr wc; do
  p=$(command -v "$t") && ln -s "$p" "$minbin/$t"
done
FAKE_REMOTE_PATH=$minbin
export FAKE_REMOTE_PATH
run --host mac compute --worktree "$lrepo" --task lint:md
assert_eq "compute --task without mise is a setup failure" 3 "$CODE"
case $ERR in *"needs mise"*) ok "a missing mise is named" ;; *) fail "a missing mise is named ($ERR)" ;; esac
unset FAKE_REMOTE_PATH

run_env FAKE_FAIL_RUN=1
assert_eq "a connection that fails after the push reports SSH's failure" 255 "$CODE"
assert_eq "a connection that fails after the push still removes the shipped ref" "" "$(git -C "$rhome/dev/proj" for-each-ref refs/planwright-compute)"

git -C "$lrepo" remote set-url origin https://example.invalid/acct/..
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh
assert_eq "a dot-dot repository name is refused" 2 "$CODE"

git -C "$lrepo" remote set-url origin https://example.invalid/acct/absent.git
run --host mac compute --worktree "$lrepo" --test tests/test-ok.sh
assert_eq "compute with no remote clone fails to ship" 4 "$CODE"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all fleet-remote tests passed"
