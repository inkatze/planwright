// Command tokenize is bake-off B's command-guard tokenizer, Go candidate:
// the contract of the shell candidate's proto_tokenize, reimplementing the
// tokenize function of scripts/worker-command-guard.sh byte for byte, with
// the standard library only.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

// maxCmdLen is the hook's MAX_CMD_LEN: a longer command is never tokenized.
const maxCmdLen = 8192

type token struct {
	typ                   byte
	val                   string
	q, x, qp, d, g, z, qm int
	subs                  []int
}

type lexer struct {
	s       string
	toks    []token
	substs  []string
	substAt int
}

// at is ${s:i:1}: the byte at i, or -1 past the end.
func (l *lexer) at(i int) int {
	if i < 0 || i >= len(l.s) {
		return -1
	}
	return int(l.s[i])
}

func isAlpha(c int) bool {
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
}

func isNameChar(c int) bool {
	return isAlpha(c) || (c >= '0' && c <= '9') || c == '_'
}

// dollarExpands: a `$` before c starts an expansion.
func dollarExpands(c int) bool {
	if isNameChar(c) {
		return true
	}
	switch c {
	case '@', '*', '#', '?', '!', '~', '=', '^', '+', '-', '{', '$', '[', '"':
		return true
	}
	return false
}

// dollarFormOK mirrors dollar_form_ok: the `$` at i opens a form whose value
// the analyzer can reason about.
func (l *lexer) dollarFormOK(i int) bool {
	switch l.at(i + 1) {
	case '[', '~':
		return false
	case '{':
		j := i + 2
		start := j
		for j < len(l.s) && l.s[j] != '}' {
			j++
		}
		if j >= len(l.s) {
			return false
		}
		body := l.s[start:j]
		if body == "" || !(isAlpha(int(body[0])) || body[0] == '_') {
			return false
		}
		for k := 0; k < len(body); k++ {
			if !isNameChar(int(body[k])) {
				return false
			}
		}
	default:
		j := i + 1
		switch l.at(j) {
		case '=', '^', '+', '#':
			j++
		}
		k := j
		for j < len(l.s) && isNameChar(int(l.s[j])) {
			j++
		}
		c := l.at(j)
		switch {
		case c == '[':
			return false
		case c == '*' || c == '@' || c == '?' || c == '!' || c == '-' || c == '$' || c == '#':
			if j == k && l.at(j+1) == '[' {
				return false
			}
		case c == -1 || c < 0x80:
		default:
			return false
		}
	}
	return true
}

// substScan mirrors subst_scan: the `$(` at i opens a substitution whose
// text runs to the first `)` and nests nothing. It returns the index past
// the `)`.
func (l *lexer) substScan(i int) (int, bool) {
	p := i + 2
	if l.at(p) == '(' {
		return 0, false
	}
	for p < len(l.s) {
		c := l.s[p]
		if c == ')' {
			break
		}
		if c == '(' || c == '`' {
			return 0, false
		}
		p++
	}
	if p >= len(l.s) {
		return 0, false
	}
	l.substs = append(l.substs, l.s[i+2:p])
	l.substAt = len(l.substs) - 1
	return p + 1, true
}

func (l *lexer) op(typ byte, v string) {
	l.toks = append(l.toks, token{typ: typ, val: v, qp: -1})
}

func allDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func (l *lexer) tokenize() bool {
	s := l.s
	n := len(s)
	var cur []byte
	have, curq, curx, curqp, curd, curg, curz, curqm := 0, 0, 0, -1, 0, 0, 0, 0
	brk, brc, brs := 0, 0, 0
	var cursub []int
	reset := func() {
		cur = nil
		cursub = nil
		have, curq, curx, curqp, curd, curg, curz, curqm = 0, 0, 0, -1, 0, 0, 0, 0
		brk, brc, brs = 0, 0, 0
	}
	push := func() {
		l.toks = append(l.toks, token{'W', string(cur), curq, curx, curqp, curd, curg, curz, curqm, cursub})
	}
	flush := func() {
		if have == 1 {
			push()
			reset()
		}
	}
	quoting := func() {
		if curq == 1 {
			curqm = 1
		}
		if curq != 1 {
			curqp = len(cur)
		}
		curq = 1
	}
	namedFdWord := func() bool {
		return have == 1 && len(cur) >= 2 && cur[0] == '{' && cur[len(cur)-1] == '}'
	}

	i := 0
	for i < n {
		c := s[i]
		switch c {
		case '\\':
			nc := l.at(i + 1)
			if nc == -1 {
				return false
			}
			switch nc {
			case '\'', '"', ';', '&', '|', '<', '>', '(', ')', '\n':
				return false
			case '$':
				curx = 1
			}
			quoting()
			cur = append(cur, byte(nc))
			have = 1
			i += 2
		case '\'':
			j := strings.IndexByte(s[i+1:], '\'')
			if j < 0 {
				return false
			}
			k := s[i+1 : i+1+j]
			if strings.IndexByte(k, '$') >= 0 {
				curx = 1
			}
			quoting()
			cur = append(cur, k...)
			have = 1
			i = i + 1 + j + 1
		case '"':
			j := i + 1
			var k []byte
			for j < n && s[j] != '"' {
				dc := s[j]
				if dc == '\\' {
					dn := l.at(j + 1)
					if dn == -1 {
						return false
					}
					if dn == '$' {
						curx = 1
					}
					k = append(k, byte(dn))
					j += 2
					continue
				}
				if dc == '$' {
					dn := l.at(j + 1)
					if dn == '(' {
						end, ok := l.substScan(j)
						if !ok {
							return false
						}
						cursub = append(cursub, l.substAt)
						if curd != 2 {
							curd = 1
						}
						k = append(k, s[j:end]...)
						j = end
						continue
					}
					if dn == '\'' {
						return false
					}
					if !l.dollarFormOK(j) {
						return false
					}
					if dn != '"' && dollarExpands(dn) && curd != 2 {
						curd = 1
					}
					if dn == '@' {
						curd = 2
					}
				}
				if dc == '`' {
					return false
				}
				k = append(k, dc)
				j++
			}
			if j >= n {
				return false
			}
			quoting()
			cur = append(cur, k...)
			have = 1
			i = j + 1
		case '`':
			return false
		case '$':
			nc := l.at(i + 1)
			if nc == '(' {
				end, ok := l.substScan(i)
				if !ok {
					return false
				}
				cursub = append(cursub, l.substAt)
				curd = 2
				if curq == 1 {
					curqm = 1
				}
				cur = append(cur, s[i:end]...)
				have = 1
				i = end
				continue
			}
			if nc == '\'' {
				return false
			}
			if !l.dollarFormOK(i) {
				return false
			}
			if dollarExpands(nc) {
				curd = 2
			}
			if curq == 1 {
				curqm = 1
			}
			cur = append(cur, c)
			have = 1
			i++
		case ' ', '\t':
			flush()
			i++
		case '\n':
			flush()
			l.op('O', ";")
			i++
		case ';':
			flush()
			if l.at(i+1) == ';' {
				l.op('O', ";;")
				i += 2
			} else {
				l.op('O', ";")
				i++
			}
		case '&':
			nc := l.at(i + 1)
			if nc == '>' && namedFdWord() {
				return false
			}
			flush()
			switch {
			case nc == '&':
				l.op('O', "&&")
				i += 2
			case nc == '>':
				if l.at(i+2) == '>' {
					l.op('R', "&>>")
					i += 3
				} else {
					l.op('R', "&>")
					i += 2
				}
			default:
				l.op('O', "&")
				i++
			}
		case '|':
			flush()
			switch l.at(i + 1) {
			case '|':
				l.op('O', "||")
				i += 2
			case '&':
				l.op('O', "|")
				i += 2
			default:
				l.op('O', "|")
				i++
			}
		case '<', '>':
			fdpfx := ""
			if namedFdWord() {
				return false
			}
			if have == 1 {
				if allDigits(string(cur)) && curq != 1 {
					fdpfx = string(cur)
				} else {
					push()
				}
				reset()
			}
			nc := l.at(i + 1)
			if c == '<' {
				switch nc {
				case '<':
					switch l.at(i + 2) {
					case '<':
						l.op('R', fdpfx+"<<<")
						i += 3
					case '-':
						l.op('R', fdpfx+"<<-")
						i += 3
					default:
						l.op('R', fdpfx+"<<")
						i += 2
					}
				case '&':
					l.op('R', fdpfx+"<&")
					i += 2
				case '(':
					return false
				default:
					l.op('R', fdpfx+"<")
					i++
				}
			} else {
				switch nc {
				case '>':
					l.op('R', fdpfx+">>")
					i += 2
				case '|':
					l.op('R', fdpfx+">|")
					i += 2
				case '&':
					l.op('R', fdpfx+">&")
					i += 2
				case '(':
					return false
				default:
					l.op('R', fdpfx+">")
					i++
				}
			}
		case '(', ')':
			flush()
			l.op('O', string(c))
			i++
		default:
			switch c {
			case '*', '?':
				curg = 1
			case '[':
				brk = 1
			case ']':
				if brk == 1 {
					curg = 1
				}
			case '{':
				brc = 1
				curz = 1
			case ',':
				if brc == 1 {
					brs = 1
				}
			case '.':
				if brc == 1 && l.at(i+1) == '.' {
					brs = 1
				}
			case '}':
				if brs == 1 {
					curg = 1
				}
				curz = 1
			case '~':
				if have == 0 {
					curg = 1
				} else {
					curz = 1
				}
			case '#':
				if have == 0 {
					return false
				}
				curz = 1
			case '^':
				curz = 1
			}
			if curq == 1 {
				curqm = 1
			}
			cur = append(cur, c)
			have = 1
			i++
		}
	}
	flush()
	return true
}

func esc(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, "\n", `\n`)
	return strings.ReplaceAll(s, "\t", `\t`)
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) != 0 {
		fmt.Fprintln(os.Stderr, "usage: tokenize <command-on-stdin>")
		return 2
	}
	in, err := io.ReadAll(io.LimitReader(os.Stdin, maxCmdLen+1))
	if err != nil {
		fmt.Fprintln(os.Stderr, "tokenize: could not read stdin")
		return 2
	}
	if len(in) > maxCmdLen || bytes.IndexByte(in, 0) >= 0 {
		return 3
	}
	l := &lexer{s: string(in)}
	if !l.tokenize() {
		return 3
	}
	w := bufio.NewWriter(os.Stdout)
	for _, t := range l.toks {
		if t.typ != 'W' {
			fmt.Fprintf(w, "%c\t%s\n", t.typ, esc(t.val))
			continue
		}
		subs := "-"
		if len(t.subs) > 0 {
			parts := make([]string, len(t.subs))
			for k, v := range t.subs {
				parts[k] = strconv.Itoa(v)
			}
			subs = strings.Join(parts, ",")
		}
		fmt.Fprintf(w, "W\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\n", t.q, t.x, t.qp, t.d, t.g, t.z, t.qm, subs, esc(t.val))
	}
	for k, v := range l.substs {
		fmt.Fprintf(w, "S\t%d\t%s\n", k, esc(v))
	}
	if w.Flush() != nil {
		return 2
	}
	return 0
}
