# BAK-132 — Trust segmented control

**Run:** 20260701-092220 · **Milestone:** Redesign · Desktop delta · **Risk:** medium (AgentConsoleView; not TrustPolicy)

Replaced the Trust dropdown `Menu` with a `.segmented` Picker tinted purple (active),
matching the prototype. The selection binding calls the SAME `trustRaw =`/`agent.applyTrust`
dispatch as before — control swap only, no gating-behaviour change. Always-visible blurb +
gated footer note (BAK-112) retained below.
