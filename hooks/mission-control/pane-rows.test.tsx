import { expect, test } from 'claude-code/testing'

import { bandOf, BAND, boot, digestText, PANE, world } from './fixture'
import { spriteCells } from './panel-art'

const tab = (...f: (string | number)[]) => f.join('\t')
const SHA = '0123456789abcdef0123456789abcdef01234567'
const CMD = ['gh', 'pr', 'merge', '1', '--repo', 'acme/widgets', '--squash', '--match-head-commit', SHA].join(' ')

// One pull request in every group the operator's ready conditions give.
const PRS = [
  tab('reviews', 'ok', 60),
  tab('review-count', 'mine', 6),
  tab('review-mine', 'acme/widgets', 1, 'ready', 'green', 0, 'yes', '-', 'Ship the widget'),
  tab('review-mine', 'acme/widgets', 2, 'draft', 'green', 0, 'yes', '-', 'Draft the gadget'),
  tab('review-mine', 'acme/widgets', 3, 'ready', 'green', 2, 'yes', '-', 'Rework the docs'),
  tab('review-mine', 'acme/widgets', 4, 'draft', 'running', 0, 'no', '-', 'Tune the cache'),
  tab('review-mine', 'acme/widgets', 5, 'draft', 'red', 0, 'no', '-', 'Break the build'),
  tab('review-mine', 'acme/widgets', 6, 'draft', 'green', 0, 'no', '-', 'Fresh branch'),
  tab('merge-ready', 1, 'all'),
  tab('merge-command', 'acme/widgets', 1, CMD),
]

// Whitespace-only Texts are the painted margins and fill of a card row, not content.
const rows = async (ui: { findAll: (q: { type: string }) => Promise<{ text?: string }[]> }) =>
  (await ui.findAll({ type: 'Text' })).map(t => t.text ?? '').filter(l => l.trim() !== '')

test('only the pull requests that need the operator are listed, the rest counted in one line', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: PRS }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  // A pull request ready to merge shows once, under Waiting on you with its command.
  expect(t.some(l => /^Ready to merge$/.test(l))).toBe(false)
  expect(t).toContain('#1 Ship the widget · ready to merge')
  expect(t.filter(l => l.includes('Ship the widget'))).toHaveLength(1)
  // A long command wraps across rows, so it is read back joined.
  expect(t.join(' ')).toContain(`run: ${CMD}`)
  expect(t.join(' ').split(`run: ${CMD}`)).toHaveLength(2)
  expect(t).toContain('#2 Draft the gadget · a draft waiting for your yes')
  for (const title of ['Rework the docs', 'Tune the cache', 'Break the build', 'Fresh branch']) {
    expect(t.some(l => l.includes(title))).toBe(false)
  }
  expect(t).toContain('+ 4 other pull requests need nothing from you')
  await ui.unmount()
})

// Waiting on you holds a ready pull request only as a count when the store
// could not be read in full, so the pull request stays named where it is listed.
test('a ready pull request the Waiting card cannot name stays listed under Pull requests', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: PRS.map(l => (l.startsWith('merge-ready\t') ? tab('merge-ready', 1, 'partial') : l)),
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t).toContain('#1 Ship the widget')
  expect(t.join(' ')).toContain(`run: ${CMD}`)
  expect(t.some(l => l === '#1 Ship the widget · ready to merge')).toBe(false)
  await ui.unmount()
})

test('with nothing for the operator to act on, the pull requests are only counted', async ($, on) => {
  const w = world(on, {
    digest: digestText({ extra: [tab('reviews', 'ok', 5), tab('review-mine', 'acme/widgets', 9, 'draft', 'red', 0, 'no', '-', 'Only one')] }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t).toContain('1 other pull request needs nothing from you')
  expect(t.some(l => /^(Ready to merge|Needs you|In review|CI running|CI failed)$/.test(l))).toBe(false)
  expect(t.some(l => l.includes('Only one'))).toBe(false)
  await ui.unmount()
})

// A ready verdict outlives the merge: the open list no longer holding the
// pull request is the evidence it is gone.
test('a merge-ready pull request that already merged is not counted or listed', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: [
        tab('reviews', 'ok', 60),
        tab('review-count', 'mine', 1),
        tab('review-mine', 'acme/widgets', 1, 'ready', 'green', 0, 'yes', '-', 'Still open'),
        tab('merge-ready', 2, 'all'),
        tab('merge-command', 'acme/widgets', 1, CMD),
        tab('merge-command', 'acme/widgets', 9, CMD.replace(' 1 ', ' 9 ')),
      ],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t).toContain('#1 Still open · ready to merge')
  expect(t.some(l => l.startsWith('#9'))).toBe(false)
  expect(t.join(' ')).toContain('2 questions wait for your answer, and 1 pull request is ready for you to merge.')
  await ui.unmount()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await bandOf(band)).toContain('1 ready to merge')
  await band.unmount()
})

test('a list cut short does not prove a ready pull request merged', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: [
        tab('reviews', 'ok', 60),
        tab('review-count', 'mine', 5),
        tab('review-mine', 'acme/widgets', 1, 'ready', 'green', 0, 'yes', '-', 'Listed'),
        tab('merge-ready', 1, 'all'),
        tab('merge-command', 'acme/widgets', 9, CMD.replace(' 1 ', ' 9 ')),
      ],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await rows(ui)).some(l => l.startsWith('#9'))).toBe(true)
  await ui.unmount()
})

test('the pane opens with one plain sentence on what is going on', async ($, on) => {
  const w = world(on, { digest: digestText().replace(/^waiting\t.*$/m, 'waiting\t0') })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t).toContain("What's going on")
  expect(t).toContain('2 sessions are working. Nothing needs you right now.')
  expect(t.indexOf("What's going on")).toBeLessThan(t.indexOf('Right now'))
  await ui.unmount()
})

test('a review session is named by its pull request title', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: [tab('reviews', 'ok', 60), tab('review-mine', 'acme/widgets', 848, 'draft', 'green', 0, 'no', '-', 'Fix the gadget'), tab('flight', 'cb-848', 'cubic-pr-848', 'tmux', 'working')],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await rows(ui)).toContain('Working on a review of PR 848 "Fix the gadget"')
  await ui.unmount()
})

test('Prop pal draws no caption: the picture alone on the terminal', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await rows(ui)).some(l => l.includes('Prop pal'))).toBe(false)
  await ui.unmount()
})

test('a surface that cannot draw pictures keeps a plain-text Prop pal and its state', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await rows(ui)).some(l => /^Prop pal: circling/.test(l))).toBe(true)
  await ui.unmount()
})

test('a ready pull request is not set beside a line saying nothing waits', async ($, on) => {
  const w = world(on, {
    digest: digestText({ extra: PRS }).replace(/^waiting\t.*$/m, 'waiting\t0'),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t).toContain('#1 Ship the widget · ready to merge')
  expect(t).not.toContain('Nothing waits on you.')
  await ui.unmount()
})

test('the mascot stays at the top of the pane, above the summary', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const t = await rows(ui)
  const prop = t.findIndex(l => l.startsWith('Prop pal'))
  expect(prop).toBeGreaterThan(-1)
  expect(prop).toBeLessThan(t.indexOf("What's going on"))
  await ui.unmount()
})

test('waiting on you is one row per item, not a count', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: [
        tab('flight', 'sd-1', 'spec-draft-panel', 'tmux', 'waiting'),
        tab('flight', 'k-1', 'alpha:kickoff', 'tmux', 'waiting'),
      ],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t).toContain('Needs your answer: the draft of the panel spec')
  expect(t).toContain('Needs your answer: the kickoff of the alpha spec')
  expect(t.filter(l => /^Needs your answer/.test(l))).toHaveLength(2)
  await ui.unmount()
})

test('what waits on the operator outside a session is still counted', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await rows(ui)).toContain('2 waiting on you, not in a session')
  await ui.unmount()
})

test('in flight is one row per session', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: [tab('flight', 'w-3', 'alpha:task-4', 'tmux', 'working')] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t.filter(l => l === 'Working on a task of the alpha spec')).toHaveLength(2)
  expect(t).toContain('Working on a one-off change (docs)')
  expect(t).toContain('In flight (3)')
  await ui.unmount()
})

test('the pane drops the sections an operator never acts on, and the jargon', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const all = (await rows(ui)).join('\n')
  for (const word of ['Tower log', 'Fuel', 'rung', 'polls_per_hour', 'Weather', 'sources', 'Instruments', 'settled share', 'failsafe', 'relaunch w-one'])
    expect(all).not.toContain(word)
  await ui.unmount()
})

test('readouts and the status line say weekly usage as well as the 5-hour window', async ($, on) => {
  const w = world(on, {
    rateLimits: [
      { kind: 'five_hour', percentUsed: 27 },
      { kind: 'seven_day', percentUsed: 88 },
    ],
    digest: digestText({ extra: ['knob\tusage-hold\t90'] }),
  })
  await boot($, w)
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(pane)
  expect(t.indexOf('Weekly usage 88% · stop at 90% · OK')).toBeLessThan(t.indexOf('5-hour usage 27% · stop at 90% · OK'))
  expect(t).toContain('Weekly usage 88% · stop at 90% · OK')
  expect(t).toContain('5-hour usage 27% · stop at 90% · OK')
  await pane.unmount()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const line = await bandOf(band)
  expect(line).toContain('weekly 88%')
  expect(line).toContain('5-hour 27%')
  await band.unmount()
})

test('what REQ-F1.1 names stays visible, in plain words', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t).toContain('Recent decisions')
  expect(t).toContain('2026-10-26 10:15  relaunch')
  expect(t).toContain('Sessions running: 2 of 4 (50%)')
  expect(t).toContain('Checks per hour: 72 of 100 (72%)')
  expect(t).toContain('Context resets since start: 0')
  expect(t).toContain('Notes last updated 10m ago')
  await ui.unmount()
})

test('a kept ready verdict does not stand over a red check or an open thread the snapshot now shows', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: [
        tab('reviews', 'ok', 60),
        tab('review-mine', 'acme/widgets', 1, 'ready', 'red', 0, 'yes', '-', 'Went red'),
        tab('review-mine', 'acme/widgets', 2, 'ready', 'green', 1, 'yes', '-', 'New thread'),
        tab('merge-command', 'acme/widgets', 1, CMD),
        tab('merge-command', 'acme/widgets', 2, CMD),
      ],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t.some(l => l.includes('Went red'))).toBe(false)
  expect(t.some(l => l.includes('New thread'))).toBe(false)
  expect(t).toContain('2 other pull requests need nothing from you')
  expect(t).not.toContain('Ready to merge')
  await ui.unmount()
})

test('with readiness not judged, a pull request is not told to wait for the operator', async ($, on) => {
  const w = world(on, {
    digest: digestText({ extra: [tab('reviews', 'ok', 60), tab('review-mine', 'acme/widgets', 3, 'draft', 'green', 0, 'yes', '-', 'Unjudged'), 'unreadable\tmerge-ready store'] }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await rows(ui)).some(l => l.includes('Unjudged'))).toBe(false)
  await ui.unmount()
})

test('an old reviews snapshot says how old it is', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: [tab('reviews', 'ok', 1800), tab('review-mine', 'acme/widgets', 3, 'draft', 'red', 0, 'no', '-', 'x')] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await rows(ui)).toContain('Pull requests (1) · read 30m ago')
  await ui.unmount()
})

const IDLE = digestText({ finished: 3 }).replace(/^flight\t.*\n/gm, '').replace(/^waiting\t.*$/m, 'waiting\t0')

test('a landing plays from its first frame whatever came before, then stops blitting', async ($, on) => {
  const w = world(on, { digest: digestText().replace(/^waiting\t.*$/m, 'waiting\t0') })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await w.clock.advance(5_000)
  w.set({ digest: IDLE })
  await w.clock.advance(10_000)
  const landing = w.blits.map(b => b.cells)
  expect(landing).toContain(spriteCells('landing', 1).cells)
  const settled = w.blits.length
  await w.clock.advance(5_000)
  expect(w.blits.length).toBe(settled)
  await ui.unmount()
})

test('a still landing is drawn in its settled pose', async ($, on) => {
  const w = world(on, { digest: IDLE.replace(/^holder\t.*$/m, 'holder\tattended') + '\nknob\tmascot\t1' })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const cells = (await ui.findAll({ type: 'Raster' })).map(n => n.props?.cells)
  expect(cells).toEqual([spriteCells('landing', 6).cells])
  await ui.unmount()
})

test('every limit mission control reports has a plain name and reads in plain words', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: [tab('headroom', 'context_steps', 3, 200, 2), tab('headroom', 'host_load', 10, 100, 10)],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t).toContain('Mission control steps: 3 of 200 (2%)')
  expect(t).toContain('Machine load: 10% of the 100% limit')
  expect(t).not.toContain('context steps')
  expect(t).not.toContain('host load')
  expect(t).not.toContain('of 100 (10%)')
  await ui.unmount()
})

test('the summary counts a session that stopped responding apart from those working', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: [tab('flight', 'st-1', 'billing:task-7', 'tmux', 'stuck')] }).replace(/^waiting\t.*$/m, 'waiting\t0') })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = (await rows(ui)).join(' ')
  expect(t).toContain('2 sessions are working, 1 is not responding. Nothing needs you right now.')
  await ui.unmount()
})

test('the Right now readout names the pull requests to merge as well as the questions', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['merge-ready\t1\tall', tab('merge-command', 'acme/widgets', 908, 'checked-merge-908')] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await rows(ui)).toContain('Waiting on you 2 questions, 1 to merge · ACT')
  await ui.unmount()
})
