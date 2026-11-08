import type { Elements, RenderSurface } from 'claude-code'

import type { PanelDigest, PanelReviews, PanelView } from '../../types'
import { age, counted, flightLines } from './digest'

type Table = Elements[RenderSurface]

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

export function Pane(t: Table, view: PanelView, isHeld: boolean) {
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
        `In flight (${flightCount(view)})`,
        [
          ...flightLines(d.flights),
          ...(d.finished ? [`${d.finished} finished, not cleaned up`] : []),
        ],
        d.unreadable.includes('tmux windows') ? '' : 'Nothing in flight.',
      )}
      {Section(
        t,
        'Holding for you',
        [
          `${d.waiting === null ? 'unknown' : d.waiting} waiting on you`,
          ...[mergeReadyCount(d)].flatMap(n => (n === null ? [] : [`${n} ready to merge`])),
          ...(d.approvals ? [`${d.approvals} ${d.approvals === 1 ? 'approval' : 'approvals'} mission control is handling`] : []),
          ...(d.pending !== null ? [`${d.pending} event(s) inbound`] : []),
        ],
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
