import type { Elements, RenderSurface } from 'claude-code'

import type { PanelDigest, PanelReviews, PanelView } from '../../types'
import { age, counted, flightLines } from './digest'
import { barPicture, COLOR, gaugesPicture, spriteCells } from './panel-art'
import type { Instruments } from './panel-art'

type Table = Elements[RenderSurface]
type PictureTable = Elements['terminal']

// Only the terminal surface carries Raster and Image; elsewhere the text stands.
// The resolved table answers `in` for any name, so the surface is what decides.
const hasPictures = (t: Table, surface: RenderSurface): t is PictureTable => surface === 'terminal' && 'Raster' in t

// A radar sweep, advanced only while a wake is held for a busy session.
const SWEEP = ['◜', '◝', '◞', '◟']

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

function limits(view: PanelView): string {
  return view.rateLimits.map(r => `${r.kind} ${Math.round(r.percentUsed)}%`).join(' · ')
}

// The pull requests ready to merge, a floor (`3+`) or `?` when some could
// not be judged; null when there is nothing to say.
function mergeReadyCount(d: PanelDigest): string | null {
  if (d.unreadable.includes('merge-ready store')) return '?'
  const n = d.mergeReady ?? 0
  if (d.isMergeReadyPartial) return n > 0 ? `${n}+` : '?'
  return n > 0 ? String(n) : null
}

const BAR_CELLS = 10
// Past this a deferred compaction would risk the window itself.
const CONTEXT_CEILING_PCT = 95
const DIAL = ['○', '◔', '◑', '◕', '●']

// A bar of filled cells; each mark, a percent, is drawn over the cell it falls in.
function bar(percent: number, marks: number[] = []): string {
  const clamped = Math.max(0, Math.min(100, percent))
  const filled = Math.round((clamped / 100) * BAR_CELLS)
  const cells = Array.from({ length: BAR_CELLS }, (_, i) => (i < filled ? '█' : '░'))
  for (const m of marks) cells[Math.min(BAR_CELLS - 1, Math.floor((m / 100) * BAR_CELLS))] = '▲'
  return `[${cells.join('')}]`
}

// A round dial: the quarter-filled circle nearest the fraction.
function dial(fraction: number): string {
  return DIAL[Math.max(0, Math.min(DIAL.length - 1, Math.round(fraction * (DIAL.length - 1))))]!
}

// The master caution lamp: lit for anything that needs the operator or is
// out of bounds, with its reasons in words; unknown where nothing was read.
export function cautionReasons(view: PanelView): string[] | null {
  const d = view.digest
  if (!d) return null
  const why: string[] = []
  if (d.waiting !== null && d.waiting > 0) why.push(`${d.waiting} waiting on you`)
  if (view.handover) why.push('handover due')
  const checks = new Set((d.health ?? []).map(h => h.check)).size
  if (checks > 0) why.push(`${checks} health ${checks === 1 ? 'check' : 'checks'}`)
  if (d.unreadable.length > 0) why.push(`${d.unreadable.length} unreadable`)
  if (view.fault) why.push('fault')
  if (why.length === 0 && d.waiting === null) return null
  return why
}

// The instrument row, round and bar shapes alternating: usage left (bar),
// host load (dial with a redline), memory (bar), context (altimeter with its
// handover and window marks), caution lamp. Every one says its number and
// its state in words, so none rests on colour.
export function instrumentLines(view: PanelView): string[] {
  const d = view.digest
  const lines: string[] = []

  if (view.rateLimits.length === 0) {
    lines.push('Usage left   no limits reported')
  } else {
    const worst = view.rateLimits.reduce((a, b) => (b.percentUsed > a.percentUsed ? b : a))
    const left = Math.max(0, 100 - Math.round(worst.percentUsed))
    lines.push(`Usage left   ${bar(left)} ${left}% left of ${worst.kind.replace(/_/g, ' ')}`)
  }

  const host = d?.host
  if (host?.load != null && host.cores != null) {
    const ratio = host.load / 100 / host.cores
    const state = ratio >= 1 ? 'REDLINE, overloaded' : ratio >= 0.7 ? 'busy' : 'ok'
    lines.push(`Host load    ${dial(ratio)} ${(host.load / 100).toFixed(1)} on ${host.cores} cores, redline at ${host.cores}: ${state}`)
  } else {
    lines.push('Host load    unknown')
  }

  if (host?.memFreePercent != null) {
    lines.push(`Memory       ${bar(host.memFreePercent)} ${host.memFreePercent}% available${host.memFreePercent < 10 ? ': LOW' : ''}`)
  } else {
    lines.push('Memory       unknown')
  }

  if (view.contextPercent === null) {
    lines.push('Context      not measured')
  } else {
    const handoverAt = d?.holder === 'registry' ? d.knobs['handover-context'] : undefined
    const marks = [...(handoverAt === undefined ? [] : [handoverAt]), CONTEXT_CEILING_PCT]
    const notes = [
      ...(handoverAt === undefined ? [] : [`hands over at ${handoverAt}%`]),
      `window limit ${CONTEXT_CEILING_PCT}%`,
    ]
    lines.push(`Context      ${dial(view.contextPercent / 100)} ${bar(view.contextPercent, marks)} ${view.contextPercent}% used, ▲ ${notes.join(', ▲ ')}`)
  }

  const why = cautionReasons(view)
  lines.push(
    why === null ? 'Caution      ? unknown' : why.length === 0 ? 'Caution      ○ clear' : `Caution      ● LIT: ${why.join(', ')}`,
  )
  return lines
}

// The numbers the gauge picture draws, from the same readings the words say.
export function instruments(view: PanelView): Instruments {
  const d = view.digest
  const worst = view.rateLimits.length === 0 ? null : view.rateLimits.reduce((a, b) => (b.percentUsed > a.percentUsed ? b : a))
  const host = d?.host
  const handoverAt = d?.holder === 'registry' ? d.knobs['handover-context'] : undefined
  const why = cautionReasons(view)
  return {
    usageLeft: worst === null ? null : Math.max(0, 100 - Math.round(worst.percentUsed)),
    load: host?.load != null && host.cores != null ? { ratio: host.load / 100 / host.cores } : null,
    memory: host?.memFreePercent ?? null,
    context: view.contextPercent === null ? null : { percent: view.contextPercent, handoverAt, windowAt: CONTEXT_CEILING_PCT },
    caution: why === null ? 'unknown' : why.length === 0 ? 'clear' : 'lit',
  }
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

export function usageLines(view: PanelView, nowMs: number): { name: string; percent: number; text: string }[] {
  const stop = usageStop(view)
  return view.rateLimits.map(r => {
    const name = WINDOW_NAME[r.kind] ?? r.kind.replace(/_/g, ' ')
    const pct = Math.round(r.percentUsed)
    const reset = resetWord(r.resetsAt, nowMs)
    return { name, percent: r.percentUsed, text: `${name} ${pct}% used · ${stopWord(stop)}${reset ? ` · ${reset}` : ''}` }
  })
}

// The context line says what the bar's marks are, in words.
export function contextLine(view: PanelView): string {
  if (view.contextPercent === null) return 'Context not measured'
  const d = view.digest
  const handoverAt = d?.holder === 'registry' ? d.knobs['handover-context'] : undefined
  return [
    `Context ${view.contextPercent}% used`,
    ...(handoverAt === undefined ? [] : [`hands over at ${handoverAt}%`]),
    `compacts at ${CONTEXT_CEILING_PCT}%`,
  ].join(' · ')
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

export function bandText(view: PanelView): string {
  const d = view.digest
  const parts = [`✈ ${view.program}`]
  if (d) {
    parts.push(`${flightCount(view)} in flight`, `${d.waiting ?? '?'} holding`)
    const toMerge = mergeReadyCount(d)
    if (toMerge !== null) parts.push(`${toMerge} to merge`)
    if (d.pending !== null && d.pending > 0) parts.push(`${d.pending} inbound`)
    parts.push(`rung ${d.rung.name}`)
    // A check can say both what is past its bound and what it cannot tell.
    const checks = new Set((d.health ?? []).map(h => h.check)).size
    if (checks > 0) parts.push(`⚠ health ${checks}`)
  } else {
    parts.push(view.fault ? `no reading: ${view.fault}` : 'no reading yet')
  }
  if (view.contextPercent !== null) parts.push(`ctx ${view.contextPercent}%`)
  const rl = limits(view)
  if (rl) parts.push(rl)
  if (view.handover) parts.push('handover due')
  return parts.join(' · ')
}

export function Band(t: Table, view: PanelView, isHeld: boolean) {
  const { Box, Text } = t
  return (
    <Box flexDirection="row">
      {isHeld && <Text color="warning">{SWEEP[view.frame % SWEEP.length]} </Text>}
      <Text dimColor={!isHeld && !view.handover}>
        {bandText(view)}
      </Text>
    </Box>
  )
}

function Section(t: Table, title: string, rows: string[], empty = '') {
  const { Box, Text } = t
  return (
    <Box flexDirection="column" marginBottom={1}>
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
    const g = spriteCells(mascotState(view), mascotMode(view) === 2 ? view.frame : 0)
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

// The wake animation redraws twice a second; the instruments move far slower,
// so the last picture stands while its readings do.
let lastGauges: { key: string; picture: ReturnType<typeof gaugesPicture> } | null = null
function gaugesFor(i: Instruments) {
  const key = JSON.stringify(i)
  if (lastGauges?.key !== key) lastGauges = { key, picture: gaugesPicture(i) }
  return lastGauges.picture
}

const GAUGE_COLUMNS = 56
const GAUGE_ROWS = 5

// The five instruments as one picture; the words below say the same numbers.
function Gauges(t: PictureTable, view: PanelView) {
  const { Box } = t
  const g = gaugesFor(instruments(view))
  return (
    <Box flexDirection="column">
      <t.Image
        key="gauges"
        source={{ rgba: g.rgba, width: g.width, height: g.height }}
        columns={GAUGE_COLUMNS}
        rows={GAUGE_ROWS}
        alt="Instruments: usage left, host load, memory, context, caution; read below"
      />
    </Box>
  )
}

const BAR_COLUMNS = 56

// The context bar with its handover and compaction marks, and each usage
// window with its stop line and reset time. Each says its numbers in words;
// the bar is the picture of them, and marks differ by position and label.
function Meters(t: Table, view: PanelView, surface: RenderSurface) {
  const { Box, Text } = t
  const d = view.digest
  const isPic = hasPictures(t, surface)
  const handoverAt = d?.holder === 'registry' ? d.knobs['handover-context'] : undefined
  const windows = usageLines(view, Date.now())
  const stop = usageStop(view)
  const stopMark = typeof stop === 'number' ? [{ at: stop, color: COLOR.red }] : []
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>Context</Text>
      <Text>{contextLine(view)}</Text>
      {isPic && view.contextPercent !== null && (
        <t.Image
          key="context-bar"
          source={barPicture(view.contextPercent, COLOR.blue, [
            ...(handoverAt === undefined ? [] : [{ at: handoverAt, color: COLOR.yellow }]),
            { at: CONTEXT_CEILING_PCT, color: COLOR.red },
          ])}
          columns={BAR_COLUMNS}
          rows={1}
          alt={bar(view.contextPercent, [CONTEXT_CEILING_PCT])}
        />
      )}
      <Text bold>Usage</Text>
      {windows.length === 0 && <Text dimColor>No limits reported.</Text>}
      {windows.map(w => (
        <Box flexDirection="column">
          <Text>{w.text}</Text>
          {isPic && (
            <t.Image
              key={`usage-${w.name}`}
              source={barPicture(w.percent, typeof stop === 'number' && w.percent >= stop ? COLOR.red : w.percent >= 70 ? COLOR.yellow : COLOR.blue, stopMark)}
              columns={BAR_COLUMNS}
              rows={1}
              alt={bar(w.percent, typeof stop === 'number' ? [stop] : [])}
            />
          )}
        </Box>
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
  const rl = limits(view)
  const health = d.health ?? []
  const instruments = [
    `context ${view.contextPercent === null ? 'not measured' : `${view.contextPercent}%`}${rl ? ` · ${rl}` : ''}`,
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
        {isHeld && <Text color="warning">{SWEEP[view.frame % SWEEP.length]} wake held</Text>}
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
      {mascotMode(view) !== 0 && Mascot(t, view, surface)}
      {hasPictures(t, surface) && Gauges(t, view)}
      {Section(t, 'Cockpit', instrumentLines(view))}
      {Meters(t, view, surface)}
      {Section(t, 'Instruments', instruments)}
    </Box>
  )
}
