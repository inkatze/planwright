import type { Elements, RenderSurface } from 'claude-code'

import type { PanelDigest, PanelReviews, PanelView } from '../../types'
import { age, counted, flightLines } from './digest'
import { spriteCells } from './panel-art'

type Table = Elements[RenderSurface]
type PictureTable = Elements['terminal']

// Only the terminal surface carries Raster and Image; elsewhere the text stands.
// The resolved table answers `in` for any name, so the surface is what decides.
const hasPictures = (t: Table, surface: RenderSurface): t is PictureTable => surface === 'terminal' && 'Raster' in t

const DECISIONS_SHOWN = 3
const WATCHERS_SHOWN = 4
const REVIEWS_SHOWN = 5

function headroomTight(view: PanelView): string | null {
  const rows = view.digest?.headroom ?? []
  if (rows.length === 0) return null
  const top = rows.reduce((a, b) => (b.percent > a.percent ? b : a))
  return `${top.dimension} ${top.percent}%`
}

// A count from a store the digest could not read is unknown, never zero.
function flightCount(view: PanelView): string {
  const d = view.digest
  if (!d) return '?'
  if (d.unreadable.includes('fleet registry')) return '?'
  // Windows of a tmux server that did not answer may hold more; without the
  // attention store an idle session reads live, so there may be fewer.
  const isFloor = d.unreadable.includes('tmux windows')
  const isCeiling = d.unreadable.includes('attention store')
  const n = d.flights.length
  return isFloor && isCeiling ? '?' : isFloor ? `${n}+` : isCeiling ? `up to ${n}` : String(n)
}

function kbLine(view: PanelView): string {
  const d = view.digest
  if (d?.unreadable.includes('knowledge base')) return 'knowledge base unreadable'
  return `knowledge base ${d?.kbAge == null ? 'not written yet' : `${age(d.kbAge)} old`}`
}

// The pull requests ready to merge, a floor (`3+`) or `?` when some could
// not be judged; null when there is nothing to say.
function mergeReadyCount(d: PanelDigest): string | null {
  if (d.unreadable.includes('merge-ready store')) return '?'
  const n = d.mergeReady ?? 0
  if (d.isMergeReadyPartial) return n > 0 ? `${n}+` : '?'
  return n > 0 ? String(n) : null
}


// The usage stop is the percent admission holds launches at (the digest's
// usage-hold knob, 0 when the stop is off); unread, it is unknown, never a default.
export type UsageStop = number | 'off' | null
export function usageStop(view: PanelView): UsageStop {
  const v = view.digest?.knobs['usage-hold']
  return v === undefined ? null : v === 0 ? 'off' : v
}
const stopWord = (stop: UsageStop) => (stop === null ? 'stop unknown' : stop === 'off' ? 'no stop set' : `stop at ${stop}%`)
const WINDOW_NAME: Record<string, string> = { five_hour: '5-hour', seven_day: 'weekly' }
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

// "1:10am" within a day of now, "Mon 6am" beyond; the clock is passed in.
export function resetWord(iso: string | undefined, nowMs: number): string {
  if (iso === undefined) return ''
  const at = new Date(iso)
  if (Number.isNaN(at.getTime())) return ''
  const h = at.getHours()
  const m = at.getMinutes()
  const clock = `${h % 12 === 0 ? 12 : h % 12}${m === 0 ? '' : `:${String(m).padStart(2, '0')}`}${h < 12 ? 'am' : 'pm'}`
  const isNear = at.getTime() - nowMs < 24 * 3_600_000
  return `resets ${isNear ? '' : `${DAYS[at.getDay()]} `}${clock}`
}

// Past this a deferred compaction would risk the window itself.
const CONTEXT_CEILING_PCT = 95
const LOW_MEMORY_PCT = 10

export type Verdict = 'OK' | 'ACT' | 'UNKNOWN'
export type Readout = { text: string; verdict: Verdict }

const line = (text: string, verdict: Verdict): Readout => ({ text: `${text} · ${verdict}`, verdict })

// One plain line per measure: a name, a value and a verdict. ACT only where
// the operator must do something; the word carries it, never the colour.
export function readouts(view: PanelView): Readout[] {
  const d = view.digest
  const out: Readout[] = []
  const stop = usageStop(view)
  for (const r of view.rateLimits) {
    const name = WINDOW_NAME[r.kind] ?? r.kind.replace(/_/g, ' ')
    const pct = Math.round(r.percentUsed)
    out.push(
      line(`${name[0]!.toUpperCase()}${name.slice(1)} usage ${pct}% · ${stopWord(stop)}`, typeof stop === 'number' && pct >= stop ? 'ACT' : 'OK'),
    )
  }
  if (view.rateLimits.length === 0) out.push(line('Usage no limits reported', 'UNKNOWN'))

  if (view.contextPercent === null) {
    out.push(line('Context not measured', 'UNKNOWN'))
  } else {
    const handoverAt = d?.holder === 'registry' ? d.knobs['handover-context'] : undefined
    const note = handoverAt === undefined ? '' : ` · hand over ${handoverAt}%`
    const isDue = view.handover !== null || (handoverAt !== undefined && view.contextPercent >= handoverAt)
    out.push(line(`Context ${view.contextPercent}%${note} · compacts at ${CONTEXT_CEILING_PCT}%`, isDue ? 'ACT' : 'OK'))
  }

  const host = d?.host
  const cores = host?.cores ?? null
  const load = host?.load != null && cores !== null ? host.load / 100 : null
  const mem = host?.memFreePercent ?? null
  if (load === null && mem === null) {
    out.push(line('Machine load unknown, mem unknown', 'UNKNOWN'))
  } else {
    const isHot = (load !== null && cores !== null && load / cores >= 1) || (mem !== null && mem < LOW_MEMORY_PCT)
    const loadWord = load === null ? 'unknown' : `${load.toFixed(1)}/${cores}`
    out.push(
      line(`Machine load ${loadWord}, mem ${mem === null ? 'unknown' : `${mem}%`}`, isHot ? 'ACT' : load === null || mem === null ? 'UNKNOWN' : 'OK'),
    )
  }

  if (!d || d.waiting === null) out.push(line('Waiting on you unknown', 'UNKNOWN'))
  else out.push(line(`Waiting on you ${d.waiting === 0 ? 'none' : d.waiting}`, d.waiting > 0 ? 'ACT' : 'OK'))
  return out
}


export type MascotState = 'bumpy' | 'circling' | 'landing' | 'cruising' | 'taxiing'
// The mascot knob: 0 off, 1 a still frame (reduced motion), 2 animated.
export type MascotMode = 0 | 1 | 2

export function mascotMode(view: PanelView): MascotMode {
  const v = view.digest?.knobs.mascot
  return v === 0 || v === 1 ? v : 2
}

// The first state that holds wins: an alert stands, then something waits on
// the operator, then work has finished, then sessions work, else nothing runs.
export function mascotState(view: PanelView): MascotState {
  const d = view.digest
  if (!d) return 'taxiing'
  const isAlert = Boolean(view.fault) || (d.health ?? []).length > 0 || d.unreadable.length > 0 || view.handover !== null
  if (isAlert) return 'bumpy'
  if (d.waiting !== null && d.waiting > 0) return 'circling'
  if (d.flights.length === 0 && (d.finished ?? 0) > 0) return 'landing'
  if (d.flights.length > 0) return 'cruising'
  return 'taxiing'
}

const MASCOT_WORD: Record<MascotState, string> = {
  bumpy: 'a bumpy ride, an alert stands',
  circling: 'circling, something waits on you',
  landing: 'landing, work finished',
  cruising: 'cruising, sessions working',
  taxiing: 'taxiing, nothing running',
}

export function mascotWord(view: PanelView): string {
  return `Prop pal: ${MASCOT_WORD[mascotState(view)]}`
}

// Whether the mascot has motion to repaint: a moving state with animation on.
export function isMascotMoving(view: PanelView): boolean {
  return mascotMode(view) === 2 && view.digest !== null && mascotState(view) !== 'taxiing'
}

// Prop pal, a chubby propeller plane with two eyes in its cockpit window.
// The still mode draws the first frame of the state; its state word always shows.
export function mascotLines(view: PanelView): string[] {
  const mode = mascotMode(view)
  if (mode === 0) return []
  const state = mascotState(view)
  const f = mode === 2 ? view.frame : 0
  const prop = f % 2 === 0 ? '|' : '+'
  const word = `Prop pal: ${MASCOT_WORD[state]}`
  const plane = (pad: number, eyes: string, tail = '') => [
    `${' '.repeat(pad)}  (${eyes})`,
    `${' '.repeat(pad)}${prop}-=[__]=-${tail}`,
  ]
  switch (state) {
    case 'bumpy':
      return [...plane(f % 2, 'O O', ' !'), word]
    case 'circling':
      return [...plane([0, 2, 4, 2][f % 4]!, 'o o', ' ↻'), word]
    case 'landing':
      return [...plane(0, '^ ^'), `  ${['‾', '_', '_', '_'][Math.min(f, 3)]!.repeat(14)}`, word]
    case 'cruising':
      return [...plane(0, 'o o', f % 2 === 0 ? ' ~' : ' ~~'), word]
    case 'taxiing':
      return [...plane(0, '- -'), '  o      o', word]
  }
}

export type Part = { text: string; tone?: 'ask' | 'merge' | 'alert' }

// The status strip: what needs the operator first, then the two limits that
// bound the work. Nothing waiting is said as such, never left blank.
export function stripParts(view: PanelView): Part[] {
  const d = view.digest
  const parts: Part[] = []
  if (!d) {
    parts.push({ text: view.fault ? `no reading: ${view.fault}` : 'no reading yet', tone: view.fault ? 'alert' : undefined })
  } else {
    if (d.waiting === null) parts.push({ text: '? waiting unknown', tone: 'alert' })
    else if (d.waiting > 0) parts.push({ text: `? ${d.waiting} waiting on you`, tone: 'ask' })
    const toMerge = mergeReadyCount(d)
    if (toMerge !== null) parts.push({ text: `${toMerge} ready to merge`, tone: 'merge' })
    const checks = new Set((d.health ?? []).map(h => h.check)).size
    if (checks > 0) parts.push({ text: `⚠ ${checks} health ${checks === 1 ? 'check' : 'checks'}`, tone: 'alert' })
    if (parts.length === 0) parts.push({ text: 'all clear' })
  }
  const stop = usageStop(view)
  const stopNote = typeof stop === 'number' ? ` (stop ${stop}%)` : ''
  if (view.rateLimits.length > 0) {
    const worst = view.rateLimits.reduce((a, b) => (b.percentUsed > a.percentUsed ? b : a))
    parts.push({ text: `${WINDOW_NAME[worst.kind] ?? worst.kind.replace(/_/g, ' ')} ${Math.round(worst.percentUsed)}%${stopNote}` })
  }
  if (view.contextPercent !== null) parts.push({ text: `context ${view.contextPercent}%` })
  if (view.handover) parts.push({ text: 'handover due', tone: 'alert' })
  return parts
}

export const bandText = (view: PanelView): string => stripParts(view).map(p => p.text).join(' · ')

// The approved render's strip and card tints.
const STRIP_BG = '#1d2230'
const CARD_BG = '#141821'

const TONE_COLOR = { ask: 'warning', merge: 'success', alert: 'error' } as const

export function Band(t: Table, view: PanelView, isHeld: boolean) {
  const { Box, Text } = t
  const parts = stripParts(view)
  return (
    <Box flexDirection="row" paddingX={1} backgroundColor={STRIP_BG}>
      {isHeld && <Text color="warning">◷ wake held · </Text>}
      {parts.map((p, i) => (
        <Box flexDirection="row">
          {i > 0 && <Text dimColor> · </Text>}
          <Text bold={p.tone !== undefined} color={p.tone ? TONE_COLOR[p.tone] : undefined}>
            {p.text}
          </Text>
        </Box>
      ))}
    </Box>
  )
}

function Section(t: Table, title: string, rows: string[], empty = '') {
  const { Box, Text } = t
  return (
    <Box flexDirection="column" marginBottom={1} paddingX={1} backgroundColor={CARD_BG}>
      <Text bold>{title}</Text>
      {rows.length === 0 ? <Text dimColor>{empty}</Text> : rows.map(r => <Text>{r}</Text>)}
    </Box>
  )
}

// The total is the search's own count, which can exceed the rows read.
function capped(rows: string[], total: number): string[] {
  const shown = rows.slice(0, REVIEWS_SHOWN)
  return total > shown.length ? [...shown, `+${total - shown.length} more`] : shown
}

// The repository is named only when the lists span more than one.
function reviewSections(t: Table, r: PanelReviews) {
  if (!r.isAvailable) return [Section(t, 'Reviews', [`Unavailable: ${r.reason || 'no reason given'}`])]
  const isMulti = new Set([...r.mine, ...r.waiting].map(p => p.repo)).size > 1
  const ref = (p: { repo: string; number: number; isDraft: boolean }) =>
    `${isMulti ? p.repo : ''}#${p.number} ${p.isDraft ? 'draft' : 'ready'}`
  const read = r.age === null ? '' : ` · read ${age(r.age)} ago`
  const mineTotal = Math.max(r.mineTotal ?? 0, r.mine.length)
  const waitingTotal = Math.max(r.waitingTotal ?? 0, r.waiting.length)
  return [
    Section(
      t,
      `My open PRs (${mineTotal})${read}`,
      capped(
        r.mine.map(p =>
          [
            ref(p),
            p.ci === 'none' ? 'no CI' : `CI ${p.ci}`,
            `${p.unresolved} unresolved`,
            p.isHeadReviewed ? 'head reviewed' : 'head not reviewed',
            p.reviewers.length > 0 ? `asks ${p.reviewers.join(', ')}` : 'no reviewer requested',
            p.title,
          ].join(' · '),
        ),
        mineTotal,
      ),
      'No open pull requests.',
    ),
    Section(
      t,
      `Waiting on my review (${waitingTotal})`,
      capped(
        r.waiting.map(p => [ref(p), `from ${p.requester}`, age(p.age), p.title].join(' · ')),
        waitingTotal,
      ),
      'Nothing waiting on your review.',
    ),
  ]
}

// Prop pal: a cell-grid picture where the surface has one, else the text art.
// Its state word always shows, so no state rests on the picture.
function Mascot(t: Table, view: PanelView, surface: RenderSurface) {
  const { Box, Text } = t
  const word = <Text color={mascotState(view) === 'bumpy' ? 'warning' : undefined}>{mascotWord(view)}</Text>
  if (hasPictures(t, surface)) {
    const g = spriteCells(mascotState(view), 0)
    return (
      <Box flexDirection="column" marginBottom={1}>
        <t.Raster key="prop-pal" columns={g.columns} rows={g.rows} cells={g.cells} />
        {word}
      </Box>
    )
  }
  return (
    <Box flexDirection="column" marginBottom={1}>
      {mascotLines(view).map(l => (
        <Text color={mascotState(view) === 'bumpy' ? 'warning' : undefined}>{l}</Text>
      ))}
    </Box>
  )
}


export function Pane(t: Table, view: PanelView, isHeld: boolean, surface: RenderSurface = 'terminal') {
  const { Box, Text } = t
  const d = view.digest
  if (!d) {
    return (
      <Box flexDirection="column">
        <Text bold>✈ Mission control · {view.program}</Text>
        <Text dimColor>{view.fault ? `No reading: ${view.fault}` : 'Waiting for the first reading.'}</Text>
      </Box>
    )
  }
  const tight = headroomTight(view)
  const health = d.health ?? []
  const instruments = [
    `compactions since start ${view.compactions} · wakes ${view.wakes}`,
    kbLine(view),
    ...d.measures.map(m =>
      m.name === '-' ? `measures ${m.value}` : `${m.name.replace(/_/g, ' ')} ${m.value} (${age(m.age)} old)`,
    ),
    `failsafe tick ${view.lastTickAt === null ? 'not yet fired' : `fired ${view.ticks}×`}`,
  ]
  return (
    <Box flexDirection="column">
      <Box flexDirection="row" justifyContent="space-between" marginBottom={1}>
        <Text bold>✈ Mission control · {view.program}</Text>
        {isHeld && <Text color="warning">◷ wake held</Text>}
      </Box>
      {view.handover && (
        <Text color="warning">
          Handover due: {view.handover}
        </Text>
      )}
      {view.fault && (
        <Text color="error">
          Fault: {view.fault}
        </Text>
      )}
      {d.unreadable.length > 0 && <Text color="error">Unreadable: {d.unreadable.join(', ')}</Text>}
      {health.length > 0 && (
        <Box flexDirection="column" marginBottom={1}>
          <Text bold color="warning">
            Health
          </Text>
          {health.map(check => (
            <Text color={check.count === null ? 'error' : 'warning'}>{check.text}</Text>
          ))}
        </Box>
      )}
      {mascotMode(view) !== 0 && Mascot(t, view, surface)}
      {Section(
        t,
        'Right now',
        readouts(view).map(r => r.text),
      )}
      {Section(
        t,
        'Waiting on you',
        [
          `${d.waiting === null ? 'unknown' : d.waiting} waiting on you`,
          ...[mergeReadyCount(d)].flatMap(n => (n === null ? [] : [`${n} ready to merge`])),
          ...(d.approvals ? [`${d.approvals} ${d.approvals === 1 ? 'approval' : 'approvals'} mission control is handling`] : []),
          ...(d.pending !== null ? [`${d.pending} event(s) inbound`] : []),
        ],
      )}
      {Section(
        t,
        `In flight (${flightCount(view)})`,
        [
          ...flightLines(d.flights),
          ...(d.finished ? [`${d.finished} finished, not cleaned up`] : []),
        ],
        d.unreadable.includes('tmux windows') ? '' : 'Nothing in flight.',
      )}
      {d.reviews && reviewSections(t, d.reviews)}
      {Section(
        t,
        'Tower log',
        d.decisions.slice(0, DECISIONS_SHOWN).map(x => `${x.time.slice(0, 16).replace('T', ' ')}  ${x.subject}: ${x.act}`),
        'No decisions recorded yet.',
      )}
      {Section(
        t,
        `Fuel · rung ${d.rung.name}`,
        [
          ...(d.rung.reason ? [d.rung.reason] : []),
          ...(tight ? [`tightest: ${tight}`] : []),
          ...counted(
            d.watchers.map(w => `${w.duty.replace(/-/g, ' ')} ${w.state}, next ${w.next === null ? 'unknown' : age(w.next)}`),
          ).slice(0, WATCHERS_SHOWN),
        ],
        'No budget computed yet.',
      )}
      {Section(
        t,
        'Weather · sources',
        d.sources.map(s => `${s.cls}: ${s.source === '-' ? 'none' : s.source} ${s.mode}${s.age === null ? '' : `, ${age(s.age)} old`}`),
        'No source map.',
      )}
      {Section(t, 'Instruments', instruments)}
    </Box>
  )
}
