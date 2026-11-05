import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import { boot, PANE, ran, world } from './fixture'

const tab = (...f: string[]) => f.join('\t')
const ROOT_66 = '/plugins/cache/planwright/planwright/0.66.0'
const toasted = (toasts: string[]) => toasts.filter(t => /planwright/.test(t))

const faultOf = async ($: Engine) => {
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = (await ui.find({ type: 'Text', text: /^Fault:/ }))?.text
  await ui.unmount()
  return text
}

// A session that outlives an upgrade must learn of it: the copy it runs is
// checked against the program's record at every start and reload.
test('every start and reload checks the planwright copy against the record', async ($, on) => {
  const w = world(on)
  await boot($, w)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(1)
  expect(ran(w, 'mc-panel.sh', 'install')[0]?.slice(3)).toEqual(['--program', 'alpha'])
  await w.clock.advance(60_000)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(1)
  await boot($, w)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(2)
})

test('an update is toasted, checked before the first reading so it counts the event', async ($, on) => {
  const w = world(on, { install: tab('install', 'changed', '0.66.0', ROOT_66, '0.65.0') })
  await boot($, w)
  expect(toasted(w.toasts)).toEqual(['Mission control: planwright is now 0.66.0 (was 0.65.0)'])
  const order = w.runs.map(r => `${(r[1] ?? '').split('/').pop()} ${r[2]}`)
  expect(order.indexOf('mc-panel.sh install')).toBeLessThan(order.indexOf('mc-panel.sh digest'))
})

test('a copy moved at one version is toasted as a move', async ($, on) => {
  const w = world(on, { install: tab('install', 'changed', '0.66.0', ROOT_66, '0.66.0') })
  await boot($, w)
  expect(toasted(w.toasts)).toEqual([`Mission control: planwright 0.66.0 moved to ${ROOT_66}`])
})

test('the same copy, or a first record, toasts nothing', async ($, on) => {
  const same = world(on)
  await boot($, same)
  expect(toasted(same.toasts)).toEqual([])
  same.set({ install: tab('install', 'first', '0.66.0', ROOT_66) })
  await boot($, same)
  expect(toasted(same.toasts)).toEqual([])
})

test('a malformed answer is a fault, never a reading', async ($, on) => {
  const w = world(on)
  for (const bad of [
    tab('installed', 'same', '0.66.0', ROOT_66),
    tab('install', 'changed', '0.66.0', ROOT_66),
    tab('install', 'same', '0.66.0', 'relative/root'),
    tab('install', 'same', '0.66', ROOT_66),
    tab('install', 'changed', '0.66.0', ROOT_66, 'x'),
    tab('install', 'odd', '0.66.0', ROOT_66),
    tab('install', 'same', '0.66.0', `${ROOT_66}\u001b[2J`),
    tab('install', 'same', '0.66.0', ROOT_66, '0.65.0'),
    tab('install', 'changed', '0.66.0', ROOT_66, '0.65.0', 'extra'),
  ]) {
    w.set({ install: bad })
    await boot($, w)
    expect(await faultOf($)).toMatch(/planwright version could not be checked: unreadable answer/)
    expect(toasted(w.toasts)).toEqual([])
  }
})

test('a failed check names the fault and is tried again a minute later, until it lands', async ($, on) => {
  const w = world(on, { installExit: 1 })
  await boot($, w)
  expect(await faultOf($)).toMatch(/planwright version could not be checked: store unreadable/)
  w.set({ installExit: 0 })
  await w.clock.advance(30_000)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(1)
  await w.clock.advance(30_000)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(2)
  await w.clock.advance(120_000)
  expect(ran(w, 'mc-panel.sh', 'install')).toHaveLength(2)
  expect(await faultOf($)).toBeUndefined()
})

test("a stale copy's warning never stands in for a script's own error", async ($, on) => {
  const w = world(on, {
    installExit: 1,
    stderrLead: 'planwright: WARNING running from /old, which is not the installed planwright (/new)\n',
  })
  await boot($, w)
  expect(await faultOf($)).toMatch(/could not be checked: store unreadable/)
})

// After a compaction the session has lost the root it resolved; the
// re-injected rules send it back to the installed record.
test('the re-injected rules name the copy the panel runs and ask for the root again', async ($, on) => {
  const compact = { trigger: 'auto' as const, messages: [{ role: 'user' as const, text: 'summary', toolUses: [] }] }
  const w = world(on, { install: tab('install', 'same', '0.66.0', ROOT_66) })
  await boot($, w)
  const out = await $.session.compact(compact)
  if (out.skip !== undefined) throw new Error(`skipped: ${out.skip}`)
  expect(out.messages.at(-1)?.text).toContain(
    `The panel runs planwright 0.66.0 from ${ROOT_66}. Before the next act, resolve the planwright root again from the installed record.`,
  )
  w.set({ installExit: 1 })
  await boot($, w)
  const again = await $.session.compact(compact)
  if (again.skip !== undefined) throw new Error(`skipped: ${again.skip}`)
  const text = again.messages.at(-1)?.text ?? ''
  expect(text).not.toContain('The panel runs planwright')
  expect(text).toContain('Before the next act, resolve the planwright root again from the installed record.')
})
