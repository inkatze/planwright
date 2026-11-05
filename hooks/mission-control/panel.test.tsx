import { expect, test } from 'claude-code/testing'

import { BAND, boot, digestText, PANE, ran, world } from './fixture'

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
    await has(/^1 spec task working$/)
    await has(/^1 one-off change working$/)
    await has(/2 waiting on you/)
    await has(/relaunch w-one: relaunch/)
    await has(/Fuel · rung throttle/)
    await has(/tightest: polls_per_hour 72%/)
    await has(/^inbox stopped, next 40s overdue \(×2\)$/)
    await has(/code-state: forge snapshot, 90s old/)
    await has(/designs: none cited/)
    await has(/context 42% · five_hour 31%/)
    await has(/compactions since start 0/)
    await has(/knowledge base 10m old/)
    await has(/interruptions per hour 2\.5/)
    await has(/settled share 80/)
    await ui.unmount()
  }
})

// REQ-L1.8 register: the in-flight section carries no session handle,
// spec, task, script or hash identifier, and repeats collapse into counts.
test('sessions in flight are said in plain words, grouped into counts', async ($, on) => {
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
      ],
    }),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text ?? '')
  const at = texts.indexOf('In flight (13)')
  expect(at).toBeGreaterThan(-1)
  // Waiting on an answer first, then not responding, each by group size.
  expect(texts.slice(at + 1, at + 9)).toEqual([
    '2 spec drafts waiting for an answer',
    '1 spec task waiting for an answer',
    '1 spec task not responding',
    '4 spec tasks working',
    '3 one-off changes working',
    '1 spec kickoff working',
    '1 other session working',
    'Holding for you',
  ])
  const ids = /92e2ac1dd8|3d062aa6a5|@7|cop486|task-\d|:kickoff|stream-json|\.sh\b/
  expect(texts.slice(at, at + 8).filter(t => ids.test(t))).toEqual([])
  await ui.unmount()
})

// REQ-F1.1: the stores change and the timer redraws with no turn.
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
  expect((await band.find({ type: 'Text', text: /✈ alpha/ }))?.text).toMatch(/^✈ alpha · 0\+ in flight · /)
  await band.unmount()
})

test('repeated background checks collapse before the list is cut', async ($, on) => {
  const watch = (script: string, duty: string) => `watcher\t${duty}\t${script}\trunning\t30`
  const w = world(on, {
    digest: digestText({
      extra: ['a.sh', 'b.sh', 'c.sh', 'd.sh'].map(s => watch(s, 'reviews')).concat(watch('e.sh', 'deadline-watch')),
    }).replace(/^watcher\tinbox.*\n/gm, ''),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^reviews running, next 30s \(×4\)$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^deadline watch running, next 30s$/ })).toBeDefined()
  await ui.unmount()
})

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
    const band = await ui.find({ type: 'Text', text: /✈ alpha/ })
    expect(band?.text).toBe('✈ alpha · 2 in flight · 2 holding · rung throttle · ctx 42% · five_hour 31%')
    await ui.unmount()
  }
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
  expect((await band.find({ type: 'Text', text: /✈ alpha/ }))?.text).toMatch(/^✈ alpha · 2 in flight · /)
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
  expect(await ui.find({ type: 'Text', text: /knowledge base unreadable/ })).toBeDefined()
  await ui.unmount()
})

test('measures not yet written are said as such', async ($, on) => {
  const w = world(on, {
    digest: digestText().replace(/^measure.*\n/gm, '').replace('handover\tabsent', 'measure\t-\tnone\t-\nhandover\tabsent'),
  })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^measures none$/ })).toBeDefined()
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
  expect((await band.find({ type: 'Text', text: /✈ alpha/ }))?.text).toBe(
    '✈ alpha · 2 in flight · 2 holding · rung throttle · ctx 42% · five_hour 31%',
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
  expect((await ui.find({ type: 'Text', text: /✈ alpha/ }))?.text).toBe(
    '✈ alpha · no reading: store unreadable · ctx 42% · five_hour 31%',
  )
  await ui.unmount()
})

// REQ-F1.2: where no surface places the pane, the text line carries it.
test('the fallback line shows where nothing draws the pane', async ($, on) => {
  const w = world(on, { isPlaced: false })
  await boot($, w)
  const line = w.statuses.filter((s): s is string => typeof s === 'string').at(-1)
  expect(line).toBe('mission control alpha: 2 in flight, 2 waiting, 0 pending, rung throttle, context 42%')
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
  expect(w.runs).toEqual([])
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
