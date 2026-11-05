## Decision required, not an implementation task

Split out of #24 on the Spec reviewer's recommendation. #24's *coverage* requirement is satisfied
by `d3ff0b9`; this is the part of #24 that coverage cannot satisfy, because it is a policy choice
about runtime behaviour.

## The question

When a descriptor arrives outside its declared range, should the app:

**(a) Skip the track** — preserve today's behaviour. Requires inspecting the `range_status` that
sonance#15 will introduce, and treating an out-of-range descriptor as a track-level failure.

**(b) Include it saturated** — accept clamping as deliberate policy, and add an assertion on the
count of contributing tracks so a silent shrink in that count is visible.

## Why it is load-bearing

Today the app's four softmax clamps are unreachable dead code, because the gem vetoes
out-of-range values first with `MalformedOutputError` — a `TrackError` the service already
rescues at `mood_grounding_service.rb:116` and `:129`. The track is skipped.

sonance#15 removes that veto by design. Once it lands and the app repins, a value that is skipped
today becomes **included, saturated to 0.0 or 1.0, and averaged into the album vector** at
`mood_grounding_service.rb:181`. No error is raised and no test fails.

Silent drift in stored mood values is worse than a crash, and **defaulting into (b) by accident
is exactly how it lands.**

## Timing

The hazard window opens at the **repin commit** in this repo, not at the sonance release. The app
pins gem tag `v0.3.0` and is insulated until someone deliberately repins. So this decision must
be made **before the repin**, not before the gem work.

Recommended sequencing, recorded on sonance#15: skip 0.4.0 in the app and repin `v0.3.0` →
`v0.5.0` in a single step, with this decision already implemented.

## Not for an implementer

Whichever option is chosen, record the rationale in this issue before the work starts. This
should not be settled by whoever happens to write the code.

## Provenance

Spec review of `d3ff0b9`, 2026-08-14. The reviewer confirmed the commit contains no such decision
and correctly attributed that to a deliberately coverage-only dispatch, then escalated rather
than treating it as an implementer defect.
