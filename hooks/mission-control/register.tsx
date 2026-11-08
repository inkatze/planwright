import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { PanelView } from '../../types'
import { emptyView, fallbackLine, handoverReason, isHandle, isProgram, parseDigest, parseInstall, parseWake } from './digest'
import type { Install } from './digest'
import { Band, Pane } from './panel'

const PANE = 'mission-control'
const TITLE = 'Mission control'
// Used only when the first digest cannot read the knobs.
const DEFAULT_REFRESH_S = 10
const DEFAULT_TICK_S = 300
const DEFAULT_REVIEWS_TTL_S = 300
// The longest wait between reviews checks, whatever the TTL; otherwise a
// check comes every fifth of it, so a read lands soon after falling due.
const REVIEWS_CHECK_MAX_MS = 60_000
const PRESENCE_EVERY_MS = 60_000
const ANIMATE_MS = 500
const SCRIPT_TIMEOUT_MS = 20_000
// How often a session not yet mission control looks for its activation record.
const RECORD_CHECK_MS = DEFAULT_REFRESH_S * 1000
// Past this a deferred compaction would risk the window itself.
const DEFER_CEILING_PCT = 95
const FAULT_MAX = 200
// A failed check of the planwright copy is tried again no sooner than this.
const INSTALL_RETRY_MS = 60_000
// The scripts' stale-copy warning, which must not stand in for the error.
const STALE_WARNING = 'planwright: WARNING running from '

// A reload keeps $.state. Change the tag only for a field a reader cannot
// do without until the next reading replaces the digest: a new tag also
// drops the program a reload reads back, which turns the mod off.
const panel = atom({ plugin: 'planwright', key: 'panel' } as const, null, { shape: 'panel-3' })
const isBusy = atom({ plugin: 'planwright', key: 'isBusy' } as const, false)

type Ctx = { program: string; target: string }
type Ran = { ok: boolean; code: number; out: string; err: string }

const REINJECT_HEAD =
  'Mission control: the active rules, re-injected after a compaction. ' +
  'Before your next act, run the post-compaction self-check against the durable stores.\n\n'

// Set at each session.start, which a reload runs again.
let ctx: Ctx | null = null
let isSubmitting = false
let isRefreshing = false
let isRaising = false
let isClaimed = false
let isFetchingReviews = false
let isRedrawing = false
let hasKnobs = false
// Faults the next good digest must not clear (an unclaimed target, events
// that could not be marked, an activation that leaked), one per kind.
let lasting: Record<string, string> = {}
// Why the last digest failed; cleared by the next good one.
let readFault: string | null = null
let timers: Timer[] = []
let armedWith = ''
let tickMs = DEFAULT_TICK_S * 1000
// A wake whose events could not be marked is not sent again before this.
let wakeHeldUntil = 0
let radar: Timer | null = null
// The planwright copy this session runs, checked against the program's
// record at each start.
let installed: Install | null = null
let installRetryAt = 0
// Where activation records live, read once per start; null until known.
let activationDir: string | null = null
let recordWatch: Timer | null = null
let isChecking = false
// The session id whose record this activation was acknowledged against; a
// record gone under that same id is a retirement.
let ackedFor: string | null = null
// How the activation was to be recorded, while that recording keeps failing:
// the record on disk is then not this activation's, so it is neither
// acknowledged nor switched to, and the recording is tried again instead.
let recordFailed: 'variable' | 'reload' | 'clear' | null = null

// Stderr reaches the pane, the status line and the event store: control
// bytes dropped, one short line.
function oneLine(text: string): string {
  return text.replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').trim().slice(0, FAULT_MAX)
}

async function run($: EngineInterface, script: string, args: string[]): Promise<Ran> {
  if (!ctx) return { ok: false, code: -1, out: '', err: 'no program' }
  return runScript($, script, args)
}

// Every script run; this one also serves a session no program is known in yet.
async function runScript($: EngineInterface, script: string, args: string[]): Promise<Ran> {
  try {
    const r = await $.process.run(['/bin/bash', `${$.plugin.root}/scripts/${script}`, ...args], {
      timeoutMs: SCRIPT_TIMEOUT_MS,
    })
    const first = r.stderr.split('\n').find(l => l !== '' && !l.startsWith(STALE_WARNING)) ?? ''
    return { ok: r.exitCode === 0, code: r.exitCode, out: r.stdout, err: oneLine(first) }
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

function standingFault(): string | null {
  const all = [...(readFault ? [readFault] : []), ...Object.values(lasting)]
  return all.length > 0 ? all.join('; ') : null
}

async function lastingFault($: EngineInterface, kind: string, text: string | null) {
  if (text) lasting = { ...lasting, [kind]: text }
  else {
    const { [kind]: _gone, ...rest } = lasting
    lasting = rest
  }
  await patch($, x => ({ ...x, fault: standingFault() }))
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
  if (!v || isRaising) return
  // Carried over from an older panel, or raised before the holder record
  // moved to the operator's own session: it would only hold the compaction
  // that session needs.
  if (v.handover && v.digest?.holder === 'attended') {
    await patch($, x => ({ ...x, handover: null }))
    return
  }
  if (v.handover) return
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
  if (!ctx || isSubmitting) return
  // The events are composed and marked in this program's store, even if
  // the panel switches program while the wake is in flight.
  const c = ctx
  // Taken before any await, so two callers never compose the same events.
  isSubmitting = true
  try {
    if (await read($, isBusy)) return
    const v = await view($)
    if (v?.digest?.rung.name === 'paused') return
    const now = await $.clock.now()
    if (now < wakeHeldUntil) return
    const composed = await run($, 'mc-wake.sh', ['compose', '--program', c.program, c.target])
    if (!composed.ok) {
      await fault($, `the wake could not be composed: ${composed.err}`)
      return
    }
    const w = parseWake(composed.out)
    if (!w || ctx !== c) return
    const entered = await $.prompt.submit({ text: isTick ? `Failsafe tick. ${w.text}` : w.text })
    if ('drop' in entered && entered.drop !== undefined) {
      await fault($, `the wake was dropped: ${oneLine(entered.drop)}`)
      return
    }
    const marked = await run($, 'mc-event.sh', [
      'mark',
      '--program',
      c.program,
      '--target',
      c.target,
      'submitted',
      ...w.ids,
    ])
    // Exit 3: an event was pruned since the wake was composed; the rest are marked.
    if (!marked.ok && marked.code !== 3) {
      wakeHeldUntil = now + tickMs
      await lastingFault($, 'mark', `the wake's events could not be marked: ${marked.err}`)
      $.ui.toast('Mission control: a wake was sent but its events could not be marked')
      return
    }
    if (lasting.mark) await lastingFault($, 'mark', null)
    await patch($, x => ({ ...x, digest: x.digest && { ...x.digest, pending: 0 } }))
  } finally {
    isSubmitting = false
    await syncRadar($)
  }
}

// On its own timer, never awaited by a redraw: the script reads the forge
// at most once per its TTL, and a slow read must not hold the digest. A
// `fresh` answer read nothing, so it never clears a fault.
async function refreshReviews($: EngineInterface) {
  if (!ctx || isFetchingReviews) return
  isFetchingReviews = true
  let isNew = false
  try {
    const r = await run($, 'mc-reviews.sh', ['refresh', '--program', ctx.program])
    isNew = r.ok && /^(written|unavailable)/.test(r.out)
    if (isNew && lasting.reviews) await lastingFault($, 'reviews', null)
    if (!r.ok) await lastingFault($, 'reviews', `the reviews snapshot could not be refreshed: ${r.err}`)
  } finally {
    isFetchingReviews = false
  }
  if (isNew) void redraw($)
}

// A changed copy raises its own event, which the reading after this counts
// and wakes the session with.
async function checkInstall($: EngineInterface) {
  if (!ctx) return
  const r = await run($, 'mc-panel.sh', ['install', '--program', ctx.program])
  const got = r.ok ? parseInstall(r.out) : null
  if (!got) {
    installRetryAt = (await $.clock.now()) + INSTALL_RETRY_MS
    await lastingFault($, 'install', `the planwright version could not be checked: ${r.err || 'unreadable answer'}`)
    return
  }
  installed = got
  if (got.state === 'changed') {
    $.ui.toast(
      got.was === got.version
        ? `Mission control: planwright ${got.version} moved to ${got.root}`
        : `Mission control: planwright is now ${got.version} (was ${got.was})`,
    )
  }
  if (lasting.install) await lastingFault($, 'install', null)
}

// One digest read laid into the view.
async function readDigest($: EngineInterface) {
  if (!ctx) return
  const c = ctx
  // Knobs are read until a reading names all of them, then carried on.
  const withKnobs = !hasKnobs
  const args = ['digest', '--program', c.program, '--target', c.target]
  const got = await run($, 'mc-panel.sh', withKnobs ? [...args, '--knobs'] : args)
  // A reading of the program the panel has since left is not drawn.
  if (ctx !== c) return
  const digest = got.ok ? parseDigest(got.out) : null
  // Done once a reading names every knob; until then each reading's
  // knobs are laid over the last.
  if (digest && withKnobs && !digest.unreadable.some(u => u.startsWith('knob '))) hasKnobs = true
  readFault = digest ? null : got.err || 'the digest could not be read'
  await patch($, x => ({
    ...x,
    digest: digest
      ? { ...digest, knobs: withKnobs ? { ...(x.digest?.knobs ?? {}), ...digest.knobs } : (x.digest?.knobs ?? {}) }
      : x.digest,
    fault: standingFault(),
  }))
}

// Draws a new reviews snapshot now, without the redraw's other duties.
// Its own flag, not isRefreshing: a redraw falling due meanwhile must still
// run its duties, and two digest reads may overlap harmlessly.
async function redraw($: EngineInterface) {
  if (!ctx || isRedrawing) return
  isRedrawing = true
  try {
    await readDigest($)
  } catch (err) {
    await fault($, oneLine(String(err)))
  } finally {
    isRedrawing = false
  }
}

async function refresh($: EngineInterface) {
  if (!ctx || isRefreshing) return
  isRefreshing = true
  try {
    if (!installed && (await $.clock.now()) >= installRetryAt) await checkInstall($)
    await readDigest($)
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
    if (!isClaimed) await claim($)
    await armTimers($)
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

// Tells the relay this target is the mod's; retried each redraw until it
// lands, since a target the relay also wakes gets every wake twice.
async function claim($: EngineInterface) {
  if (!ctx) return
  const claiming = ctx
  const claimed = await run($, 'mc-wake.sh', ['target', 'add', '--program', claiming.program, claiming.target, '--mod'])
  if (ctx?.program !== claiming.program || ctx.target !== claiming.target) {
    // Stood down or switched while the claim ran: hand it straight back.
    await release($, claiming)
    return
  }
  isClaimed = claimed.ok
  if (claimed.ok && lasting.claim) await lastingFault($, 'claim', null)
  if (!claimed.ok) await lastingFault($, 'claim', `the wake target could not be claimed: ${claimed.err}`)
}

// On its own timer, so the lease the relay reads never lapses between
// redraws, whatever the redraw cadence.
async function restampPresence($: EngineInterface) {
  if (ctx) await run($, 'mc-panel.sh', ['presence', '--program', ctx.program, '--refresh', '--target', ctx.target])
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

async function close($: EngineInterface) {
  await $.ui.close({ id: PANE })
  await patch($, x => ({ ...x, isFallback: false }))
  $.ui.status(undefined)
}

// The cadences from the knobs, or the defaults until a reading carries
// them; armed again once, when the knobs first arrive.
async function armTimers($: EngineInterface) {
  // A reading that finished after a stand-down or a switch arms nothing,
  // checked again after the read, since the timers were cancelled meanwhile.
  const c = ctx
  if (!c) return
  const knobs = (await view($))?.digest?.knobs
  if (ctx !== c) return
  const refreshMs = (knobs?.refresh ?? DEFAULT_REFRESH_S) * 1000
  const nextTickMs = (knobs?.tick ?? DEFAULT_TICK_S) * 1000
  const reviewsMs = Math.min(
    REVIEWS_CHECK_MAX_MS,
    Math.max(refreshMs, ((knobs?.['reviews-ttl'] ?? DEFAULT_REVIEWS_TTL_S) * 1000) / 5),
  )
  const key = `${refreshMs}/${nextTickMs}/${reviewsMs}`
  if (key === armedWith) return
  armedWith = key
  for (const t of timers) t.cancel()
  tickMs = nextTickMs
  timers = [
    $.clock.every(refreshMs, () => void refresh($)),
    $.clock.every(tickMs, () => void tick($)),
    $.clock.every(PRESENCE_EVERY_MS, () => void restampPresence($)),
    $.clock.every(reviewsMs, () => void refreshReviews($)),
  ]
}

// Out of the start hook, which the first prompt waits on: the presence
// marker, then the first reading, which claims the target and arms the
// timers, then the first reviews check.
async function bringUp($: EngineInterface) {
  if (!ctx) return
  try {
    await restampPresence($)
    await refresh($)
  } finally {
    await armTimers($)
  }
  void refreshReviews($)
}

async function recordPresence($: EngineInterface) {
  if (ctx) await run($, 'mc-panel.sh', ['presence', '--program', ctx.program, '--prompt', '--target', ctx.target])
}

function stopWatch() {
  recordWatch?.cancel()
  recordWatch = null
}

function parseRecord(text: string): { program: string; target: string } | null {
  const get = (k: string) => text.split('\n').find(l => l.startsWith(`${k}\t`))?.slice(k.length + 1)
  const program = get('program')
  const target = get('target')
  if (program === undefined || !isProgram(program)) return null
  return { program, target: target !== undefined && isHandle(target) ? target : program }
}

// The record the skill's bring-up writes under this session's own id is
// looked for on a timer and at turn boundaries, active or not: inactive it
// activates, active it re-acknowledges a rewritten record, follows a new
// program, and stands down when the record is retired.
function watchForRecord($: EngineInterface) {
  if (!recordWatch) recordWatch = $.clock.every(RECORD_CHECK_MS, () => void checkRecord($))
}

async function resolveDir($: EngineInterface): Promise<string | null> {
  if (activationDir !== null) return activationDir
  const where = await runScript($, 'mc-panel.sh', ['where'])
  const dir = where.out.trim()
  // A failed read is tried again at the next check.
  if (where.ok && dir.startsWith('/')) activationDir = dir
  return activationDir
}

async function checkRecord($: EngineInterface) {
  if (isChecking) return
  isChecking = true
  try {
    const dir = await resolveDir($)
    if (dir === null) return
    // Read each time: a /clear goes on under another id with no start event.
    const sessionId = await $.session.id()
    // First, so neither a retried activation nor a /clear's move records a
    // released session again.
    const ids = ackedFor !== null && ackedFor !== sessionId ? [sessionId, ackedFor] : [sessionId]
    if (ctx && (await isRetiredForExit($, dir, ids))) {
      await endReleased($, ids)
      return
    }
    if (ctx && recordFailed) {
      await acknowledge($, recordFailed)
      return
    }
    const has = await $.fs.exists(`${dir}/${sessionId}`)
    if (!has) {
      if (ctx && ackedFor === sessionId) await standDown($)
      // Acknowledged under an id the session no longer carries (a /clear the
      // end hook could not follow): record it under this one.
      else if (ctx && ackedFor !== null) {
        await runScript($, 'mc-panel.sh', ['retire', '--session', ackedFor])
        await acknowledge($, 'clear')
      }
      return
    }
    // Only a regular, non-empty acknowledgment counts: anything else is
    // written again.
    const ack = await $.fs.stat(`${dir}/${sessionId}.ack`).catch(() => undefined)
    if (ctx && ack && !ack.isLink && ack.kind === 'file' && ack.size > 0) return
    const found = await runScript($, 'mc-panel.sh', ['lookup', '--session', sessionId])
    const rec = found.ok ? parseRecord(found.out) : null
    if (!rec) return
    if (ctx && rec.program === ctx.program && rec.target === ctx.target) {
      await acknowledge($, 'record')
      return
    }
    // The old program's target goes back to the relay before the switch.
    if (ctx) await release($, ctx)
    await activate($, rec.program, rec.target, await view($), 'record')
  } catch {
    // The next check tries again.
  } finally {
    isChecking = false
  }
}

// Hands a wake target back to the relay, once more on a failure; one still
// held is said, since the relay takes it only once its lease lapses.
async function release($: EngineInterface, c: Ctx) {
  const args = ['target', 'add', '--program', c.program, c.target]
  if ((await runScript($, 'mc-wake.sh', args)).ok || (await runScript($, 'mc-wake.sh', args)).ok) return
  $.ui.toast(`Mission control: the ${c.program} wake target could not be handed back; the relay takes it once its lease lapses`)
}

function cancelTimers() {
  for (const t of timers) t.cancel()
  timers = []
  armedWith = ''
  radar?.cancel()
  radar = null
}

// The record was retired: the wake target goes back to the relay and the
// panel stops drawing.
async function standDown($: EngineInterface) {
  const was = ctx
  if (!was) return
  cancelTimers()
  ctx = null
  ackedFor = null
  recordFailed = null
  await update($, panel, () => null)
  $.ui.status(undefined)
  await release($, was)
}

// Only a regular file counts, as for the acknowledgment.
async function isRetiredForExit($: EngineInterface, dir: string, ids: string[]) {
  for (const id of ids) {
    const marker = await $.fs.stat(`${dir}/${id}.exit`).catch(() => undefined)
    if (marker && !marker.isLink && marker.kind === 'file') return true
  }
  return false
}

// A released predecessor ends itself: the operator's own session has no
// launcher row through which its successor could retire it. The retire
// clears the exit markers; /exit is queued until the session is idle, so
// the release's turn finishes first, and it is not awaited since a run that
// ends the session never resolves.
async function endReleased($: EngineInterface, ids: string[]) {
  // The /clear path and a record check can both find the marker.
  if (!ctx) return
  const program = ctx.program
  try {
    await standDown($)
  } finally {
    for (const id of ids) await runScript($, 'mc-panel.sh', ['retire', '--session', id])
    void $.command.run({ command: 'exit' }).catch(() =>
      $.ui.toast(
        `Mission control: this session released the ${program} program name but could not end itself; type /exit to close it`,
      ),
    )
  }
}

async function activate(
  $: EngineInterface,
  program: string,
  target: string,
  prior: PanelView | null,
  how: 'variable' | 'record' | 'reload',
) {
  cancelTimers()
  ctx = { program, target }
  installed = null
  installRetryAt = 0
  ackedFor = null
  recordFailed = null
  isClaimed = false
  hasKnobs = false
  lasting = {}
  readFault = null
  try {
    // A session this one starts must not take its wakes: the variables are
    // read once and cleared, and a reload finds the program in the view.
    let cleared = true
    if (how === 'variable') {
      try {
        const a = await $.env.set('PLANWRIGHT_MC_PROGRAM', undefined)
        cleared = !('deny' in a && a.deny)
      } catch {
        cleared = false
      }
      try {
        const b = await $.env.set('PLANWRIGHT_MC_TARGET', undefined)
        cleared = cleared && !('deny' in b && b.deny)
      } catch {
        cleared = false
      }
    }
    if (!prior || prior.program !== program || prior.target !== target) {
      await update($, panel, () => emptyView(program, target))
    }
    // A turn that ran across a reload ended unheard.
    await update($, isBusy, () => false)
    if (!cleared) {
      await lastingFault($, 'activation', 'the activation could not be cleared: sessions started from here inherit it')
    }
    // Not 'mission-control': a typed command a skill shares opens the skill.
    // A refused registration must not skip the rest of this activation: the
    // bring-up below starts every reading.
    try {
      await $.command.register({
        name: 'mc-panel',
        description: 'Open or close the mission-control panel (add open or close to choose)',
      })
    } catch (err) {
      await lastingFault($, 'command', `the panel command could not be registered: ${oneLine(String(err))}`)
    }
    await open($)
  } finally {
    // A step above that failed must not leave the session active with no
    // readings and no acknowledgment.
    $.clock.after(0, () => void acknowledge($, how))
    $.clock.after(0, () => void bringUp($))
  }
}

// The skill waits on the acknowledgment before falling back to the text
// form. A session the variable marked (or a reload of one) records its
// activation first, so the skill's entry and the keeper see it as any other.
async function acknowledge($: EngineInterface, how: 'variable' | 'record' | 'reload' | 'clear') {
  if (!ctx) return
  const sessionId = await $.session.id()
  if (how !== 'record') {
    // An ack here would answer for whatever record stood before, which may
    // name another program.
    const recorded = await run($, 'mc-panel.sh', [
      'activate',
      '--program',
      ctx.program,
      '--target',
      ctx.target,
      '--session',
      sessionId,
    ])
    if (!recorded.ok) {
      recordFailed = how
      await lastingFault($, 'ack', `the activation could not be recorded: ${recorded.err}`)
      return
    }
    recordFailed = null
  }
  const acked = await run($, 'mc-panel.sh', ['ack', '--session', sessionId])
  if (acked.ok) {
    ackedFor = sessionId
    if (lasting.ack) await lastingFault($, 'ack', null)
  } else {
    await lastingFault($, 'ack', `the activation could not be acknowledged: ${acked.err}`)
  }
}

// The ending id's record, and the one this activation was acknowledged
// under when a /clear left the two apart before a check could follow it.
async function retireRecords($: EngineInterface, endingId: string) {
  const ids = ackedFor !== null && ackedFor !== endingId ? [endingId, ackedFor] : [endingId]
  ackedFor = null
  for (const id of ids) await run($, 'mc-panel.sh', ['retire', '--session', id])
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    const prior = await view($)
    const named = await $.env.get('PLANWRIGHT_MC_PROGRAM')
    const isNamed = named !== undefined && isProgram(named)
    const program = isNamed ? named : prior?.program
    stopWatch()
    watchForRecord($)
    if (program === undefined) return started
    const namedTarget = await $.env.get('PLANWRIGHT_MC_TARGET')
    const target =
      namedTarget !== undefined && isHandle(namedTarget)
        ? namedTarget
        : prior?.program === program
          ? prior.target
          : program
    await activate($, program, target, prior, isNamed ? 'variable' : 'reload')
    return started
  })

  on('session.end', async ($, e, next) => {
    const dir = ctx && e.reason === 'clear' ? await resolveDir($) : null
    const clearedIds = ackedFor !== null && ackedFor !== e.sessionId ? [e.sessionId, ackedFor] : [e.sessionId]
    if (ctx && dir !== null && (await isRetiredForExit($, dir, clearedIds))) {
      // Released just before the /clear: end it rather than move the record.
      const ended = await next(e)
      $.clock.after(0, () => void endReleased($, clearedIds).catch(() => undefined))
      return ended
    }
    if (ctx && e.reason === 'clear') {
      // A /clear keeps the session and the mod, and starts the counts over;
      // the record moves to the id the session goes on under.
      await patch($, x => ({ ...emptyView(x.program, x.target), digest: x.digest, isFallback: x.isFallback }))
      await retireRecords($, e.sessionId)
      const ended = await next(e)
      $.clock.after(0, () => void acknowledge($, 'clear'))
      return ended
    } else if (ctx) {
      await run($, 'mc-wake.sh', ['target', 'add', '--program', ctx.program, ctx.target])
      await retireRecords($, e.sessionId)
    }
    return next(e)
  })

  on('command.run', { command: 'mc-panel' }, async ($, e) => {
    if (!ctx) return { text: 'Mission control is not running in this session.' }
    const asked = e.args.trim().toLowerCase()
    if (asked !== '' && asked !== 'open' && asked !== 'close') {
      return { text: 'Type /mc-panel to open or close the panel, or /mc-panel open or /mc-panel close to choose.' }
    }
    // A pane opened unasked on a narrow terminal is listed but not drawn;
    // the command then opens it, as an asked open places it.
    const isShown = (await $.ui.panes()).some(p => p.id === PANE && p.isPlaced && p.isShown)
    if (asked === 'close' || (asked === '' && isShown)) {
      await close($)
      return { text: 'Mission control panel closed.' }
    }
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
    if (e.agentId === undefined) $.clock.after(0, () => void checkRecord($))
    if (ctx && e.agentId === undefined) {
      await update($, isBusy, () => false)
      await patch($, x => ({ ...x, wakes: x.wakes + 1 }))
      await checkHandover($)
      await syncRadar($)
      // After the hook: the submit resolves only once the session is idle.
      $.clock.after(0, () => void wake($, false))
    }
    return done
  })

  on('prompt.submit', async ($, e, next) => {
    $.clock.after(0, () => void checkRecord($))
    if (ctx && (e.origin.kind === 'composer' || e.origin.kind === 'bridge')) {
      // Never holds the operator's prompt on the fleet lock.
      $.clock.after(0, () => void recordPresence($))
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // A failed hook never holds the compaction: the catch replays or runs it.
  on('session.compact', async ($, e, next) => {
    if (!ctx || e.agentId !== undefined || e.trigger === 'precompute') return next(e)
    const before = await view($)
    // The holder is checked here too: a redraw can read an attended holder
    // before the handover check withdraws the handover it would clear.
    if (
      e.trigger !== 'manual' &&
      before?.handover &&
      before.digest?.isHandoverInstalled &&
      before.digest.holder !== 'attended'
    ) {
      let pct: number | undefined
      try {
        pct = (await $.session.usage()).context.percent
      } catch {
        pct = undefined
      }
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
    const copy = installed ? `The panel runs planwright ${installed.version} from ${installed.root}. ` : ''
    const text = `${REINJECT_HEAD}${rules.out}\n\n${copy}Before the next act, resolve the planwright root again from the installed record.`
    return { ...done, messages: [...kept, { role: 'user', text, toolUses: [] }] }
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
