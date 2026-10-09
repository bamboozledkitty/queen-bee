import type { EngineInterface, Register } from 'claude-code'

/**
 * Loaded by Queen Bee into every session it starts. Two jobs: when the session's
 * turn ends, ask the app where the reply goes and send it there as a session
 * message; and refuse a SendMessage between two agents the canvas doesn't link.
 * The app is reached through its helper binary, named in QB_HELPER.
 */

type Delivery = { to: string; text: string }

/** Runs the helper with a JSON body on stdin and reads its JSON answer; null when it can't. */
async function ask($: EngineInterface, command: string, body: unknown, timeoutMs: number): Promise<any> {
  const helper = await $.env.get('QB_HELPER')
  if (!helper) return null
  const out = await $.process.run([helper, command], { stdin: JSON.stringify(body), timeoutMs }).catch(() => null)
  if (!out || out.exitCode !== 0 || !out.stdout.trim()) return null
  try {
    return JSON.parse(out.stdout)
  } catch {
    return null
  }
}

async function handOff($: EngineInterface, answer: string) {
  // Conditions on the way can take a few seconds each to judge.
  const routed = await ask($, 'route', { answer }, 300000)
  const deliveries: Delivery[] = Array.isArray(routed?.deliveries) ? routed.deliveries : []
  if (deliveries.length === 0) return
  const results = []
  for (const d of deliveries) {
    const sent = await $.session.send({ to: { sessionId: d.to }, text: d.text }).catch(err => ({ isDelivered: false, reason: String(err) }))
    results.push({ to: d.to, isDelivered: sent.isDelivered, reason: sent.reason ?? null })
  }
  await ask($, 'sent', { results }, 30000)
}

export const register: Register = on => {
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId || e.isAborted || e.reason !== 'answer') return result
    if (!(await $.env.get('QB_SESSION'))) return result
    // Not awaited: the turn ends now, the hand-off follows.
    void handOff($, e.answer).catch(() => {})
    return result
  })

  on('session.send', async ($, e, next) => {
    if (e.origin.kind !== 'model' || !(await $.env.get('QB_SESSION'))) return next(e)
    const verdict = await ask($, 'may-send', { to: e.to }, 15000).catch(() => null)
    if (verdict && verdict.allowed === false) {
      return { isDelivered: false, reason: String(verdict.reason ?? 'These two agents are not linked on the canvas.') }
    }
    // The recipient is a card of this flow. Other sessions on the machine may carry the same
    // name, so deliver to the card's own session and not to whoever the name finds.
    if (verdict && typeof verdict.sessionId === 'string' && verdict.sessionId) {
      return $.session.send({ to: { sessionId: verdict.sessionId }, text: e.text }).catch(err => ({ isDelivered: false as const, reason: String(err) }))
    }
    return next(e)
  })
}
