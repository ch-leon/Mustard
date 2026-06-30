# Risk Report — BAK-112
**HIGH** (path match: `TrustPolicy.swift` → risk.yml high path "TrustPolicy") → auto-merge only after the deep-review panel passes.
- Label: Improvement. Paths: TrustPolicy.swift (Logic — **blurb display strings only**, no gating logic touched: shouldAutoApprove/shouldAutoAccept/thresholds unchanged), AgentConsoleView.swift (view: always-visible blurb + footer note), docs (parity report).
- **Why high despite a copy-only change:** risk.yml classifies any TrustPolicy touch as high (autonomy gating) and prefers over-matching. Honoured.
- No outward actions. No schema change.
