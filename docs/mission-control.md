# Mission control: one conversation for a whole program

Mission control is a standing conversation that runs a program of work for
you: one or more repositories, the specs that describe the work, and every
agent session doing it. You talk to it in plain words. It starts the
sessions, keeps them moving, answers what it can on your behalf, and brings
you only what needs your judgment, each item packaged so you can decide
from that message alone. You do not need to know how planwright works
inside to use it; it does that part for you.

What it never does, whatever it is told:

- merge a pull request (merging is yours);
- approve a spec, or start reviewing one with you unless you ask;
- send a message to a person without your yes on the exact text and the
  recipient;
- edit a repository itself (every change is made by a session it starts);
- change your settings or loosen its own guardrails (it hands you a
  settings change ready to apply instead).

## First run

Open Claude Code and type:

```text
/mission-control
```

With no program set up yet, mission control walks you through one, one
question at a time, showing how far along you are:

1. **The program's name and its repositories.** A short name you will use
   to come back, and the repositories the work touches.
2. **Where your specs live.** The folder holding the program's specs.
3. **Your code host.** It checks that the GitHub CLI is signed in
   (`gh auth status`) and stores nothing: no token, no password.
4. **Where the state of the work lives**, one kind of fact at a time (see
   [State sources](#state-sources)).
5. **Duties to turn on.** Each is shown by what it saves you; none is on
   until you say yes (see [Duties](#duties)).
6. **Your voice and quiet hours.** How drafts written for you should sound,
   and when it should not interrupt you.

It then writes the program's configuration, sets up the program's private
folder, records your answers, starts its background watchers, and tells you
in one line per write what it wrote. If a write is refused, you hear why
and that question is asked again.

How much it explains as it goes is up to you: guided (the default on a
fresh installation, explaining each idea the first time it comes up),
standard (hints only when you seem stuck) or expert (asks and moves on).
Say which you want at any time; it is remembered.

**The program's private folder** sits under your planwright configuration
folder, outside every repository, and is never committed. It holds the
rules you set, what mission control has learned about the program, its
logs of what it decided and how to undo each act, and the note it leaves
for its successor. It holds no secret. Ask mission control where it is.

## State sources

Different facts about a program live in different places: work items in a
tracker or in the specs, code state on the code host, decisions in the
specs or a document, deadlines wherever you keep them. For each kind of
fact, you tell mission control where the truth lives and how it can know
it:

- **Read directly:** a place it reads itself, such as the specs.
- **Kept fresh:** a place it copies on a schedule, such as your pull
  requests on the code host. Every report built from it says how old the
  copy is.
- **Only cited:** a place it cannot read yet, such as most trackers,
  document tools and design tools. It keeps the links and what you told it,
  and never claims to know the current state there; when it reports on such
  a fact, it says the picture is yours, not a fresh reading.

It offers a starting map and you change it as you like. It never guesses a
place for you.

## Duties

A duty is a job mission control does for you in the background, each with
a one-line summary of what it saves you. The ones that ship cover keeping
sessions moving and closing them when their work lands, turning what waits
on you into decide-ready items and drafts, checking that a pull request is
really ready before it is offered, predicting overlapping changes and merge
order, letting known dates set priorities, preparing what you need before a
decision, recording how to undo each act, checking what was done against
your rules, and noticing what you keep doing by hand.

Ask for the list at any time ("what duties are there?"), and turn any duty
on or off by saying so. A duty that is off watches nothing and costs
nothing. A duty can also run in a trial mode first: it decides as if it
were on, writes down what it would have done, and bothers you with none of
it, so you can compare before you trust it. Moving it out of trial is your
call; mission control suggests it once the trial agrees with you often
enough.

The watching itself is done by small scripts, not by an agent sitting in a
loop, so a quiet program costs very little.

## Proposals

When mission control notices a repeat (you give the same answer to the
same question, or take the same manual step after the same kind of event),
it may propose making it automatic. A proposal says what it noticed, what
it would change, how often that would run, where you would still step in,
what it costs, and how to turn it off, and you can always say no:

- **Yes:** it applies the change where it is allowed to (your rules, the
  program's configuration, which duties are on), and logs how to undo it.
  A change to your Claude Code settings is handed to you ready to apply,
  never made for you; a change to a repository is made by a session it
  starts, landing as a draft pull request you review.
- **Not now:** it holds the proposal until a date or an event you name.
- **No:** it records that and does not ask again unless the pattern
  changes.

Nothing turns itself on.

**Rules you state directly** skip the proposal. Say "from now on, never
ask me before closing a finished session" and it is recorded at once,
echoed back in one line, and can be undone with "undo that". A later
statement on the same subject replaces the earlier one, and if two of your
rules seem to collide, it asks you which you meant rather than deciding.

## Preferences

Almost everything mission control does that you might want done
differently is a setting with a sensible default: how often it checks the
code host, how long a session may sit still before it is treated as
stuck, when it hands over to a fresh session, how much it explains, how a
spec review you ask for runs, where drafts go, and more. The simplest way
to change one is to say what you want ("check pull requests every two
minutes", "explain less"). Each setting, its default and why that default
was chosen is listed in the
[options reference](options-reference.md).

## Resume

Coming back is one act: type `/mission-control` again, with the program's
name after it if you run more than one. With exactly one program set up,
the name can be left off; with several, it asks which; with none, it starts
the first run.

The fresh session rebuilds its picture from what is recorded (your rules,
the program's folder, the code host, the specs and the sessions still
running), never from a stale summary. Its first message says what changed
since you last looked, what waits on you, and what is moving. If an older
mission-control session for the same program is still open, the new one
takes over the program. An old one that does not let go in time is shut
down if mission control started it; one you opened yourself stays open but
stops acting for the program.

Ask for status at any time ("where are we?"). It answers in one fixed
shape: decisions waiting on you first, then what landed, then what is
moving.

While you are away it keeps going: sessions keep working, answers it can
give on your behalf are given and logged, and anything that needs you
waits in order for your return, with nothing dropped. A question with an
obvious safe default may settle on that default after a while; it shows
you each one it settled, and you can reverse it.

## Handover

A long conversation eventually fills up. Rather than letting it compress
its memory and lose detail, mission control hands over to a fresh session
of itself: it writes a note of everything open, starts its successor, the
successor checks that it holds every rule and open item against that note,
and the old session closes. You see one line saying it happened. Where
your setup cannot move the conversation on its own, you are offered the one
step that does it.

If a compression happens anyway, it reloads your rules and checks its
picture against the records before doing anything else, and tells you if
that check fails.
