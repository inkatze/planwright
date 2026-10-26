import type { Elements, RenderSurface } from 'claude-code'

import type { PanelView } from '../../types'
import { age } from './digest'

type Table = Elements[RenderSurface]

// A radar sweep, advanced only while a wake is held for a busy session.
const SWEEP = ['◜', '◝', '◞', '◟']

const DECISIONS_SHOWN = 3
const WATCHERS_SHOWN = 4

function headroomTight(view: PanelView): string | null {
  const rows = view.digest?.headroom ?? []
  if (rows.length === 0) return null
  const top = rows.reduce((a, b) => (b.percent > a.percent ? b : a))
  return `${top.dimension} ${top.percent}%`
}

function limits(view: PanelView): string {
  return view.rateLimits.map(r => `${r.kind} ${Math.round(r.percentUsed)}%`).join(' · ')
}

export function bandText(view: PanelView): string {
  const d = view.digest
  const parts = [`✈ ${view.program}`]
  if (d) {
    parts.push(`${d.flights.length} in flight`, `${d.waiting ?? '?'} holding`)
    if (d.pending !== null && d.pending > 0) parts.push(`${d.pending} inbound`)
    parts.push(`rung ${d.rung.name}`)
  } else {
    parts.push('no reading yet')
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

function Section(t: Table, title: string, rows: string[], empty: string) {
  const { Box, Text } = t
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>{title}</Text>
      {rows.length === 0 ? <Text dimColor>{empty}</Text> : rows.map(r => <Text>{r}</Text>)}
    </Box>
  )
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
  const instruments = [
    `context ${view.contextPercent === null ? 'not measured' : `${view.contextPercent}%`}${
      limits(view) ? ` · ${limits(view)}` : ''
    }`,
    `compactions since start ${view.compactions} · wakes ${view.wakes}`,
    `knowledge base ${d.kbAge === null ? 'not written yet' : `${age(d.kbAge)} old`}`,
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
          Last reading failed: {view.fault}
        </Text>
      )}
      {d.unreadable.length > 0 && <Text color="error">Unreadable: {d.unreadable.join(', ')}</Text>}
      {Section(
        t,
        `In flight (${d.flights.length})`,
        d.flights.map(f => `${f.worker}  ${f.scope}  ${f.backend}`),
        'Nothing in flight.',
      )}
      {Section(
        t,
        'Holding for you',
        [
          `${d.waiting === null ? 'unknown' : d.waiting} waiting on you`,
          ...(d.pending !== null ? [`${d.pending} event(s) inbound`] : []),
        ],
        '',
      )}
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
          ...d.watchers
            .slice(0, WATCHERS_SHOWN)
            .map(w => `${w.duty}/${w.script} ${w.state}, next ${w.next === null ? 'unknown' : age(w.next)}`),
        ],
        'No budget computed yet.',
      )}
      {Section(
        t,
        'Weather · sources',
        d.sources.map(s => `${s.cls}: ${s.source === '-' ? 'none' : s.source} ${s.mode}${s.age === null ? '' : `, ${age(s.age)} old`}`),
        'No source map.',
      )}
      {Section(t, 'Instruments', instruments, '')}
    </Box>
  )
}
