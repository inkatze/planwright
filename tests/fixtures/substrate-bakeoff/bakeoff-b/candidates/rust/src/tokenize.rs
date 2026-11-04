//! tokenize — bake-off B's command-guard tokenizer, Rust candidate: the
//! contract of the shell candidate's proto_tokenize, reimplementing the
//! tokenize function of scripts/worker-command-guard.sh byte for byte, with
//! the standard library only.

use std::io::{self, BufWriter, Read, Write};
use std::process::exit;

/// The hook's MAX_CMD_LEN: a longer command is never tokenized.
const MAX_CMD_LEN: usize = 8192;

struct Token {
    typ: u8,
    val: Vec<u8>,
    flags: [i32; 7],
    subs: Vec<usize>,
}

struct Lexer<'a> {
    s: &'a [u8],
    toks: Vec<Token>,
    substs: Vec<Vec<u8>>,
}

fn is_alpha(c: Option<u8>) -> bool {
    matches!(c, Some(b'A'..=b'Z' | b'a'..=b'z'))
}

fn is_name_char(c: Option<u8>) -> bool {
    matches!(c, Some(b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'_'))
}

/// A `$` before c starts an expansion.
fn dollar_expands(c: Option<u8>) -> bool {
    is_name_char(c)
        || matches!(
            c,
            Some(
                b'@' | b'*'
                    | b'#'
                    | b'?'
                    | b'!'
                    | b'~'
                    | b'='
                    | b'^'
                    | b'+'
                    | b'-'
                    | b'{'
                    | b'$'
                    | b'['
                    | b'"'
            )
        )
}

impl<'a> Lexer<'a> {
    /// ${s:i:1}: the byte at i, or None past the end.
    fn at(&self, i: usize) -> Option<u8> {
        self.s.get(i).copied()
    }

    /// dollar_form_ok: the `$` at i opens a form whose value the analyzer
    /// can reason about.
    fn dollar_form_ok(&self, i: usize) -> bool {
        match self.at(i + 1) {
            Some(b'[' | b'~') => false,
            Some(b'{') => {
                let start = i + 2;
                let mut j = start;
                while j < self.s.len() && self.s[j] != b'}' {
                    j += 1;
                }
                if j >= self.s.len() {
                    return false;
                }
                let body = &self.s[start..j];
                !body.is_empty()
                    && (is_alpha(Some(body[0])) || body[0] == b'_')
                    && body.iter().all(|&b| is_name_char(Some(b)))
            }
            _ => {
                let mut j = i + 1;
                if matches!(self.at(j), Some(b'=' | b'^' | b'+' | b'#')) {
                    j += 1;
                }
                let k = j;
                while is_name_char(self.at(j)) {
                    j += 1;
                }
                match self.at(j) {
                    Some(b'[') => false,
                    Some(b'*' | b'@' | b'?' | b'!' | b'-' | b'$' | b'#') => {
                        !(j == k && self.at(j + 1) == Some(b'['))
                    }
                    None => true,
                    Some(c) => c < 0x80,
                }
            }
        }
    }

    /// subst_scan: the `$(` at i opens a substitution whose text runs to the
    /// first `)` and nests nothing. Returns the index past the `)` and the
    /// substitution's index.
    fn subst_scan(&mut self, i: usize) -> Option<(usize, usize)> {
        let mut p = i + 2;
        if self.at(p) == Some(b'(') {
            return None;
        }
        while p < self.s.len() {
            match self.s[p] {
                b')' => break,
                b'(' | b'`' => return None,
                _ => p += 1,
            }
        }
        if p >= self.s.len() {
            return None;
        }
        self.substs.push(self.s[i + 2..p].to_vec());
        Some((p + 1, self.substs.len() - 1))
    }

    fn op(&mut self, typ: u8, v: &[u8]) {
        self.toks.push(Token {
            typ,
            val: v.to_vec(),
            flags: [0, 0, -1, 0, 0, 0, 0],
            subs: Vec::new(),
        });
    }

    fn tokenize(&mut self) -> bool {
        let n = self.s.len();
        let mut w = Word::new();
        let mut i = 0;
        while i < n {
            let c = self.s[i];
            match c {
                b'\\' => {
                    let nc = match self.at(i + 1) {
                        None => return false,
                        Some(
                            b'\'' | b'"' | b';' | b'&' | b'|' | b'<' | b'>' | b'(' | b')' | b'\n',
                        ) => return false,
                        Some(x) => x,
                    };
                    if nc == b'$' {
                        w.x = 1;
                    }
                    w.quoting();
                    w.cur.push(nc);
                    w.have = true;
                    i += 2;
                }
                b'\'' => {
                    let j = match self.s[i + 1..].iter().position(|&b| b == b'\'') {
                        None => return false,
                        Some(j) => i + 1 + j,
                    };
                    if self.s[i + 1..j].contains(&b'$') {
                        w.x = 1;
                    }
                    w.quoting();
                    w.cur.extend_from_slice(&self.s[i + 1..j]);
                    w.have = true;
                    i = j + 1;
                }
                b'"' => {
                    let mut j = i + 1;
                    let mut k: Vec<u8> = Vec::new();
                    while j < n && self.s[j] != b'"' {
                        let dc = self.s[j];
                        if dc == b'\\' {
                            let dn = match self.at(j + 1) {
                                None => return false,
                                Some(x) => x,
                            };
                            if dn == b'$' {
                                w.x = 1;
                            }
                            k.push(dn);
                            j += 2;
                            continue;
                        }
                        if dc == b'$' {
                            let dn = self.at(j + 1);
                            if dn == Some(b'(') {
                                let (end, idx) = match self.subst_scan(j) {
                                    None => return false,
                                    Some(r) => r,
                                };
                                w.subs.push(idx);
                                if w.d != 2 {
                                    w.d = 1;
                                }
                                k.extend_from_slice(&self.s[j..end]);
                                j = end;
                                continue;
                            }
                            if dn == Some(b'\'') || !self.dollar_form_ok(j) {
                                return false;
                            }
                            if dn != Some(b'"') && dollar_expands(dn) && w.d != 2 {
                                w.d = 1;
                            }
                            if dn == Some(b'@') {
                                w.d = 2;
                            }
                        }
                        if dc == b'`' {
                            return false;
                        }
                        k.push(dc);
                        j += 1;
                    }
                    if j >= n {
                        return false;
                    }
                    w.quoting();
                    w.cur.extend_from_slice(&k);
                    w.have = true;
                    i = j + 1;
                }
                b'`' => return false,
                b'$' => {
                    let nc = self.at(i + 1);
                    if nc == Some(b'(') {
                        let (end, idx) = match self.subst_scan(i) {
                            None => return false,
                            Some(r) => r,
                        };
                        w.subs.push(idx);
                        w.d = 2;
                        if w.q == 1 {
                            w.qm = 1;
                        }
                        w.cur.extend_from_slice(&self.s[i..end]);
                        w.have = true;
                        i = end;
                        continue;
                    }
                    if nc == Some(b'\'') || !self.dollar_form_ok(i) {
                        return false;
                    }
                    if dollar_expands(nc) {
                        w.d = 2;
                    }
                    if w.q == 1 {
                        w.qm = 1;
                    }
                    w.cur.push(c);
                    w.have = true;
                    i += 1;
                }
                b' ' | b'\t' => {
                    w.flush(&mut self.toks);
                    i += 1;
                }
                b'\n' => {
                    w.flush(&mut self.toks);
                    self.op(b'O', b";");
                    i += 1;
                }
                b';' => {
                    w.flush(&mut self.toks);
                    if self.at(i + 1) == Some(b';') {
                        self.op(b'O', b";;");
                        i += 2;
                    } else {
                        self.op(b'O', b";");
                        i += 1;
                    }
                }
                b'&' => {
                    let nc = self.at(i + 1);
                    if nc == Some(b'>') && w.named_fd() {
                        return false;
                    }
                    w.flush(&mut self.toks);
                    if nc == Some(b'&') {
                        self.op(b'O', b"&&");
                        i += 2;
                    } else if nc == Some(b'>') {
                        if self.at(i + 2) == Some(b'>') {
                            self.op(b'R', b"&>>");
                            i += 3;
                        } else {
                            self.op(b'R', b"&>");
                            i += 2;
                        }
                    } else {
                        self.op(b'O', b"&");
                        i += 1;
                    }
                }
                b'|' => {
                    w.flush(&mut self.toks);
                    match self.at(i + 1) {
                        Some(b'|') => {
                            self.op(b'O', b"||");
                            i += 2;
                        }
                        Some(b'&') => {
                            self.op(b'O', b"|");
                            i += 2;
                        }
                        _ => {
                            self.op(b'O', b"|");
                            i += 1;
                        }
                    }
                }
                b'<' | b'>' => {
                    let mut fd: Vec<u8> = Vec::new();
                    if w.named_fd() {
                        return false;
                    }
                    if w.have {
                        let digits = !w.cur.is_empty() && w.cur.iter().all(|b| b.is_ascii_digit());
                        if digits && w.q != 1 {
                            fd = w.cur.clone();
                        } else {
                            w.push(&mut self.toks);
                        }
                        w = Word::new();
                    }
                    let nc = self.at(i + 1);
                    let (opr, len): (&[u8], usize) = if c == b'<' {
                        match nc {
                            Some(b'<') => match self.at(i + 2) {
                                Some(b'<') => (b"<<<", 3),
                                Some(b'-') => (b"<<-", 3),
                                _ => (b"<<", 2),
                            },
                            Some(b'&') => (b"<&", 2),
                            Some(b'(') => return false,
                            _ => (b"<", 1),
                        }
                    } else {
                        match nc {
                            Some(b'>') => (b">>", 2),
                            Some(b'|') => (b">|", 2),
                            Some(b'&') => (b">&", 2),
                            Some(b'(') => return false,
                            _ => (b">", 1),
                        }
                    };
                    fd.extend_from_slice(opr);
                    self.op(b'R', &fd);
                    i += len;
                }
                b'(' | b')' => {
                    w.flush(&mut self.toks);
                    self.op(b'O', &[c]);
                    i += 1;
                }
                _ => {
                    match c {
                        b'*' | b'?' => w.g = 1,
                        b'[' => w.brk = true,
                        b']' => {
                            if w.brk {
                                w.g = 1;
                            }
                        }
                        b'{' => {
                            w.brc = true;
                            w.z = 1;
                        }
                        b',' => {
                            if w.brc {
                                w.brs = true;
                            }
                        }
                        b'.' => {
                            if w.brc && self.at(i + 1) == Some(b'.') {
                                w.brs = true;
                            }
                        }
                        b'}' => {
                            if w.brs {
                                w.g = 1;
                            }
                            w.z = 1;
                        }
                        b'~' => {
                            if w.have {
                                w.z = 1;
                            } else {
                                w.g = 1;
                            }
                        }
                        b'#' => {
                            if !w.have {
                                return false;
                            }
                            w.z = 1;
                        }
                        b'^' => w.z = 1,
                        _ => {}
                    }
                    if w.q == 1 {
                        w.qm = 1;
                    }
                    w.cur.push(c);
                    w.have = true;
                    i += 1;
                }
            }
        }
        w.flush(&mut self.toks);
        true
    }
}

/// The word being accumulated, with tok_push's provenance flags.
struct Word {
    cur: Vec<u8>,
    have: bool,
    q: i32,
    x: i32,
    qp: i32,
    d: i32,
    g: i32,
    z: i32,
    qm: i32,
    brk: bool,
    brc: bool,
    brs: bool,
    subs: Vec<usize>,
}

impl Word {
    fn new() -> Word {
        Word {
            cur: Vec::new(),
            have: false,
            q: 0,
            x: 0,
            qp: -1,
            d: 0,
            g: 0,
            z: 0,
            qm: 0,
            brk: false,
            brc: false,
            brs: false,
            subs: Vec::new(),
        }
    }

    fn quoting(&mut self) {
        if self.q == 1 {
            self.qm = 1;
        } else {
            self.qp = self.cur.len() as i32;
        }
        self.q = 1;
    }

    fn named_fd(&self) -> bool {
        self.have
            && self.cur.len() >= 2
            && self.cur[0] == b'{'
            && self.cur[self.cur.len() - 1] == b'}'
    }

    fn push(&self, toks: &mut Vec<Token>) {
        toks.push(Token {
            typ: b'W',
            val: self.cur.clone(),
            flags: [self.q, self.x, self.qp, self.d, self.g, self.z, self.qm],
            subs: self.subs.clone(),
        });
    }

    fn flush(&mut self, toks: &mut Vec<Token>) {
        if self.have {
            self.push(toks);
            *self = Word::new();
        }
    }
}

fn esc(v: &[u8], out: &mut Vec<u8>) {
    for &b in v {
        match b {
            b'\\' => out.extend_from_slice(b"\\\\"),
            b'\n' => out.extend_from_slice(b"\\n"),
            b'\t' => out.extend_from_slice(b"\\t"),
            _ => out.push(b),
        }
    }
}

fn main() {
    if std::env::args_os().len() != 1 {
        eprintln!("usage: tokenize <command-on-stdin>");
        exit(2);
    }
    let mut input = Vec::new();
    if io::stdin()
        .take(MAX_CMD_LEN as u64 + 1)
        .read_to_end(&mut input)
        .is_err()
    {
        eprintln!("tokenize: could not read stdin");
        exit(2);
    }
    if input.len() > MAX_CMD_LEN || input.contains(&0) {
        exit(3);
    }
    let mut l = Lexer {
        s: &input,
        toks: Vec::new(),
        substs: Vec::new(),
    };
    if !l.tokenize() {
        exit(3);
    }
    let mut out: Vec<u8> = Vec::new();
    for t in &l.toks {
        if t.typ != b'W' {
            out.push(t.typ);
            out.push(b'\t');
            esc(&t.val, &mut out);
            out.push(b'\n');
            continue;
        }
        let subs = if t.subs.is_empty() {
            "-".to_string()
        } else {
            t.subs
                .iter()
                .map(|v| v.to_string())
                .collect::<Vec<_>>()
                .join(",")
        };
        let f = t.flags;
        out.extend_from_slice(
            format!(
                "W\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t",
                f[0], f[1], f[2], f[3], f[4], f[5], f[6], subs
            )
            .as_bytes(),
        );
        esc(&t.val, &mut out);
        out.push(b'\n');
    }
    for (k, v) in l.substs.iter().enumerate() {
        out.extend_from_slice(format!("S\t{}\t", k).as_bytes());
        esc(v, &mut out);
        out.push(b'\n');
    }
    let mut w = BufWriter::new(io::stdout().lock());
    if w.write_all(&out).is_err() || w.flush().is_err() {
        exit(2);
    }
}
