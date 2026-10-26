import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { PanelView } from '../../types'
import { emptyView, fallbackLine, handoverReason, isHandle, isProgram, parseDigest, parseWake } from './digest'
import { Band, Pane } from './panel'

const PANE = 'mission-control'
const TITLE = 'Mission control'
// Used only when the first digest cannot read the knobs.
const DEFAULT_REFRESH_S = 10
const DEFAULT_TICK_S = 300
const PRESENCE_EVERY_MS = 60_000
const ANIMATE_MS = 500
const SCRIPT_TIMEOUT_MS = 20_000
// Past this a deferred compaction would risk the window itself.
const DEFER_CEILING_PCT = 95
const FAULT_MAX = 200

// Change the tag when PanelView's fields change: a reload keeps $.state.
const panel = atom({ plugin: 'planwright', key: 'panel' } as const, null, { shape: 'panel-2' })
const isBusy = atom({ plugin: 'planwright', key: 'isBusy' } as const, false)

type Ctx = { program: string; target: string; root: string }
type Ran = { ok: boolean; code: number; out: string; err: string }

const REINJECT_HEAD =
  'Mission control: the active rules, re-injected after a compaction. ' +
  'Before your next act, run the post-compaction self-check against the durable stores.\n\n'

// Set at each session.start, which a reload runs again.
let ctx: Ctx | null = null
let isSubmitting = false
let isRefreshing = false
let isRaising = false
let lastPresence = 0
let tickMs = DEFAULT_TICK_S * 1000
// A wake whose events could not be marked is not sent again before this.
let wakeHeldUntil = 0
let radar: Timer | null = null

// Stderr reaches the pane, the status line and the event store: control
// bytes dropped, one short line.
function oneLine(text: string): string {
  return text.replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').trim().slice(0, FAULT_MAX)
}

async function run($: EngineInterface, script: string, args: string[]): Promise<Ran> {
  if (!ctx) return { ok: false, code: -1, out: '', err: 'no program' }
  try {
    const r = await $.process.run(['/bin/bash', `${ctx.root}/scripts/${script}`, ...args], {
      timeoutMs: SCRIPT_TIMEOUT_MS,
    })
    return { ok: r.exitCode === 0, code: r.exitCode, out: r.stdout, err: oneLine(r.stderr.split('\n')[0] ?? '') }
  } catch (err) {
    return { ok: false, code: -1, out: '', err: oneLine(String(err)) }
  }
}

async function view($: EngineInterface): Promise<PanelView | null> {
  return read($, panel)
}

async function patch($: EngineInterface, fn: (v: PanelView) => PanelView) {
  await update($, panel, v => (v ? fn(v) : v))
}

async function fault($: EngineInterface, text: string) {
  await patch($, x => ({ ...x, fault: text }))
}

async function emit($: EngineInterface, kind: string, text: string): Promise<boolean> {
  if (!ctx) return false
  const r = await run($, 'mc-event.sh', ['emit', '--program', ctx.program, '--', kind, ctx.program, oneLine(text)])
  return r.ok
}

async function isHeld($: EngineInterface, v: PanelView): Promise<boolean> {
  return (v.digest?.pending ?? 0) > 0 && (await read($, isBusy))
}

// Raised once: the view records it only after the event is in the store, so
// a failed emit is tried again at the next check.
async function checkHandover($: EngineInterface) {
  const v = await view($)
  if (!v || v.handover || isRaising) return
  const reason = handoverReason(v)
  if (!reason) return
  isRaising = true
  try {
    if (!(await emit($, 'handover-due', reason))) return
    await patch($, x => ({ ...x, handover: reason }))
    $.ui.toast(`Mission control: handover due (${reason})`)
  } finally {
    isRaising = false
  }
}

// Submits the target's events not yet submitted, when the session is idle;
// a busy session holds them for the next redraw or the turn's end.
async function wake($: EngineInterface, isTick: boolean) {
  if (!ctx || isSubmitting || (await read($, isBusy))) return
  const v = await view($)
  if (v?.digest?.rung.name === 'paused') return
  const now = await $.clock.now()
  if (now < wakeHeldUntil) return
  isSubmitting = true
  try {
    const composed = await run($, 'mc-wake.sh', ['compose', '--program', ctx.program, ctx.target])
    if (!composed.ok) {
      await fault($, `the wake could not be composed: ${composed.err}`)
      return
    }
    const w = parseWake(composed.out)
    if (!w) return
    const entered = await $.prompt.submit({ text: isTick ? `Failsafe tick. ${w.text}` : w.text })
    if ('drop' in entered && entered.drop !== undefined) {
      await fault($, `the wake was dropped: ${oneLine(entered.drop)}`)
      return
    }
    const marked = await run($, 'mc-event.sh', [
      'mark',
      '--program',
      ctx.program,
      '--target',
      ctx.target,
      'submitted',
      ...w.ids,
    ])
    // Exit 3: an event was pruned since the wake was composed; the rest are marked.
    if (!marked.ok && marked.code !== 3) {
      wakeHeldUntil = now + tickMs
      await fault($, `the wake's events could not be marked: ${marked.err}`)
      $.ui.toast('Mission control: a wake was sent but its events could not be marked')
      return
    }
    await patch($, x => ({ ...x, digest: x.digest && { ...x.digest, pending: 0 } }))
  } finally {
    isSubmitting = false
    await syncRadar($)
  }
}

async function refresh($: EngineInterface, withKnobs = false) {
  if (!ctx || isRefreshing) return
  isRefreshing = true
  try {
    const args = ['digest', '--program', ctx.program, '--target', ctx.target]
    const got = await run($, 'mc-panel.sh', withKnobs ? [...args, '--knobs'] : args)
    const digest = got.ok ? parseDigest(got.out) : null
    await patch($, x => ({
      ...x,
      // Knobs are read once at bring-up and carried on.
      digest: digest ? { ...digest, knobs: withKnobs ? digest.knobs : (x.digest?.knobs ?? {}) } : x.digest,
      fault: digest ? null : got.err || 'the digest could not be read',
    }))
    const usage = await $.session.usage()
    const pct = usage.context.percent
    await patch($, x => ({
      ...x,
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
  } catch (err) {
    await fault($, oneLine(String(err)))
  } finally {
    isRefreshing = false
  }
  const v = await view($)
  // Not awaited: the submit resolves only once its turn starts, and the
  // redraws go on meanwhile.
  if ((v?.digest?.pending ?? 0) > 0) void wake($, false)
  await syncRadar($)
}

async function tick($: EngineInterface) {
  const now = await $.clock.now()
  await patch($, x => ({ ...x, ticks: x.ticks + 1, lastTickAt: now }))
  await wake($, true)
}

async function sweep($: EngineInterface) {
  await patch($, x => ({ ...x, frame: x.frame + 1 }))
}

// The radar sweeps only while a wake is held for a busy session, so an idle
// panel costs no redraws.
async function syncRadar($: EngineInterface) {
  const v = await view($)
  const held = v !== null && (await isHeld($, v))
  if (held && !radar) radar = $.clock.every(ANIMATE_MS, () => void sweep($))
  if (!held && radar) {
    radar.cancel()
    radar = null
  }
}

async function open($: EngineInterface) {
  const placed = await $.ui.open({ id: PANE, title: TITLE })
  await patch($, x => ({ ...x, isFallback: !placed.isPlaced }))
  const v = await view($)
  if (v) $.ui.status(v.isFallback ? fallbackLine(v) : undefined)
}

// Out of the start hook, which the first prompt waits on: the first reading,
// then the timers, then the claim that tells the relay this target is ours.
async function bringUp($: EngineInterface) {
  if (!ctx) return
  try {
    await refresh($, true)
  } finally {
    const knobs = (await view($))?.digest?.knobs
    tickMs = (knobs?.tick ?? DEFAULT_TICK_S) * 1000
    $.clock.every((knobs?.refresh ?? DEFAULT_REFRESH_S) * 1000, () => void refresh($))
    $.clock.every(tickMs, () => void tick($))
  }
  const claimed = await run($, 'mc-wake.sh', ['target', 'add', '--program', ctx.program, ctx.target, '--mod'])
  if (!claimed.ok) await fault($, `the wake target could not be claimed: ${claimed.err}`)
}

async function recordPresence($: EngineInterface) {
  if (ctx) await run($, 'mc-panel.sh', ['presence', '--program', ctx.program, '--prompt'])
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    const prior = await view($)
    const named = await $.env.get('PLANWRIGHT_MC_PROGRAM')
    const program = named !== undefined && isProgram(named) ? named : prior?.program
    if (program === undefined) return started
    const namedTarget = await $.env.get('PLANWRIGHT_MC_TARGET')
    const target =
      namedTarget !== undefined && isHandle(namedTarget)
        ? namedTarget
        : prior?.program === program
          ? prior.target
          : program
    // A session this one starts must not take its wakes: the variables are
    // read once and cleared, and a reload finds the program in the view.
    await $.env.set('PLANWRIGHT_MC_PROGRAM', undefined)
    await $.env.set('PLANWRIGHT_MC_TARGET', undefined)
    ctx = { program, target, root: $.plugin.root }
    if (!prior || prior.program !== program || prior.target !== target) {
      await update($, panel, () => emptyView(program, target))
    }
    // A turn that ran across a reload ended unheard.
    await update($, isBusy, () => false)
    await $.command.register({ name: 'mission-control', description: 'Open the mission-control panel' })
    await open($)
    $.clock.after(0, () => void bringUp($))
    return started
  })

  on('session.end', async ($, e, next) => {
    if (ctx && e.reason === 'clear') {
      // A /clear keeps the session and the mod, and starts the counts over.
      await patch($, x => ({ ...emptyView(x.program, x.target), digest: x.digest, isFallback: x.isFallback }))
    } else if (ctx) {
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
      // After the hook: the submit resolves only once the session is idle.
      $.clock.after(0, () => void wake($, false))
    }
    return done
  })

  on('prompt.submit', async ($, e, next) => {
    if (ctx && (e.origin.kind === 'composer' || e.origin.kind === 'bridge')) {
      lastPresence = await $.clock.now()
      // Never holds the operator's prompt on the fleet lock.
      $.clock.after(0, () => void recordPresence($))
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // A failed hook never holds the compaction: the catch replays or runs it.
  on('session.compact', async ($, e, next) => {
    if (!ctx || e.agentId !== undefined || e.trigger === 'precompute') return next(e)
    const before = await view($)
    if (e.trigger !== 'manual' && before?.handover && before.digest?.isHandoverInstalled) {
      const pct = (await $.session.usage()).context.percent
      if (pct !== undefined && pct < DEFER_CEILING_PCT) {
        return { skip: 'mission control: deferred while the handover is due' }
      }
    }
    const done = await next(e)
    if (done.skip !== undefined) return done
    const rules = await run($, 'mc-rules.sh', ['load', ctx.program])
    try {
      await patch($, x => ({ ...x, compactions: x.compactions + 1 }))
      await checkHandover($)
    } catch {
      // The count is the panel's; the rules below are what the session needs.
    }
    if (!rules.ok) {
      await emit($, 'rules-reinjection-failed', rules.err || 'the rule store could not be loaded')
      $.ui.toast('Mission control: the rules could not be re-injected after the compaction')
      return done
    }
    const kept = done.messages.filter(m => !(m.role === 'user' && m.text.startsWith(REINJECT_HEAD)))
    return { ...done, messages: [...kept, { role: 'user', text: REINJECT_HEAD + rules.out, toolUses: [] }] }
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (!ctx) return next(e)
    const v = await view($)
    if (!v) return next(e)
    return Pane($.ui.resolve(e), v, await isHeld($, v))
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (!ctx || e.props.hasSurvey) return next(e)
    const v = await view($)
    if (!v) return next(e)
    return Band($.ui.resolve(e), v, await isHeld($, v))
  })
}
