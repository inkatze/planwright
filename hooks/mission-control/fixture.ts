import { mock } from 'claude-code/testing'
import type { Engine, MockClock } from 'claude-code/testing'
import type { On } from 'claude-code'

// The world beneath the mod in the plugin tests: every call it makes on `$`
// answered from fixture stores, every script run recorded.

export const START = 1_000_000_000

const tab = (...f: (string | number)[]) => f.join('\t')

export function digestText(
  o: {
    pending?: number
    extra?: string[]
    refresh?: number
    tick?: number
    reviewsTtl?: number
    holder?: 'registry' | 'attended' | '-'
    finished?: number
  } = {},
): string {
  return [
    tab('format', 1),
    tab('program', 'alpha'),
    tab('taken', 1000),
    tab('knob', 'refresh', o.refresh ?? 10),
    tab('knob', 'tick', o.tick ?? 300),
    ...(o.reviewsTtl === undefined ? [] : [tab('knob', 'reviews-ttl', o.reviewsTtl)]),
    tab('knob', 'handover-context', 70),
    tab('knob', 'handover-wakes', 3),
    tab('knob', 'handover-compactions', 2),
    tab('flight', 'w-one', 'alpha:task-3', 'stream-json', 'working'),
    tab('flight', 'w-two', 'flight:docs', 'tmux', 'working'),
    tab('finished', o.finished ?? 0),
    tab('waiting', 2),
    tab('pending', o.pending ?? 0),
    tab('decision', '2026-10-26T10:15:00Z', 'relaunch w-one', 'relaunch'),
    tab('rung', 'throttle', 'polls_per_hour at 72%'),
    tab('headroom', 'sessions', 2, 4, 50),
    tab('headroom', 'polls_per_hour', 72, 100, 72),
    tab('watcher', 'inbox', 'inbox-watch.sh', 'stopped', -40),
    tab('source', 'work-items', 'specs', 'record', '-'),
    tab('source', 'code-state', 'forge', 'snapshot', 90),
    tab('source', 'designs', '-', 'cited', '-'),
    tab('kb', 600),
    tab('measure', 'interruptions_per_hour', '2.5', 130),
    tab('measure', 'settled_share', '80', 130),
    tab('handover', 'absent'),
    tab('holder', o.holder ?? 'attended'),
    ...(o.extra ?? []),
    tab('line', 'mission control alpha: 2 in flight, 2 waiting, 0 pending, rung throttle'),
  ].join('\n')
}

// A reviews snapshot as the digest carries it: nine of my PRs, two of them
// listed, and one waiting on my review.
export const REVIEWS = [
  tab('reviews', 'ok', 120),
  tab('review-count', 'mine', 9),
  tab('review-count', 'waiting', 1),
  tab('review-mine', 'acme/widgets', 7, 'ready', 'red', 2, 'yes', 'carol, core-team', 'Add the widget'),
  tab('review-mine', 'acme/widgets', 8, 'draft', 'none', 0, 'no', '-', 'Fix the gadget'),
  tab('review-waiting', 'acme/widgets', 12, 'draft', 'dave', 5400, 'Rework the docs'),
]

export const WAKE = ['wake\t1\te1000.ab12', 'mission control (alpha): 1 event(s) pending.', '- pr-ready pr-7'].join(
  '\n',
)

export const PANE = {
  plugin: 'planwright',
  component: 'Pane',
  requestId: 'mission-control',
  props: {
    title: 'Mission control',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

export const BAND = {
  plugin: 'planwright',
  component: 'AbovePrompt',
  requestId: 'band',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 3,
    bodyColumns: 120,
    scroll: { offset: 0, bodyRows: 3 },
    view: {},
  },
} as const

export const turn = (id: string, agentId?: string) => ({ text: '', turnId: id, ...(agentId ? { agentId } : {}) })
export const done = (id: string, agentId?: string) =>
  ({
    text: '',
    turnId: id,
    answer: '',
    durationMs: 5,
    isAborted: false,
    reason: 'answer',
    ...(agentId ? { agentId } : {}),
  }) as const

export type World = {
  clock: MockClock
  runs: string[][]
  submitted: string[]
  statuses: (string | undefined)[]
  toasts: string[]
  opened: number
  closed: number
  commands: { name: string; description: string }[]
  envWrites: [string, string | undefined][]
  set: (o: Partial<Fixture>) => void
}

export type Fixture = {
  digest: string
  digestExit: number
  wake: string
  composeExit: number
  claimExit: number
  markExit: number
  emitExit: number
  rules: string
  rulesExit: number
  reviewsExit: number
  reviewsOut: string
  isPlaced: boolean
  isPaneOpen: boolean
  isDropped: boolean
  isEnvDenied: boolean
  isCommandRefused: boolean
  contextPercent: number | undefined
  env: Record<string, string>
}

export function world(on: On, given: Partial<Fixture> = {}): World {
  const fx: Fixture = {
    digest: digestText(),
    digestExit: 0,
    wake: 'idle',
    composeExit: 0,
    claimExit: 0,
    markExit: 0,
    emitExit: 0,
    rules: '<!-- rules begin -->\n- R1 never merge\n<!-- rules end -->',
    rulesExit: 0,
    reviewsExit: 0,
    reviewsOut: 'written',
    isPlaced: true,
    isPaneOpen: false,
    isDropped: false,
    isEnvDenied: false,
    isCommandRefused: false,
    contextPercent: 42,
    env: { PLANWRIGHT_MC_PROGRAM: 'alpha' },
    ...given,
  }
  const w: World = {
    clock: mock.clock(on, { now: START }),
    runs: [],
    submitted: [],
    statuses: [],
    toasts: [],
    opened: 0,
    closed: 0,
    commands: [],
    envWrites: [],
    set: o => Object.assign(fx, o),
  }
  on('env.get', (_, e) => ({ value: fx.env[e.name] }))
  on('env.set', (_, e) => {
    w.envWrites.push([e.name, e.value])
    if (fx.isEnvDenied) return { value: { deny: 'managed' } }
    if (e.value === undefined) delete fx.env[e.name]
    else fx.env[e.name] = e.value
    return { value: {} }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('command.register', (_, e) => {
    if (fx.isCommandRefused) throw new Error('refused')
    w.commands.push({ name: e.name, description: e.description })
    return { value: { command: 'mc-panel' } }
  })
  on('ui.open', () => {
    w.opened += 1
    fx.isPaneOpen = true
    return { value: fx.isPlaced ? { isPlaced: true } : { isPlaced: false, reason: 'no-surface' } }
  })
  on('ui.close', (_, e) => {
    if (fx.isPaneOpen && e.id === 'mission-control') {
      w.closed += 1
      fx.isPaneOpen = false
    }
    return { value: undefined }
  })
  on('ui.panes', () => ({
    value: fx.isPaneOpen
      ? [{ id: 'mission-control', title: 'Mission control', isShown: true, isFocused: false, isPlaced: fx.isPlaced }]
      : [],
  }))
  on('ui.status', (_, e) => {
    w.statuses.push(e.text)
    return { value: undefined }
  })
  on('ui.toast', (_, e) => {
    w.toasts.push(e.text)
    return { value: undefined }
  })
  on('session.usage', () => ({
    value: {
      startedAt: START,
      context: { window: 200_000, percent: fx.contextPercent },
      rateLimits: [{ kind: 'five_hour', percentUsed: 31 }],
    },
  }))
  on('prompt.submit', (_, e) => {
    if (fx.isDropped) return { drop: 'a guard refused it' }
    w.submitted.push(e.text)
    return { text: e.text }
  })
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.compact', (_, e) => ({ messages: e.messages }))
  on('process.run', (_, e) => {
    const argv = [...e.argv]
    w.runs.push(argv)
    const script = (argv[1] ?? '').split('/').pop()
    const verb = argv[2]
    const answer = (stdout: string, exitCode = 0) => ({
      value: {
        exitCode,
        stdout,
        stderr: exitCode === 0 ? '' : 'store unreadable',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    })
    if (script === 'mc-panel.sh' && verb === 'digest') return answer(fx.digest, fx.digestExit)
    if (script === 'mc-wake.sh' && verb === 'compose') return answer(fx.wake, fx.composeExit)
    if (script === 'mc-wake.sh' && verb === 'target') return answer('', argv.includes('--mod') ? fx.claimExit : 0)
    if (script === 'mc-event.sh' && verb === 'mark') return answer('', fx.markExit)
    if (script === 'mc-event.sh' && verb === 'emit') return answer('e1.ff', fx.emitExit)
    if (script === 'mc-reviews.sh' && verb === 'refresh') return answer(fx.reviewsOut, fx.reviewsExit)
    if (script === 'mc-rules.sh') return answer(fx.rulesExit === 0 ? fx.rules : '', fx.rulesExit)
    return answer('')
  })
  return w
}

export const ran = (w: World, script: string, verb: string): string[][] =>
  w.runs.filter(r => (r[1] ?? '').endsWith(`/scripts/${script}`) && r[2] === verb)

// Starts the session and lets the bring-up the start hook schedules run.
export async function boot($: Engine, w: World) {
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await w.clock.settle()
}
