# Cowork validation record

Whether planwright works inside a Cowork session is settled only by running it there. This file
holds the procedure and the outcome of each run, newest last, pass or blocked. The platform facts
the procedure leans on are in the [platform claims register](platform-claims.md); a run that
contradicts one updates that entry in the same change.

## Procedure

Run on a machine with the Claude desktop app and Cowork available, with planwright installed as a
plugin.

1. **Plugin load.** Start a Cowork session and check whether planwright's skills are offered
   (`/inception` among them). Record which: loaded, not offered, or refused (with the message).
2. **Detection.** In the session, run `scripts/inception-venture.sh detect` from the plugin
   root with `PLANWRIGHT_INCEPTION_HOST=cowork`, then once without it. Record each output
   verbatim, and whether any environment variable in the session marks it as Cowork (`env`
   listing, values redacted). A variable that does is the signal PC-2 is waiting for.
3. **Persistence.** Write a file in the session's working folder, end the session, start a new one
   on the same folder, and check whether the file survived. Do it once in a cloud session and once
   in a local session over a connected folder.
4. **The sync protocol.** Connect a folder holding a cloned test venture (not a real one) and ask
   the session to edit an assumption's evidence, then to change that assumption's `Status:`.
   Record whether the session pulled first, committed with a plain-language message, pushed, and
   proposed the status change under `proposals/` instead of making it. Record whether it read the
   protocol through `CLAUDE.md`'s import or some other file.
5. **Blocked network.** With the network allowlist excluding the git host, repeat the evidence
   edit and record what the session did when `git pull` and `git push` failed.

Record the planwright version, the desktop app version, the plan tier, and the date. Never paste
tokens, account identifiers, or hostnames that are not public.

## Runs

### 2026-10-25 — not performed: no Cowork install reachable

- **Outcome:** blocked. The detection, the sync protocol, and the platform-claims register were
  built by an unattended worker on a Linux host with no Claude desktop app installed, so no Cowork
  session was available to run the procedure in.
- **What stands in for it:** the detection is tested under stubbed environments (a Cowork host,
  a cloud host, a durable override, no git, no installed plugin), and the protocol's content is
  tested where the scaffold emits it. Neither shows how Cowork itself behaves.
- **Next:** the operator runs the procedure above on a machine with Cowork and records the outcome
  as the next entry.
