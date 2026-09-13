#!/bin/sh
# check-purged-identifiers.sh — the purged-identifier guard (guard-coverage
# Task 3; D-5; REQ-B1.1, REQ-B1.2, REQ-H1.3).
#
# Identifiers deliberately removed from this repo's history must stay removed.
# A secret scanner cannot help: a repo or person's name is not a credential
# pattern, so a re-leak is caught only by a reviewer noticing. This guard makes
# it mechanical.
#
# Nothing readable is committed. The seed file carries SHA-256 hashes over
# NORMALIZED identifiers; the scanner normalizes candidate text the same way
# and compares hashes, so the plaintext exists only on the human's side of the
# provisioning path (scripts/seed-purged-identifiers.sh, stdin-only).
#
# NORMALIZATION AND CANDIDATE GENERATION (the same rules on both sides):
#   1. A line is split into WORDS: maximal runs of [A-Za-z0-9], lowercased.
#      Every other byte — punctuation, whitespace, '/', '@', ':', '.', '-',
#      '_' — is a word separator and nothing else.
#   2. Every run of 1..max-words CONSECUTIVE words is concatenated with no
#      separator and offered as a CANDIDATE.
#   3. A seed is normalized by the same rule (its own words, concatenated).
#   4. A candidate matches only on FULL equality of the normalized forms.
# So `Acme-Internal`, `acme_internal`, `acme.internal`, `acmeinternal`,
# `https://example.com/acme-internal/x` and `mailto:a@acme-internal.example`
# all reduce to the same candidate, while `xacme-internal` (no word boundary
# before the identifier) and `acme` alone do not. The full in-scope and
# out-of-scope shape tables are in docs/purged-identifier-guard.md; the
# fixtures in tests/test-check-purged-identifiers.sh pin the boundary in both
# directions.
#
# Matched text is NEVER printed: a match is reported as location only, so the
# identifier the guard exists to keep out of the tree does not land in a CI
# log instead.
#
# Modes:
#   (default)              scan the tracked tree (`git ls-files`); untracked
#                          and ignored content is out of reach by design, and
#                          binary files (any NUL byte) are skipped.
#   --message-file <path>  screen one commit message (the githooks/commit-msg
#                          backstop's write-time call).
#   --commit-range <range> screen every commit message in a git range (the CI
#                          scan, which covers unwired clones and fork PRs the
#                          hook never runs in). Unlike check-commit-msgs.sh's
#                          FORMAT walk, merge commits are included: their
#                          subjects are GitHub's to format but their message
#                          CONTENT is permanent history like any other.
#
# Usage: check-purged-identifiers.sh [--seed-file <path>]
#                                    [--message-file <path> | --commit-range <range>]
# Exit: 0 clean · 1 a purged identifier reappears · 2 usage, environment, or
#   fail-closed seed error (missing, unreadable, malformed, or below the
#   committed minimum-seed floor — never a vacuous pass, REQ-H1.3).
#
# Portable POSIX sh plus perl with Digest::SHA (present on every target
# platform); the hashing is one batched in-process pass, never a fork per
# candidate (D-5).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: check-purged-identifiers.sh [--seed-file <path>]" \
    "[--message-file <path> | --commit-range <range>]" >&2
  exit 2
}

seed_file=""
message_file=""
commit_range=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --seed-file)
      [ "$#" -ge 2 ] || usage
      [ -z "$seed_file" ] || usage
      seed_file="$2"
      shift 2
      ;;
    --message-file)
      [ "$#" -ge 2 ] || usage
      [ -z "$message_file" ] || usage
      message_file="$2"
      shift 2
      ;;
    --commit-range)
      [ "$#" -ge 2 ] || usage
      [ -z "$commit_range" ] || usage
      commit_range="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

# The two message modes read different sources; asking for both is a usage
# error rather than a silent precedence rule.
if [ -n "$message_file" ] && [ -n "$commit_range" ]; then
  usage
fi

if ! top=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "check-purged-identifiers: not inside a git work tree; cannot resolve" \
    "the seed file or the tracked tree (failing, not skipping)" >&2
  exit 2
fi

# The default seed lives with the repo's other tracked guard data. It is
# planwright-repo-local: adopters inherit the checker, not this repo's seeds.
[ -n "$seed_file" ] || seed_file="$top/config/purged-identifiers.seed"
# Pinned absolute while the original working directory is still current: the
# tree scan below moves to the repo root, and a relative --seed-file would
# stop resolving there.
case "$seed_file" in
  /*) ;;
  *) seed_file="$PWD/$seed_file" ;;
esac

if [ ! -f "$seed_file" ] || [ ! -r "$seed_file" ]; then
  printf 'check-purged-identifiers: seed file %s is missing or unreadable; failing closed.\n' \
    "'$seed_file'" >&2
  echo "  Remedy: scripts/seed-purged-identifiers.sh (reads the plaintext from stdin)." >&2
  exit 2
fi

if ! command -v perl >/dev/null 2>&1; then
  echo "check-purged-identifiers: perl not found; cannot hash candidates (failing, not skipping)" >&2
  exit 2
fi
if ! perl -MDigest::SHA -e 1 >/dev/null 2>&1; then
  echo "check-purged-identifiers: perl is present but Digest::SHA is not; cannot hash candidates" >&2
  exit 2
fi

# The scanner. Held in a variable and expanded once inside double quotes: the
# expansion is not re-scanned, so perl's own '$' sigils survive intact.
# shellcheck disable=SC2016 # the $-sigils below are perl variables, not shell expansions
scan_program='
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

my ($seed_path, $mode, $comment_char) = @ARGV;
$comment_char = "#" unless defined $comment_char && $comment_char ne "";

sub closed {
    print STDERR "check-purged-identifiers: $_[0]\n";
    print STDERR "  A guard that cannot read its seeds fails closed rather than passing vacuously.\n";
    exit 2;
}

# ---- seed load. Any line that is not a comment, a known directive, or a bare
# ---- 64-char lowercase hex hash is a malformed seed file, which includes
# ---- every plaintext-shaped line: the file cannot carry a readable identifier
# ---- without failing this parse (REQ-B1.2).
open my $sfh, "<", $seed_path or closed("cannot open seed file: $!");
my (%seeds, $min_seeds, $max_words, $min_max_words);
my $sline = 0;
while (my $line = <$sfh>) {
    $sline++;
    $line =~ s/\r?\n\z//;
    next if $line =~ /\A\s*\z/ || $line =~ /\A\s*#/;
    if ($line =~ /\Amin-seeds:[ ]([0-9]{1,4})\z/) {
        closed("seed line $sline: duplicate min-seeds directive") if defined $min_seeds;
        $min_seeds = $1 + 0;
        next;
    }
    # Order matters: min-max-words is tested BEFORE max-words, because the
    # max-words pattern would otherwise never see it -- but a leading-anchored
    # match cannot confuse them anyway, and testing the longer key first keeps
    # that independent of the anchor.
    if ($line =~ /\Amin-max-words:[ ]([0-9]{1,2})\z/) {
        closed("seed line $sline: duplicate min-max-words directive") if defined $min_max_words;
        $min_max_words = $1 + 0;
        next;
    }
    if ($line =~ /\Amax-words:[ ]([0-9]{1,2})\z/) {
        closed("seed line $sline: duplicate max-words directive") if defined $max_words;
        $max_words = $1 + 0;
        next;
    }
    if ($line =~ /\A[0-9a-f]{64}\z/) {
        $seeds{$line} = 1;
        next;
    }
    closed("seed line $sline is neither a directive nor a 64-char lowercase hex hash");
}
close $sfh;

closed("seed file declares no min-seeds directive") unless defined $min_seeds;
closed("seed file declares no max-words directive") unless defined $max_words;
# min-seeds stops the seed list being emptied; min-max-words stops the
# candidate WINDOW being narrowed under it, which would leave every wider seed
# unmatchable with the hash count and the seed floor both untouched.
#
# ABSENCE is treated differently by surface, deliberately. The tree scan and
# the commit-range scan fail closed on it, and that is where the anti-tamper
# property lives: deleting the line is then a visible diff CI refuses. The
# write-time message screen does NOT, because a seed file predating the
# directive would otherwise wedge every commit in a wired clone -- the hook
# could not even be used to land the re-seed. Nothing the hook actually guards
# gets weaker: token screening is hash comparison, which the window floor does
# not affect. Same layering as the comment-line case, hook best-effort and CI
# authoritative.
#
# A min-max-words that is PRESENT is enforced everywhere, including the hook.
# Only its absence is tolerated, and only there.
if (!defined $min_max_words && $mode ne "message") {
    closed("seed file declares no min-max-words directive; re-seed with scripts/seed-purged-identifiers.sh to add it");
}
closed("min-seeds is 0: a guard with no floor could run green on an empty seed file")
    if $min_seeds < 1;
closed("max-words must be between 1 and 8, not $max_words")
    if $max_words < 1 || $max_words > 8;
if (defined $min_max_words) {
    closed("min-max-words must be between 1 and 8, not $min_max_words")
        if $min_max_words < 1 || $min_max_words > 8;
    closed("max-words is $max_words, below the declared min-max-words floor of $min_max_words: seeds wider than the window would never match")
        if $max_words < $min_max_words;
} elsif ($mode eq "message") {
    print STDERR "check-purged-identifiers: note: this seed file predates the min-max-words floor.\n";
    print STDERR "  Screening continues; CI refuses the file until it is re-seeded (scripts/seed-purged-identifiers.sh).\n";
}
my $seed_count = scalar keys %seeds;
closed("seed file holds $seed_count hash(es), below its own declared min-seeds of $min_seeds")
    if $seed_count < $min_seeds;

# ---- scanning
my $hits = 0;

# A label is a tracked path or a commit sha, and a tracked path is
# fork-PR-controllable: an embedded escape sequence in a filename would drive
# the terminal of whoever reads the report. Stripped before it is echoed, the
# echo discipline the security posture requires of every framework script.
sub safe_label {
    my ($label) = @_;
    $label =~ s/[^[:print:]]//g;
    return $label;
}

# report_line <label> <lineno> — location only. Printing the match would
# re-publish the very identifier this guard exists to keep out of the tree.
sub report_line {
    print STDERR "check-purged-identifiers: $_[0]:$_[1]: a purged identifier reappears (matched text withheld)\n";
    $hits++;
}

# report_where <label> <what> — the same withholding, for a match that has no
# line number because it is not in a line: a path, or a symlink target.
sub report_where {
    print STDERR "check-purged-identifiers: $_[0]: a purged identifier reappears in the $_[1] (matched text withheld)\n";
    $hits++;
}

# matches <text> — true when any candidate the text yields is seeded. The
# candidate walk report_line uses, without the reporting.
sub matches {
    my ($text) = @_;
    my @w = map { lc } ($text =~ /([A-Za-z0-9]+)/g);
    return 0 unless @w;
    for my $i (0 .. $#w) {
        my $candidate = "";
        for my $len (0 .. $max_words - 1) {
            last if $i + $len > $#w;
            $candidate .= $w[$i + $len];
            return 1 if $seeds{ sha256_hex($candidate) };
        }
    }
    return 0;
}

# redact <text> — the text with every word run that takes part in a seeded
# candidate replaced by a marker, separators and non-matching runs intact. It
# is what makes a path reportable at all: the operator still sees which
# directory and which part of the name to fix, and the identifier itself
# reaches no log. Splitting on a captured pattern alternates separator and
# word fields, so the word runs are exactly the odd indices.
sub redact {
    my ($text) = @_;
    my @parts = split /([A-Za-z0-9]+)/, $text, -1;
    my @widx  = grep { $_ % 2 == 1 } (0 .. $#parts);
    my @w     = map  { lc $parts[$_] } @widx;
    my %hide;
    for my $i (0 .. $#w) {
        my $candidate = "";
        for my $len (0 .. $max_words - 1) {
            last if $i + $len > $#w;
            $candidate .= $w[$i + $len];
            next unless $seeds{ sha256_hex($candidate) };
            $hide{$_} = 1 for ($i .. $i + $len);
        }
    }
    $parts[ $widx[$_] ] = "[redacted]" for keys %hide;
    return join("", @parts);
}

# scan_line <label> <lineno> <line> — one line of text against the seed set.
sub scan_line {
    my ($label, $lineno, $line) = @_;
    my @w = map { lc } ($line =~ /([A-Za-z0-9]+)/g);
    return unless @w;
    for my $i (0 .. $#w) {
        my $candidate = "";
        for my $len (0 .. $max_words - 1) {
            last if $i + $len > $#w;
            $candidate .= $w[$i + $len];
            next unless $seeds{ sha256_hex($candidate) };
            report_line($label, $lineno);
            return;    # one report per line; the location is the whole point
        }
    }
}

sub scan_text {
    my ($label, $text) = @_;
    $label = safe_label($label);
    my $lineno = 0;
    for my $line (split /\n/, $text, -1) {
        scan_line($label, ++$lineno, $line);
    }
}

if ($mode eq "tree") {
    # The NUL-delimited path list is drained first, so the per-file reads
    # below run under the default line separator rather than this one.
    my @paths;
    {
        local $/ = "\0";
        while (my $p = <STDIN>) {
            chomp $p;
            push @paths, $p if $p ne "";
        }
    }
    my $scanned = 0;
    for my $path (@paths) {
        # The path itself is tracked content: git records it as permanently as
        # any line of prose, so a reintroduction carried by a file or
        # directory name is one the guard has to see (REQ-B1.1, "anywhere in
        # the tracked tree"). Checked before the -f screen below, so a binary
        # file name is still read even though its content is not.
        #
        # A path match is the one case where the location IS the matched text,
        # so the label has to be redacted before it is echoed -- reporting it
        # raw would publish the identifier into a CI log, the very swap this
        # guard refuses to make everywhere else.
        my $path_hit = matches($path);
        my $label = safe_label($path_hit ? redact($path) : $path);
        report_where($label, "tracked path") if $path_hit;

        # A symlink tracks a target path, not the target file: following it
        # would scan content the repository does not own. But git stores that
        # target string AS the link blob, so that string is tracked content
        # even though the file behind it is not ours to read. Scan the target,
        # never the file it points at.
        if (-l $path) {
            my $target = readlink $path;
            report_where($label, "symlink target")
                if defined $target && matches($target);
            next;
        }
        # A path git lists but the checkout lacks (a sparse checkout, a broken
        # link) is skipped rather than fatal; the scan reports on what is
        # actually present.
        next unless -f $path;
        open my $fh, "<:raw", $path or next;
        # Binary exclusion by a bounded probe: a NUL byte in the first 8 KiB.
        # Bounded so a large tracked file is never slurped whole -- the rest
        # is then read a line at a time, so memory tracks the longest line
        # rather than the file.
        my $head = "";
        read $fh, $head, 8192;
        if (index($head, "\0") >= 0) {
            close $fh;
            next;
        }
        seek $fh, 0, 0;
        $scanned++;
        my $lineno = 0;
        while (my $line = <$fh>) {
            $line =~ s/\r?\n\z//;
            scan_line($label, ++$lineno, $line);
        }
        close $fh;
    }
    closed("the tracked tree enumerated 0 scannable files") if $scanned == 0;
    print "check-purged-identifiers: $scanned tracked text file(s) scanned against $seed_count seed(s).\n"
        if $hits == 0;
} elsif ($mode eq "message") {
    my $text = do { local $/; <STDIN> };
    closed("the commit message is empty") unless defined $text && $text =~ /\S/;
    # Screen what git will KEEP, which is very nearly everything.
    #
    # Comment lines are NOT dropped here, and that is deliberate. git removes
    # them only when the message goes through an editor: with -F or -m the
    # cleanup mode is "whitespace", which keeps them, so a hash line in a -F
    # commit is permanent history like any other. A screen that always stripped
    # them would blank the very text git was about to publish. Screening them
    # costs a false positive only when an editor session WOULD have removed
    # them, and the identifiers that could appear in a git-generated template are
    # branch names and paths -- things the tree scan already refuses.
    #
    # Everything from a --verbose scissors line on IS dropped, because git
    # truncates it under every cleanup mode that produces one, so screening it
    # would reject a remediation commit for the diff it removes. Dropped lines
    # are blanked, not deleted, so reported line numbers still match the file
    # the author is looking at.
    #
    # The scissors marker is written with the configured comment character,
    # read by the caller and passed in. Quoted before use, never compiled as a
    # pattern -- the configured value can be a regex metacharacter such as $
    # or |. Under "auto" git chose the character while composing the message
    # and the finished file no longer shows which candidate it picked, so no
    # scissors line is recognised and the whole message is screened, the
    # fail-closed direction.
    my $auto      = ($comment_char eq "auto");
    my $cq        = quotemeta($comment_char);
    my @kept;
    my $scissored = 0;
    for my $line (split /\n/, $text, -1) {
        if (!$auto && $line =~ /\A$cq\s*-{2,}\s*>8\s*-{2,}/) {
            $scissored = 1;
        }
        push @kept, $scissored ? "" : $line;
    }
    scan_text("commit message", join("\n", @kept));
    print "check-purged-identifiers: commit message clean against $seed_count seed(s).\n"
        if $hits == 0;
} elsif ($mode eq "range") {
    local $/ = "\0";
    my $commits = 0;
    while (my $record = <STDIN>) {
        chomp $record;
        # The tformat semantics of git log terminate each entry with a
        # newline, so every record after the first opens with that newline.
        $record =~ s/\A\s+//;
        next if $record eq "";
        my ($sha, $message) = split /\n/, $record, 2;
        next unless defined $sha && $sha =~ /\A[0-9a-f]{7,64}\z/;
        $commits++;
        scan_text("commit " . substr($sha, 0, 12), defined $message ? $message : "");
    }
    closed("the commit range yielded 0 commits") if $commits == 0;
    print "check-purged-identifiers: $commits commit message(s) screened against $seed_count seed(s).\n"
        if $hits == 0;
} else {
    closed("internal: unknown scan mode");
}

if ($hits > 0) {
    print STDERR "check-purged-identifiers: $hits location(s) carry a purged identifier.\n";
    print STDERR "  These identifiers were removed from this history deliberately; remove the\n";
    print STDERR "  reintroduction rather than widening the guard.\n";
    exit 1;
}
exit 0;
'

if [ -n "$message_file" ]; then
  if [ ! -f "$message_file" ] || [ ! -r "$message_file" ]; then
    printf 'check-purged-identifiers: message file %s is missing or unreadable; failing closed.\n' \
      "'$message_file'" >&2
    exit 2
  fi
  # What opens a comment line is configurable, and git's own message cleanup
  # follows the setting. Read it here so the screen strips exactly what git
  # will drop and screens exactly what git will keep.
  #
  # core.commentChar and core.commentString are aliases of each other, not a
  # primary and a variant: git >= 2.45 accepts a multi-byte string in EITHER,
  # while older git ignores commentString and rejects a multi-byte commentChar.
  # They stay separate keys on read, though, so setting one does not make the
  # other resolve, and both have to be consulted. When a config sets both, the
  # later line wins; commentString is preferred here because the pairing git
  # documents for cross-version configs puts it last for exactly that reason.
  comment_char=$(git config --get core.commentString 2>/dev/null || true)
  if [ -z "$comment_char" ]; then
    comment_char=$(git config --get core.commentChar 2>/dev/null || true)
  fi
  [ -n "$comment_char" ] || comment_char='#'
  perl -e "$scan_program" -- "$seed_file" message "$comment_char" <"$message_file"
  exit
fi

if [ -n "$commit_range" ]; then
  # A range beginning with '-' would reach git as an OPTION rather than a
  # revision. The CI caller builds its range from a branch name, so refusing
  # the shape outright costs nothing and closes the injection.
  case "$commit_range" in
    -*)
      echo "check-purged-identifiers: a commit range may not begin with '-'" >&2
      exit 2
      ;;
  esac
  # Resolve the range before walking it: a bad range must be a loud usage
  # error, not an empty stream the scanner would have to guess about.
  if ! git rev-list --count "$commit_range" >/dev/null 2>&1; then
    printf 'check-purged-identifiers: cannot walk commit range %s\n' "'$commit_range'" >&2
    exit 2
  fi
  # %x00 record separator, sha on the first line and the full message (%B)
  # after it, so a message containing blank lines stays one record. Streamed,
  # never captured: command substitution cannot carry the NUL separators.
  # An empty range yields zero records and fails closed inside the scanner —
  # an empty range upstream should be visible, not a silent pass, the same
  # posture check-commit-msgs.sh takes on its own range walk.
  git log --format='%H%n%B%x00' "$commit_range" \
    | perl -e "$scan_program" -- "$seed_file" range
  exit
fi

# Tree mode. `git ls-files -z` is the tracked-tree definition REQ-B1.1 names.
# Run it from the top level: `git ls-files` in a subdirectory lists only that
# subtree, so a run from anywhere but the root would silently scan less than
# the whole tree and still report success.
cd "$top" || {
  echo "check-purged-identifiers: cannot enter the work tree root" >&2
  exit 2
}
git ls-files -z | perl -e "$scan_program" -- "$seed_file" tree
