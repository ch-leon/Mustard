# ADR-0005 — "Things 3 calm" as the fixed design language

**Status:** Accepted (2026-06-12)

## Context
The first scaffolding UI was undesigned default SwiftUI and Leon disliked it. Three
directions were mocked — Things 3 calm, Akiflow density, dark ambient. On a product
whose pitch is ambient + calm, the UI is the product, not a coat of paint.

## Decision
Adopt **"Things 3 calm"**: warm off-white `#FBFAF7`, hairline dividers, generous
spacing, large readable type, a **single blue accent** `#2D7FF9` (agent purple
`#7F77DD`, done green `#1D9E75` used sparingly). Density comes from hierarchy, not
cramming. All tokens live in `Logic/Theme.swift`; **views never hardcode colors**.

**Exception:** the notch surface is intentionally **dark** (it extends the physical
notch hardware) and uses explicit dark hex, not `Theme`.

## Consequences
- Consistent, calm look enforced through one token file.
- Easy retheme later by editing `Theme`.
- Reviewers can flag any hardcoded color as a defect.
