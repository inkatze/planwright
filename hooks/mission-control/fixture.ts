import { mock } from 'claude-code/testing'
import type { MockClock } from 'claude-code/testing'
import type { On } from 'claude-code'

// The world beneath the mod in the plugin tests: every call it makes on `$`
// answered from fixture stores, every script run recorded.

export const START = 1_000_000_000

const tab = (...f: (string | number)[]) => f.join('\t')

export function digestText(o: { pending?: number; extra?: string[] } = {}): string {
  return [
    tab('format', 1),
    tab('program', 'alpha'),
    tab('taken', 1000),
    tab('knob', 'refresh', 10),
    tab('knob', 'tick', 300),
    tab('knob', 'handover-context', 70),
    tab('knob', 'handover-wakes', 3),
    tab('knob', 'handover-compactions', 2),
    tab('flight', 'w-one', 'mission-control:alpha', 'stream-json'),
    tab('flight', 'w-two', 'flight:docs', 'tmux'),
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
    ...(o.extra ?? []),
    tab('line', 'mission control alpha: 2 in flight, 2 waiting, 0 pending, rung throttle'),
  ].join('\n')
}

export const WAKE = ['wake\t1\te1000.ab12', 'mission control (alpha): 1 event(s) pending.', '- pr-ready pr-7'].join(
  '\n',
)

export type World = {
  clock: MockClock
  runs: string[][]
  submitted: string[]
  statuses: (string | undefined)[]
  toasts: string[]
  set: (o: Partial<Fixture>) => void
}

export type Fixture = {
  digest: string
  digestExit: number
  wake: string
  rules: string
  rulesExit: number
  isPlaced: boolean
  contextPercent: number | undefined
  program: string | undefined
}

export function world(on: On, given: Partial<Fixture> = {}): World {
  const fx: Fixture = {
    digest: digestText(),
    digestExit: 0,
    wake: 'idle',
    rules: '<!-- rules begin -->\n- R1 never merge\n<!-- rules end -->',
    rulesExit: 0,
    isPlaced: true,
    contextPercent: 42,
    program: 'alpha',
    ...given,
  }
  const w: World = {
    clock: mock.clock(on, { now: START }),
    runs: [],
    submitted: [],
    statuses: [],
    toasts: [],
    set: o => Object.assign(fx, o),
  }
  mock.env(on, fx.program === undefined ? {} : { PLANWRIGHT_MC_PROGRAM: fx.program })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('command.register', () => ({ value: { command: 'mission-control' } }))
  on('ui.open', () => ({ value: fx.isPlaced ? { isPlaced: true } : { isPlaced: false, reason: 'no-surface' } }))
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
    const ok = (stdout: string, exitCode = 0) => ({
      value: { exitCode, stdout, stderr: exitCode === 0 ? '' : 'store unreadable', isStdoutTruncated: false, isStderrTruncated: false },
    })
    if (script === 'mc-panel.sh' && verb === 'digest') return ok(fx.digest, fx.digestExit)
    if (script === 'mc-wake.sh' && verb === 'compose') return ok(fx.wake)
    if (script === 'mc-rules.sh') return ok(fx.rulesExit === 0 ? fx.rules : '', fx.rulesExit)
    return ok('')
  })
  return w
}

export const ran = (w: World, script: string, verb: string): string[][] =>
  w.runs.filter(r => (r[1] ?? '').endsWith(`/scripts/${script}`) && r[2] === verb)

export const start = { cwd: '/', surface: 'terminal', isInteractive: true } as const
