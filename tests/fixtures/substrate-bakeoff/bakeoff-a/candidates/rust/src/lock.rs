//! lock: bake-off A's lock primitive, Rust candidate. The contract of the
//! shell candidate's proto_lock, reimplemented over the same on-disk shape as
//! scripts/lock-lib.sh (the lock is a symlink whose target is the owner
//! token), with the standard library only: the two libc calls std does not
//! wrap are declared directly rather than pulled in through a crate.

use std::ffi::{CString, OsStr, OsString};
use std::fs;
use std::io::{self, Write};
use std::os::raw::{c_char, c_int};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::symlink;
use std::path::Path;
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

extern "C" {
    fn kill(pid: c_int, sig: c_int) -> c_int;
    fn access(path: *const c_char, mode: c_int) -> c_int;
}

const EPERM: i32 = 1;
const W_OK: c_int = 2;

struct State {
    seq: u64,
    epoch: String,
    uptime: String,
    broken: Vec<Vec<u8>>,
}

fn warn(msg: &str) {
    let _ = writeln!(io::stderr(), "lock: {msg}");
}

fn usage() -> i32 {
    warn("usage: lock try-for <path> <pid> | owner <path> | alive <token> | release <path> <token>");
    2
}

fn main() {
    let args: Vec<Vec<u8>> = std::env::args_os().skip(1).map(OsString::into_vec).collect();
    let mut st = State { seq: 0, epoch: String::new(), uptime: String::new(), broken: Vec::new() };
    let mut out: Vec<u8> = Vec::new();
    let mut rc = run(&args, &mut st, &mut out);
    // A result that never reached stdout is a real error, whatever the verb
    // did on disk: a caller must not read a lost `held` line as success.
    let mut stdout = io::stdout();
    if let Err(e) = stdout.write_all(&out).and_then(|()| stdout.flush()) {
        warn(&format!("writing the result failed: {e}"));
        rc = 2;
    }
    process::exit(rc);
}

fn run(args: &[Vec<u8>], st: &mut State, out: &mut Vec<u8>) -> i32 {
    let Some(verb) = args.first() else { return usage() };
    match verb.as_slice() {
        b"try-for" => {
            if args.len() != 3 {
                return usage();
            }
            let rc = acquire_for(st, &args[1], &args[2]);
            for b in &st.broken {
                out.extend_from_slice(b"broken ");
                out.extend_from_slice(b);
                out.push(b'\n');
            }
            if rc != 0 {
                return rc;
            }
            let owner = readlink(&args[1]);
            let field = owner.split(|&c| c == b'-').next().unwrap_or(&[]);
            out.extend_from_slice(b"held ");
            out.extend_from_slice(field);
            out.push(b'\n');
            0
        }
        b"owner" => {
            if args.len() != 2 {
                return usage();
            }
            let owner = readlink(&args[1]);
            if owner.is_empty() {
                return 1;
            }
            out.extend_from_slice(&owner);
            out.push(b'\n');
            0
        }
        b"alive" => {
            if args.len() != 2 {
                return usage();
            }
            if owner_alive(&args[1]) { 0 } else { 1 }
        }
        b"release" => {
            if args.len() != 3 {
                return usage();
            }
            release_token(st, &args[1], &args[2])
        }
        _ => usage(),
    }
}

fn p(b: &[u8]) -> &Path {
    Path::new(OsStr::from_bytes(b))
}

fn cat(parts: &[&[u8]]) -> Vec<u8> {
    parts.concat()
}

fn last_component(b: &[u8]) -> &[u8] {
    match b.iter().rposition(|&c| c == b'/') {
        Some(i) => &b[i + 1..],
        None => b,
    }
}

/// Refuse the lock paths lock-lib.sh refuses, in the same order: a derived
/// working path is the lock path plus a `#` suffix, so a `#` in the last
/// component, a newline, a trailing slash or a leading dash would let one
/// lock's name collide with another's working path or read as an option.
fn path_ok(verb: &str, b: &[u8]) -> bool {
    let why = if b.is_empty() {
        "needs a lock path"
    } else if last_component(b).contains(&b'#') {
        "refuses a lock name containing '#'"
    } else if b.contains(&b'\n') {
        "refuses a lock path containing a newline"
    } else if b.ends_with(b"/") {
        "refuses a lock path ending in '/'"
    } else if b.starts_with(b"-") {
        "refuses a lock path beginning with '-'"
    } else {
        return true;
    };
    warn(&format!("{verb} {why}"));
    false
}

fn lexists(b: &[u8]) -> bool {
    fs::symlink_metadata(p(b)).is_ok()
}

fn is_link(b: &[u8]) -> bool {
    fs::symlink_metadata(p(b)).map(|m| m.file_type().is_symlink()).unwrap_or(false)
}

fn readlink(b: &[u8]) -> Vec<u8> {
    fs::read_link(p(b)).map(|t| t.into_os_string().into_vec()).unwrap_or_default()
}

fn is_digits(b: &[u8]) -> bool {
    !b.is_empty() && b.iter().all(u8::is_ascii_digit)
}

/// The question lock-lib.sh asks before blaming the store rather than
/// contention: is the lock's directory there and writable.
fn parent_writable(b: &[u8]) -> bool {
    let dir: &[u8] = match b.iter().rposition(|&c| c == b'/') {
        Some(0) => b"/",
        Some(i) => &b[..i],
        None => b".",
    };
    if !fs::metadata(p(dir)).map(|m| m.is_dir()).unwrap_or(false) {
        return false;
    }
    let Ok(c) = CString::new(dir) else { return false };
    unsafe { access(c.as_ptr(), W_OK) == 0 }
}

fn read_uptime() -> String {
    let Ok(s) = fs::read_to_string("/proc/uptime") else { return String::new() };
    let whole = s.split_whitespace().next().unwrap_or("").split('.').next().unwrap_or("");
    match whole.parse::<u64>() {
        Ok(n) => n.to_string(),
        Err(_) => String::new(),
    }
}

fn mint(st: &mut State, owner_field: &[u8]) -> Vec<u8> {
    if st.epoch.is_empty() {
        st.epoch = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0).to_string();
    }
    st.seq += 1;
    let tail = format!("-{}-{}-{}-{}", st.epoch, st.uptime, process::id(), st.seq);
    cat(&[owner_field, tail.as_bytes()])
}

/// Create the symlink and prove it landed by reading it back.
fn link(target: &[u8], at: &[u8]) -> bool {
    symlink(p(target), p(at)).is_ok() && readlink(at) == target
}

fn slug(tok: &[u8]) -> Vec<u8> {
    tok.iter()
        .take(64)
        .map(|&c| if c.is_ascii_alphanumeric() || c == b'.' || c == b'_' || c == b'-' { c } else { b'_' })
        .collect()
}

/// A free scratch name beside the lock, never an occupied one: everything
/// downstream renames onto it without clearing it first.
fn work_path(st: &mut State, lock: &[u8], kind: &str, tok: &[u8]) -> Option<Vec<u8>> {
    let s = slug(tok);
    for _ in 0..64 {
        st.seq += 1;
        let tail = format!(".{}-{}", process::id(), st.seq);
        let at = cat(&[lock, b"#", kind.as_bytes(), b"#", &s, tail.as_bytes()]);
        if !lexists(&at) {
            return Some(at);
        }
    }
    None
}

/// Move `at` aside onto a fresh scratch name: 0 moved, 1 it was not there to
/// move (contention), 2 a real error.
fn displace(st: &mut State, at: &[u8], kind: &str, tok: &[u8]) -> (Vec<u8>, i32) {
    let Some(aside) = work_path(st, at, kind, tok) else {
        warn("no free working path beside the lock");
        return (Vec::new(), 2);
    };
    if fs::rename(p(at), p(&aside)).is_ok() {
        return (aside, 0);
    }
    if lexists(at) && !parent_writable(at) {
        warn("cannot move the lock out of the way");
        return (Vec::new(), 2);
    }
    (Vec::new(), 1)
}

/// Put a displaced link back, or leave it on disk under its aside name: the
/// link in hand may be the only copy of a live hold.
fn restore_or_keep(aside: &[u8], at: &[u8]) {
    let back = readlink(aside);
    if !back.is_empty() && link(&back, at) {
        let _ = fs::remove_file(p(aside));
        return;
    }
    warn("the lock was taken again; the displaced lock is kept beside it");
}

fn proc_exists(pid: i32) -> bool {
    if unsafe { kill(pid, 0) } == 0 || io::Error::last_os_error().raw_os_error() == Some(EPERM) {
        return true;
    }
    fs::metadata(format!("/proc/{pid}")).map(|m| m.is_dir()).unwrap_or(false)
}

fn owner_alive(tok: &[u8]) -> bool {
    let field = tok.split(|&c| c == b'-').next().unwrap_or(&[]);
    if field == b"detached" {
        return true;
    }
    if !is_digits(field) || field.len() > 10 {
        return false;
    }
    let pid: u64 = std::str::from_utf8(field).ok().and_then(|s| s.parse().ok()).unwrap_or(0);
    if pid == 0 || pid > i32::MAX as u64 {
        return false;
    }
    proc_exists(pid as i32) && owner_is_minter(tok, pid as i32)
}

fn drop_through_dash(b: &[u8]) -> &[u8] {
    match b.iter().position(|&c| c == b'-') {
        Some(i) => &b[i + 1..],
        None => b,
    }
}

/// How many seconds after boot `pid` started, from procfs; None where the
/// host will not say, and the pid alone then decides.
fn started_up(pid: i32) -> Option<u64> {
    let s = fs::read(format!("/proc/{pid}/stat")).ok()?;
    let i = s.iter().rposition(|&c| c == b')')?;
    let rest = std::str::from_utf8(&s[i + 1..]).ok()?;
    // starttime is field 22 overall, the 20th after the command name.
    let ticks: u64 = rest.split_whitespace().nth(19)?.parse().ok()?;
    Some(ticks / 100)
}

/// A live-looking owner reads absent when the process holding its pid
/// started after the token was minted: a recycled pid.
fn owner_is_minter(tok: &[u8], pid: i32) -> bool {
    let rest = drop_through_dash(drop_through_dash(tok));
    let mint_up = rest.split(|&c| c == b'-').next().unwrap_or(&[]);
    if !is_digits(mint_up) || !drop_through_dash(rest).contains(&b'-') {
        return true;
    }
    let Some(started) = started_up(pid) else { return true };
    let Some(m) = std::str::from_utf8(mint_up).ok().and_then(|s| s.parse::<u64>().ok()) else { return true };
    started <= m.saturating_add(2)
}

fn break_lock(st: &mut State, lock: &[u8], dead: &[u8], tok: &[u8]) -> i32 {
    let claim = cat(&[lock, b"#break#", &slug(dead)]);
    let me = process::id().to_string();
    let claim_tok = mint(st, me.as_bytes());
    if !link(&claim_tok, &claim) {
        let holder = readlink(&claim);
        if !holder.is_empty() && !owner_alive(&holder) {
            let (aside, rc) = displace(st, &claim, "dead", &claim_tok);
            if rc == 2 {
                return 2;
            }
            if rc == 0 {
                if readlink(&aside) == holder {
                    let _ = fs::remove_file(p(&aside));
                } else {
                    restore_or_keep(&aside, &claim);
                }
            }
        }
        return 1;
    }
    if readlink(lock) != dead {
        let _ = fs::remove_file(p(&claim));
        return 1;
    }
    let (taken, rc) = displace(st, lock, "taken", &claim_tok);
    if rc != 0 {
        let _ = fs::remove_file(p(&claim));
        return rc;
    }
    if readlink(&taken) != dead {
        restore_or_keep(&taken, lock);
        let _ = fs::remove_file(p(&claim));
        return 1;
    }
    let _ = fs::remove_file(p(&taken));
    st.broken.push(dead.to_vec());
    let ok = link(tok, lock);
    let _ = fs::remove_file(p(&claim));
    if ok { 0 } else { 1 }
}

fn try_core(st: &mut State, lock: &[u8], owner_field: &[u8]) -> i32 {
    st.uptime = read_uptime();
    let tok = mint(st, owner_field);
    if !lexists(lock) && link(&tok, lock) {
        return 0;
    }
    if is_link(lock) {
        let owner = readlink(lock);
        if owner.is_empty() || owner_alive(&owner) {
            return 1;
        }
        return break_lock(st, lock, &owner, &tok);
    }
    if lexists(lock) {
        warn("the lock path exists and is not a lock symlink");
        return 2;
    }
    if link(&tok, lock) {
        return 0;
    }
    if !lexists(lock) && !parent_writable(lock) {
        warn("cannot create the lock");
        return 2;
    }
    1
}

fn acquire_for(st: &mut State, lock: &[u8], pid: &[u8]) -> i32 {
    if !path_ok("try-for", lock) {
        return 2;
    }
    if !is_digits(pid) || pid[0] == b'0' {
        warn("try-for needs a non-zero numeric owner pid with no leading zero");
        return 2;
    }
    if pid.len() > 10 {
        warn("try-for refuses an owner pid wider than ten digits");
        return 2;
    }
    try_core(st, lock, pid)
}

fn release_token(st: &mut State, lock: &[u8], tok: &[u8]) -> i32 {
    if !path_ok("release", lock) {
        return 2;
    }
    if tok.is_empty() {
        return usage();
    }
    if readlink(lock) != tok {
        return 1;
    }
    let (taken, rc) = displace(st, lock, "taken", tok);
    if rc != 0 {
        return rc;
    }
    if readlink(&taken) != tok {
        restore_or_keep(&taken, lock);
        return 1;
    }
    // Gone already counts as removed, as lock-lib's `rm -f` has it.
    if let Err(e) = fs::remove_file(p(&taken)) {
        if e.kind() != io::ErrorKind::NotFound {
            return 2;
        }
    }
    0
}
