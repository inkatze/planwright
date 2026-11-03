//! deps: bake-off A's dependency-line parser, Rust candidate. The contract of
//! the shell candidate's proto_deps, reimplementing the shared spec grammar's
//! task-heading and Dependencies extraction byte for byte
//! (scripts/spec-parse.sh), with the standard library only. Input is read as
//! bytes, never as a String, so a file that is not UTF-8 parses as awk
//! parses it.

use std::ffi::OsString;
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::OsStringExt;
use std::process;

/// awk's default field splitting: runs of blanks (space and tab) only. A
/// carriage return is an ordinary byte, which is how a CRLF heading or token
/// stays unmatched.
fn fields(s: &[u8]) -> impl Iterator<Item = &[u8]> {
    s.split(|&c| c == b' ' || c == b'\t').filter(|f| !f.is_empty())
}

/// The task-id grammar, `^[0-9]+(\.[0-9]+)?$`.
fn is_task_id(t: &[u8]) -> bool {
    let mut parts = t.splitn(2, |&c| c == b'.');
    let digits = |p: &[u8]| !p.is_empty() && p.iter().all(u8::is_ascii_digit);
    match (parts.next(), parts.next()) {
        (Some(a), None) => digits(a),
        (Some(a), Some(b)) => digits(a) && digits(b),
        _ => false,
    }
}

fn find_last(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).rposition(|w| w == needle)
}

/// spec_parse_dep_ids: past the last bolded lead, before the first
/// parenthetical, commas and semicolons as separators, trailing periods
/// stripped, and only whole tokens in the task-id grammar kept.
fn dep_ids(line: &[u8]) -> Vec<Vec<u8>> {
    let lead = b"**Dependencies:**";
    let start = find_last(line, lead).map(|i| i + lead.len()).unwrap_or(0);
    let mut s: Vec<u8> = line[start..].to_vec();
    if let Some(i) = s.iter().position(|&c| c == b'(') {
        s.truncate(i);
    }
    for c in s.iter_mut() {
        if *c == b',' || *c == b';' {
            *c = b' ';
        }
    }
    fields(&s)
        .map(|t| {
            let end = t.iter().rposition(|&c| c != b'.').map(|i| i + 1).unwrap_or(0);
            t[..end].to_vec()
        })
        .filter(|t| is_task_id(t))
        .collect()
}

fn main() {
    process::exit(run());
}

fn run() -> i32 {
    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    if args.len() != 1 {
        let _ = writeln!(io::stderr(), "usage: deps <tasks.md>");
        return 2;
    }
    let path = &args[0];
    let unreadable = || {
        let _ = writeln!(io::stderr(), "deps: {} is not a readable file", String::from_utf8_lossy(&path.clone().into_vec()));
        2
    };
    // Checked before the read: a FIFO or a device would block or never end.
    if !fs::metadata(path).map(|m| m.is_file()).unwrap_or(false) {
        return unreadable();
    }
    let data = match fs::read(path) {
        Ok(d) => d,
        Err(_) => return unreadable(),
    };
    let mut out: Vec<u8> = Vec::new();
    let body = data.strip_suffix(b"\n").unwrap_or(&data);
    let mut fence = false;
    let mut cur: Vec<u8> = Vec::new();
    if !data.is_empty() {
        for line in body.split(|&c| c == b'\n') {
            if line.starts_with(b"```") {
                fence = !fence;
                continue;
            }
            if fence {
                continue;
            }
            if line.starts_with(b"## ") {
                cur.clear();
            } else if line.starts_with(b"### Task ") {
                cur.clear();
                if let Some(id) = fields(line).nth(2).filter(|t| is_task_id(t)) {
                    cur = id.to_vec();
                    out.extend_from_slice(b"TASK\t");
                    out.extend_from_slice(&cur);
                    out.push(b'\n');
                }
            } else if line.starts_with(b"### ") {
                cur.clear();
            } else if !cur.is_empty() && line.starts_with(b"- **Dependencies:**") {
                for d in dep_ids(line) {
                    out.extend_from_slice(b"TASKDEP\t");
                    out.extend_from_slice(&cur);
                    out.push(b'\t');
                    out.extend_from_slice(&d);
                    out.push(b'\n');
                }
            }
        }
    }
    let _ = io::stdout().write_all(&out);
    let _ = io::stdout().flush();
    if fence {
        let _ = writeln!(io::stderr(), "deps: end of file inside an open column-0 code fence");
        return 3;
    }
    0
}
