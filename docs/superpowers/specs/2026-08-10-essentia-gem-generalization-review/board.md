# TASK BOARD — ESSENTIA-GEM-V2 — DESIGN CONVERGED. AWAITING HUMAN CHECKPOINT.

Goal: generalize mood_probe from a mirror of vibe-doctor's MoodVector into an unopinionated Essentia
wrapper (registry + typed results + planner); refactor vibe-doctor to consume a subset via a mapper.
Brief: /Users/lukeolson/Downloads/mood_probe_gem_brainstorm_prompt.md
FINAL DESIGN: docs/superpowers/specs/2026-08-10-essentia-gem-generalization-design.md (93KB, CHANGELOG at section 0)
Original kept for diffing: principal.md. Reviews: security.md, spec.md, test.md, spec-rereview.md,
test-rereview.md, inventory.md.
Repos: vibe-doctor 0499d9c / mood_probe 5360f8f. BOTH TREES CLEAN — verified after all eight passes.
NO CODE HAS BEEN WRITTEN. No branch, no commit, no migration. Design phase only.

## TIER 1 — full chain. STATUS: design complete, HUMAN CHECKPOINT NOT YET PASSED.
No implementation may be dispatched until the user signs off on §J.4.

## Four rounds, eight agent passes, converged
| Round | Pass | Who | Result |
|---|---|---|---|
| 1 | Architecture Q1/2/3/7 | Principal (Keystone) | APPROVE-WITH-CHANGES on the brief |
| 1 | Current-state inventory | Implementer (Rivet) | facts for Q4/Q6 |
| 1 | Security + supply chain Q5 | Security (Warden) | 7 hard constraints |
| 2 | Spec review | Spec (Plumb) | 8 MUST / 11 SHOULD |
| 2 | Test-strategy review | Test (Litmus) | 10 MUST / 9 SHOULD |
| 3 | Design revision | Principal | 16/18 accepted outright, 2 partial disputes |
| 3 | Scoped re-review | Spec | RESOLVED-WITH-RESIDUAL, 8/8 CLOSED, +1 new MUST (N1) |
| 3 | Scoped re-review | Test | RESOLVED-WITH-RESIDUAL, 10/10 CLOSED, BOTH disputes CONCEDED, +1 new (NF-1 = N1) |
| 4 | Narrow amendment | Principal | 8/8 accepted, nothing disputed, +3 volunteered |

FINAL: every MUST-FIX closed — 18 from round 3 plus N1/NF-1 from round 4. Principal declares Phase A
READY TO IMPLEMENT at §M.3.

## THE DEFECT BOTH REVIEWERS FOUND INDEPENDENTLY — and I verified in Ruby
principal-v2 section B proposed: return true if required.subset?(verified_files)
Set[].subset?(Set[]) and Set[].subset?(Set["a.pb"]) BOTH return true. I ran it.
So any algorithm-only request (bpm needs no .pb) returned on line one and NEITHER model_store.verify!
NOR backend.preflight! ever ran => verify!(descriptors: [:bpm]) would return true on a machine with NO
ESSENTIA AT ALL. That is MF-9's defect relocated from a boolean to a file set, not eliminated. Phase A
blast radius nil (the app requests six model-backed descriptors), which is exactly why it would have
shipped unnoticed and surfaced in Phase C.
RESOLVED by taking both halves: preflight_environment! split out under its own boolean memo (correct
there and only there — "does python3 launch, does Essentia import" is precondition-free and invariant);
descriptor-scoped path memoizes on the DESCRIPTOR-ID SET, passing the resolved file set as an argument.
(b) fixes the bug, (a) makes the bug class unreachable. Gates G7/G8/G9 added; G8 is RED under the old
pseudocode, which is the proof the gate bites.

## RISK 1 RETIRED — by the Principal verifying his own dispute
RhythmExtractor2013's required sample rate was marked UNVERIFIED since round 1. Verifying dispute-1
ground (b) turned up the answer on the same Essentia reference page: 44100 Hz, stated in the Description,
independently corroborated by two agents. Consequences folded in: the loads gate pins NOW at
[16_000, 44_100] as a day-one pure-Ruby spec (G16); Risk 1 downgrades from unknown-rate to a cost
question; the measurement reframes to "does resampling from 16 kHz change the answer" (G19).

## BOTH PRINCIPAL DISPUTES WERE CONCEDED BY THE TEST REVIEWER — on verified evidence, not deference
1. MF-3 placement. RhythmExtractor2013's only input is signal; complete parameter list is
   maxTempo/method/minTempo — no filename, no graph, no TensorFlow. So gem-side it runs from
   Dockerfile.essentia with NO models fetch, making it the only real-Essentia gate in the plan with no
   network dependency on essentia.upf.edu. Relocating to the app would have ADDED dependencies.
   Principal's essentia_offline / essentia_golden split judged the better answer.
2. MF-6 voice_instrumental direction control. Conceded: a gate whose red does not IDENTIFY a defect is
   no more a gate than one that cannot fail, and sine_440 is out-of-distribution for a music-trained
   model. Measure first; the measurement must complete into an artefact (B6) with exactly two acceptable
   endings — a committed gate carrying its measured margin, or a written note that the head has no
   automated gate. Phase C re-runs it against the C-major arpeggio fixture, which is instrumental AND
   in-distribution, so the head earns a real gate one phase later instead of never.

## PHASE A — READY. §J.4 is a standalone checkable list: 10 structural items (A1-A10), 21 gates (G1-G21).
Every gate has a state in which it fails and a stated home. G1-G3 and G6-G18 are pure Ruby or
fake-double — no Docker, no Essentia, no models dir. G4/G5/G19 need real Essentia but NO model files.
Only the gem's essentia_golden job and the app's essentia job need models.
Rollback (§J.5): revert the behaviour commit, Gemfile back to tag v0.1.0, bundle, commit lockfile.
Nothing else — mood_vectors was never migrated and the numbers are identical to within 1e-4.
Infrastructure commit (dependabot ignore, ci.yml fix, frozen baseline) MUST SURVIVE the rollback.

## THINGS THE PRINCIPAL FLAGGED RATHER THAN HID — carry these to the user
- Phase A is LARGE and will not land in a day. Scale expectations, not scope.
- Biggest execution risk: the ~40-line Python wire-hardening block, which has no pre-existing analogue
  in either repo.
- G1 has an ordering constraint that is UNRECOVERABLE if violated (parity must run before any golden is
  rewritten). That is why it is checkbox one.
- Rollback is TWO COMMITS, not two lines. The difference is whether someone budgets an hour or a day.

## CLAIMS CORRECTED DURING THE PROCESS — verified by me, not taken on report
- FOUR extractor construction sites, not one — but none of them need to change, because registry: gets
  a default. Two analyze sites and three verify! sites move. (I was wrong twice here; the second
  correction is the Principal's, against his own round-1 text.)
- Golden tolerance 1e-4 rel + 1e-10 floor is the APP spec (essentia_extract_golden_spec.rb:23-24); the
  GEM spec (essentia_golden_spec.rb:36) uses exact eq. Both preserved, deliberately different.
- The APP has a working amd64 essentia CI job (ci.yml:105-123) that RAN AND PASSED — run 31332017915,
  2026-08-09, success. The GEM has NEVER had CI: git log --all -- .github returns ZERO commits.
- Bug 1 is fixed (album.rb:12) — the clamp risk is loud-and-recoverable, not a dead end.
- FOUR of ten MusiCNN heads are inverted relative to a naive positive_index (mood_relaxed, mood_sad,
  mood_party, and tonal_atonal ['atonal','tonal']). Select by class NAME, never index.
- timbre / approachability / engagement need the 1280-d Discogs-EffNet extractor, not 200-d MusiCNN.
  Out of Tier 1, into an opt-in pack (~21 MiB). The five genuine near-free heads total 0.39 MiB.
- All four decodable fixtures are 16000 Hz / 1ch / 10.0 s (ffprobe). Production input is ~30s 44.1 kHz
  stereo AAC.
- M3 arithmetic confirmed exact in binary floating point: raw = 8*rescaled + 1, so the existing
  -0.5..1.5 rescaled sanity window is exactly -3.0..13.0 raw. Behaviour preserved bit for bit.

## USER DECISIONS — settled, design built to them
1. Personal / non-commercial only => non-commercial MTG weights acceptable. NOTICE:7-13 corrected
   (its "depending on the model" claim is unsupported); licence/attribution shown before model fetch (G21).
2. Backfill is a SEPARATE WORKSTREAM. §H states what Phase B will need from it. Premise correction
   stands: NO versioned invalidation exists — only a status-only scope and enrichment:reground_all,
   which unconditionally resets EVERY album.
3. mood_probe gets its OWN CI in Phase A — four jobs per §F.3.

## NEXT — blocked on the user
COMMITTED: design + full four-round review record, branch docs/essentia-gem-v2-design @ a385f5b.
Not pushed, no PR — publishing is the user's call; the repo is public.
Authoritative design: docs/superpowers/specs/2026-08-10-essentia-gem-generalization-design.md.
§J.4 is the standalone Phase A definition of done.
TIER-1 HUMAN CHECKPOINT: STILL NOT PASSED. No implementation authorized. Not delegable; do not skip.
On sign-off: Phase A to the Implementer, infrastructure commit first then behaviour, per §J.3.
The two pre-code specs from §J.1 — frozen baseline E.1 and mapper identity E.2 — are writable before
any Phase A code exists; treat their absence in the first commit as the flag.
OPEN / UNOWNED: file the backfill workstream as a GitHub issue. User decision 2 put it out of scope;
§H states what Phase B needs from it.
The former session-local ESSENTIA-GEM-V2 review directory is referenced nowhere in this tree; assume it is gone.
The repo is now the only copy.
