import type { PanelDigest, PanelFlight, PanelHealth, PanelView } from '../../types'

const PROGRAM = /^[a-z](?:[a-z0-9]|-(?=[a-z0-9])){0,63}$/
const HANDLE = /^[A-Za-z0-9._=@:-]{1,128}$/

export const isProgram = (s: string): boolean => PROGRAM.test(s)
export const isHandle = (s: string): boolean => HANDLE.test(s) && !s.startsWith('-') && s !== '.' && s !== '..'

const int = (s: string | undefined): number | null =>
  s !== undefined && /^-?[0-9]+$/.test(s) ? Number(s) : null

// The digest scripts/mc-panel.sh prints, one tab-separated record per line;
// an unknown record is skipped so an additive format change draws as before.
export function parseDigest(text: string): PanelDigest | null {
  const d: PanelDigest = {
    taken: 0,
    knobs: {},
    flights: [],
    finished: null,
    waiting: null,
    mergeReady: null,
    isMergeReadyPartial: false,
    mergeCommands: [],
    pending: null,
    approvals: null,
    decisions: [],
    rung: { name: '-', reason: '' },
    headroom: [],
    watchers: [],
    sources: [],
    kbAge: null,
    measures: [],
    reviews: null,
    host: { load: null, cores: null, memFreePercent: null },
    isHandoverInstalled: false,
    holder: null,
    unreadable: [],
    line: '',
  }
  const health: PanelHealth[] = []
  d.health = health
  let format = ''
  for (const row of text.split('\n')) {
    const f = row.split('\t')
    switch (f[0]) {
      case 'format':
        format = f[1] ?? ''
        break
      case 'taken':
        d.taken = int(f[1]) ?? 0
        break
      case 'knob': {
        const v = int(f[2])
        if (f[1] && v !== null) d.knobs[f[1]] = v
        break
      }
      case 'flight':
        d.flights.push({ worker: f[1] ?? '', scope: f[2] ?? '', backend: f[3] ?? '', state: f[4] === 'waiting' || f[4] === 'stuck' ? f[4] : 'working' })
        break
      case 'finished':
        d.finished = int(f[1])
        break
      case 'waiting':
        d.waiting = int(f[1])
        break
      case 'merge-ready':
        d.mergeReady = int(f[1])
        d.isMergeReadyPartial = f[2] === 'partial'
        break
      case 'merge-command': {
        const n = int(f[2])
        if (f[1] && n !== null && f[3]) d.mergeCommands?.push({ repo: f[1], number: n, command: f.slice(3).join(' ') })
        break
      }
      case 'pending':
        d.pending = int(f[1])
        break
      case 'approvals':
        d.approvals = int(f[1])
        break
      case 'decision':
        d.decisions.push({ time: f[1] ?? '', subject: f[2] ?? '', act: f[3] ?? '' })
        break
      case 'rung':
        d.rung = { name: f[1] ?? '-', reason: f[2] ?? '' }
        break
      case 'headroom':
        d.headroom.push({
          dimension: f[1] ?? '',
          used: int(f[2]) ?? 0,
          limit: int(f[3]) ?? 0,
          percent: int(f[4]) ?? 0,
        })
        break
      case 'watcher':
        d.watchers.push({ duty: f[1] ?? '', script: f[2] ?? '', state: f[3] ?? '', next: int(f[4]) })
        break
      case 'source':
        d.sources.push({ cls: f[1] ?? '', source: f[2] ?? '', mode: f[3] ?? '', age: int(f[4]) })
        break
      case 'kb':
        d.kbAge = int(f[1])
        break
      case 'measure':
        d.measures.push({ name: f[1] ?? '-', value: f[2] ?? '', age: int(f[3]) })
        break
      case 'reviews':
        d.reviews = {
          isAvailable: f[1] === 'ok',
          reason: f[1] === 'ok' ? '' : (f[2] ?? ''),
          age: f[1] === 'ok' ? int(f[2]) : null,
          mineTotal: null,
          waitingTotal: null,
          mine: [],
          waiting: [],
        }
        break
      case 'review-count': {
        const n = int(f[2])
        if (d.reviews?.isAvailable && n !== null) {
          if (f[1] === 'mine') d.reviews.mineTotal = n
          if (f[1] === 'waiting') d.reviews.waitingTotal = n
        }
        break
      }
      case 'review-mine': {
        const n = int(f[2])
        if (d.reviews?.isAvailable && n !== null) {
          d.reviews.mine.push({
            repo: f[1] ?? '',
            number: n,
            isDraft: f[3] === 'draft',
            ci: f[4] ?? 'none',
            unresolved: int(f[5]) ?? 0,
            isHeadReviewed: f[6] === 'yes',
            reviewers: !f[7] || f[7] === '-' ? [] : f[7].split(', '),
            title: f.slice(8).join(' '),
          })
        }
        break
      }
      case 'review-waiting': {
        const n = int(f[2])
        if (d.reviews?.isAvailable && n !== null) {
          d.reviews.waiting.push({
            repo: f[1] ?? '',
            number: n,
            isDraft: f[3] === 'draft',
            requester: f[4] ?? '-',
            age: int(f[5]) ?? 0,
            title: f.slice(6).join(' '),
          })
        }
        break
      }
      case 'host':
        d.host = { load: int(f[1]), cores: int(f[2]), memFreePercent: int(f[3]) }
        break
      case 'handover':
        d.isHandoverInstalled = f[1] === 'available'
        break
      case 'holder':
        d.holder = f[1] === 'registry' || f[1] === 'attended' ? f[1] : null
        break
      case 'unreadable':
        if (f[1]) d.unreadable.push(f[1])
        break
      case 'health':
        if (f[1] && f[4]) health.push({ check: f[1], count: int(f[2]), worst: f[3] ?? '-', text: f.slice(4).join(' ') })
        break
      case 'line':
        d.line = f.slice(1).join(' ')
        break
    }
  }
  return format === '1' ? d : null
}

// A wake from `mc-wake.sh compose`: `idle`, or a `wake` line naming the
// count and ids, then the text to submit.
export function parseWake(text: string): { ids: string[]; text: string } | null {
  const [head, ...rest] = text.replace(/\n+$/, '').split('\n')
  const f = (head ?? '').split('\t')
  if (f[0] !== 'wake' || !f[2]) return null
  const ids = f[2].split(' ').filter(id => /^e[0-9]+\.[0-9a-f]+$/.test(id))
  return ids.length > 0 ? { ids, text: rest.join('\n') } : null
}

const KINDS = {
  task: 'spec task',
  kickoff: 'spec kickoff',
  draft: 'spec draft',
  change: 'one-off change',
  review: 'review',
  mc: 'mission-control session',
  other: 'other session',
} as const

// What a session is doing, read from the shapes its launcher gives the
// scope and handle; the operator sees this, never the scope or handle.
export function flightKind(f: Pick<PanelFlight, 'worker' | 'scope'>): keyof typeof KINDS {
  const s = f.scope
  if (/^flight[:-]/.test(s)) return 'change'
  if (/(^|[:-])task-?[0-9]+(\.[0-9]+)*$|:[0-9]+(\.[0-9]+)*$/.test(s)) return 'task'
  if (/^spec-draft/.test(s)) return 'draft'
  if (/(^|[:-])kickoff([:-]|$)/.test(s)) return 'kickoff'
  if (/review|cubic|copilot/.test(s)) return 'review'
  if (/-mission-control-/.test(f.worker) || /^gen-[0-9]/.test(s)) return 'mc'
  return 'other'
}

const STATES = { waiting: 'waiting for an answer', stuck: 'not responding', working: 'working' } as const
const STATE_ORDER = ['waiting', 'stuck', 'working'] as const

// A digest a reload carried over from before states were read has none.
type ReloadedFlight = Pick<PanelFlight, 'worker' | 'scope'> & { state?: PanelFlight['state'] }

const flightState = (f: ReloadedFlight): PanelFlight['state'] => (f.state && STATES[f.state] ? f.state : 'working')

// The spec or change a session is about, read from the scope its launcher
// gives (`spec:task-3`, `flight:name`, `spec-draft-name`); null where it names none.
export function flightSubject(f: Pick<PanelFlight, 'worker' | 'scope'>, program: string): string | null {
  const kind = flightKind(f)
  const s = f.scope
  if (kind === 'mc') return program || null
  if (s === '' || s === '-') return null
  if (kind === 'review') {
    const pr = /pr-?([0-9]+)/.exec(s)
    return pr ? `PR ${pr[1]}` : null
  }
  if (/^flight[:-]/.test(s)) return s.replace(/^flight[:-]/, '')
  if (/^spec-draft-/.test(s)) return s.replace(/^spec-draft-/, '')
  // The spec name, without its task part (`spec:task-3`, `spec:3.1`, `spec-task-3`).
  const named = s.replace(/((^|[:-])task-?[0-9]+(\.[0-9]+)*|:[0-9]+(\.[0-9]+)*)$/, '')
  const colon = named.indexOf(':')
  return (colon > 0 ? named.slice(0, colon) : named) || null
}

// One plain row per session: what it is, what it is about and where it
// stands, never its handle or scope. Those waiting on an answer come first,
// then those not responding.
export function flightRows(flights: ReloadedFlight[], program = ''): { state: PanelFlight['state']; text: string }[] {
  return flights
    .map((f, i) => ({ i, state: flightState(f), kind: flightKind(f), subject: flightSubject(f, program) }))
    .sort((a, b) => STATE_ORDER.indexOf(a.state) - STATE_ORDER.indexOf(b.state) || a.i - b.i)
    .map(r => ({
      state: r.state,
      text: [KINDS[r.kind], r.subject, STATES[r.state]].filter(Boolean).join(' · '),
    }))
}

export type Install =
  | { state: 'changed'; version: string; root: string; was: string }
  | { state: 'first' | 'same'; version: string; root: string; was: null }

// The answer of `mc-panel.sh install`: the copy the session runs, against
// the program's record.
const VERSION = /^[0-9]+\.[0-9]+\.[0-9]+$/

// The root reaches a toast and the re-injected rules, so control bytes void it.
const CONTROL = /[\u0000-\u001f\u007f]/

export function parseInstall(text: string): Install | null {
  const fields = text.split('\n')[0]?.split('\t') ?? []
  const [head, state, version, root, was] = fields
  if (head !== 'install' || !version || !VERSION.test(version) || !root?.startsWith('/') || CONTROL.test(root))
    return null
  if (state === 'changed' && fields.length === 5 && was && VERSION.test(was)) return { state, version, root, was }
  if ((state === 'first' || state === 'same') && fields.length === 4) return { state, version, root, was: null }
  return null
}

export function age(seconds: number | null): string {
  if (seconds === null) return 'no age'
  if (seconds < 0) return `${-seconds}s overdue`
  if (seconds < 120) return `${seconds}s`
  if (seconds < 7200) return `${Math.round(seconds / 60)}m`
  if (seconds < 172800) return `${Math.round(seconds / 3600)}h`
  return `${Math.round(seconds / 86400)}d`
}

// The handover trigger: measured context where the harness gives
// it, the completed-wake count otherwise, and the compaction ceiling either
// way. Null while no threshold is reached or the knobs are unread, and
// always outside a launched holder: the operator's own session compacts.
export function handoverReason(view: PanelView): string | null {
  const k = view.digest?.knobs
  if (!k || view.digest?.holder !== 'registry') return null
  const compactions = k['handover-compactions']
  if (compactions !== undefined && view.compactions >= compactions) {
    return `${view.compactions} compactions`
  }
  if (view.contextPercent !== null) {
    const ctx = k['handover-context']
    return ctx !== undefined && view.contextPercent >= ctx ? `context at ${view.contextPercent}%` : null
  }
  const wakes = k['handover-wakes']
  return wakes !== undefined && view.wakes >= wakes ? `${view.wakes} wakes` : null
}

export function emptyView(program: string, target: string): PanelView {
  return {
    program,
    target,
    digest: null,
    contextPercent: null,
    rateLimits: [],
    compactions: 0,
    wakes: 0,
    ticks: 0,
    lastTickAt: null,
    handover: null,
    isFallback: false,
    fault: null,
    frame: 0,
  }
}
