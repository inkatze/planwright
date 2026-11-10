import type { Elements, RenderSurface } from 'claude-code'

import type { PanelDigest, PanelMergeCommand, PanelReviews, PanelView } from '../../types'
import { age, flightRows } from './digest'
import { restFrame, spriteCells } from './panel-art'

type Table = Elements[RenderSurface]
type PictureTable = Elements['terminal']

// Only the terminal surface carries Raster and Image; elsewhere the text stands.
// The resolved table answers `in` for any name, so the surface is what decides.
const hasPictures = (t: Table, surface: RenderSurface): t is PictureTable => surface === 'terminal' && 'Raster' in t

const REVIEWS_SHOWN = 5
const STALE_READ_S = 600
const DECISIONS_SHOWN = 3

// A count from a store the digest could not read is unknown, never zero.
function flightCount(view: PanelView): string {
  const d = view.digest
  if (!d) return '?'
  if (d.unreadable.includes('fleet registry')) return '?'
  // Windows of a tmux server that did not answer may hold more; without the
  // attention store an idle session reads live, so there may be fewer.
  const isFloor = d.unreadable.includes('tmux windows')
  const isCeiling = d.unreadable.includes('attention store')
  const n = flightRows(d.flights, view.program).filter(r => r.state !== 'waiting').length
  return isFloor && isCeiling ? '?' : isFloor ? `${n}+` : isCeiling ? `up to ${n}` : String(n)
}

// The pull requests ready to merge, a floor (`3+`) or `?` when some could
// not be judged; null when there is nothing to say.
// A ready verdict outlives the merge by up to the store's age, so a pull
// request the complete open list no longer holds is merged or closed: it is
// dropped. A list cut short proves nothing about what it leaves out.
function liveCommands(d: PanelDigest): PanelMergeCommand[] {
  const all = d.mergeCommands ?? []
  const r = d.reviews
  if (!r || !r.isAvailable || r.mine.length < (r.mineTotal ?? 0)) return all
  return all.filter(c => r.mine.some(p => p.repo === c.repo && p.number === c.number))
}

const liveMergeReady = (d: PanelDigest): number =>
  Math.max((d.mergeReady ?? 0) - ((d.mergeCommands ?? []).length - liveCommands(d).length), 0)

function mergeReadyCount(d: PanelDigest): string | null {
  if (d.unreadable.includes('merge-ready store')) return '?'
  const n = liveMergeReady(d)
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
// The weekly window first: it is the limit the operator plans around.
const byWindow = <T extends { kind: string }>(limits: T[]): T[] =>
  [...limits].sort((a, b) => Number(b.kind === 'seven_day') - Number(a.kind === 'seven_day'))
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
  for (const r of byWindow(view.rateLimits)) {
    const name = WINDOW_NAME[r.kind] ?? r.kind.replace(/_/g, ' ')
    const pct = Math.round(r.percentUsed)
    out.push(
      line(`${name[0]!.toUpperCase()}${name.slice(1)} usage ${pct}% · ${stopWord(stop)}`, stop === null ? 'UNKNOWN' : typeof stop === 'number' && pct >= stop ? 'ACT' : 'OK'),
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
  else {
    // The Waiting on you card lists the pull requests to merge too, so the
    // readout names them rather than counting questions alone.
    const ready = mergeReadyCount(d)
    const toMerge = ready === null ? '' : `, ${ready} to merge`
    const asks = d.waiting === 0 ? 'none' : toMerge ? `${d.waiting} ${d.waiting === 1 ? 'question' : 'questions'}` : d.waiting
    out.push(line(`Waiting on you ${asks}${toMerge}`, d.waiting > 0 || ready !== null ? 'ACT' : 'OK'))
  }
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
  cruising: 'flying, sessions working',
  taxiing: 'taxiing, nothing running',
}

// Whether the mascot has motion to repaint: every state moves (taxiing rolls),
// so animation on and a reading in is all it takes.
export function isMascotMoving(view: PanelView): boolean {
  return mascotMode(view) === 2 && view.digest !== null
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
  }
  if (view.fault && d) parts.push({ text: `fault: ${view.fault}`, tone: 'alert' })
  if (d && parts.length === 0) parts.push({ text: 'all clear' })
  const stop = usageStop(view)
  const stopNote = typeof stop === 'number' ? ` (stop ${stop}%)` : ''
  byWindow(view.rateLimits).forEach((r, i) => {
    parts.push({ text: `${WINDOW_NAME[r.kind] ?? r.kind.replace(/_/g, ' ')} ${Math.round(r.percentUsed)}%${i === 0 ? stopNote : ''}` })
  })
  if (view.contextPercent !== null) parts.push({ text: `context ${view.contextPercent}%` })
  if (view.handover) parts.push({ text: 'handover due', tone: 'alert' })
  return parts
}

export const bandText = (view: PanelView): string => stripParts(view).map(p => p.text).join(' · ')

// The approved render's strip and card tints.
const STRIP_BG = '#1d2230'
const CARD_BG = '#141821'

const TONE_COLOR = { ask: 'warning', merge: 'success', alert: 'error' } as const
type TextColor = (typeof TONE_COLOR)[keyof typeof TONE_COLOR]
type LineStyle = { bold?: boolean; dimColor?: boolean; color?: TextColor }

// A Text paints only the cells it holds, so a short row would leave a gap in
// its card's colour. Every row therefore carries its colour across the whole
// width, a one-cell margin each side, and wraps at the word boundary inside it.
// Terminal cells: a wide glyph (CJK, most emoji) takes two.
const isWide = (c: number): boolean =>
  (c >= 0x1100 && c <= 0x115f) ||
  (c >= 0x2e80 && c <= 0xa4cf) ||
  (c >= 0xac00 && c <= 0xd7a3) ||
  (c >= 0xf900 && c <= 0xfaff) ||
  (c >= 0xfe30 && c <= 0xfe4f) ||
  (c >= 0xff00 && c <= 0xff60) ||
  (c >= 0xffe0 && c <= 0xffe6) ||
  (c >= 0x1f300 && c <= 0x1f64f) ||
  (c >= 0x1f680 && c <= 0x1f6ff) ||
  (c >= 0x1f900 && c <= 0x1f9ff) ||
  (c >= 0x20000 && c <= 0x3fffd)
export const cellsOf = (s: string): number => [...s].reduce((n, ch) => n + (isWide(ch.codePointAt(0) ?? 0) ? 2 : 1), 0)

// The longest run of leading characters that fits in n cells, at least one
// character so a wide glyph in a one-cell row still moves the text on.
function splitCells(s: string, n: number): [string, string] {
  const chars = [...s]
  let head = ''
  let w = 0
  let i = 0
  for (; i < chars.length; i++) {
    const cw = cellsOf(chars[i]!)
    if (w + cw > n && i > 0) break
    head += chars[i]
    w += cw
  }
  return [head, chars.slice(i).join('')]
}

export function wrapRows(text: string, inner: number): string[] {
  const rows: string[] = []
  let cur = ''
  for (const word of text.split(' ')) {
    let rest = word
    while (cellsOf(rest) > inner) {
      if (cur !== '') {
        rows.push(cur)
        cur = ''
      }
      const [head, tail] = splitCells(rest, inner)
      rows.push(head)
      rest = tail
    }
    const next = cur === '' ? rest : `${cur} ${rest}`
    if (cellsOf(next) <= inner) cur = next
    else {
      rows.push(cur)
      cur = rest
    }
  }
  if (cur !== '' || rows.length === 0) rows.push(cur)
  return rows
}

function Painted(t: Table, text: string, width: number, bg: string, style: LineStyle = {}) {
  const { Box, Text } = t
  return wrapRows(text, Math.max(1, width - 2)).map(row => (
    <Box flexDirection="row" backgroundColor={bg}>
      <Text backgroundColor={bg}>{' '}</Text>
      <Text backgroundColor={bg} bold={style.bold} dimColor={style.dimColor} color={style.color}>
        {row}
      </Text>
      <Text backgroundColor={bg}>{' '.repeat(Math.max(0, width - 1 - cellsOf(row)))}</Text>
    </Box>
  ))
}

type CardLine = { text: string } & LineStyle

function Card(t: Table, width: number, title: string, lines: CardLine[]) {
  const { Box } = t
  return (
    <Box flexDirection="column" marginBottom={1} backgroundColor={CARD_BG}>
      {Painted(t, title, width, CARD_BG, { bold: true })}
      {lines.flatMap(l => Painted(t, l.text, width, CARD_BG, l))}
    </Box>
  )
}

function Section(t: Table, width: number, title: string, rows: string[], empty = '') {
  return Card(
    t,
    width,
    title,
    rows.length === 0 ? [{ text: empty, dimColor: true }] : rows.map(text => ({ text })),
  )
}

export function Band(t: Table, view: PanelView, isHeld: boolean, width: number) {
  const { Box, Text } = t
  const segments: ({ text: string } & LineStyle)[] = []
  if (isHeld) segments.push({ text: '◷ wake held · ', color: 'warning' })
  stripParts(view).forEach((p, i) => {
    if (i > 0) segments.push({ text: ' · ', dimColor: true })
    segments.push({ text: p.text, bold: p.tone !== undefined, color: p.tone ? TONE_COLOR[p.tone] : undefined })
  })
  const used = 1 + segments.reduce((n, s) => n + cellsOf(s.text), 0)
  return (
    <Box flexDirection="row" backgroundColor={STRIP_BG}>
      <Text backgroundColor={STRIP_BG}>{' '}</Text>
      {segments.map((s, i) => (
        <Text key={i} backgroundColor={STRIP_BG} bold={s.bold} dimColor={s.dimColor} color={s.color}>
          {s.text}
        </Text>
      ))}
      <Text backgroundColor={STRIP_BG}>{' '.repeat(Math.max(0, width - used))}</Text>
    </Box>
  )
}

const PR_GROUPS = [
  { id: 'ready', title: 'Ready to merge' },
  { id: 'needs-you', title: 'Needs you' },
  { id: 'review', title: 'In review' },
  { id: 'running', title: 'CI running' },
  { id: 'failed', title: 'CI failed' },
] as const
type PrGroup = (typeof PR_GROUPS)[number]['id']
type PrRow = { group: PrGroup; text: string; command: string | null }

const threads = (n: number) => `${n} review ${n === 1 ? 'thread' : 'threads'} still open`

// My open pull requests by where each stands against the operator's ready
// conditions, the first unmet one named. A pull request the readiness check
// passed carries its checked merge command; the rest are read from the
// reviews snapshot, so a sign-off or screenshot the check would still ask for
// shows as "needs you" once everything else holds.
export function prRows(reviews: PanelReviews, commands: PanelMergeCommand[], isJudged = true): PrRow[] {
  const isMulti = new Set([...reviews.mine, ...reviews.waiting].map(p => p.repo)).size > 1
  return reviews.mine.map(p => {
    const ref = `${isMulti ? p.repo : ''}#${p.number} ${p.title}`
    const command = commands.find(c => c.repo === p.repo && c.number === p.number)?.command ?? null
    const row = (group: PrGroup, unmet: string): PrRow => ({ group, text: unmet ? `${ref} · ${unmet}` : ref, command })
    // The snapshot is the fresher read: a verdict kept from before a CI run or
    // a new thread does not stand over what the snapshot now shows.
    if (p.ci === 'red') return row('failed', 'CI failed')
    if (p.ci === 'running') return row('running', 'CI still running')
    if (p.unresolved > 0) return row('review', threads(p.unresolved))
    if (command !== null) return row('ready', '')
    if (p.ci === 'none') return row('review', 'no CI reported yet')
    if (!p.isHeadReviewed) return row('review', 'head not reviewed yet')
    if (!isJudged) return row('review', 'readiness not judged yet')
    return row('needs-you', p.isDraft ? 'a draft waiting for your yes' : 'waiting for your sign-off')
  })
}

function PullRequests(t: Table, view: PanelView, width: number) {
  const r = view.digest?.reviews
  if (!r) return null
  if (!r.isAvailable) {
    return Card(t, width, 'Pull requests', [{ text: `Unavailable: ${r.reason || 'no reason given'}`, dimColor: true }])
  }
  const d = view.digest
  const isJudged = !d?.unreadable.includes('merge-ready store') && !d?.isMergeReadyPartial
  const rows = prRows(r, d?.mergeCommands ?? [], isJudged)
  const total = Math.max(r.mineTotal ?? 0, r.mine.length)
  // A stale snapshot shows its age; a fresh one needs no caption.
  const stale = r.age !== null && r.age >= STALE_READ_S ? ` · read ${age(r.age)} ago` : ''
  const title = `Pull requests (${total})${stale}`
  if (rows.length === 0) {
    return Card(t, width, title, [{ text: total === 0 ? 'No open pull requests.' : `${total} open, none listed`, dimColor: true }])
  }
  const lines: CardLine[] = []
  // Only what the operator must act on is listed: a ready pull request or one
  // awaiting their decision. The rest are counted, never named. A ready one
  // the Waiting on you card already names is counted there, not listed twice.
  const isNamedAbove = d ? namedReady(d) !== null : false
  const hidden = isNamedAbove ? rows.filter(x => x.group === 'ready').length : 0
  const mine = rows.filter(x => x.group === 'needs-you' || (x.group === 'ready' && !isNamedAbove))
  for (const g of PR_GROUPS.filter(x => x.id === 'ready' || x.id === 'needs-you')) {
    const inGroup = mine.filter(x => x.group === g.id)
    if (inGroup.length === 0) continue
    lines.push({ text: g.title, bold: true })
    for (const x of inGroup) {
      lines.push({ text: x.text })
      if (x.command) lines.push({ text: `run: ${x.command}` })
    }
  }
  const rest = total - mine.length - hidden
  if (hidden > 0 && mine.length === 0) {
    lines.push({ text: `${hidden} ready to merge, named under Waiting on you`, dimColor: true })
  }
  if (rest > 0) {
    const noun = rest === 1 ? 'request needs' : 'requests need'
    lines.push({ text: `${mine.length === 0 ? '' : '+ '}${rest} other pull ${noun} nothing from you`, dimColor: true })
  }
  return Card(t, width, title, lines)
}

// A pull request's title by number, from either reviews list, for the rows
// that name a review by its pull request.
const prTitle = (d: PanelDigest) => (n: number): string | undefined =>
  [...(d.reviews?.mine ?? []), ...(d.reviews?.waiting ?? [])].find(p => p.number === n)?.title

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`

// One plain overview: how many sessions work, and what, if anything, is the
// operator's to do. An unknown count is said as such, never as none.
function summary(view: PanelView): string {
  const d = view.digest!
  const n = flightCount(view)
  // Counted from the rows In flight shows: a session not responding is not working.
  const stuck = flightRows(d.flights, view.program).filter(r => r.state === 'stuck').length
  const busy = /^[0-9]+$/.test(n) ? Number(n) - stuck : 0
  const stuckNote = stuck > 0 ? `, ${stuck} ${stuck === 1 ? 'is' : 'are'} not responding` : ''
  const working = /^[0-9]+$/.test(n)
    ? `${busy === 0 ? 'No sessions are' : plural(busy, 'session is', 'sessions are')} working${stuckNote}.`
    : `Sessions working: ${n === '?' ? 'unknown' : n}.`
  const ready = mergeReadyCount(d)
  const readyN = ready === null ? 0 : /^[0-9]+$/.test(ready) ? Number(ready) : null
  if (d.waiting === null || readyN === null) return `${working} What needs you could not be fully read.`
  const asks = [
    ...(d.waiting > 0 ? [`${plural(d.waiting, 'question waits', 'questions wait')} for your answer`] : []),
    ...(readyN > 0 ? [`${plural(readyN, 'pull request is', 'pull requests are')} ready for you to merge`] : []),
  ]
  return `${working} ${asks.length === 0 ? 'Nothing needs you right now.' : `${asks.join(', and ')}.`}`
}

// The pull requests waiting on the operator's own review.
function reviewRequests(t: Table, r: PanelReviews, width: number) {
  if (!r.isAvailable) return null
  const isMulti = new Set([...r.mine, ...r.waiting].map(p => p.repo)).size > 1
  const total = Math.max(r.waitingTotal ?? 0, r.waiting.length)
  const shown = r.waiting.slice(0, REVIEWS_SHOWN).map(p => `${isMulti ? p.repo : ''}#${p.number} ${p.title} · from ${p.requester} · ${age(p.age)}`)
  return Section(
    t,
    width,
    `Waiting on my review (${total})`,
    total > shown.length ? [...shown, `+${total - shown.length} more`] : shown,
    'Nothing waiting on your review.',
  )
}

// Prop pal: a cell-grid picture where the surface has one, drawn alone (the
// Waiting on you section says the rest); else the text art with its state
// word, so no state rests on a picture the surface cannot draw.
function Mascot(t: Table, view: PanelView, surface: RenderSurface) {
  const { Box, Text } = t
  if (hasPictures(t, surface)) {
    const g = spriteCells(mascotState(view), restFrame(mascotState(view)))
    return (
      <Box flexDirection="column" marginBottom={1}>
        <t.Raster key="prop-pal" columns={g.columns} rows={g.rows} cells={g.cells} />
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

// One row per item that waits on the operator: each session waiting on an
// answer, then the queued questions no such session asks, each named by its
// question; a count stands for any beyond those.
function waitingRows(view: PanelView): string[] {
  const d = view.digest!
  const sessions = flightRows(d.flights, view.program, prTitle(d)).filter(r => r.state === 'waiting')
  const sessionWorkers = new Set(d.flights.filter(f => f.state === 'waiting').map(f => f.worker))
  const rows = sessions.map(r => r.text)
  if (d.waiting === null) return [...rows, 'unknown whether more wait on you']
  const rest = d.waiting - rows.length
  const queued = (d.queued ?? []).filter(q => !sessionWorkers.has(q.worker)).map(q => `${q.question} · waiting for an answer`)
  const named = queued.slice(0, Math.max(rest, 0))
  const unnamed = Math.max(rest - named.length, 0)
  const all = [...rows, ...named, ...(unnamed > 0 ? [`${unnamed} waiting on you, not in a session`] : [])]
  return all.length === 0 ? ['Nothing waits on you.'] : all
}

// The pull requests the readiness check passed, each named; the count stands
// where they cannot all be named.
// A ready pull request shows once: named here with its merge command when the
// store was read in full and every one has a command, else only counted here
// and left to the Pull requests card to name.
function namedReady(d: PanelDigest): PanelMergeCommand[] | null {
  if (mergeReadyCount(d) === null) return null
  const commands = liveCommands(d)
  const isNamed = !d.isMergeReadyPartial && !d.unreadable.includes('merge-ready store') && commands.length === liveMergeReady(d)
  return isNamed ? commands : null
}

function readyRows(view: PanelView): CardLine[] {
  const d = view.digest!
  const toMerge = mergeReadyCount(d)
  if (toMerge === null) return []
  const commands = namedReady(d)
  if (commands === null) return [{ text: `${toMerge} ready to merge` }]
  const isMulti = new Set(commands.map(c => c.repo)).size > 1
  return commands.flatMap(c => {
    const pr = d.reviews?.mine.find(p => p.repo === c.repo && p.number === c.number)
    return [{ text: `${isMulti ? `${c.repo} ` : ''}#${c.number}${pr ? ` ${pr.title}` : ''} · ready to merge` }, { text: `run: ${c.command}` }]
  })
}

// One plain name per limit the budget script emits (scripts/mc-budget.sh
// DIMENSIONS); tests/test-mc-budget.sh holds the two lists together.
const HEADROOM_NAME: Record<string, string> = {
  sessions: 'Sessions running',
  polls_per_hour: 'Checks per hour',
  context_steps: 'Mission control steps',
  host_load: 'Machine load',
}

// Machine load is a percent of the processors, so it reads as a percent of its
// limit; the other limits are counts.
function headroomRow(h: { dimension: string; used: number; limit: number; percent: number }): string {
  const name = HEADROOM_NAME[h.dimension] ?? h.dimension.replace(/_/g, ' ')
  return h.dimension === 'host_load' ? `${name}: ${h.used}% of the ${h.limit}% limit` : `${name}: ${h.used} of ${h.limit} (${h.percent}%)`
}

// The low-signal facts, plainly worded, in one compact card: how much of each
// limit is used, how often the session's context has been reset, and how
// fresh mission control's notes are.
function upkeep(view: PanelView): string[] {
  const d = view.digest!
  const notes = d.unreadable.includes('knowledge base')
    ? 'Notes unreadable'
    : d.kbAge == null
      ? 'Notes not written yet'
      : `Notes last updated ${age(d.kbAge)} ago`
  return [
    ...d.headroom.map(headroomRow),
    `Context resets since start: ${view.compactions}`,
    notes,
  ]
}

export function Pane(t: Table, view: PanelView, isHeld: boolean, surface: RenderSurface, width: number) {
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
  const health = d.health ?? []
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
      {Section(t, width, "What's going on", [summary(view)])}
      {Section(t, width, 'Right now', readouts(view).map(r => r.text))}
      {Card(t, width, 'Waiting on you', [...waitingRows(view).map(text => ({ text })), ...readyRows(view)])}
      {Section(
        t,
        width,
        `In flight (${flightCount(view)})`,
        [
          ...flightRows(d.flights, view.program, prTitle(d)).filter(r => r.state !== 'waiting').map(r => r.text),
          ...(d.finished ? [`${d.finished} finished, not cleaned up`] : []),
        ],
        d.unreadable.includes('tmux windows') ? '' : 'Nothing in flight.',
      )}
      {PullRequests(t, view, width)}
      {d.reviews && reviewRequests(t, d.reviews, width)}
      {Section(
        t,
        width,
        'Recent decisions',
        d.decisions.slice(0, DECISIONS_SHOWN).map(x => `${x.time.slice(0, 16).replace('T', ' ')}  ${x.act || x.subject}`),
        'No decisions recorded yet.',
      )}
      {Section(t, width, 'Limits and upkeep', upkeep(view))}
      {mascotMode(view) !== 0 && Mascot(t, view, surface)}
    </Box>
  )
}
