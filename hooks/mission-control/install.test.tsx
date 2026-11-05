import { expect, test } from 'claude-code/testing'

import { boot, digestText, PANE, ran, WAKE, world } from './fixture'

const tab = (...f: string[]) => f.join('\t')
const ROOT_66 = '/plugins/cache/planwright/planwright/0.66.0'

// A session that outlives an upgrade must learn of it: the copy it runs is
// checked against the program's record at every start and reload.
test('every start and reload checks the planwright copy against the record', async ($, on) => {
  const w = world(on)
  await boot($, w)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(1)
  expect(ran(w, 'mc-panel.sh', 'install')[0]?.slice(3)).toEqual(['--program', 'alpha'])
  await boot($, w)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(2)
})

test('an update is toasted and its event wakes the session', async ($, on) => {
  const w = world(on, {
    install: tab('install', 'changed', '0.66.0', ROOT_66, '0.65.0'),
    digest: digestText({ pending: 1 }),
    wake: WAKE,
  })
  await boot($, w)
  expect(w.toasts).toContain('Mission control: planwright is now 0.66.0 (was 0.65.0)')
  // The check runs before the first reading, so that reading counts its event.
  const order = w.runs.map(r => `${(r[1] ?? '').split('/').pop()} ${r[2]}`)
  expect(order.indexOf('mc-panel.sh install')).toBeLessThan(order.indexOf('mc-panel.sh digest'))
  expect(w.submitted).toHaveLength(1)
})

test('the same copy toasts nothing', async ($, on) => {
  const w = world(on)
  await boot($, w)
  expect(w.toasts.filter(t => /planwright is now/.test(t))).toEqual([])
})

test('a failed check names the fault and is tried again until it lands', async ($, on) => {
  const w = world(on, { installExit: 1 })
  await boot($, w)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Fault:/ }))?.text).toMatch(/planwright version could not be checked/)
  await ui.unmount()
  w.set({ installExit: 0 })
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(2)
  await w.clock.advance(10_000)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(2)
  const after = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await after.find({ type: 'Text', text: /^Fault:/ })).toBeUndefined()
  await after.unmount()
})

// After a compaction the session has lost the root it resolved; the
// re-injected rules carry the copy the mod runs.
test('the re-injected rules name the planwright copy the session runs', async ($, on) => {
  const w = world(on, { install: tab('install', 'same', '0.66.0', ROOT_66) })
  await boot($, w)
  const out = await $.session.compact({
    trigger: 'auto',
    messages: [{ role: 'user', text: 'summary', toolUses: [] }],
  })
  if (out.skip !== undefined) throw new Error(`skipped: ${out.skip}`)
  expect(out.messages.at(-1)?.text).toContain(`Planwright 0.66.0 runs from ${ROOT_66}`)
})
