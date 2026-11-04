//! ready — bake-off B's ready-guard decision path, Rust candidate: the
//! contract of the shell candidate's proto_ready, reimplementing the
//! evaluate_predicate path of scripts/ready-guard.sh with the standard
//! library only, so it carries its own JSON reader. The GitHub answers are
//! files in the working directory, as the contract names them.

use std::fs;
use std::process::exit;

const REASON_PREFIX: &str = "planwright ready-guard: ";

/// gh_timeout's default; the harness passes no override.
const GH_TIMEOUT: &str = "10";

/// Nesting past this reads as unparseable rather than risking the stack.
const MAX_DEPTH: usize = 512;

enum Json {
    Null,
    Bool(bool),
    Num(String),
    Str(Vec<u8>),
    Arr,
    Obj(Vec<(Vec<u8>, Json)>),
}

struct Parser<'a> {
    s: &'a [u8],
    p: usize,
}

impl<'a> Parser<'a> {
    fn ws(&mut self) {
        while self.p < self.s.len() && matches!(self.s[self.p], b' ' | b'\t' | b'\n' | b'\r') {
            self.p += 1;
        }
    }

    fn eat(&mut self, lit: &[u8]) -> Option<()> {
        if self.s[self.p..].starts_with(lit) {
            self.p += lit.len();
            Some(())
        } else {
            None
        }
    }

    fn value(&mut self, depth: usize) -> Option<Json> {
        if depth > MAX_DEPTH {
            return None;
        }
        self.ws();
        match *self.s.get(self.p)? {
            b'{' => {
                self.p += 1;
                let mut members = Vec::new();
                self.ws();
                if self.s.get(self.p) == Some(&b'}') {
                    self.p += 1;
                    return Some(Json::Obj(members));
                }
                loop {
                    self.ws();
                    if self.s.get(self.p) != Some(&b'"') {
                        return None;
                    }
                    let k = self.string()?;
                    self.ws();
                    self.eat(b":")?;
                    let v = self.value(depth + 1)?;
                    members.push((k, v));
                    self.ws();
                    match *self.s.get(self.p)? {
                        b',' => self.p += 1,
                        b'}' => {
                            self.p += 1;
                            return Some(Json::Obj(members));
                        }
                        _ => return None,
                    }
                }
            }
            b'[' => {
                self.p += 1;
                self.ws();
                if self.s.get(self.p) == Some(&b']') {
                    self.p += 1;
                    return Some(Json::Arr);
                }
                loop {
                    self.value(depth + 1)?;
                    self.ws();
                    match *self.s.get(self.p)? {
                        b',' => self.p += 1,
                        b']' => {
                            self.p += 1;
                            return Some(Json::Arr);
                        }
                        _ => return None,
                    }
                }
            }
            b'"' => Some(Json::Str(self.string()?)),
            b't' => self.eat(b"true").map(|_| Json::Bool(true)),
            b'f' => self.eat(b"false").map(|_| Json::Bool(false)),
            b'n' => self.eat(b"null").map(|_| Json::Null),
            _ => self.number(),
        }
    }

    fn digits(&mut self) -> usize {
        let start = self.p;
        while self.p < self.s.len() && self.s[self.p].is_ascii_digit() {
            self.p += 1;
        }
        self.p - start
    }

    fn number(&mut self) -> Option<Json> {
        let start = self.p;
        if self.s.get(self.p) == Some(&b'-') {
            self.p += 1;
        }
        match self.s.get(self.p) {
            Some(b'0') => self.p += 1,
            Some(b'1'..=b'9') => {
                self.digits();
            }
            _ => return None,
        }
        if self.s.get(self.p) == Some(&b'.') {
            self.p += 1;
            if self.digits() == 0 {
                return None;
            }
        }
        if matches!(self.s.get(self.p), Some(b'e' | b'E')) {
            self.p += 1;
            if matches!(self.s.get(self.p), Some(b'+' | b'-')) {
                self.p += 1;
            }
            if self.digits() == 0 {
                return None;
            }
        }
        Some(Json::Num(
            String::from_utf8_lossy(&self.s[start..self.p]).into_owned(),
        ))
    }

    fn hex4(&mut self) -> Option<u32> {
        let h = self.s.get(self.p..self.p + 4)?;
        let v = u32::from_str_radix(std::str::from_utf8(h).ok()?, 16).ok()?;
        self.p += 4;
        Some(v)
    }

    /// A string's bytes, escapes decoded; a lone surrogate becomes U+FFFD.
    fn string(&mut self) -> Option<Vec<u8>> {
        self.p += 1;
        let mut out = Vec::new();
        loop {
            let c = *self.s.get(self.p)?;
            self.p += 1;
            match c {
                b'"' => return Some(out),
                0x00..=0x1f => return None,
                b'\\' => {
                    let e = *self.s.get(self.p)?;
                    self.p += 1;
                    let ch = match e {
                        b'"' => '"',
                        b'\\' => '\\',
                        b'/' => '/',
                        b'b' => '\u{8}',
                        b'f' => '\u{c}',
                        b'n' => '\n',
                        b'r' => '\r',
                        b't' => '\t',
                        b'u' => {
                            let hi = self.hex4()?;
                            let cp = if (0xd800..0xdc00).contains(&hi)
                                && self.s.get(self.p..self.p + 2) == Some(b"\\u")
                            {
                                let save = self.p;
                                self.p += 2;
                                let lo = self.hex4()?;
                                if (0xdc00..0xe000).contains(&lo) {
                                    0x10000 + ((hi - 0xd800) << 10) + (lo - 0xdc00)
                                } else {
                                    self.p = save;
                                    0xfffd
                                }
                            } else {
                                hi
                            };
                            char::from_u32(cp).unwrap_or('\u{fffd}')
                        }
                        _ => return None,
                    };
                    let mut buf = [0u8; 4];
                    out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                }
                _ => out.push(c),
            }
        }
    }
}

/// One JSON value and nothing after it; anything else reads as unparseable,
/// as a failed jq does.
fn parse(s: &[u8]) -> Option<Json> {
    let mut p = Parser { s, p: 0 };
    let v = p.value(0)?;
    p.ws();
    if p.p != s.len() {
        return None;
    }
    Some(v)
}

fn member<'j>(obj: &'j Json, k: &str) -> Option<&'j Json> {
    match obj {
        Json::Obj(m) => m
            .iter()
            .rev()
            .find(|(key, _)| key == k.as_bytes())
            .map(|(_, v)| v),
        _ => None,
    }
}

/// json_field: a present, non-null scalar as jq -r prints it, captured by
/// $(...).
fn field(obj: &Json, k: &str) -> Vec<u8> {
    let v = match member(obj, k) {
        Some(Json::Str(s)) => s.clone(),
        Some(Json::Num(n)) => n.clone().into_bytes(),
        Some(Json::Bool(b)) => b.to_string().into_bytes(),
        _ => return Vec::new(),
    };
    capture(v)
}

/// What $(...) keeps of a command's output: NUL bytes dropped, trailing
/// newlines stripped.
fn capture(mut v: Vec<u8>) -> Vec<u8> {
    v.retain(|&b| b != 0);
    while v.last() == Some(&b'\n') {
        v.pop();
    }
    v
}

/// sanitize_printable: C0, DEL and C1 bytes removed, the fallback when
/// nothing is left.
fn sanitize(s: &[u8], fallback: &str) -> Vec<u8> {
    let v: Vec<u8> = s
        .iter()
        .copied()
        .filter(|&c| !(c <= 0x1f || (0x7f..=0x9f).contains(&c)))
        .collect();
    if v.is_empty() {
        fallback.as_bytes().to_vec()
    } else {
        v
    }
}

/// emit_deny: the decision object as jq -nc builds it, then exit 0.
fn deny(parts: &[&[u8]]) -> ! {
    let reason = sanitize(
        &parts.concat(),
        "refusing an unconfirmable draft->ready flip",
    );
    let mut out = b"{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"".to_vec();
    for c in REASON_PREFIX.as_bytes().iter().chain(reason.iter()) {
        match *c {
            b'"' | b'\\' => {
                out.push(b'\\');
                out.push(*c);
            }
            c if c < 0x20 || c == 0x7f => out.extend_from_slice(format!("\\u{:04x}", c).as_bytes()),
            c => out.push(c),
        }
    }
    out.extend_from_slice(b"\"}}\n");
    use std::io::Write;
    let _ = std::io::stdout().write_all(&out);
    exit(0);
}

fn answer(name: &str) -> (Vec<u8>, i32) {
    let out = capture(fs::read(name).unwrap_or_default());
    let rc = match fs::read(format!("{}.rc", name)) {
        Ok(b) => {
            std::str::from_utf8(&capture(b))
                .ok()
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(1)
                & 0xff
        }
        Err(_) => 0,
    };
    (out, rc)
}

struct View {
    base: Vec<u8>,
    oid: Vec<u8>,
    mergeable: Vec<u8>,
    url: Vec<u8>,
}

/// check_view_rc then read_view_fields; None means the PR is already ready.
fn read_view((out, rc): (Vec<u8>, i32)) -> Option<View> {
    if rc == 124 || rc == 143 {
        deny(&[b"the GitHub query for this pull request did not finish within ", GH_TIMEOUT.as_bytes(), b"s, so its currency and mergeability could not be confirmed - refusing (fail closed). Wait and retry."]);
    }
    if rc != 0 {
        deny(&[b"the GitHub query for this pull request failed, so its currency with its base branch and its mergeability could not be confirmed - refusing (fail closed). Check that gh is authenticated and that the pull request exists, then retry."]);
    }
    if out.is_empty() {
        deny(&[b"the GitHub query for this pull request returned nothing, so its currency and mergeability could not be confirmed - refusing (fail closed)."]);
    }
    let doc = parse(&out);
    let draft = match doc.as_ref().and_then(|d| member(d, "isDraft")) {
        Some(Json::Bool(b)) if matches!(doc, Some(Json::Obj(_))) => *b,
        _ => deny(&[b"the GitHub query for this pull request returned an answer the guard could not read (its draft state is missing or malformed), so a draft->ready flip could not be ruled out - refusing (fail closed)."]),
    };
    if !draft {
        return None;
    }
    let d = doc.unwrap();
    let v = View {
        base: field(&d, "baseRefName"),
        oid: field(&d, "headRefOid"),
        mergeable: field(&d, "mergeable"),
        url: field(&d, "url"),
    };
    if v.base.is_empty() || v.oid.is_empty() || v.mergeable.is_empty() || v.url.is_empty() {
        deny(&[b"the GitHub query for this pull request returned an incomplete answer, so its currency with its base branch and its mergeability could not be confirmed - refusing (fail closed)."]);
    }
    Some(v)
}

fn only(s: &[u8], ok: fn(u8) -> bool) -> bool {
    s.iter().all(|&c| ok(c))
}

fn valid_pr_number(s: &[u8]) -> bool {
    !s.is_empty() && only(s, |c| c.is_ascii_digit()) && s[0] != b'0' && s.len() <= 12
}

fn valid_owner(s: &[u8]) -> bool {
    !s.is_empty()
        && only(s, |c| c.is_ascii_alphanumeric() || c == b'-')
        && s[0] != b'-'
        && s[s.len() - 1] != b'-'
        && s.len() <= 39
}

fn valid_repo(s: &[u8]) -> bool {
    !s.is_empty()
        && only(s, |c| {
            c.is_ascii_alphanumeric() || matches!(c, b'.' | b'_' | b'-')
        })
        && s != b"."
        && s != b".."
        && s.len() <= 100
}

fn valid_owner_repo(s: &[u8]) -> bool {
    if s.iter().filter(|&&c| c == b'/').count() != 1
        || s.first() == Some(&b'/')
        || s.last() == Some(&b'/')
    {
        return false;
    }
    let k = s.iter().position(|&c| c == b'/').unwrap();
    valid_owner(&s[..k]) && valid_repo(&s[k + 1..])
}

fn valid_ref_name(s: &[u8]) -> bool {
    !s.is_empty()
        && only(s, |c| {
            c.is_ascii_alphanumeric() || matches!(c, b'.' | b'_' | b'/' | b'+' | b'@' | b'-')
        })
        && s[0] != b'-'
        && s[0] != b'/'
        && s[s.len() - 1] != b'/'
        && !s.windows(2).any(|w| w == b"..")
        && s.len() <= 255
}

fn valid_oid(s: &[u8]) -> bool {
    only(s, |c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
        && (s.len() == 40 || s.len() == 64)
}

fn valid_count(s: &[u8]) -> bool {
    !s.is_empty() && only(s, |c| c.is_ascii_digit()) && s.len() <= 12
}

fn rfind(s: &[u8], pat: &[u8]) -> Option<usize> {
    if s.len() < pat.len() {
        return None;
    }
    (0..=s.len() - pat.len())
        .rev()
        .find(|&i| &s[i..i + pat.len()] == pat)
}

/// parse_owner_repo_from_url, its shell pattern removals spelled out.
fn owner_repo_from_url(u: &[u8], pr: &[u8]) -> (Vec<u8>, Vec<u8>) {
    let k = match rfind(u, b"/pull/") {
        Some(k) => k,
        None => deny(&[b"the pull-request URL GitHub returned could not be read, so the guard cannot identify the repository to compare against - refusing (fail closed)."]),
    };
    let tail = &u[k + 6..];
    if !valid_pr_number(tail) {
        deny(&[b"the pull-request URL GitHub returned does not end in a pull-request number - refusing (fail closed)."]);
    }
    if !pr.is_empty() && tail != pr {
        deny(&[b"the pull request GitHub resolved is not the one this call named - refusing (fail closed)."]);
    }
    let mut rest = &u[..k];
    let after_slash =
        |s: &[u8]| s[s.iter().rposition(|&c| c == b'/').map_or(0, |j| j + 1)..].to_vec();
    let name = after_slash(rest);
    if let Some(j) = rest.iter().rposition(|&c| c == b'/') {
        rest = &rest[..j];
    }
    let owner = after_slash(rest);
    if !valid_owner(&owner) {
        deny(&[b"the pull-request URL GitHub returned names no readable repository owner - refusing (fail closed)."]);
    }
    if !valid_repo(&name) {
        deny(&[b"the pull-request URL GitHub returned names no readable repository - refusing (fail closed)."]);
    }
    (owner, name)
}

fn evaluate(pr: &[u8], repo: &[u8], policy: &[u8]) {
    let mut v = match read_view(answer("view")) {
        None => return,
        Some(v) => v,
    };
    if v.mergeable == b"UNKNOWN" {
        v = match read_view(answer("requery")) {
            None => return,
            Some(v) => v,
        };
        if v.mergeable == b"UNKNOWN" {
            deny(&[b"GitHub has not finished computing mergeability for this pull request (mergeable is still UNKNOWN after a re-query), so its currency and conflict state could not be confirmed - refusing (fail closed). Wait a few seconds and retry; do not fetch, GitHub computes this server-side."]);
        }
    }
    match v.mergeable.as_slice() {
        b"MERGEABLE" => {}
        b"CONFLICTING" => deny(&[b"this pull request conflicts with its base branch ", &sanitize(&v.base, "its base"), b" (mergeable is CONFLICTING) - refusing the draft->ready flip (a ready PR must be mergeable). Merge the base into the branch, resolve the conflict, re-verify, then retry."]),
        _ => deny(&[b"this pull request's mergeability could not be confirmed (mergeable was ", &sanitize(&v.mergeable, "unreadable"), b", not MERGEABLE) - refusing (fail closed)."]),
    }
    if !valid_ref_name(&v.base) {
        deny(&[b"this pull request's base branch name is not a shape the guard will put in a compare query (", &sanitize(&v.base, "unprintable"), b") - refusing (fail closed)."]);
    }
    if !valid_oid(&v.oid) {
        deny(&[b"this pull request's head commit id could not be read as a plain hex object id - refusing (fail closed)."]);
    }
    let (owner, name) = owner_repo_from_url(&v.url, pr);
    if !repo.is_empty()
        && [owner, b"/".to_vec(), name].concat().to_ascii_lowercase() != repo.to_ascii_lowercase()
    {
        deny(&[b"the pull request gh resolved does not belong to the repository this call named - refusing (fail closed)."]);
    }
    let (behind, rc) = answer("compare");
    if rc == 124 || rc == 143 {
        deny(&[b"the GitHub compare query did not finish within ", GH_TIMEOUT.as_bytes(), b"s, so this pull request's currency with its base branch could not be confirmed - refusing (fail closed). Wait and retry."]);
    }
    if rc != 0 {
        deny(&[b"GitHub's compare endpoint could not be reached for this pull request, so its currency with base branch ", &sanitize(&v.base, "its base"), b" could not be confirmed - refusing (fail closed). Wait and retry."]);
    }
    if !valid_count(&behind) {
        deny(&[b"GitHub's compare endpoint returned no readable `behind_by` for this pull request, so its currency with its base branch could not be confirmed - refusing (fail closed). Wait and retry."]);
    }
    if behind != b"0" && policy != b"conflict-only" {
        deny(&[b"this pull request is ", &behind, b" commit(s) behind its base branch ", &sanitize(&v.base, "its base"), b", so it has NOT been verified on a current head - refusing the draft->ready flip. Merge the base branch into it ('git fetch origin && git merge FETCH_HEAD'), let CI and review re-run, then retry."]);
    }
}

fn main() {
    use std::os::unix::ffi::OsStrExt;
    let args: Vec<Vec<u8>> = std::env::args_os()
        .skip(1)
        .map(|a| a.as_bytes().to_vec())
        .collect();
    if args.len() != 3 {
        eprintln!("usage: ready <pr|-> <owner/repo|-> <refuse|conflict-only>");
        exit(2);
    }
    let pr: &[u8] = if args[0] == b"-" { b"" } else { &args[0] };
    let repo: &[u8] = if args[1] == b"-" { b"" } else { &args[1] };
    if (!pr.is_empty() && !valid_pr_number(pr)) || (!repo.is_empty() && !valid_owner_repo(repo)) {
        eprintln!("ready: the pr must be a pull-request number and the repo owner/repo, or -");
        exit(2);
    }
    if args[2] != b"refuse" && args[2] != b"conflict-only" {
        eprintln!("ready: the policy must be refuse or conflict-only");
        exit(2);
    }
    evaluate(pr, repo, &args[2]);
}
