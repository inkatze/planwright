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

With no program set up yet, mission control sets one up with you. It asks
only what you can answer from your own work, one question at a time, and
settles the rest itself, telling you in one plain line what it chose so you
can change it:

- **What the work is and which repositories it touches.** Asked first. It
  suggests the repository you are in and a short name to come back with.
- **Where your specs live.** Found in the repository; asked only when it
  finds none.
- **Your code host.** It checks that the GitHub CLI is signed in
  (`gh auth status`) and stores nothing: no token, no password. Only if you
  are signed out does it tell you how to sign in.
- **Where the state of the work lives.** It uses the default (see
  [State sources](#state-sources)) and says where each kind of fact comes
  from; tell it if your work items live in a tracker instead.
- **Duties to turn on.** One yes or no for the recommended set, each duty
  in one line by what it saves you, or name the changes you want; none is
  on until you say yes (see [Duties](#duties)).
- **Your voice and quiet hours.** None until you state them, any time.

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

- **Read directly:** a place it keeps up itself, through the sessions it
  starts, and so can always read, such as the specs.
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
your rules, and noticing what you keep doing by hand. The last three
do not run in the background yet, and turning them on changes nothing for
now: mission control records how to undo its acts and proposes automations
as it works with you, and the check against your rules does not run yet.

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
it may propose making it automatic. When a safety guard keeps refusing for
a reason a setting controls, it proposes that setting, saying what it would
change and which file it goes in. A proposal says what it noticed, what
it would change, how often that would run, where you would still step in,
what it costs, and how to turn it off, and you can always say no:

- **Yes:** it applies the change where it is allowed to (your rules, the
  program's configuration, which duties are on), and logs how to undo it.
  A change to your Claude Code settings or to a guard's setting is handed
  to you ready to apply, never made for you; a change to a repository is made by a session it
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
to change one is to say what you want ("explain less", "treat a session as
stuck after twenty minutes"). A setting that changes how much it may do
on its own, what it spends or what it copies is handed to you ready to
apply rather than changed for you. Each setting, its default and why that default
was chosen is listed in the
[options reference](options-reference.md).

## Resume

Coming back is one act: type `/mission-control` again, with the program's
name after it if you run more than one. With exactly one program set up,
the name can be left off; with several, it asks which; with none, it starts
the first run.

Type `/mc-panel` in that session to close the mission-control panel beside
the conversation when you can see it, or to show it when you cannot
(`/mc-panel open` or `/mc-panel close` to choose).

When you update planwright and reload, mission control notices: the panel
shows a short notice with the new version, and mission control rereads
what changed before it next tells you how something works.

The fresh session rebuilds its picture from what is recorded (your rules,
the program's folder, the code host, the specs and the sessions still
running), never from a stale summary. Its first message says what changed
since you last looked, what waits on you, and what is moving. If an older
mission-control session for the same program is still open, the new one
takes over the program. An old one that does not let go in time is shut
down if mission control started it; one you opened yourself stops acting
for the program and ends itself once it notices (Handover, below).

Ask for status at any time ("where are we?"). It answers in one fixed
shape: decisions waiting on you first, then what landed, then what is
moving.

While you are away it keeps going: sessions keep working, answers it can
give on your behalf are given and logged, and anything that needs you
waits in order for your return, with nothing dropped. Only the session
that asked a question waits for your answer; mission control never stops
everything else to wait on you. A question that
comes with a stated default, and goes unanswered for as long as it says
it will wait, settles on that default or is set aside for later; it shows
you each one settled that way, and you can reverse it.

## Handover

A long conversation eventually fills up. In the session you started
yourself, mission control lets it compress: it then reloads your rules and
checks its picture against the records before doing anything else, and
tells you only if that check fails. The panel never asks you to hand over.

A session mission control launched on its own hands over instead, since no
terminal has to move: it writes a note of everything open, starts its
successor, the successor checks that it holds every rule and open item
against that note, and the old session closes. You see one line saying it
happened.

The old session ends itself: once it gives up the program name, or finds
it already taken, its panel ends it as soon as its last turn finishes,
closing its tmux pane when Claude Code was the pane's command. The same
happens to an older mission-control session you started yourself when you
open a new one for the program, so nothing has to close it for you. A
session without the panel cannot end itself; it stops working and says it
can be closed.

A mission-control session that mission control starts, a successor
included, runs in Claude Code's auto mode, so a routine command does not
leave it waiting on an approval no other session is allowed to give.
Auto mode lets Claude Code's own safety check approve a routine command
in place of asking you. It changes nothing about what is forbidden:
merging, editing a repository, changing settings and the other refusals
at the top of this page still stop it, and marking a pull request ready
for review, where your repository leaves that to you, still asks you in
its window. If that safety check keeps refusing, the session pauses auto
mode and asks you in its window. A mission-control session you open
yourself keeps your own settings.
