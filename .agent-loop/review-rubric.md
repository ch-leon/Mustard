# Agent Loop Review Rubric

Fresh-context review has four axes. Any blocking finding stops the merge. On
high-risk work these same axes are re-run independently by the `deep-review` panel.

## Standards Review

Check the diff against this repo's documented standards.

- Does it respect architecture boundaries?
- Does it use project vocabulary correctly?
- Does it avoid shallow modules and unnecessary seams?
- Does it match local style?
- Does it avoid unrelated refactors?

## Spec Review

Check the diff against the originating issue, PRD, or plan.

- Are acceptance criteria implemented?
- Is any requested behavior missing or partial?
- Did the implementation add unrequested behavior?
- Are out-of-scope items left alone?

## Risk Review

Check labels and touched paths.

- What is the highest applicable risk class?
- Were any high-risk paths touched? (high risk → `deep-review` panel before merge)
- Does the task's stated risk match the actual diff?
- Does the change perform any irreversible outward action? (if so → confirm with Leon)

## Test Review

Check verification quality.

- Do tests cover observable behavior through public interfaces?
- Were relevant checks run?
- Are skipped checks justified?
- Did the code reveal missing test seams that should become follow-up work?
