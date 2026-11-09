import { expect, test } from 'claude-code/testing'

import { bandOf, BAND, boot, digestText, PANE, world } from './fixture'
import { spriteCells } from './panel-art'

const tab = (...f: (string | number)[]) => f.join('\t')
const SHA = '0123456789abcdef0123456789abcdef01234567'
const CMD = `gh pr merge 1 --repo acme/widgets --squash --match-head-commit ${SHA}`

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
  tab('merge-command', 'acme/widgets', 1, CMD),
]

const rows = async (ui: { findAll: (q: { type: string }) => Promise<{ text?: string }[]> }) =>
  (await ui.findAll({ type: 'Text' })).map(t => t.text ?? '')

test('pull requests are listed by title, grouped by where they stand against the ready conditions', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: PRS }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  const at = (re: RegExp) => t.findIndex(l => re.test(l))
  const order = [/^Ready to merge$/, /^Needs you$/, /^In review$/, /^CI running$/, /^CI failed$/].map(at)
  expect(order.every(i => i > -1)).toBe(true)
  expect([...order].sort((a, b) => a - b)).toEqual(order)
  expect(t).toContain('#1 Ship the widget')
  expect(t).toContain(`run: ${CMD}`)
  expect(t).toContain('#2 Draft the gadget · a draft waiting for your yes')
  expect(t).toContain('#3 Rework the docs · 2 review threads still open')
  expect(t).toContain('#4 Tune the cache · CI still running')
  expect(t).toContain('#5 Break the build · CI failed')
  expect(t).toContain('#6 Fresh branch · head not reviewed yet')
  expect(at(/^#1 /)).toBeLessThan(at(/^#2 /))
  expect(at(/^#2 /)).toBeLessThan(at(/^#3 /))
  expect(at(/^#3 /)).toBeLessThan(at(/^#4 /))
  expect(at(/^#4 /)).toBeLessThan(at(/^#5 /))
  await ui.unmount()
})

test('a group with no pull request is not drawn', async ($, on) => {
  const w = world(on, {
    digest: digestText({ extra: [tab('reviews', 'ok', 5), tab('review-mine', 'acme/widgets', 9, 'draft', 'red', 0, 'no', '-', 'Only one')] }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const t = await rows(ui)
  expect(t).toContain('CI failed')
  expect(t.some(l => /^(Ready to merge|Needs you|In review|CI running)$/.test(l))).toBe(false)
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
  expect(t).toContain('spec draft · waiting for an answer')
  expect(t).toContain('spec kickoff · waiting for an answer')
  expect(t.filter(l => /waiting for an answer/.test(l))).toHaveLength(4)
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
  expect(t.filter(l => l === 'spec task · working')).toHaveLength(2)
  expect(t).toContain('one-off change · working')
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
  expect(t).toContain('#1 Went red · CI failed')
  expect(t).toContain('#2 New thread · 1 review thread still open')
  expect(t).not.toContain('Ready to merge')
  await ui.unmount()
})

test('with readiness not judged, a pull request is not told to wait for the operator', async ($, on) => {
  const w = world(on, {
    digest: digestText({ extra: [tab('reviews', 'ok', 60), tab('review-mine', 'acme/widgets', 3, 'draft', 'green', 0, 'yes', '-', 'Unjudged'), 'unreadable\tmerge-ready store'] }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await rows(ui)).toContain('#3 Unjudged · readiness not judged yet')
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
