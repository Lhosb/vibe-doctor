# IMPLEMENTATION BOARD — Pre-deploy hardening — updated 2026-08-14

APP /Users/lukeolson/projects/vibe-doctor   origin/main 5c9dfcc
GEM /Users/lukeolson/projects/gems/mood_probe (repo=sonance)   origin/main d514137
Milestone: 23 issues. 5 resolved pending merge. NOTHING IS MERGED YET — see STACKING RISK below.

## BRANCH STATE

| Repo | Branch | Issues | Status |
|---|---|---|---|
| app | fix/pre-deploy-record-and-clamp-coverage | #27 #24 | PUSHED d3ff0b9. APPROVED x2 (spec, quality) |
| app | fix/model-attribution-notice | #29 | PUSHED a046b69. Verified by Baton; suite/rubocop/brakeman clean |
| app | fix/fetch-models-at-build-time | #23 | 24e1779. REQUEST-CHANGES x2. In fix round |
| gem | fix/pin-python-stack-and-notice-uris | #17 #19 | PUSHED 11a1baf. Full Tier 2 chain APPROVED |
| gem | fix/cli-output-and-bounded-subprocess-reads | #5 #6 | Dispatched to Keystone (implementing) |

## *** STACKING RISK — the thing most likely to cause pain next ***

Five unmerged branches, two repos. It has ALREADY cost one round trip: #23 re-created ALL of #29
(LICENSE, NOTICE, README) because I wrongly briefed that #29 was on main. It is not — it is pushed
and unmerged. The two branches conflict add/add on NOTICE.
MITIGATION IN PLACE: #23 rebases onto fix/model-attribution-notice and drops the duplicates.
SON #5/#6 was given an explicit do-not-touch list for the files #17 owns.
REAL FIX: merge the approved branches so later work branches off a clean main. OWNER DECISION.

## VD-23 — TIER 1, the only genuinely deploy-blocking issue

Security APPROVE. Spec + Test both REQUEST-CHANGES. Five fixes routed to Rivet:
1. HIGH, found independently by BOTH reviewers — Dockerfile fetch at :71 sits AFTER COPY . . at :59,
   so it caches on the whole app tree and RE-RUNS ON EVERY CODE DEPLOY. The accepted design's risk
   bound depends on the opposite. Move it after bundle install (~:53-56). Baton verified the line
   numbers.
2. HIGH — spec/integration/essentia_extract_golden_spec.rb:19 and spec/fixtures/sonance/
   generate_goldens.rb:9 hardcode tmp/essentia_models. This BREAKS THE APP'S ONLY REAL-ESSENTIA
   GATE. Missed because the implementer grepped app/ and lib/ only. DERIVE REPO-WIDE.
   *** A green 298/0 is fully compatible with this being broken *** — the golden spec is
   essentia-tagged and excluded locally, AND git rm --cached left the files on disk in the worktree.
   Baton's own independent 298/0 was equally blind.
3. MEDIUM — NOTICE:19 claims models are "not redistributed in deployable artefacts". FALSE:
   Dockerfile:85 copies all six into the image. On a public CC-BY-NC-ND repo that sentence must be
   true.
4. LOW but flagged by THREE reviewers independently — Dockerfile:87 claims verify checks digests,
   ownership AND mode. verify_model! checks DIGEST ONLY; no File.stat anywhere in model_store.rb.
5. LOW — verify $ESSENTIA_MODELS_DIR rather than repeating the literal.

TRAP 2 RESOLVED: both reviewers judged the sabotage evidence DOES discriminate, though not as a
matched pair. The leg doing the real work: because the negations are already absent in NEW, the
canonical build IS the OLD sabotage condition. Structural reason it holds — the NEW gate's subject
is the final-stage path, downstream of every delivery mechanism.

## ORDERINGS THAT CANNOT BE INVERTED

1. VD#24 before SON#15. (VD#24 DONE and pushed.)
2. SON#17 before SON#16 before SON#9.
3. NEW — SON#16 must REGENERATE the goldens under the pinned environment BEFORE adding the
   bit-identity gate. The committed goldens date from 2026-08-11 under an unrecorded numpy and
   PROVENANCE.md says they cannot be re-derived. Anchor the gate to them and it is either red or
   accidentally green with no way to tell which.

## OPEN — OWNER DECISIONS

- vibe-doctor#30: out-of-range descriptor policy — SKIP THE TRACK or INCLUDE IT SATURATED.
  Must be decided BEFORE the gem repin, not after. Saturated values average into the album vector
  at mood_grounding_service.rb:181 silently.
- Merge the five approved/pushed branches, or keep stacking.

## UNRESOLVED, NEEDS THE amd64 ENVIRONMENT

- Whether a 180 s fixture actually diverges for these signals. Unmeasured.
- Whether NATIVE_CPU_PATTERN must narrow from "Xeon or EPYC" to one family. numpy dispatches
  reduction kernels on runtime-detected CPU features, so two microarchitectures with different
  AVX-512 sets can select different float32 kernels. Structurally supported, empirically unverified.

## RECURRING LESSON — six premise corrections today, five of them mine

Every claim INFERRED was wrong. Every claim DERIVED FROM CODE held. Dispatches now say
"derive it, do not transcribe it" — including when the thing to transcribe comes from me.
It has caught real defects four times.
