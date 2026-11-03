// Command lock is bake-off A's lock primitive, Go candidate: the contract of
// the shell candidate's proto_lock, reimplemented over the same on-disk shape
// as scripts/lock-lib.sh (the lock is a symlink whose target is the owner
// token), with the standard library only.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var (
	seq    int
	epoch  string
	uptime string
	broken []string
	out    = bufio.NewWriter(os.Stdout)
)

func main() {
	rc := run(os.Args[1:])
	// A result that never reached stdout is a real error, whatever the verb
	// did on disk: a caller must not read a lost `held` line as success.
	if err := out.Flush(); err != nil {
		warn("writing the result failed: %v", err)
		rc = 2
	}
	os.Exit(rc)
}

func warn(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "lock: "+format+"\n", a...)
}

func usage() int {
	fmt.Fprintln(os.Stderr, "usage: lock try-for <path> <pid> | owner <path> | alive <token> | release <path> <token>")
	return 2
}

func run(args []string) int {
	if len(args) == 0 {
		return usage()
	}
	switch args[0] {
	case "try-for":
		if len(args) != 3 {
			return usage()
		}
		rc := acquireFor(args[1], args[2])
		for _, b := range broken {
			fmt.Fprintf(out, "broken %s\n", b)
		}
		if rc != 0 {
			return rc
		}
		owner, _ := os.Readlink(args[1])
		fmt.Fprintf(out, "held %s\n", strings.SplitN(owner, "-", 2)[0])
		return 0
	case "owner":
		if len(args) != 2 {
			return usage()
		}
		owner, err := os.Readlink(args[1])
		if err != nil || owner == "" {
			return 1
		}
		fmt.Fprintln(out, owner)
		return 0
	case "alive":
		if len(args) != 2 {
			return usage()
		}
		if ownerAlive(args[1]) {
			return 0
		}
		return 1
	case "release":
		if len(args) != 3 {
			return usage()
		}
		return releaseToken(args[1], args[2])
	}
	return usage()
}

// pathOK refuses the lock paths lock-lib.sh refuses, in the same order: a
// derived working path is the lock path plus a `#` suffix, so a `#` in the
// last component, a newline, a trailing slash or a leading dash would let one
// lock's name collide with another's working path or read as an option.
func pathOK(verb, p string) bool {
	switch {
	case p == "":
		warn("%s needs a lock path", verb)
	case strings.Contains(p[strings.LastIndex(p, "/")+1:], "#"):
		warn("%s refuses a lock name containing '#'", verb)
	case strings.Contains(p, "\n"):
		warn("%s refuses a lock path containing a newline", verb)
	case strings.HasSuffix(p, "/"):
		warn("%s refuses a lock path ending in '/'", verb)
	case strings.HasPrefix(p, "-"):
		warn("%s refuses a lock path beginning with '-'", verb)
	default:
		return true
	}
	return false
}

func lexists(p string) bool {
	_, err := os.Lstat(p)
	return err == nil
}

func isLink(p string) bool {
	fi, err := os.Lstat(p)
	return err == nil && fi.Mode()&os.ModeSymlink != 0
}

func readlink(p string) string {
	t, err := os.Readlink(p)
	if err != nil {
		return ""
	}
	return t
}

// parentWritable answers the question lock-lib.sh asks before blaming the
// store rather than contention: is the lock's directory there and writable.
func parentWritable(p string) bool {
	dir := "."
	if i := strings.LastIndex(p, "/"); i >= 0 {
		dir = p[:i]
		if dir == "" {
			dir = "/"
		}
	}
	fi, err := os.Stat(dir)
	return err == nil && fi.IsDir() && syscall.Access(dir, 2) == nil
}

func readUptime() string {
	b, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return ""
	}
	f := strings.Fields(string(b))
	if len(f) == 0 {
		return ""
	}
	whole := strings.SplitN(f[0], ".", 2)[0]
	n, err := strconv.ParseInt(whole, 10, 64)
	if err != nil || n < 0 {
		return ""
	}
	return strconv.FormatInt(n, 10)
}

func mint(ownerField string) string {
	if epoch == "" {
		epoch = strconv.FormatInt(time.Now().Unix(), 10)
	}
	seq++
	return fmt.Sprintf("%s-%s-%s-%d-%d", ownerField, epoch, uptime, os.Getpid(), seq)
}

// link creates the symlink and proves it landed by reading it back.
func link(target, p string) bool {
	if err := os.Symlink(target, p); err != nil {
		return false
	}
	return readlink(p) == target
}

func slug(tok string) string {
	var b strings.Builder
	for i := 0; i < len(tok) && i < 64; i++ {
		c := tok[i]
		if c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '.' || c == '_' || c == '-' {
			b.WriteByte(c)
		} else {
			b.WriteByte('_')
		}
	}
	return b.String()
}

// workPath hands out a free scratch name beside the lock, never an occupied
// one: everything downstream renames onto it without clearing it first.
func workPath(lock, kind, tok string) (string, bool) {
	s := slug(tok)
	for tries := 0; tries < 64; tries++ {
		seq++
		p := fmt.Sprintf("%s#%s#%s.%d-%d", lock, kind, s, os.Getpid(), seq)
		if !lexists(p) {
			return p, true
		}
	}
	return "", false
}

// displace moves p aside onto a fresh scratch name: 0 moved, 1 it was not
// there to move (contention), 2 a real error.
func displace(p, kind, tok string) (string, int) {
	aside, ok := workPath(p, kind, tok)
	if !ok {
		warn("no free working path beside %s", p)
		return "", 2
	}
	if err := os.Rename(p, aside); err == nil {
		return aside, 0
	}
	if lexists(p) && !parentWritable(p) {
		warn("cannot move %s out of the way", p)
		return "", 2
	}
	return "", 1
}

// restoreOrKeep puts a displaced link back, or leaves it on disk under its
// aside name: the link in hand may be the only copy of a live hold.
func restoreOrKeep(aside, p string) {
	back := readlink(aside)
	if back != "" && link(back, p) {
		os.Remove(aside)
		return
	}
	warn("%s was taken again; the displaced lock is kept at %s", p, aside)
}

func procExists(pid int) bool {
	err := syscall.Kill(pid, 0)
	if err == nil || errors.Is(err, syscall.EPERM) {
		return true
	}
	fi, err := os.Stat("/proc/" + strconv.Itoa(pid))
	return err == nil && fi.IsDir()
}

func ownerAlive(tok string) bool {
	field := strings.SplitN(tok, "-", 2)[0]
	if field == "detached" {
		return true
	}
	if field == "" || strings.Trim(field, "0123456789") != "" || len(field) > 10 {
		return false
	}
	pid, err := strconv.ParseInt(field, 10, 64)
	if err != nil || pid <= 0 || pid > math.MaxInt32 {
		return false
	}
	if !procExists(int(pid)) {
		return false
	}
	return ownerIsMinter(tok, int(pid))
}

func dropThroughDash(s string) string {
	if i := strings.Index(s, "-"); i >= 0 {
		return s[i+1:]
	}
	return s
}

// startedUp is how many seconds after boot pid started, from procfs; ok is
// false where the host will not say, and the pid alone then decides.
func startedUp(pid int) (int64, bool) {
	b, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/stat")
	if err != nil {
		return 0, false
	}
	s := string(b)
	i := strings.LastIndex(s, ")")
	if i < 0 {
		return 0, false
	}
	f := strings.Fields(s[i+1:])
	// starttime is field 22 overall, the 20th after the command name.
	if len(f) < 20 {
		return 0, false
	}
	ticks, err := strconv.ParseInt(f[19], 10, 64)
	if err != nil {
		return 0, false
	}
	return ticks / 100, true
}

// ownerIsMinter turns a live-looking owner absent when the process holding
// its pid started after the token was minted: a recycled pid.
func ownerIsMinter(tok string, pid int) bool {
	rest := dropThroughDash(dropThroughDash(tok))
	mintUp := strings.SplitN(rest, "-", 2)[0]
	if mintUp == "" || strings.Trim(mintUp, "0123456789") != "" {
		return true
	}
	if !strings.Contains(dropThroughDash(rest), "-") {
		return true
	}
	started, ok := startedUp(pid)
	if !ok {
		return true
	}
	m, err := strconv.ParseInt(mintUp, 10, 64)
	if err != nil {
		return true
	}
	return started <= m+2
}

func publish(lock, tok string) bool {
	return link(tok, lock)
}

func breakLock(lock, dead, tok string) int {
	claim := lock + "#break#" + slug(dead)
	claimTok := mint(strconv.Itoa(os.Getpid()))
	if !link(claimTok, claim) {
		holder := readlink(claim)
		if holder != "" && !ownerAlive(holder) {
			aside, rc := displace(claim, "dead", claimTok)
			if rc == 2 {
				return 2
			}
			if rc == 0 {
				if readlink(aside) == holder {
					os.Remove(aside)
				} else {
					restoreOrKeep(aside, claim)
				}
			}
		}
		return 1
	}
	if readlink(lock) != dead {
		os.Remove(claim)
		return 1
	}
	taken, rc := displace(lock, "taken", claimTok)
	if rc != 0 {
		os.Remove(claim)
		return rc
	}
	if readlink(taken) != dead {
		restoreOrKeep(taken, lock)
		os.Remove(claim)
		return 1
	}
	os.Remove(taken)
	broken = append(broken, dead)
	ok := publish(lock, tok)
	os.Remove(claim)
	if ok {
		return 0
	}
	return 1
}

func tryCore(lock, ownerField string) int {
	uptime = readUptime()
	tok := mint(ownerField)
	if !lexists(lock) && publish(lock, tok) {
		return 0
	}
	if isLink(lock) {
		owner := readlink(lock)
		if owner == "" || ownerAlive(owner) {
			return 1
		}
		return breakLock(lock, owner, tok)
	}
	if lexists(lock) {
		warn("%s exists and is not a lock symlink", lock)
		return 2
	}
	if publish(lock, tok) {
		return 0
	}
	if !lexists(lock) && !parentWritable(lock) {
		warn("cannot create %s", lock)
		return 2
	}
	return 1
}

func acquireFor(lock, pid string) int {
	if !pathOK("try-for", lock) {
		return 2
	}
	if pid == "" || pid[0] == '0' || strings.Trim(pid, "0123456789") != "" {
		warn("try-for needs a non-zero numeric owner pid with no leading zero")
		return 2
	}
	if len(pid) > 10 {
		warn("try-for refuses an owner pid wider than ten digits")
		return 2
	}
	return tryCore(lock, pid)
}

func releaseToken(lock, tok string) int {
	if !pathOK("release", lock) {
		return 2
	}
	if tok == "" {
		return usage()
	}
	if readlink(lock) != tok {
		return 1
	}
	taken, rc := displace(lock, "taken", tok)
	if rc != 0 {
		return rc
	}
	if readlink(taken) != tok {
		restoreOrKeep(taken, lock)
		return 1
	}
	if err := os.Remove(taken); err != nil {
		return 2
	}
	return 0
}
