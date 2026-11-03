// Command deps is bake-off A's dependency-line parser, Go candidate: the
// contract of the shell candidate's proto_deps, reimplementing the shared
// spec grammar's task-heading and Dependencies extraction byte for byte
// (scripts/spec-parse.sh), with the standard library only.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"regexp"
)

var taskID = regexp.MustCompile(`^[0-9]+(\.[0-9]+)?$`)

// fields splits as awk's default field splitting does: runs of blanks
// (space and tab) only. A carriage return is an ordinary byte, which is how
// a CRLF heading or token stays unmatched.
func fields(s []byte) [][]byte {
	return bytes.FieldsFunc(s, func(r rune) bool { return r == ' ' || r == '\t' })
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: deps <tasks.md>")
		return 2
	}
	fi, err := os.Stat(args[0])
	if err != nil || !fi.Mode().IsRegular() {
		fmt.Fprintf(os.Stderr, "deps: %s is not a readable file\n", args[0])
		return 2
	}
	data, err := os.ReadFile(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "deps: %s is not a readable file\n", args[0])
		return 2
	}
	out := bufio.NewWriter(os.Stdout)
	lines := bytes.Split(data, []byte("\n"))
	if len(data) > 0 && data[len(data)-1] == '\n' {
		lines = lines[:len(lines)-1]
	}
	if len(data) == 0 {
		lines = nil
	}
	fence := false
	cur := ""
	for _, line := range lines {
		if bytes.HasPrefix(line, []byte("```")) {
			fence = !fence
			continue
		}
		if fence {
			continue
		}
		switch {
		case bytes.HasPrefix(line, []byte("## ")):
			cur = ""
		case bytes.HasPrefix(line, []byte("### Task ")):
			cur = ""
			if f := fields(line); len(f) >= 3 && taskID.Match(f[2]) {
				cur = string(f[2])
				fmt.Fprintf(out, "TASK\t%s\n", cur)
			}
		case bytes.HasPrefix(line, []byte("### ")):
			cur = ""
		case cur != "" && bytes.HasPrefix(line, []byte("- **Dependencies:**")):
			for _, d := range depIDs(line) {
				fmt.Fprintf(out, "TASKDEP\t%s\t%s\n", cur, d)
			}
		}
	}
	// A record that never reached stdout is not a parse: exit 2, as the shell
	// candidate's awk does, never a 0 a caller reads as "no dependencies".
	if err := out.Flush(); err != nil {
		fmt.Fprintf(os.Stderr, "deps: writing the records failed: %v\n", err)
		return 2
	}
	if fence {
		fmt.Fprintln(os.Stderr, "deps: end of file inside an open column-0 code fence")
		return 3
	}
	return 0
}

// depIDs is spec_parse_dep_ids: past the last bolded lead, before the first
// parenthetical, commas and semicolons as separators, trailing periods
// stripped, and only whole tokens in the task-id grammar kept.
func depIDs(line []byte) []string {
	lead := []byte("**Dependencies:**")
	s := line[bytes.LastIndex(line, lead)+len(lead):]
	if i := bytes.IndexByte(s, '('); i >= 0 {
		s = s[:i]
	}
	// Byte by byte, not bytes.Map: that decodes UTF-8 and would rewrite an
	// invalid byte as U+FFFD.
	s = bytes.Clone(s)
	for i, c := range s {
		if c == ',' || c == ';' {
			s[i] = ' '
		}
	}
	var ids []string
	for _, tok := range fields(s) {
		tok = bytes.TrimRight(tok, ".")
		if taskID.Match(tok) {
			ids = append(ids, string(tok))
		}
	}
	return ids
}
