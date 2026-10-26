import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { PanelView } from '../../types'
import { emptyView, fallbackLine, handoverReason, isHandle, isProgram, parseDigest, parseWake } from './digest'
import { Band, Pane } from './panel'

const PANE = 'mission-control'
const TITLE = 'Mission control'
const DEFAULT_REFRESH_S = 10
const DEFAULT_TICK_S = 300
const PRESENCE_EVERY_MS = 60_000
const ANIMATE_MS = 500
const SCRIPT_TIMEOUT_MS = 20_000
// Past this a deferred compaction would risk the window itself.
const DEFER_CEILING_PCT = 95

// Change the tag when PanelView's fields change: a reload keeps $.state.
const panel = atom({ plugin: 'planwright', key: 'panel' } as const, null, { shape: 'panel-1' })
const isBusy = atom({ plugin: 'planwright', key: 'isBusy' } as const, false)

type Ctx = { program: string; target: string; root: string }
type Ran = { ok: boolean; out: string; err: string }

const REINJECT_HEAD =
  'Mission control: the active rules, re-injected after a compaction. ' +
  'Before your next act, run the post-compaction self-check against the durable stores.\n\n'

// Set at each session.start, which a reload runs again.
let ctx: Ctx | null = null
let isSubmitting = false
let isRefreshing = false
let lastPresence = 0
let radar: Timer | null = null

async function run($: EngineInterface, script: string, args: string[]): Promise<Ran> {
  if (!ctx) return { ok: false, out: '', err: 'no program' }
  try {
    const r = await $.process.run(['/bin/bash', `${ctx.root}/scripts/${script}`, ...args], {
      timeoutMs: SCRIPT_TIMEOUT_MS,
    })
    return { ok: r.exitCode === 0, out: r.stdout, err: r.stderr.split('\n')[0] ?? '' }
  } catch (err) {
    return { ok: false, out: '', err: String(err) }
  }
}

async function view($: EngineInterface): Promise<PanelView | null> {
  return read($, panel)
}

async function patch($: EngineInterface, fn: (v: PanelView) => PanelView) {
  await update($, panel, v => (v ? fn(v) : v))
}

async function emit($: EngineInterface, kind: string, text: string) {
  if (!ctx) return
  await run($, 'mc-event.sh', ['emit', '--program', ctx.program, '--', kind, ctx.program, text])
}

async function checkHandover($: EngineInterface) {
  const v = await view($)
  if (!v || v.handover) return
  const reason = handoverReason(v)
  if (!reason) return
  await patch($, x => ({ ...x, handover: reason }))
  await emit($, 'handover-due', reason)
  $.ui.toast(`Mission control: handover due (${reason})`)
}

// Submits the target's events not yet submitted, when the session is idle;
// a busy session holds them for the next redraw or the turn's end.
async function wake($: EngineInterface, isTick: boolean): Promise<boolean> {
  if (!ctx || isSubmitting || (await read($, isBusy))) return false
  isSubmitting = true
  try {
    const composed = await run($, 'mc-wake.sh', ['compose', '--program', ctx.program, ctx.target])
    const w = composed.ok ? parseWake(composed.out) : null
    if (!w) return false
    const text = isTick ? `Failsafe tick. ${w.text}` : w.text
    await $.prompt.submit({ text })
    await run($, 'mc-event.sh', ['mark', '--program', ctx.program, '--target', ctx.target, 'submitted', ...w.ids])
    const now = await $.clock.now()
    // Submitted: nothing is held any more until the next reading says so.
    await patch($, x => ({ ...x, lastWakeAt: now, digest: x.digest && { ...x.digest, pending: 0 } }))
    return true
  } finally {
    isSubmitting = false
  }
}

async function refresh($: EngineInterface) {
  if (!ctx || isRefreshing) return
  isRefreshing = true
  try {
    const got = await run($, 'mc-panel.sh', ['digest', '--program', ctx.program, '--target', ctx.target])
    const digest = got.ok ? parseDigest(got.out) : null
    const usage = await $.session.usage()
    const pct = usage.context.percent
    await patch($, x => ({
      ...x,
      digest: digest ?? x.digest,
      fault: digest ? null : got.err || 'the digest could not be read',
      contextPercent: pct === undefined ? null : Math.round(pct),
      rateLimits: usage.rateLimits.map(r => ({ kind: r.kind, percentUsed: r.percentUsed })),
    }))
    const v = await view($)
    if (v?.isFallback) $.ui.status(fallbackLine(v))
    await checkHandover($)
    const now = await $.clock.now()
    if (now - lastPresence >= PRESENCE_EVERY_MS) {
      lastPresence = now
      await run($, 'mc-panel.sh', ['presence', '--program', ctx.program, '--refresh'])
    }
    if ((v?.digest?.pending ?? 0) > 0) await wake($, false)
    await syncRadar($)
  } finally {
    isRefreshing = false
  }
}

async function sweep($: EngineInterface) {
  await patch($, x => ({ ...x, frame: x.frame + 1 }))
}

// The radar sweeps only while a wake is held for a busy session, so an idle
// panel costs no redraws.
async function syncRadar($: EngineInterface) {
  const v = await view($)
  const isHeld = (v?.digest?.pending ?? 0) > 0 && (await read($, isBusy))
  if (isHeld && !radar) radar = $.clock.every(ANIMATE_MS, () => void sweep($))
  if (!isHeld && radar) {
    radar.cancel()
    radar = null
  }
}

async function tick($: EngineInterface) {
  const now = await $.clock.now()
  await patch($, x => ({ ...x, ticks: x.ticks + 1, lastTickAt: now }))
  await wake($, true)
}

async function open($: EngineInterface) {
  const placed = await $.ui.open({ id: PANE, title: TITLE })
  await patch($, x => ({ ...x, isFallback: !placed.isPlaced }))
  const v = await view($)
  if (v) $.ui.status(v.isFallback ? fallbackLine(v) : undefined)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    const program = await $.env.get('PLANWRIGHT_MC_PROGRAM')
    if (program === undefined || !isProgram(program)) return started
    const named = await $.env.get('PLANWRIGHT_MC_TARGET')
    const target = named !== undefined && isHandle(named) ? named : program
    ctx = { program, target, root: $.plugin.root }
    const prior = await view($)
    if (!prior || prior.program !== program) await update($, panel, () => emptyView(program))
    await $.command.register({ name: 'mission-control', description: 'Open the mission-control panel' })
    // The relay leaves a target the mod wakes alone.
    await run($, 'mc-wake.sh', ['target', 'add', '--program', program, target, '--mod'])
    await open($)
    await refresh($)
    const v = await view($)
    const refreshMs = (v?.digest?.knobs.refresh ?? DEFAULT_REFRESH_S) * 1000
    const tickMs = (v?.digest?.knobs.tick ?? DEFAULT_TICK_S) * 1000
    $.clock.every(refreshMs, () => void refresh($))
    $.clock.every(tickMs, () => void tick($))
    return started
  })

  on('session.end', async ($, e, next) => {
    // A /clear keeps the session, and the mod in it.
    if (ctx && e.reason !== 'clear') {
      await run($, 'mc-wake.sh', ['target', 'add', '--program', ctx.program, ctx.target])
    }
    return next(e)
  })

  on('command.run', { command: 'mission-control' }, async $ => {
    if (!ctx) return { text: 'Mission control is not running in this session.' }
    await open($)
    return { text: 'Mission control panel opened.' }
  })

  on('turn.start', async ($, e, next) => {
    if (ctx && e.agentId === undefined) {
      await update($, isBusy, () => true)
      await syncRadar($)
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (ctx && e.agentId === undefined) {
      await update($, isBusy, () => false)
      await patch($, x => ({ ...x, wakes: x.wakes + 1 }))
      await checkHandover($)
      const v = await view($)
      if ((v?.digest?.pending ?? 0) > 0) await wake($, false)
      await syncRadar($)
    }
    return done
  })

  on('prompt.submit', async ($, e, next) => {
    if (ctx && (e.origin.kind === 'composer' || e.origin.kind === 'bridge')) {
      lastPresence = await $.clock.now()
      await run($, 'mc-panel.sh', ['presence', '--program', ctx.program, '--prompt'])
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // A failed hook never holds the compaction: the catch replays or runs it.
  on('session.compact', async ($, e, next) => {
    if (!ctx || e.agentId !== undefined) return next(e)
    const before = await view($)
    if (
      e.trigger !== 'manual' &&
      before?.handover &&
      before.digest?.isHandoverInstalled &&
      (before.contextPercent ?? 0) < DEFER_CEILING_PCT
    ) {
      return { skip: 'mission control: deferred while the handover is due' }
    }
    const done = await next(e)
    if (done.skip !== undefined) return done
    if (e.trigger !== 'precompute') await patch($, x => ({ ...x, compactions: x.compactions + 1 }))
    const rules = await run($, 'mc-rules.sh', ['load', ctx.program])
    await checkHandover($)
    if (!rules.ok) {
      await emit($, 'rules-reinjection-failed', rules.err || 'the rule store could not be loaded')
      $.ui.toast('Mission control: the rules could not be re-injected after the compaction')
      return done
    }
    return {
      ...done,
      messages: [...done.messages, { role: 'user', text: REINJECT_HEAD + rules.out, toolUses: [] }],
    }
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    const v = await view($)
    if (!ctx || !v) return next(e)
    const held = (v.digest?.pending ?? 0) > 0 && (await read($, isBusy))
    return Pane($.ui.resolve(e), v, held)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const v = await view($)
    if (!ctx || !v || e.props.hasSurvey) return next(e)
    const held = (v.digest?.pending ?? 0) > 0 && (await read($, isBusy))
    return Band($.ui.resolve(e), v, held)
  })
}
