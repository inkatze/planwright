// Command ready is bake-off B's ready-guard decision path, Go candidate: the
// contract of the shell candidate's proto_ready, reimplementing the
// evaluate_predicate path of scripts/ready-guard.sh with the standard library
// only. The GitHub answers are files in the working directory, as the
// contract names them.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"unicode/utf8"
)

const reasonPrefix = "planwright ready-guard: "

// ghTimeout is gh_timeout's default; the harness passes no override.
const ghTimeout = "10"

func main() {
	os.Exit(run(os.Args[1:]))
}

// denied carries a deny out of the predicate, as emit_deny's exit does.
type denied struct{ reason string }

func deny(reason string) { panic(denied{reason}) }

func run(args []string) (code int) {
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: ready <pr|-> <owner/repo|-> <refuse|conflict-only>")
		return 2
	}
	pr, repo, policy := args[0], args[1], args[2]
	if pr == "-" {
		pr = ""
	}
	if repo == "-" {
		repo = ""
	}
	if (pr != "" && !validPRNumber(pr)) || (repo != "" && !validOwnerRepo(repo)) {
		fmt.Fprintln(os.Stderr, "ready: the pr must be a pull-request number and the repo owner/repo, or -")
		return 2
	}
	if policy != "refuse" && policy != "conflict-only" {
		fmt.Fprintln(os.Stderr, "ready: the policy must be refuse or conflict-only")
		return 2
	}
	defer func() {
		if r := recover(); r != nil {
			d, ok := r.(denied)
			if !ok {
				panic(r)
			}
			emitDeny(d.reason)
			code = 0
		}
	}()
	evaluate(pr, repo, policy)
	return 0
}

// emitDeny writes the decision object as jq -nc builds it.
func emitDeny(reason string) {
	r := reasonPrefix + sanitize(reason, "refusing an unconfirmable draft->ready flip")
	fmt.Printf("{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":%s}}\n", jsonString(r))
}

// toValid replaces invalid UTF-8 with U+FFFD by jq's own decoding rule,
// both when jq parses an answer and when --arg reads the decision text:
// the lead byte alone sets the sequence length, any 80-BF byte continues
// it, and one U+FFFD covers a bad lead, a sequence cut short by a
// non-continuation byte (up to that byte), one cut short by the end of the
// text (to the end), and an overlong, surrogate or out-of-range code point.
func toValid(s string) string {
	if utf8.ValidString(s) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); {
		c := s[i]
		if c < 0x80 {
			b.WriteByte(c)
			i++
			continue
		}
		need := 0
		switch {
		case c >= 0xc2 && c <= 0xdf:
			need = 2
		case c >= 0xe0 && c <= 0xef:
			need = 3
		case c >= 0xf0 && c <= 0xf4:
			need = 4
		}
		if need == 0 {
			b.WriteRune(utf8.RuneError)
			i++
			continue
		}
		if i+need > len(s) {
			b.WriteRune(utf8.RuneError)
			break
		}
		cp := rune(c) & (0x7f >> need)
		n, ok := need, true
		for k := 1; k < need; k++ {
			if s[i+k] < 0x80 || s[i+k] > 0xbf {
				n, ok = k, false
				break
			}
			cp = cp<<6 | rune(s[i+k]&0x3f)
		}
		first := [...]rune{0, 0, 0x80, 0x800, 0x10000}[need]
		if ok && (cp < first || (cp >= 0xd800 && cp <= 0xdfff) || cp > 0x10ffff) {
			ok = false
		}
		if ok {
			b.WriteString(s[i : i+n])
		} else {
			b.WriteRune(utf8.RuneError)
		}
		i += n
	}
	return b.String()
}

// maxDepth caps nesting well below every jq release's parsing-depth limit,
// so no answer jq refuses for its depth reads here; encoding/json alone
// allows far deeper.
const maxDepth = 100

// validStrings applies toValid to each string token's raw text on its own,
// as jq decodes a token, so a sequence cut short at a token's end swallows
// only the rest of that token.
func validStrings(s string) string {
	if utf8.ValidString(s) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] != '"' {
			b.WriteByte(s[i])
			continue
		}
		j := i + 1
		for j < len(s) && s[j] != '"' {
			if s[j] == '\\' {
				j++
			}
			j++
		}
		if j > len(s) {
			j = len(s)
		}
		b.WriteByte('"')
		b.WriteString(toValid(s[i+1 : j]))
		if j < len(s) {
			b.WriteByte('"')
		}
		i = j
	}
	return b.String()
}

// tooDeep reports nesting of arrays and objects, outside strings, past
// maxDepth.
func tooDeep(s string) bool {
	depth, inStr := 0, false
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case inStr && c == '\\':
			i++
		case c == '"':
			inStr = !inStr
		case inStr:
		case c == '[' || c == '{':
			depth++
			if depth > maxDepth {
				return true
			}
		case c == ']' || c == '}':
			depth--
		}
	}
	return false
}

// jsonString escapes as jq does for a string sanitize has already stripped
// of control bytes. sanitize drops bytes, not characters, so it can leave a
// broken sequence, which toValid repairs as jq --arg does, keeping the
// decision valid JSON.
func jsonString(s string) string {
	s = toValid(s)
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); {
		_, n := utf8.DecodeRuneInString(s[i:])
		c := s[i]
		switch {
		case c == '"' || c == '\\':
			b.WriteByte('\\')
			b.WriteByte(c)
		case c < 0x20 || c == 0x7f:
			fmt.Fprintf(&b, "\\u%04x", c)
		default:
			b.WriteString(s[i : i+n])
		}
		i += n
	}
	b.WriteByte('"')
	return b.String()
}

// sanitize is sanitize_printable: C0, DEL and C1 bytes removed, the fallback
// when nothing is left.
func sanitize(s, fallback string) string {
	var b []byte
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c <= 0x1f || (c >= 0x7f && c <= 0x9f) {
			continue
		}
		b = append(b, c)
	}
	if len(b) == 0 {
		return fallback
	}
	return string(b)
}

// answer is one gh call as $(...) captures it: trailing newlines stripped,
// NUL bytes dropped, and the recorded exit status, which is digits or else
// a failure (1).
func answer(name string) (string, int) {
	out, err := os.ReadFile(name)
	if err != nil {
		out = nil
	}
	out = bytes.ReplaceAll(out, []byte{0}, nil)
	rc := 0
	if b, err := os.ReadFile(name + ".rc"); err == nil {
		t := strings.TrimRight(string(b), "\n")
		rc = 1
		if t != "" && only(t, digits) && len(t) <= 9 {
			v, _ := strconv.Atoi(t)
			rc = v & 0xff
		}
	}
	return strings.TrimRight(string(out), "\n"), rc
}

// parseObject decodes one JSON value; anything that is not exactly one value
// reads as unparseable, as a failed jq does.
func parseObject(s string) (map[string]any, bool) {
	if loneHighSurrogate(s) || tooDeep(s) {
		return nil, false
	}
	dec := json.NewDecoder(strings.NewReader(validStrings(s)))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		return nil, false
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		return nil, false
	}
	m, ok := v.(map[string]any)
	return m, ok
}

// loneHighSurrogate reports a \u escape of a high surrogate not followed by
// one of a low surrogate. jq refuses such an answer outright, where
// encoding/json would read U+FFFD and let the predicate go on.
func loneHighSurrogate(s string) bool {
	hex4 := func(i int) (uint64, bool) {
		if i+4 > len(s) {
			return 0, false
		}
		v, err := strconv.ParseUint(s[i:i+4], 16, 32)
		return v, err == nil
	}
	for i := 0; i < len(s); i++ {
		if s[i] != '\\' || i+1 >= len(s) {
			continue
		}
		if s[i+1] != 'u' {
			i++
			continue
		}
		hi, ok := hex4(i + 2)
		if ok && hi >= 0xd800 && hi < 0xdc00 {
			if i+8 > len(s) || s[i+6] != '\\' || s[i+7] != 'u' {
				return true
			}
			lo, ok := hex4(i + 8)
			if !ok || lo < 0xdc00 || lo >= 0xe000 {
				return true
			}
		}
		i++
	}
	return false
}

// field is json_field: a present, non-null scalar as jq -r prints it. A
// number keeps its literal text, its exponent marker upper-cased as jq
// prints it; jq's other reformatting differs by version and is not
// reproduced.
func field(m map[string]any, k string) string {
	var s string
	switch v := m[k].(type) {
	case string:
		s = v
	case json.Number:
		s = strings.ReplaceAll(v.String(), "e", "E")
	case bool:
		s = strconv.FormatBool(v)
	default:
		return ""
	}
	return strings.TrimRight(strings.ReplaceAll(s, "\x00", ""), "\n")
}

// oidNumber marks a headRefOid answered as a JSON number. However jq prints
// it, a number is never an object id GitHub reports, so it never reads as
// one, whatever its digits.
type view struct {
	base, headOID, mergeable, url string
	oidNumber                     bool
}

// readView is check_view_rc then read_view_fields; false means the PR is
// already ready.
func readView(out string, rc int) (view, bool) {
	if rc == 124 || rc == 143 {
		deny("the GitHub query for this pull request did not finish within " + ghTimeout + "s, so its currency and mergeability could not be confirmed - refusing (fail closed). Wait and retry.")
	}
	if rc != 0 {
		deny("the GitHub query for this pull request failed, so its currency with its base branch and its mergeability could not be confirmed - refusing (fail closed). Check that gh is authenticated and that the pull request exists, then retry.")
	}
	if out == "" {
		deny("the GitHub query for this pull request returned nothing, so its currency and mergeability could not be confirmed - refusing (fail closed).")
	}
	m, ok := parseObject(out)
	draft, isBool := m["isDraft"].(bool)
	if !ok || !isBool {
		deny("the GitHub query for this pull request returned an answer the guard could not read (its draft state is missing or malformed), so a draft->ready flip could not be ruled out - refusing (fail closed).")
	}
	if !draft {
		return view{}, false
	}
	_, oidNumber := m["headRefOid"].(json.Number)
	v := view{field(m, "baseRefName"), field(m, "headRefOid"), field(m, "mergeable"), field(m, "url"), oidNumber}
	if v.base == "" || v.headOID == "" || v.mergeable == "" || v.url == "" {
		deny("the GitHub query for this pull request returned an incomplete answer, so its currency with its base branch and its mergeability could not be confirmed - refusing (fail closed).")
	}
	return v, true
}

func evaluate(pr, repo, policy string) {
	v, draft := readView(answer("view"))
	if !draft {
		return
	}
	if v.mergeable == "UNKNOWN" {
		v, draft = readView(answer("requery"))
		if !draft {
			return
		}
		if v.mergeable == "UNKNOWN" {
			deny("GitHub has not finished computing mergeability for this pull request (mergeable is still UNKNOWN after a re-query), so its currency and conflict state could not be confirmed - refusing (fail closed). Wait a few seconds and retry; do not fetch, GitHub computes this server-side.")
		}
	}
	switch v.mergeable {
	case "MERGEABLE":
	case "CONFLICTING":
		deny("this pull request conflicts with its base branch " + sanitize(v.base, "its base") + " (mergeable is CONFLICTING) - refusing the draft->ready flip (a ready PR must be mergeable). Merge the base into the branch, resolve the conflict, re-verify, then retry.")
	default:
		deny("this pull request's mergeability could not be confirmed (mergeable was " + sanitize(v.mergeable, "unreadable") + ", not MERGEABLE) - refusing (fail closed).")
	}
	if !validRefName(v.base) {
		deny("this pull request's base branch name is not a shape the guard will put in a compare query (" + sanitize(v.base, "unprintable") + ") - refusing (fail closed).")
	}
	if v.oidNumber || !validOID(v.headOID) {
		deny("this pull request's head commit id could not be read as a plain hex object id - refusing (fail closed).")
	}
	owner, name := ownerRepoFromURL(v.url, pr)
	if repo != "" && strings.ToLower(owner+"/"+name) != strings.ToLower(repo) {
		deny("the pull request gh resolved does not belong to the repository this call named - refusing (fail closed).")
	}
	behind, rc := answer("compare")
	if rc == 124 || rc == 143 {
		deny("the GitHub compare query did not finish within " + ghTimeout + "s, so this pull request's currency with its base branch could not be confirmed - refusing (fail closed). Wait and retry.")
	}
	if rc != 0 {
		deny("GitHub's compare endpoint could not be reached for this pull request, so its currency with base branch " + sanitize(v.base, "its base") + " could not be confirmed - refusing (fail closed). Wait and retry.")
	}
	if !validCount(behind) {
		deny("GitHub's compare endpoint returned no readable `behind_by` for this pull request, so its currency with its base branch could not be confirmed - refusing (fail closed). Wait and retry.")
	}
	if behind != "0" && policy != "conflict-only" {
		deny("this pull request is " + behind + " commit(s) behind its base branch " + sanitize(v.base, "its base") + ", so it has NOT been verified on a current head - refusing the draft->ready flip. Merge the base branch into it ('git fetch origin && git merge FETCH_HEAD'), let CI and review re-run, then retry.")
	}
}

// ownerRepoFromURL is parse_owner_repo_from_url, its shell pattern
// removals spelled out.
func ownerRepoFromURL(u, pr string) (string, string) {
	k := strings.LastIndex(u, "/pull/")
	if k < 0 {
		deny("the pull-request URL GitHub returned could not be read, so the guard cannot identify the repository to compare against - refusing (fail closed).")
	}
	tail := u[k+len("/pull/"):]
	if !validPRNumber(tail) {
		deny("the pull-request URL GitHub returned does not end in a pull-request number - refusing (fail closed).")
	}
	if pr != "" && tail != pr {
		deny("the pull request GitHub resolved is not the one this call named - refusing (fail closed).")
	}
	rest := u[:k]
	name := rest[strings.LastIndex(rest, "/")+1:]
	if j := strings.LastIndex(rest, "/"); j >= 0 {
		rest = rest[:j]
	}
	owner := rest[strings.LastIndex(rest, "/")+1:]
	if !validOwner(owner) {
		deny("the pull-request URL GitHub returned names no readable repository owner - refusing (fail closed).")
	}
	if !validRepo(name) {
		deny("the pull-request URL GitHub returned names no readable repository - refusing (fail closed).")
	}
	return owner, name
}

func only(s, set string) bool {
	for i := 0; i < len(s); i++ {
		if strings.IndexByte(set, s[i]) < 0 {
			return false
		}
	}
	return true
}

const (
	alnum  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	digits = "0123456789"
)

func validPRNumber(s string) bool {
	return s != "" && only(s, digits) && s[0] != '0' && len(s) <= 12
}

func validOwner(s string) bool {
	return s != "" && only(s, alnum+"-") && s[0] != '-' && s[len(s)-1] != '-' && len(s) <= 39
}

func validRepo(s string) bool {
	return s != "" && only(s, alnum+"._-") && s != "." && s != ".." && len(s) <= 100
}

func validOwnerRepo(s string) bool {
	if strings.Count(s, "/") != 1 || strings.HasPrefix(s, "/") || strings.HasSuffix(s, "/") {
		return false
	}
	o, r, _ := strings.Cut(s, "/")
	return validOwner(o) && validRepo(r)
}

func validRefName(s string) bool {
	return s != "" && only(s, alnum+"._/+@-") && s[0] != '-' && s[len(s)-1] != '/' &&
		s[0] != '/' && !strings.Contains(s, "..") && len(s) <= 255
}

func validOID(s string) bool {
	return only(s, "0123456789abcdef") && (len(s) == 40 || len(s) == 64)
}

func validCount(s string) bool {
	return s != "" && only(s, digits) && len(s) <= 12
}
