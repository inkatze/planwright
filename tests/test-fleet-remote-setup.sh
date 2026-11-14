#!/bin/bash
# Tests for what scripts/fleet-remote.sh puts in force on a remote host before
# work runs there: the shipped deny floor and guard hooks as a launch's caller
# layer, the clone fetched before a launch, mise trusting exactly an offloaded
# run's paths, and the setup verb that brings a folder marketplace's plugin
# current. A fake `ssh` runs the remote program under /bin/sh in a sandbox
# HOME; the remote root carries the real posture check and shipped profile,
# and a stub `claude` records each plugin command. Plain bash 3.2.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(cd "$here/.." && pwd -P)"
script="$repo/scripts/fleet-remote.sh"
floor_src="$repo/config/mission-control-settings.json"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/fleet-remote-setup-test.XXXXXX")" || {
  echo "FAIL: mktemp could not create a work dir" >&2
  exit 1
}
tmp=$(cd -P "$tmp" && pwd -P) || exit 1
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
has() {
  case $3 in *"$2"*) ok "$1" ;; *) fail "$1 (no '$2' in: $3)" ;; esac
}
lacks() {
  case $3 in *"$2"*) fail "$1 ('$2' in: $3)" ;; *) ok "$1" ;; esac
}

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

bin="$tmp/bin"
rbin="$tmp/rbin"
rhome="$tmp/rhome"
rroot="$tmp/rroot"
mkdir -p "$bin" "$rbin" "$rhome/.config/planwright" "$rroot/scripts" "$rroot/config"

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
cd "$FAKE_REMOTE_HOME" || exit 255
exec env -i HOME="$FAKE_REMOTE_HOME" PATH="$FAKE_REMOTE_PATH" /bin/sh -c "$2"
EOF
chmod +x "$bin/ssh"

# The remote root: the shipped posture check and profile, the guards the
# profile wires (stubs, executable, under this root), and a launcher whose
# posture gate is the real launcher's: a non-mission-control launch is held
# to its caller's posture.
cp "$repo/scripts/mc-posture.sh" "$rroot/scripts/mc-posture.sh"
cp "$floor_src" "$rroot/config/mission-control-settings.json"
for g in tower-command-guard policy-guard; do
  printf '#!/bin/sh\nexit 0\n' >"$rroot/scripts/$g.sh"
  chmod +x "$rroot/scripts/$g.sh"
done
cat >"$rroot/scripts/mission-control-launch.sh" <<'EOF'
#!/bin/sh
d=$(cd "$(dirname "$0")" && pwd -P)
if [ "$1" = launch ]; then
  out=$(/bin/bash "$d/mc-posture.sh" check </dev/null)
  case $? in
    0) ;;
    1)
      echo "mission-control-launch: refusing to launch: the posture check failed: $(printf '%s\n' "$out" | awk -F '\t' '$2 == "fail" { print $3; exit }')" >&2
      exit 4
      ;;
    *)
      echo "mission-control-launch: refusing to launch: the posture check did not run: $out" >&2
      exit 4
      ;;
  esac
fi
echo launched
prev=''
for a in "$@"; do
  printf '[%s]\n' "$a"
  case $prev in --repo | --cwd) printf 'origin-main:%s\n' "$(git -C "$a" rev-parse origin/main 2>/dev/null)" ;; esac
  prev=$a
done
printf 'mise-trust:%s\n' "${MISE_TRUSTED_CONFIG_PATHS-}"
printf 'project-dir:%s\n' "${CLAUDE_PROJECT_DIR-unset}"
EOF
printf '#!/bin/sh\necho fleet-streamjson\n' >"$rroot/scripts/fleet-streamjson.sh"

rcache="$rhome/.claude/plugins/cache/pw-local/planwright/1.0.0/scripts"
mkdir -p "$rcache"
# shellcheck disable=SC2016 # the $1 belongs to the fake
printf '#!/bin/sh\n[ "$1" = --current ] && echo %s\n' "$rroot" >"$rcache/resolve-installed-roots.sh"
: >"$rhome/.config/planwright/remote-env.sh"

# The folder marketplace on the remote: a checkout of a bare upstream that
# has moved one release ahead of it.
pw_bare="$tmp/pw.git"
pw_up="$tmp/pw-up"
git init -q --bare "$pw_bare"
git -C "$pw_bare" symbolic-ref HEAD refs/heads/main
git init -q -b main "$pw_up"
mkdir -p "$pw_up/.claude-plugin"
printf '{"name":"planwright","version":"1.0.0"}\n' >"$pw_up/.claude-plugin/plugin.json"
git -C "$pw_up" add .claude-plugin
git -C "$pw_up" commit -q -m one
git -C "$pw_up" remote add origin "$pw_bare"
git -C "$pw_up" push -q origin main
git clone -q "$pw_bare" "$rhome/planwright"
printf '{"name":"planwright","version":"1.1.0"}\n' >"$pw_up/.claude-plugin/plugin.json"
git -C "$pw_up" commit -q -am two
git -C "$pw_up" push -q origin main
pw_new=$(git -C "$pw_up" rev-parse HEAD)

mkt="$tmp/marketplaces.json"
mkdir -p "$rhome/.claude/plugins"
printf '{"version":2,"plugins":{"planwright@pw-local":[{"scope":"user","installPath":"%s","version":"1.0.0"}]}}\n' \
  "$rroot" >"$rhome/.claude/plugins/installed_plugins.json"
printf '[{"name":"pw-local","source":"directory","path":"%s","installLocation":"%s"}]\n' \
  "$rhome/planwright" "$rhome/planwright" >"$mkt"

# The stub claude: a plugin update installs the marketplace's version when it
# differs from the recorded one, and reports up to date otherwise. The remote
# runs under env -i, so its settings sit beside it: the call log, the
# marketplace list, and optional failures (list_fail, update_out).
claude_log="$tmp/claude.log"
stub_conf() {
  printf 'claude_log=%s\nmkt=%s\n%s\n' "$claude_log" "$mkt" "${1-}" >"$rbin/claude.conf"
}
stub_conf
cat >"$rbin/claude" <<'EOF'
#!/bin/sh
list_fail='' update_out=''
. "$(dirname "$0")/claude.conf"
printf '%s\n' "$*" >>"$claude_log"
rec="$HOME/.claude/plugins/installed_plugins.json"
case $1:${2-}:${3-} in
  plugin:marketplace:list)
    [ -z "$list_fail" ] || { echo "stub claude: not logged in" >&2; exit 1; }
    cat "$mkt"
    ;;
  plugin:marketplace:update) echo "Successfully updated marketplace: $4" ;;
  plugin:update:*)
    [ -z "$update_out" ] || { printf '%s\n' "$update_out"; exit 0; }
    old=$(jq -r --arg id "$3" '.plugins[$id][0].version' "$rec")
    src=$(jq -r '.[0].path // empty' "$mkt")
    new=$(jq -r .version "$src/.claude-plugin/plugin.json" 2>/dev/null) || new=$old
    if [ "$new" = "$old" ]; then
      printf '{"outcome":"ok","updateOutcome":"up_to_date","oldVersion":"%s","newVersion":"%s"}\n' "$old" "$new"
    else
      jq --arg id "$3" --arg v "$new" '.plugins[$id][0].version = $v' "$rec" >"$rec.new" && mv "$rec.new" "$rec"
      printf '{"outcome":"ok","updateOutcome":"updated","oldVersion":"%s","newVersion":"%s"}\n' "$old" "$new"
    fi
    ;;
  *) echo "stub claude: unexpected $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$rbin/claude"

export FAKE_SSH_LOG="$tmp/ssh.log"
export FAKE_REMOTE_HOME="$rhome"
export FAKE_REMOTE_PATH="$rbin:$PATH"
export PATH="$bin:$PATH"

# This host's own posture: a session under the shipped floor, its guards
# under this checkout.
lclaude="$tmp/lclaude"
mkdir -p "$lclaude" "$tmp/lproj"
cp "$floor_src" "$lclaude/settings.json"
unset PLANWRIGHT_MC_TOKEN
export CLAUDE_CONFIG_DIR="$lclaude" CLAUDE_PLUGIN_ROOT="$repo" CLAUDE_PROJECT_DIR="$tmp/lproj"

run() {
  OUT=$(/bin/sh "$script" "$@" </dev/null 2>"$tmp/err")
  CODE=$?
  ERR=$(cat "$tmp/err")
}
launch() {
  OUT=$(printf 'brief body\n' | /bin/sh "$script" --host mac launch "$@" 2>"$tmp/err")
  CODE=$?
  ERR=$(cat "$tmp/err")
}
snap() {
  (cd "$rhome" && find . "$@" -print | sort && find . "$@" -type f -exec cksum {} + | sort)
}
floor_n=$(jq '.permissions.deny | length' "$floor_src")

# --- the deny floor and guard hooks at a remote launch -------------------------
# A bare remote launch, the launcher run there with no caller layer, refuses
# with the deny floor missing.
OUT=$(cd "$rhome" && env -i HOME="$rhome" PATH="$FAKE_REMOTE_PATH" /bin/sh "$rroot/scripts/mission-control-launch.sh" launch --program p 2>&1)
CODE=$?
assert_eq "a bare remote launch is refused by its posture check" 4 "$CODE"
has "the refusal is the missing-floor message" \
  "the shipped deny floor is not in force: $floor_n of its entries are in no loaded settings layer" "$OUT"

: >"$FAKE_SSH_LOG"
launch --program p --kind tower --scope s
assert_eq "a launch through the channel passes the remote posture check" 0 "$CODE"
has "the remote launcher ran" launched "$OUT"
lacks "no posture refusal" "posture check failed" "$ERR"
has "the launched session is handed no project directory" project-dir:unset "$OUT"
has "a kind that starts where it is launched still starts in the remote home" "$(printf '[--cwd]\n[%s]' "$rhome")" "$OUT"
launch --program p --kind tower --scope s --cwd "$tmp"
lacks "a named --cwd is passed as given" "$(printf '[--cwd]\n[%s]' "$rhome")" "$OUT"
launch --program p --kind worker --scope 's:a\b'
assert_eq "a launch argument holding a backslash is refused" 2 "$CODE"

printf '{"disableAllHooks": true}\n' >"$rhome/.claude/settings.json"
launch --program p --kind worker --scope s
assert_eq "a remote user layer turning hooks off still fails the launch" 4 "$CODE"
has "the remote check names the hooks switch" "every hook is turned off" "$ERR"
rm -f "$rhome/.claude/settings.json"

printf '{}\n' >"$lclaude/settings.json"
: >"$FAKE_SSH_LOG"
launch --program p --kind worker --scope s
assert_eq "a caller here without the floor cannot launch remotely" 4 "$CODE"
has "the refusal names this host's posture" "this host's posture check failed" "$ERR"
assert_eq "the refused launch never reached ssh" "" "$(cat "$FAKE_SSH_LOG")"
launch --program p --kind mission-control --scope s
assert_eq "a mission control without a token is left to the remote launcher's own check" 0 "$CODE"
cp "$floor_src" "$lclaude/settings.json"

mv "$rroot/config/mission-control-settings.json" "$tmp/floor.aside"
launch --program p --kind worker --scope s
assert_eq "a remote root shipping no profile is not set up" 3 "$CODE"
has "the refusal names the missing profile" "ships no config/mission-control-settings.json" "$ERR"
mv "$tmp/floor.aside" "$rroot/config/mission-control-settings.json"

# --- a launch fetches the remote clone first -----------------------------------
app_bare="$tmp/app.git"
git init -q --bare "$app_bare"
git -C "$app_bare" symbolic-ref HEAD refs/heads/main
git init -q -b main "$tmp/app-up"
git -C "$tmp/app-up" commit -q --allow-empty -m one
git -C "$tmp/app-up" remote add origin "$app_bare"
git -C "$tmp/app-up" push -q origin main
mkdir -p "$rhome/dev"
git clone -q "$app_bare" "$rhome/dev/app"
git -C "$tmp/app-up" commit -q --allow-empty -m two
git -C "$tmp/app-up" push -q origin main
app_new=$(git -C "$tmp/app-up" rev-parse HEAD)
printf 'MISE_TRUSTED_CONFIG_PATHS=/env/listed\nexport MISE_TRUSTED_CONFIG_PATHS\n' >"$rhome/.config/planwright/remote-env.sh"
launch --program p --kind worker --scope s --repo "$rhome/dev/app"
assert_eq "a launch naming a remote clone succeeds" 0 "$CODE"
has "the clone was fetched before the launcher ran" "origin-main:$app_new" "$OUT"
has "the launched session trusts the account's global mise config" "mise-trust:$rhome/.config/mise:" "$OUT"
assert_eq "the launched session trusts the global mise config and the clone, ahead of the env file's" \
  "mise-trust:$rhome/.config/mise:$rhome/dev/app:/env/listed" "$(printf '%s\n' "$OUT" | grep '^mise-trust:')"
git -C "$tmp/app-up" commit -q --allow-empty -m three
git -C "$tmp/app-up" push -q origin main
app_new=$(git -C "$tmp/app-up" rev-parse HEAD)
launch --program p --kind worker --scope s --cwd "$rhome/dev/app"
has "a --cwd clone is fetched too" "origin-main:$app_new" "$OUT"
has "a --cwd clone is trusted" "mise-trust:$rhome/.config/mise:$rhome/dev/app" "$OUT"
mkdir -p "$rhome/dev/app/sub"
launch --program p --kind worker --scope s --repo "$rhome/dev/app/sub"
assert_eq "a directory inside a clone is not trusted" "mise-trust:$rhome/.config/mise:/env/listed" "$(printf '%s\n' "$OUT" | grep '^mise-trust:')"
launch --program p --kind ad-hoc --scope s --cwd /
assert_eq "the root directory is never trusted" "mise-trust:$rhome/.config/mise:/env/listed" "$(printf '%s\n' "$OUT" | grep '^mise-trust:')"
git clone -q "$app_bare" "$rhome/dev/gone"
git -C "$rhome/dev/gone" remote set-url origin "$tmp/no-such.git"
launch --program p --kind worker --scope s --repo "$rhome/dev/gone"
assert_eq "a launch whose clone cannot be fetched still runs" 0 "$CODE"
has "the failed fetch is a warning" "warning: could not fetch $rhome/dev/gone" "$ERR"
: >"$rhome/.config/planwright/remote-env.sh"

# --- mise inside an offloaded run trusts exactly the run's paths ---------------
real_mise=$(command -v mise 2>/dev/null) || real_mise=''
mkdir -p "$rhome/.config/mise" "$rhome/dev/other"
printf '[env]\nFLEET_GLOBAL = "1"\n' >"$rhome/.config/mise/config.toml"
printf '[env]\nOUTSIDE = "1"\n' >"$rhome/dev/other/mise.toml"
# The env file trusts all of ~/dev, as a host's may.
printf 'MISE_TRUSTED_CONFIG_PATHS=%s\nexport MISE_TRUSTED_CONFIG_PATHS\nMISE_CEILING_PATHS=%s\nexport MISE_CEILING_PATHS\n' \
  "$rhome/dev" "$tmp" >"$rhome/.config/planwright/remote-env.sh"
lrepo="$tmp/lrepo"
mkdir -p "$lrepo/tests"
git -C "$lrepo" init -q
git -C "$lrepo" remote add origin https://example.invalid/acct/proj.git
cat >"$lrepo/tests/test-mise.sh" <<EOF
echo "trust=\$MISE_TRUSTED_CONFIG_PATHS"
[ -n '$real_mise' ] || exit 0
# A suite that resets HOME, as many fixtures do: the account's real global
# config is then found walking up from the run, no longer as the global one.
HOME=\$TMPDIR/fakehome
export HOME
mkdir -p "\$HOME"
if '$real_mise' env -s bash >"\$TMPDIR/o" 2>&1; then echo global:trusted; else echo global:untrusted; cat "\$TMPDIR/o"; fi
if (cd '$rhome/dev/other' && '$real_mise' env -s bash) >"\$TMPDIR/o" 2>&1; then
  echo outside:trusted
elif grep -q 'dev/other/mise.toml' "\$TMPDIR/o"; then
  echo outside:untrusted
else
  echo outside:other-error; cat "\$TMPDIR/o"
fi
# The positive control: the same config, listed, is trusted.
if (cd '$rhome/dev/other' && MISE_TRUSTED_CONFIG_PATHS="\$MISE_TRUSTED_CONFIG_PATHS:$rhome/dev/other" '$real_mise' env -s bash) >"\$TMPDIR/o" 2>&1; then
  echo listed:trusted
else
  echo listed:untrusted; cat "\$TMPDIR/o"
fi
EOF
git -C "$lrepo" add tests
git -C "$lrepo" commit -q -m one
git clone -q "$lrepo" "$rhome/dev/proj"
run --host mac compute --worktree "$lrepo" --test tests/test-mise.sh
assert_eq "the offloaded run succeeds" 0 "$CODE"
trust=$(printf '%s\n' "$OUT" | sed -n 's/^trust=//p')
case $trust in
  "$rhome/dev/.planwright-compute/run."??????":$rhome/.config/mise") ok "mise trusts the run's own directory and the account's global config, nothing else" ;;
  *) fail "mise trusts the run's own directory and the account's global config, nothing else ($trust)" ;;
esac
if [ -n "$real_mise" ]; then
  has "a suite resetting HOME still reads the account's global mise config" global:trusted "$OUT"
  has "a config outside the run stays untrusted, whatever the env file trusts" outside:untrusted "$OUT"
  has "that config is trusted once listed" listed:trusted "$OUT"
else
  echo "skip: mise not installed; the real-mise trust checks did not run"
fi
printf 'MISE_CONFIG_DIR=%s\nexport MISE_CONFIG_DIR\n' "$rhome/mise-cfg" >"$rhome/.config/planwright/remote-env.sh"
run --host mac compute --worktree "$lrepo" --test tests/test-mise.sh
case $(printf '%s\n' "$OUT" | sed -n 's/^trust=//p') in
  *":$rhome/mise-cfg") ok "the global mise config is the one MISE_CONFIG_DIR names" ;;
  *) fail "the global mise config is the one MISE_CONFIG_DIR names ($OUT)" ;;
esac
: >"$rhome/.config/planwright/remote-env.sh"

# --- the run's PATH: the account's mise tool paths, and a jq preflight --------
# A remote PATH holding the tools the channel itself uses, but no jq.
farm="$tmp/farm"
mkdir -p "$farm" "$tmp/tools"
for t in sh bash env git git-receive-pack git-upload-pack perl mkdir mktemp find date sed cat getconf sysctl nproc kill chmod rm pkill cut awk tr wc sleep ls dirname cp mv grep sort head tail uname id; do
  tp=$(command -v "$t" 2>/dev/null) || continue
  ln -s "$tp" "$farm/$t"
done
ln -s "$(command -v jq)" "$tmp/tools/jq"
cat >"$lrepo/tests/test-path.sh" <<'EOF'
HOME=$TMPDIR/fakehome
export HOME
if command -v jq >/dev/null 2>&1; then echo jq:found; else echo jq:missing; fi
EOF
git -C "$lrepo" add tests
git -C "$lrepo" commit -q -m path
FAKE_REMOTE_PATH="$farm"
run --host mac compute --worktree "$lrepo" --test tests/test-path.sh
assert_eq "an offloaded run with no jq on the remote is refused as not set up" 3 "$CODE"
has "the preflight names the missing jq" "jq not found" "$ERR"
lacks "the command never started" "fleet-remote: running" "$ERR"
run --host mac setup
assert_eq "setup with no jq on the remote is refused as not set up" 3 "$CODE"
has "setup's preflight names the missing jq" "jq not found" "$ERR"
# A mise whose tool paths hold jq: the run finds it even after resetting HOME.
# shellcheck disable=SC2016 # the $1 belongs to the fake
printf '#!/bin/sh\n[ "$1" = bin-paths ] && echo %s\n' "$tmp/tools" >"$rbin/mise"
chmod +x "$rbin/mise"
FAKE_REMOTE_PATH="$rbin:$farm"
run --host mac compute --worktree "$lrepo" --test tests/test-path.sh
assert_eq "an offloaded run with jq among the account's mise tool paths runs" 0 "$CODE"
has "a suite resetting HOME still finds jq" jq:found "$OUT"
rm -f "$rbin/mise"
FAKE_REMOTE_PATH="$tmp/tools:$farm"
run --host mac setup
assert_eq "setup with no claude on the remote is refused as not set up" 3 "$CODE"
has "setup's preflight names the missing claude" "claude not found" "$ERR"
FAKE_REMOTE_PATH="$rbin:$PATH"
# This host's posture check cannot run without jq: the launch is refused.
saved_path=$PATH
PATH="$bin:$farm"
: >"$FAKE_SSH_LOG"
launch --program p --kind worker --scope s
PATH=$saved_path
assert_eq "a launch whose posture check here cannot run is refused" 4 "$CODE"
has "the refusal says the check did not run" "this host's posture check did not run" "$ERR"
assert_eq "that refused launch never reached ssh" "" "$(cat "$FAKE_SSH_LOG")"

# --- setup: the folder marketplace's plugin brought current, posture verified --
: >"$claude_log"
before=$(snap -path ./.claude -prune -o -path ./planwright -prune -o)
run --host mac setup
assert_eq "setup succeeds on a fixture remote" 0 "$CODE"
assert_eq "setup brings the folder marketplace checkout to its upstream" "$pw_new" "$(git -C "$rhome/planwright" rev-parse HEAD)"
assert_eq "setup updates the marketplace, then the plugin" \
  "$(printf 'plugin marketplace list --json\nplugin marketplace update pw-local\nplugin update planwright@pw-local --scope user --json')" \
  "$(cat "$claude_log")"
assert_eq "the plugin record holds the marketplace's version" 1.1.0 \
  "$(jq -r '.plugins["planwright@pw-local"][0].version' "$rhome/.claude/plugins/installed_plugins.json")"
has "setup reports the posture a launch sees" "$(printf 'posture\tpass')" "$OUT"
assert_eq "setup writes nothing outside ~/.claude and the marketplace checkout" "$before" \
  "$(snap -path ./.claude -prune -o -path ./planwright -prune -o)"

first=$(snap)
: >"$claude_log"
run --host mac setup
assert_eq "a second setup succeeds" 0 "$CODE"
assert_eq "a second setup changes nothing" "$first" "$(snap)"
has "a second setup reports the plugin up to date" "up to date" "$OUT"

printf 'dirty\n' >>"$rhome/planwright/.claude-plugin/plugin.json"
: >"$claude_log"
run --host mac setup
assert_eq "setup refuses a marketplace checkout with local changes" 3 "$CODE"
has "the refusal names the checkout" "$rhome/planwright" "$ERR"
assert_eq "a refused setup updates nothing" "plugin marketplace list --json" "$(cat "$claude_log")"
git -C "$rhome/planwright" checkout -q -- .claude-plugin/plugin.json

printf '[{"name":"pw-local","source":"github","repo":"acct/planwright","installLocation":"%s"}]\n' \
  "$rhome/.claude/plugins/marketplaces/pw-local" >"$mkt"
: >"$claude_log"
run --host mac setup
assert_eq "setup on a hosted marketplace succeeds" 0 "$CODE"
assert_eq "a hosted marketplace is updated, then the plugin, with no checkout touched" \
  "$(printf 'plugin marketplace list --json\nplugin marketplace update pw-local\nplugin update planwright@pw-local --scope user --json')" \
  "$(cat "$claude_log")"

dir_mkt() {
  printf '[{"name":"pw-local","source":"directory","path":"%s","installLocation":"%s"}]\n' "$1" "$1" >"$mkt"
}
dir_mkt "$rhome/planwright"
stub_conf 'list_fail=1'
run --host mac setup
assert_eq "setup refuses when the marketplace list fails" 3 "$CODE"
has "the refusal names the failed list, not a missing marketplace" "claude plugin marketplace list failed" "$ERR"
stub_conf "update_out='{\"outcome\":\"error\",\"message\":\"nope\"}'"
run --host mac setup
assert_eq "setup refuses an update that did not succeed" 3 "$CODE"
has "the refusal names the outcome" "did not succeed (outcome error)" "$ERR"
stub_conf "update_out=' '"
run --host mac setup
assert_eq "setup refuses an update that printed no result" 3 "$CODE"
has "the refusal says so" "printed no result" "$ERR"
stub_conf "update_out='{
  \"outcome\": \"ok\",
  \"updateOutcome\": \"up_to_date\",
  \"oldVersion\": \"1.1.0\",
  \"newVersion\": \"1.1.0\"
}'"
run --host mac setup
assert_eq "setup reads a pretty-printed update result" 0 "$CODE"
has "the pretty-printed result is reported" "1.1.0 up to date" "$OUT"
stub_conf

git -C "$rhome/planwright" commit -q --allow-empty -m local
run --host mac setup
assert_eq "setup refuses a marketplace checkout ahead of its upstream" 3 "$CODE"
has "the refusal says ahead" "is ahead of origin/main" "$ERR"
git -C "$tmp/pw-up" commit -q --allow-empty -m upstream-moved
git -C "$tmp/pw-up" push -q origin main
run --host mac setup
assert_eq "setup refuses a diverged marketplace checkout" 3 "$CODE"
has "the refusal says diverged" "has diverged from origin/main" "$ERR"
git -C "$rhome/planwright" reset -q --hard origin/main
git -C "$rhome/planwright" branch -q --unset-upstream
run --host mac setup
assert_eq "setup refuses a checkout with no upstream" 3 "$CODE"
has "the refusal says no upstream" "not on a branch with an upstream" "$ERR"
git -C "$rhome/planwright" branch -q -u origin/main

dir_mkt "$rhome/planwright/.claude-plugin"
inner_head=$(git -C "$rhome/planwright" rev-parse HEAD)
git -C "$tmp/pw-up" commit -q --allow-empty -m upstream-again
git -C "$tmp/pw-up" push -q origin main
run --host mac setup
assert_eq "setup on a marketplace inside another repository succeeds" 0 "$CODE"
has "that directory is read as it is" "not a git checkout: read as it is" "$OUT"
assert_eq "the enclosing repository is left alone" "$inner_head" "$(git -C "$rhome/planwright" rev-parse HEAD)"
dir_mkt "$rhome/planwright"

rec="$rhome/.claude/plugins/installed_plugins.json"
jq --arg p "$tmp/elsewhere" '.plugins["planwright@aaa"] = [{"scope":"user","installPath":$p,"version":"0.1.0"}]' "$rec" >"$rec.new" && mv "$rec.new" "$rec"
: >"$claude_log"
run --host mac setup
assert_eq "setup with two planwright installs succeeds" 0 "$CODE"
has "setup updates the install the root came from" "plugin marketplace update pw-local" "$(cat "$claude_log")"

printf '{"disableAllHooks": true}\n' >"$rhome/.claude/settings.json"
run --host mac setup
assert_eq "setup fails when the remote posture fails" 1 "$CODE"
has "setup prints the failing posture" "$(printf 'posture\tfail\tevery hook is turned off')" "$OUT"
rm -f "$rhome/.claude/settings.json"

run --host mac setup extra
assert_eq "setup takes no arguments" 2 "$CODE"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
