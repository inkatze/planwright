import { expect, test } from 'claude-code/testing'

import { BAND, bandOf, boot, digestText, PANE, ran, world } from './fixture'

const SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const

// REQ-F1.1, REQ-L1.4, REQ-H1.4, REQ-M1.8
test('the pane draws every store from the fixture digest, on every surface', async ($, on) => {
  const w = world(on)
  await boot($, w)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    const has = async (text: RegExp) => expect((await ui.find({ type: 'Text', text }))?.text).toMatch(text)
    await has(/Mission control · alpha/)
    await has(/In flight \(2\)/)
    await has(/^spec task · working$/)
    await has(/^one-off change · working$/)
    await has(/2 waiting on you/)
    await has(/^Context 42% · compacts at 95% · OK$/)
    await ui.unmount()
  }
})

// REQ-L1.8 register: the in-flight section carries no session handle,
// spec, task, script or hash identifier, and each session has its own row.
test('sessions in flight are said in plain words, one row each', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: [
        'flight\tmc-alpha-worker-92e2ac1dd8\tflight-panel-fix\tstream-json-persistent\tworking',
        'flight\tre-11-1\treview-effectiveness:task-11.1\tstream-json-persistent\tstuck',
        'flight\tkl-3\tkickoff-lifecycle:3\tstream-json-persistent\tworking',
        'flight\tfl-k\tflight:spec-kickoff-lens-fix\tstream-json-persistent\tworking',
        'flight\tsd-k\tspec-draft-amend-kickoff-lifecycle\tstream-json-persistent\twaiting',
        'flight\tprose-task-5\tprose:task-5\tstream-json-persistent\twaiting',
        'flight\tub-task-7\tuniversal-binary:task-7\tstream-json-persistent\tworking',
        'flight\tkickoff-ub\tuniversal-binary:kickoff\tstream-json-persistent\tworking',
        'flight\tmc-alpha-ad-hoc-3d062aa6a5\tspec-draft-mc-panel\tstream-json-persistent\twaiting',
        'flight\t@7\toffload\ttmux\tworking',
        'flight\tcop486\ttower-comms-task-8\tstream-json-persistent\tworking',
        'flight\tcb-848\tcubic-pr-848\tstream-json-persistent\tworking',
        'flight\tpw-mission-control-a1b2c3\tgen-2\ttmux\tworking',
      ],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text ?? '')
  const at = texts.indexOf('In flight (15)')
  expect(at).toBeGreaterThan(-1)
  // Waiting on an answer first, then not responding, one row each.
  expect(texts.slice(at + 1, at + 16)).toEqual([
    'spec draft · waiting for an answer',
    'spec task · waiting for an answer',
    'spec draft · waiting for an answer',
    'spec task · not responding',
    'spec task · working',
    'one-off change · working',
    'one-off change · working',
    'spec task · working',
    'one-off change · working',
    'spec task · working',
    'spec kickoff · working',
    'other session · working',
    'spec task · working',
    'review · working',
    'mission-control session · working',
  ])
  const ids = /92e2ac1dd8|3d062aa6a5|@7|cop486|a1b2c3|cubic|gen-2|task-\d|:kickoff|stream-json|\.sh\b/
  expect(texts.slice(at, at + 16).filter(t => ids.test(t))).toEqual([])
  await ui.unmount()
})

test('with tmux unreadable the in-flight count is a floor, never exact', async ($, on) => {
  const w = world(on, {
    digest: digestText({ extra: ['unreadable\ttmux windows'] }).replace(/^flight\t.*\n/gm, ''),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^In flight \(0\+\)$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Nothing in flight/ })).toBeUndefined()
  await ui.unmount()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await bandOf(band))).toMatch(/^\? 2 waiting on you/)
  await band.unmount()
})

test('with the attention store unreadable the in-flight count is a ceiling', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['unreadable\tattention store'] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^In flight \(up to 2\)$/ })).toBeDefined()
  await ui.unmount()
})

test('with tmux and the attention store both unreadable the in-flight count is unknown', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['unreadable\ttmux windows', 'unreadable\tattention store'] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^In flight \(\?\)$/ })).toBeDefined()
  await ui.unmount()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await bandOf(band))).toMatch(/^\? 2 waiting on you/)
  await band.unmount()
})

// REQ-F1.1: the stores change and the timer redraws with no turn.
test('the pane redraws from the stores on the timer, without a turn', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  w.set({ digest: digestText().replace(/^flight\tw-two.*\n/m, '') })
  await w.clock.advance(10_000)
  expect((await ui.find({ type: 'Text', text: /In flight/ }))?.text).toBe('In flight (1)')
  expect(w.submitted).toEqual([])
  await ui.unmount()
})

test('the knobs set the redraw and tick cadences', async ($, on) => {
  const w = world(on, { digest: digestText({ refresh: 3, tick: 60 }) })
  await boot($, w)
  const digests = () => ran(w, 'mc-panel.sh', 'digest').length
  const first = digests()
  await w.clock.advance(3_000)
  expect(digests()).toBe(first + 1)
  expect(ran(w, 'mc-wake.sh', 'compose')).toEqual([])
  await w.clock.advance(57_000)
  expect(ran(w, 'mc-wake.sh', 'compose')).toHaveLength(1)
  expect(ran(w, 'mc-panel.sh', 'digest')[0]).toContain('--knobs')
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).not.toContain('--knobs')
})

test('the band draws the summary line above the prompt', async ($, on) => {
  const w = world(on)
  await boot($, w)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect(await bandOf(ui)).toBe('? 2 waiting on you · 5-hour 31% · context 42%')
    await ui.unmount()
  }
})

test('pull requests ready to merge are held for the operator, in the pane and the band', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['merge-ready\t3\tall'] }) })
  await boot($, w)
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ type: 'Text', text: /ready to merge/ }))?.text).toBe('3 ready to merge')
  await pane.unmount()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await bandOf(band))).toBe(
    '? 2 waiting on you · 3 ready to merge · 5-hour 31% · context 42%',
  )
  await band.unmount()
})

test('pull requests that could not all be judged read as a floor, or unknown', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['merge-ready\t2\tpartial'] }) })
  await boot($, w)
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ type: 'Text', text: /ready to merge/ }))?.text).toBe('2+ ready to merge')
  await pane.unmount()
})

test('with none judged ready and some unknown, the band says unknown', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['merge-ready\t0\tpartial'] }) })
  await boot($, w)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await bandOf(band))).toContain('? ready to merge')
  await band.unmount()
})

test('a merge-ready store that cannot be read is unknown, never hidden', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['unreadable\tmerge-ready store'] }) })
  await boot($, w)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await bandOf(band))).toContain('? ready to merge')
  await band.unmount()
})

// The health line: shown only when a check is out of bounds, an unknown one
// said as such.
test('the health section draws each check out of bounds, and nothing when all is well', async ($, on) => {
  const w = world(on, {
    digest: digestText({
      extra: [
        'health\tworker-age\t3\tw-old\t3 workers live past 4h (oldest w-old, 6h)',
        'health\tci-queue\t?\t-\tCI queue times unknown (the throughput measure is 3h old)',
        'health\tcontext\t1\tbeta\t1 mission control at or past the handover context (beta 75% of 70%)',
        'health\tcontext\t?\t-\tcontext unknown for gamma (no fresh reading from a live session)',
      ],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^Health$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^3 workers live past 4h \(oldest w-old, 6h\)$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^CI queue times unknown/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^1 mission control at or past the handover context \(beta 75% of 70%\)$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^context unknown for gamma/ })).toBeDefined()
  await ui.unmount()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  // Checks, not records: the context check said two things.
  expect((await bandOf(band))).toContain('⚠ 3 health checks')
  await band.unmount()
  w.set({ digest: digestText() })
  await w.clock.advance(10_000)
  const well = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await well.find({ type: 'Text', text: /^Health$/ })).toBeUndefined()
  await well.unmount()
  const quiet = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await bandOf(quiet))).not.toContain('health')
  await quiet.unmount()
})

test('the band leaves a survey alone', async ($, on) => {
  const w = world(on)
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal', props: { ...BAND.props, hasSurvey: true } })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
})

// Registry rows whose session is gone are not in flight.
test('sessions that finished but were not cleaned up are a separate count', async ($, on) => {
  const w = world(on, { digest: digestText({ finished: 352 }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: /finished/ }))?.text).toBe('352 finished, not cleaned up')
  await ui.unmount()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await bandOf(band))).toMatch(/^\? 2 waiting on you/)
  await band.unmount()
})

test('with none finished the count is not drawn', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /finished/ })).toBeUndefined()
  await ui.unmount()
})

test('a store the digest could not read is said, its count unknown', async ($, on) => {
  const w = world(on, {
    digest: digestText({ extra: ['unreadable\toperator queue', 'unreadable\tfleet registry', 'unreadable\tknowledge base'] }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Unreadable/ }))?.text).toBe(
    'Unreadable: operator queue, fleet registry, knowledge base',
  )
  expect(await ui.find({ type: 'Text', text: /In flight \(\?\)/ })).toBeDefined()
  await ui.unmount()
})

test('a failed digest keeps the last reading and names the fault', async ($, on) => {
  const w = world(on)
  await boot($, w)
  w.set({ digestExit: 1 })
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toBe(
    'Fault: store unreadable',
  )
  expect(await ui.find({ type: 'Text', text: /In flight \(2\)/ })).toBeDefined()
  await ui.unmount()
})

// The engine refuses a command whose name collides with one the plugin
// already ships; the start hook must still bring the readings up.
test('a refused command registration still brings the readings up', async ($, on) => {
  const w = world(on, { isCommandRefused: true })
  await boot($, w)
  const first = ran(w, 'mc-panel.sh', 'digest').length
  expect(first).toBeGreaterThan(0)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await bandOf(band))).toBe(
    '? 2 waiting on you · fault: the panel command could not be registered: HooksError: no implementation for command.register · 5-hour 31% · context 42%',
  )
  await band.unmount()
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pane.find({ type: 'Text', text: /^Fault:/ }))?.text).toMatch(
    /^Fault: the panel command could not be registered: /,
  )
  await pane.unmount()
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'digest').length).toBeGreaterThan(first)
})

test('with no reading the band says why', async ($, on) => {
  const w = world(on, { digestExit: 1 })
  await boot($, w)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await bandOf(ui))).toBe(
    'no reading: store unreadable · 5-hour 31% · context 42%',
  )
  await ui.unmount()
})

// REQ-F1.2: where no surface places the pane, the text line carries it.
test('the fallback line shows where nothing draws the pane', async ($, on) => {
  const w = world(on, { isPlaced: false })
  await boot($, w)
  const line = w.statuses.filter((s): s is string => typeof s === 'string').at(-1)
  expect(line).toBe('? 2 waiting on you · 5-hour 31% · context 42%')
  await w.clock.advance(10_000)
  expect(w.statuses.at(-1)).toBe(line)
})

test('a placed pane clears the fallback line', async ($, on) => {
  const w = world(on)
  await boot($, w)
  expect(w.statuses).toEqual([undefined])
})

const mcPanel = ($: Parameters<Parameters<typeof test>[1]>[0], args: string) =>
  $.command.run({ command: 'mc-panel', args, origin: { kind: 'composer' } } as never).then(o => JSON.stringify(o))

test('the slash command toggles the pane: closes it when open, opens it when closed', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const opened = w.opened
  expect(await mcPanel($, '')).toContain('Mission control panel closed.')
  expect(w.closed).toBe(1)
  expect(w.opened).toBe(opened)
  expect(await mcPanel($, '')).toContain('Mission control panel opened.')
  expect(w.opened).toBe(opened + 1)
  expect(w.closed).toBe(1)
})

test('the slash command takes open or close to choose', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const opened = w.opened
  expect(await mcPanel($, 'open')).toContain('Mission control panel opened.')
  expect(w.closed).toBe(0)
  expect(await mcPanel($, ' close ')).toContain('Mission control panel closed.')
  expect(await mcPanel($, 'close')).toContain('Mission control panel closed.')
  expect(w.closed).toBe(1)
  expect(w.opened).toBe(opened + 1)
  expect(await mcPanel($, 'sideways')).toContain('/mc-panel open')
  expect(w.opened).toBe(opened + 1)
})

// A pane opened unasked on a narrow terminal is listed but not drawn.
test('the slash command opens a pane that is listed but not drawn', async ($, on) => {
  const w = world(on, { isPlaced: false })
  await boot($, w)
  const opened = w.opened
  expect(await mcPanel($, '')).toContain('Mission control panel opened.')
  expect(w.closed).toBe(0)
  expect(w.opened).toBe(opened + 1)
})

test('closing the pane drops its text-line fallback', async ($, on) => {
  const w = world(on, { isPlaced: false })
  await boot($, w)
  expect(await mcPanel($, 'close')).toContain('Mission control panel closed.')
  expect(w.statuses.at(-1)).toBeUndefined()
  await w.clock.advance(10_000)
  expect(w.statuses.at(-1)).toBeUndefined()
})

test("the command's description says it opens and closes the panel", async ($, on) => {
  const w = world(on)
  await boot($, w)
  expect(w.commands).toEqual([{ name: 'mc-panel', description: expect.stringMatching(/open or close/i) }])
})

test('the mod stays inert in a session that is not mission control', async ($, on) => {
  const w = world(on, { env: {} })
  // Stands for the engine's own band.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await boot($, w)
  await w.clock.advance(60_000)
  // Only where activation records live, read once to watch for its own.
  expect(w.runs.map(r => r[2])).toEqual(['where'])
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
})

// A session this one starts must not inherit the activation and take its wakes.
test('the activation variables are read once and cleared', async ($, on) => {
  const w = world(on, { env: { PLANWRIGHT_MC_PROGRAM: 'alpha', PLANWRIGHT_MC_TARGET: 'mc-main' } })
  await boot($, w)
  expect(w.envWrites).toEqual([
    ['PLANWRIGHT_MC_PROGRAM', undefined],
    ['PLANWRIGHT_MC_TARGET', undefined],
  ])
  expect(ran(w, 'mc-wake.sh', 'target')[0]).toEqual(expect.arrayContaining(['alpha', 'mc-main', '--mod']))
  expect(ran(w, 'mc-panel.sh', 'digest')[0]).toEqual(expect.arrayContaining(['--target', 'mc-main']))
})

test('a target outside the handle grammar falls back to the program', async ($, on) => {
  const w = world(on, { env: { PLANWRIGHT_MC_PROGRAM: 'alpha', PLANWRIGHT_MC_TARGET: 'bad;target' } })
  await boot($, w)
  expect(ran(w, 'mc-wake.sh', 'target')[0]).toEqual(expect.arrayContaining(['alpha', '--mod']))
  expect(ran(w, 'mc-wake.sh', 'target')[0]).not.toContain('bad;target')
})

test('a refused clear of the activation stays on the pane', async ($, on) => {
  const w = world(on, { isEnvDenied: true })
  await boot($, w)
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toBe(
    'Fault: the activation could not be cleared: sessions started from here inherit it',
  )
  await ui.unmount()
})

test('knobs that arrive after a failed first reading set the cadences then', async ($, on) => {
  const w = world(on, { digestExit: 1, digest: digestText({ refresh: 3, tick: 60 }) })
  await boot($, w)
  await w.clock.advance(10_000)
  w.set({ digestExit: 0 })
  await w.clock.advance(10_000)
  const after = ran(w, 'mc-panel.sh', 'digest').length
  await w.clock.advance(3_000)
  expect(ran(w, 'mc-panel.sh', 'digest').length).toBe(after + 1)
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).not.toContain('--knobs')
})

test('a lasting fault clearing leaves a failing reading on the pane', async ($, on) => {
  const w = world(on, { claimExit: 1 })
  await boot($, w)
  w.set({ digestExit: 1, claimExit: 0 })
  await w.clock.advance(10_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toBe('Fault: store unreadable')
  await ui.unmount()
})

test('a knob unread at bring-up is read again until every knob arrives', async ($, on) => {
  const partial = digestText({ holder: 'registry' }).replace(/^knob\thandover-context.*$/m, 'unreadable\tknob mission_control_handover_context')
  const w = world(on, { digest: partial })
  await boot($, w)
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).toContain('--knobs')
  w.set({ digest: digestText({ holder: 'registry' }), contextPercent: 75 })
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-event.sh', 'emit').at(-1)?.slice(-3)).toEqual(['handover-due', 'alpha', 'context at 75%'])
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'digest').at(-1)).not.toContain('--knobs')
})

test('approvals mission control is handling are not drawn: the operator acts on none', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['approvals\t4'] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /approval/ })).toBeUndefined()
  await ui.unmount()
})

const rows = async (ui: { findAll: (q: { type: string }) => Promise<{ text?: string }[]> }) =>
  (await ui.findAll({ type: 'Text' })).map(t => t.text ?? '')

const readoutsAt = async ($: Parameters<typeof boot>[0], on: Parameters<typeof world>[0], given: Parameters<typeof world>[1], surface: (typeof SURFACES)[number] = 'terminal') => {
  const w = world(on, given)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface })
  const t = await rows(ui)
  await ui.unmount()
  return t
}

test('the readouts say each measure as a name, a value and a verdict', async ($, on) => {
  const texts = await readoutsAt($, on, {})
  expect(texts).toContain('5-hour usage 31% · stop unknown · UNKNOWN')
  expect(texts).toContain('Context 42% · compacts at 95% · OK')
  expect(texts).toContain('Machine load 1.5/4, mem 62% · OK')
  expect(texts).toContain('Waiting on you 2 · ACT')
})

test('host load past the core count and memory under a tenth are ACT', async ($, on) => {
  const texts = await readoutsAt($, on, { digest: digestText().replace(/^host\t.*$/m, 'host\t520\t4\t6') })
  expect(texts).toContain('Machine load 5.2/4, mem 6% · ACT')
})

test('a host reading that is missing is unknown, never zero', async ($, on) => {
  const texts = await readoutsAt($, on, { digest: digestText().replace(/^host\t.*$/m, 'host\t-\t-\t-') })
  expect(texts).toContain('Machine load unknown, mem unknown · UNKNOWN')
})

const registry = digestText({ holder: 'registry' })
const CASES: [string, Parameters<typeof world>[1], string][] = [
  ['context under the hand-over point is OK and says where it hands over', { digest: registry }, 'Context 42% · hand over 70% · compacts at 95% · OK'],
  ['context at the hand-over point is ACT', { digest: registry, contextPercent: 75 }, 'Context 75% · hand over 70% · compacts at 95% · ACT'],
  ['nothing waiting is OK', { digest: digestText().replace(/^waiting\t.*$/m, 'waiting\t0') }, 'Waiting on you none · OK'],
  ['an unread queue is unknown', { digest: digestText().replace(/^waiting\t.*$/m, 'waiting\t-') }, 'Waiting on you unknown · UNKNOWN'],
  ['a usage stop is the value admission reads', { digest: digestText({ extra: ['knob\tusage-hold\t90'] }) }, '5-hour usage 31% · stop at 90% · OK'],
  ['a usage stop that is off says so', { digest: digestText({ extra: ['knob\tusage-hold\t0'] }) }, '5-hour usage 31% · no stop set · OK'],
  ['usage at the stop is ACT', { digest: digestText({ extra: ['knob\tusage-hold\t30'] }) }, '5-hour usage 31% · stop at 30% · ACT'],
]
for (const [name, given, line] of CASES) {
  test(`readout: ${name}`, async ($, on) => {
    expect(await readoutsAt($, on, given)).toContain(line)
  })
}

const mascot = async (ui: Parameters<typeof rows>[0]) => (await rows(ui)).filter(t => t.includes('Prop pal') || /\[__\]/.test(t) || /\(.* .*\)/.test(t))
const withKnob = (n: number) => digestText({ extra: [`knob\tmascot\t${n}`] })

test('Prop pal circles while something waits on the operator', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const t = await mascot(ui)
  expect(t).toContain('Prop pal: circling, something waits on you')
  expect(t.some(l => l.includes('(o o)'))).toBe(true)
  await ui.unmount()
})

test('Prop pal flies while sessions work and nothing waits', async ($, on) => {
  const w = world(on, { digest: digestText().replace(/^waiting\t.*$/m, 'waiting\t0') })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await mascot(ui)).toContain('Prop pal: flying, sessions working')
  await ui.unmount()
})

test('Prop pal taxis when nothing runs and lands when work has finished', async ($, on) => {
  const idle = digestText({ finished: 0 }).replace(/^flight\t.*\n/gm, '').replace(/^waiting\t.*$/m, 'waiting\t0')
  const w = world(on, { digest: idle })
  await boot($, w)
  let ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await mascot(ui)).toContain('Prop pal: taxiing, nothing running')
  await ui.unmount()
  w.set({ digest: idle.replace(/^finished\t.*$/m, 'finished\t3') })
  await w.clock.advance(10_000)
  ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await mascot(ui)).toContain('Prop pal: landing, work finished')
  await ui.unmount()
})

test('an alert makes the ride bumpy, ahead of everything else', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['unreadable\tfleet registry'] }) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const t = await mascot(ui)
  expect(t).toContain('Prop pal: a bumpy ride, an alert stands')
  expect(t.some(l => l.includes('(O O)'))).toBe(true)
  await ui.unmount()
})

test('the mascot knob: still draws one frame', async ($, on) => {
  const w = world(on, { digest: withKnob(1) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const before = await mascot(ui)
  expect(before.some(l => l.startsWith('Prop pal'))).toBe(true)
  await w.clock.advance(3_000)
  expect(await mascot(ui)).toEqual(before)
  await ui.unmount()
})

test('the mascot knob: off draws nothing', async ($, on) => {
  const w = world(on, { digest: withKnob(0) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const texts = await rows(ui)
  expect(texts.some(t => t.startsWith('Machine load'))).toBe(true)
  expect(texts.some(l => l.includes('Prop pal') || /\[__\]/.test(l))).toBe(false)
  await ui.unmount()
})

// The approved high-fidelity render: pictures where the surface has them.
const pictures = async (ui: { findAll: (q: { type: string }) => Promise<{ props?: Record<string, unknown> }[]> }, type: string) =>
  (await ui.findAll({ type })).map(n => n.props ?? {})

test('the terminal pane draws Prop pal as a cell grid with no caption and no picture repeating the readouts', async ($, on) => {
  const w = world(on)
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await pictures(ui, 'Raster')).map(r => r.key)).toEqual(['prop-pal'])
  expect(await pictures(ui, 'Image')).toEqual([])
  expect((await rows(ui)).some(l => l.includes('Prop pal'))).toBe(false)
  await ui.unmount()
})

test('a surface without pictures draws none, and the readouts stay', async ($, on) => {
  const w = world(on)
  await boot($, w)
  for (const surface of ['desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await pictures(ui, 'Raster')).toEqual([])
    expect(await pictures(ui, 'Image')).toEqual([])
    expect(await rows(ui)).toContain('Waiting on you 2 · ACT')
    await ui.unmount()
  }
})

// The panel flickered when the mascot's frame was state: every frame redrew the
// whole pane. A frame is now a blit of the Raster alone.
test('Prop pal animates by blit, never by redrawing the pane', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['flight\tw-three\tflight-x\ttmux\tworking'] }).replace(/^waiting\t.*$/m, 'waiting\t0') })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const before = await rows(ui)
  const cells = (await pictures(ui, 'Raster'))[0]?.cells
  await w.clock.advance(1_000)
  expect(w.blits.length).toBeGreaterThanOrEqual(2)
  expect(w.blits.every(b => b.key === 'prop-pal')).toBe(true)
  expect(new Set(w.blits.map(b => b.cells)).size).toBeGreaterThan(1)
  expect((await pictures(ui, 'Raster'))[0]?.cells).toBe(cells)
  expect(await rows(ui)).toEqual(before)
  await ui.unmount()
})

test('a still mascot blits nothing', async ($, on) => {
  const w = world(on, { digest: withKnob(1) })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await w.clock.advance(2_000)
  expect(w.blits).toEqual([])
  await ui.unmount()
})

test('a pane that is not the terminal blits nothing, its text mascot moving by redraw', async ($, on) => {
  const w = world(on, { digest: digestText({ extra: ['flight\tw-three\tflight-x\ttmux\tworking'] }).replace(/^waiting\t.*$/m, 'waiting\t0') })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await w.clock.advance(2_000)
  expect(w.blits).toEqual([])
  await ui.unmount()
})

test('the mascot knob keeps its meaning with pictures: off draws no grid, still holds one frame', async ($, on) => {
  const off = world(on, { digest: withKnob(0) })
  await boot($, off)
  let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await pictures(ui, 'Raster')).toEqual([])
  await ui.unmount()
  off.set({ digest: withKnob(1) })
  await off.clock.advance(10_000)
  ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const before = (await pictures(ui, 'Raster'))[0]?.cells
  await off.clock.advance(3_000)
  expect((await pictures(ui, 'Raster'))[0]?.cells).toBe(before)
  await ui.unmount()
})
