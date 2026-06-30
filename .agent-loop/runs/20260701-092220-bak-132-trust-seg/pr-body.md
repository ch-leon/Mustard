## BAK-132 — Trust segmented control

Replace the Trust dropdown `Menu` with a `.segmented` Picker (active = purple), matching the prototype. The selection binding uses the same `trustRaw`/`agent.applyTrust` dispatch — control swap only, no gating-behaviour change. Always-visible blurb + gated footer note (BAK-112) retained.

swift build clean · swift test 417 pass/1 skip. Risk: medium (AgentConsoleView view-only; not TrustPolicy).
