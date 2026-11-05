# Spec Re-Review (Round 3) — ESSENTIA-GEM-V2

**Reviewer:** Spec Reviewer (Plumb). Scoped re-review of my own M1–M8 and S1–S11 only.
**READ-ONLY — no repo file created, edited, or deleted. Both repos verified unchanged this round.**
**Date:** 2026-08-10

| Repo | HEAD | Tree |
| --- | --- | --- |
| vibe-doctor | `0499d9cd38e7009eccbc6f75e50e93bd4800bc3e` | clean |
| mood_probe | `5360f8fd8609eae39edb5dfab8a07f6439a0b137` | clean |

Reviewed: `principal-v2.md` (915 lines, read in full), diffed against `principal.md` and my
`spec.md`. Every disposition below was checked against the section it points at and, where it makes a
claim about current behaviour, against source.

---

## VERDICT: **RESOLVED-WITH-RESIDUAL**

**8 of 8 CLOSED.** Every one of my MUST-FIX is resolved in substance, not merely acknowledged — I
checked each pointed-at section and each is a real mechanism, not a restatement. All 11 SHOULD-FIX
accepted and located.

The residual is **one new defect that the M1 resolution itself introduces** (N1 below). It is the same
*class* of bug M1/MF-9 identified — a memo key that is a lossy proxy for what is being memoized — and
it is in the area I own, so it is in scope. It is a one-line fix.

Two secondary residuals, both SHOULD-level: one Phase A scope item that is genuinely deferrable
(N2), and a revert-sequencing hazard created by the enlarged app-side change list (N3).

---

## M1–M8 dispositions

| # | Finding | Status | Reason |
| --- | --- | --- | --- |
| **M1** | `verify!` specified two ways; whole-registry reading breaks Phase-B-is-gem-only | **CLOSED** | §B makes `verify!(descriptors:)` a required keyword, removes it from §5.3's frozen surface, and makes `ModelStore#verify!(filenames:)` demand-driven. Phase B's six requested descriptors resolve to exactly the six committed `.pb` files, so a tag bump preflights clean. §B gate 2 pins it as a Phase B criterion. **But see N1 — the memo key is still lossy.** |
| **M2** | Wire boundary must be a constrained instruction set | **CLOSED** | §C.1 adopts (a) static enum / no `getattr`, (b) basename + root containment, (c) param whitelist, (d) `schema_version`, (e) `--capabilities`. In J.2's checklist and in J.4 as two acceptance lines, including the adversarial `../../etc/passwd` + unlisted-algorithm test asserting exit 2 with **no Essentia import** — which correctly pins the ordering requirement that validation precede `build_pipeline`. |
| **M3** | Clamp intended not mechanized; `SANITY_RANGE` silently deleted | **CLOSED** | `sanity_range` restored as a fourth `Descriptor` field (§A.2), the clamp mechanized by §E.2's boundary spec, the range check made a boot initializer (§E.2, J.3 item 5). Arithmetic verified exact — see below. |
| **M4** | Phase B has no gate that can catch a class-name inversion | **CLOSED** | §E.5 promotes the upstream-JSON check to a hard Phase B acceptance criterion, adds SHA-256 + fetch date to the row, requires row-by-row review against *its own* JSON. The "what cannot catch it" list is a real addition — naming the `plan_for(…) → take: {index: 1}` unit test as "the trap, and the most natural test an implementer will write" is exactly right, and I had not named it. |
| **M5** | Two selector forms | **CLOSED** | §A.1: `{ class: "<name>" } \| nil`, `{ output: … }` dropped. J.2 checklist. §A.1's added observation is correct and strengthens the fix: under one form, emomusic falls under the same upstream-JSON gate as every other head instead of being the one model that escapes it. |
| **M6** | Five app files hard-depend on the deleted API, missing from scope | **CLOSED** | §J.3 enumerates 15 items with line numbers. All five of mine present with stated replacements: `mood_grounding_service_spec.rb:19,193` → `Analysis` builder (item 9, correctly scheduled first); `phase3_parity.rb` → **delete**, with rationale (item 10); `generate_goldens.rb:10,15` (item 11 — line numbers verified accurate); `essentia_extract_golden_spec.rb:20,38-39` (item 12); `enrich_album_job_spec.rb:99-114` (item 13). |
| **M7** | Dependabot has no `ignore` for `mood_probe` | **CLOSED** | §J.3 item 7, a row in the DoD's change table — structural, not prose. Re-verified `.github/dependabot.yml:3-7` still has no `ignore` and `Gemfile:34` is still branch-pinned, so the finding stands and the fix is correctly placed in Phase A. **See N3** for a sequencing hazard this creates. |
| **M8** | `:musicnn_embedding` registered with nothing constructing a `Vector` | **CLOSED** | Option (a) taken. §A.3 adds the Ruby `values.length == descriptor.shape` assertion I asked for; §E.6(b) adds the 200-float fixture, the 199 wrong-length negative, and the nested-`NaN` sibling; J.4 carries all three. The concession — "my own argument for `:bpm` applies verbatim, and I applied it inconsistently" — is the right read. |

---

## N1 — NEW DEFECT introduced by the M1 resolution (MUST-FIX)

§B's literal code:

```ruby
def verify!(descriptors:)
  required = plan_for(descriptors:).required_files   # Set<String> of basenames; [] for algorithm-only
  return true if required.subset?(@verified_files)
  ...
  model_store.verify!(filenames: required)
  backend.preflight!(plan_for(descriptors:))
```

**`Set[].subset?(anything)` is `true`.** So for any request whose descriptors need no `.pb` file, the
guard returns on the first line and **neither `model_store.verify!` nor `backend.preflight!` ever
runs**. The inline comment — "`[]` for algorithm-only" — states the precondition without following it
to the consequence.

Two concrete failures:

1. **Algorithm-only requests lose preflight entirely.** `verify!(descriptors: [:bpm])` returns `true`
   on a machine with no Essentia installed at all. That destroys the "fail before touching a file"
   property, which is reason 3 of the four arguments for the Ruby-side planner (`principal.md` §3.1)
   and which §B itself invokes when explaining why MF-9 mattered. It also silently no-ops the verify
   step of the gem's new `essentia_offline` CI job (§F.3), the job §F.2 calls "the strongest gate in
   the plan."
2. **The file set is a lossy proxy even for mixed requests.** `verify!(descriptors: [:mood_happy])`
   requires `{msd-musicnn-1.pb, mood_happy-….pb}`. A subsequent
   `verify!(descriptors: [:mood_happy, :bpm])` requires the *same two files*, so
   `required.subset?(@verified_files)` is true and `RhythmExtractor2013` is never preflighted. This is
   MF-9's defect exactly — a memo key too coarse to distinguish the thing being verified — relocated
   from a boolean to a file set rather than eliminated.

**What breaks if unfixed.** The preflight guarantee that `enrich_album_job.rb:8` depends on becomes
conditional on the requested descriptor set in a way nothing states or tests. For Phase A specifically
the blast radius is nil — vibe-doctor requests six model-backed descriptors, so `required` is
non-empty — which is precisely why this will ship unnoticed and surface in Phase C, when the first DSP
descriptor is consumed.

**Fix (one line).** Memoize on the **resolved descriptor-id set**, not the file set; keep the file set
as the argument to `ModelStore#verify!`:

```ruby
def verify!(descriptors:)
  wanted = descriptors.to_set
  return true if wanted.subset?(@verified_descriptors)

  plan = plan_for(descriptors:)
  model_store.verify!(filenames: plan.required_files)   # still demand-driven
  backend.preflight!(plan)
  @verified_descriptors |= wanted
  true
end
```

M1's property is untouched (Phase B still preflights only the six files), MF-9's hole stays closed,
and the empty-set case now verifies rather than short-circuits. As a side benefit it calls `plan_for`
once instead of twice.

**Gate.** §B's gate 1 (`verify!(descriptors: [:bpm])` then `analyze(descriptors: [:mood_happy])` on an
empty dir must raise) does **not** catch this — it passes under the buggy code, because `analyze`
re-verifies with its own descriptors. Add a sibling: with a **stubbed backend recording
`preflight!` calls**, assert `verify!(descriptors: [:bpm])` invokes `preflight!` exactly once, and
that `verify!(descriptors: [:mood_happy])` followed by `verify!(descriptors: [:mood_happy, :bpm])`
invokes it **twice**. Pure Ruby, no Essentia, no models dir.

---

## The three items the dispatch flagged for particular attention

### M1 + MF-9 — does it actually restore Phase B's gem-only property? **Yes.**

Traced end to end. Phase B adds five `Model` rows and six `Descriptor` rows to `Registry.default`
(§I.1: `mood_sad`, `mood_aggressive`, `mood_party`, `mood_electronic`, `voice_instrumental`, optionally
`tonal_atonal`). vibe-doctor still requests `EssentiaMapper::DESCRIPTORS` — the six — which resolve
through `plan_for` to six files: `msd-musicnn-1.pb` plus the four softmax heads plus
`emomusic-msd-musicnn-2.pb`. Those are exactly the six committed under `tmp/essentia_models`
(re-verified last round via `git ls-tree`). `ModelStore#verify!(filenames:)` sees only those six, so
the `"missing model: …mood_sad-….pb"` abort at `model_store.rb:58` cannot fire. The gem-only tag bump
is clean. §B gate 2 — "a vibe-doctor spec that Phase B's registry, with only the six committed `.pb`
files present, preflights and analyses successfully" — is the right assertion and makes the property
tested rather than argued. §I.2 correctly identifies that this and Security constraint 5 are now the
same change.

Caveat: N1, and one structural note — **Phase B has no checkable DoD**. Phase A gets §J.4; Phase B's
criteria are scattered as prose across §B gate 2, §E.5, §F.4, and §I.2. Given that Phase B is the
phase whose whole purpose is to falsify Phase A's architecture, it deserves the same treatment §J.4
gives Phase A. SHOULD-level.

### M3 — is behaviour preserved bit for bit, and is the clamp mechanized? **Yes to both.**

*The arithmetic is exact, not approximate,* and that is worth stating because it is what makes the
"behaviour-preserving by construction" claim load-bearing. Verified at
`mood_probe/lib/mood_probe/features.rb:6` (`SANITY_RANGE = (-0.5..1.5)`) and `:44-52`, applied to the
value *after* Python's rescale at `mood_probe_extract.py:63-64`. The map `raw = 8·rescaled + 1` is
affine and increasing, and every constant involved (`0.5`, `1.5`, `8`, `1`) is exactly representable in
binary floating point: `8 × −0.5 + 1 = −3.0` and `8 × 1.5 + 1 = 13.0` with no rounding, and the inverse
`(−3.0 − 1)/8 = −0.5` likewise. So the accept/reject decision at the boundary is identical under both
formulations, down to the ULP. §A.2's `(-3.0..13.0)` is correct.

*The clamp is mechanized* — but **not by the mechanism §A.2 credits.** §A.2 says the clamp is
"mechanized by §E.2's mapper-identity spec plus a boot initializer." The identity spec cannot do it:
§E.1's own verified precondition records that all eight golden `valence`/`arousal` values lie strictly
inside `(0, 1)` (0.226–0.726), so `features.rb:19`'s clamp was **inert** on every fixture — and a
mapper that dropped the clamp would produce identical output and pass the identity spec. What actually
mechanizes it is the *other* half of §E.2: the boundary spec (`9.4 → exactly 1.0`, `0.6 → exactly 0.0`,
with passing controls at `9.0 → 1.0` and `1.0 → 0.0`), carried into J.4 as "Mapper clamp boundaries
with passing controls (M3)" and J.3 item 15. That construction is right — `9.4` would be `1.05`
unclamped so it proves the clamp bites, and `9.0` proves it does not over-trigger on a legitimate
maximum. My M3(a) is satisfied. **Correct the attribution sentence in §A.2**, or an implementer who
reads only §A.2 will consider the identity spec sufficient and skip the one spec that does the work.

Also confirmed: M3(3) is closed at the *gem* boundary rather than the mapper — a raw 500 now raises
`MalformedOutputError` from `sanity_range` before the mapper sees it (§A.2, §E.2), preserving today's
skip-the-track behaviour (`app/services/mood_grounding_service.rb:94-96`) instead of silently
saturating. That was the more serious half of M3 and it is properly closed.

One precision residual: §A.2 gives the four softmax heads **both** `range_kind: :hard` with
`native_range: (0.0..1.0)` **and** `sanity_range: (0.0..1.0)`. Two fields with the same value and the
same consequence, and `principal.md` §1.2 defined `:hard` as "the gem asserts the value is inside
`native_range`." State which is authoritative — or require `sanity_range == native_range` whenever
`range_kind` is `:hard` — otherwise someone later widens one and is surprised the other still raises.

### M6 — all five present, and `phase3_parity.rb`'s fate is decided

Verified against §J.3's table. All five of my files are there with a stated replacement, and the list
grew to 15 by finding things I did not (the initializer, the `ci.yml` arithmetic, the frozen baseline
directory). `phase3_parity.rb` is item 10: **delete**, with the reasoning I asked for — it compares
against a script deleted at `96e546f` (confirmed at `spec/support/phase3_parity.rb:2`) and §E.1's
frozen baseline supersedes its purpose. That is a decision, not a deferral, which is what M6 required.

Line-number spot check: `generate_goldens.rb:10` is `MoodProbe::Extractor.new(models_dir:)` and `:15`
is `extractor.analyze(...).to_h` — both accurate.

One undercount, adjacent to M8 rather than M6: §E.6(a) says the current suite "has exactly these two"
negative-contract specs. It has **three** — `spec/extractor_spec.rb:145-160` iterates a hash of
`"a missing key"`, `"an unexpected key"`, **and** `"a non-numeric type"` (`features.merge(valence: "0.4")`,
which exercises `validate_number!` at `features.rb:37-38`). Since §E.6 says these "must not be deleted
without replacement," undercounting means the type-validation case is the one that gets dropped. One
line to fix.

### M7 — in the DoD, not prose. Confirmed.

§J.3 item 7 is a row in the change table under §J, which is titled "Phase A — definition of done, as a
checkable list." That is structural placement. Re-verified the underlying fact is unchanged:
`.github/dependabot.yml:3-7` declares the whole `bundler` ecosystem with no `ignore`, and `Gemfile:34`
is still `branch: "main"`. Would be marginally stronger as a line in §J.4's acceptance list alongside
the tag pin, since J.3 reads as "files that change" and J.4 as "things that must be true" — but the
obligation is captured.

---

## SHOULD-FIX dispositions (all 11 accepted; located and checked)

| # | Where it landed | Adequate? |
| --- | --- | --- |
| S1 `reduction` enforced | §A.4 — `reduce:` in plan `emit`, Python asserts single supported value, exit 2 | Yes. Closes the "declaration that can lie" gap that would have hollowed out his own §8.1 challenge. |
| S2 `Model` fields | §A.4 — `byte_length`, `license`, `attribution`, `pack` | Yes, and `byte_length` is made load-bearing in §C.3. **But see N2** on how far §C.3 goes. |
| S3 bounded readers | §C.3 — Phase E DoD, stated byte cap, spec shape written now (SF-4) | Yes. Scheduled obligation with a named home (`spec/backends/command_runner_spec.rb`), which is what I asked for instead of silence. |
| S4 no Phase A backfill | §H.1 | Yes — and correctly warns that `reground_all` loads `Album.all` and resets unconditionally (`lib/tasks/enrichment.rake:23-24`). |
| S5 `llm_only` | §I.3 — named, deferred to Phase C | Yes. |
| S6 registration hardening | §C.2 rules 5–6 — `allow_custom_models` default off, basename/HTTPS/digest validation at `add_model` | Yes. Correctly placed at registration per §2.4's own "fail at registration, not at inference." |
| S7 gem CI | §F, §F.3 four-job table | Yes, and better than I asked: splitting `essentia_offline` from `essentia_golden` keeps the strongest gate free of the `essentia.upf.edu` fetch dependency. |
| S8 Bug 1 correction | §A.2, §L | Accepted; severity of M3 correctly downgraded to "loud and recoverable" while keeping the fix. |
| S9 Risk 4 stale | §F.1, §L — withdrawn on the app side, run `31332017915` cited | Yes; correctly narrowed to a gem-side item that user decision 3 closes. |
| S10 zero constructor sites | §J.3 note | **Checked as a forward claim and it holds** — see below. |
| S11 sample-rate timing | §E.7 — Phase A, §1.4's "before Phase C" corrected | Yes. §E.7 also found something I missed: all four fixtures are 16 kHz, so no existing fixture can answer the question at all. |

**S10 verified as a forward claim about the new API.** Nothing in v2 forces a constructor change.
`registry:` keeps its `Registry.default` default (`principal.md` §2.1, unchanged per v2's preamble), so
all four sites — `enrich_album_job.rb:5-7`, `mood_grounding_service.rb:9-11`, `enrichment.rake:18-20`,
`:31-33` — continue to work as written. The new `verify!(descriptors:)` and `analyze(…, descriptors:)`
are call-site changes, not construction changes, and `backend.preflight!(plan)` takes the plan as an
argument so the backend never needs the registry either. Two `analyze` sites and three `verify!` sites
move; zero constructors. The `enrichment.rake:21` (not `:20`) correction is also right.

---

## N2 — one Phase A scope item is genuinely deferrable (SHOULD-FIX)

The dispatch asked me to judge §K's claim that none of the growth is new work. **It holds for
everything except one item.**

Sorting the growth honestly:

- **Precondition for the payoff:** the `verify!` redesign. Without it Phase B takes the catalogue down
  on a tag bump. Must be in Phase A because 0.2.0 is the one breaking release.
- **Zero marginal cost:** the wire hardening. The plan executor is being *written* in Phase A;
  writing it with a static enum instead of `getattr` is not extra work, it is the same work done
  correctly. Deferring means deliberately writing the unsafe version first.
- **Behaviour preservation:** `sanity_range` — one field, two derived values. Deferring it means
  shipping a regression.
- **Always required, merely un-enumerated:** the five extra app files. These were missing from the
  *estimate*, not added to the *scope*. §K makes this distinction and it is the right one — the suite
  does not load without them.
- **A user decision, not review creep:** the gem CI.

**The exception is §C.3's streaming download rewrite.** My S2 asked for the `byte_length` *field* in
Phase A, on the grounds that adding a field to `Data.define` is free while the struct is being authored
and a registry-wide edit afterwards. §C.3 goes considerably further and puts the whole bounded/streaming
downloader in Phase A — HTTPS-only, host allowlist, redirect policy, connect/read timeouts, stream-to-temp
while hashing, abort on `byte_length` overrun — replacing `ModelStore::Downloader`
(`model_store.rb:9-33`). The justification offered is "Phase A is where `byte_length` lands and where
the gem's new CI first exercises `models fetch`." That is a reason it *can* happen in Phase A, not a
reason it *must*: nothing else in Phase A depends on it, it is Security constraint 3 rather than any
finding of mine, and the existing downloader already fails closed on a digest mismatch
(`model_store.rb:69-72`). §C.3's own best argument — that a post-hoc length check can never
independently fail, because a file with the declared SHA-256 necessarily has the declared length — is
correct and shows the *field* is inert without the streaming rewrite, but that argues for doing them
together, not for doing them now.

**Recommendation:** keep `byte_length` (and `license`/`attribution`/`pack`) in Phase A per S2 — free,
and load-bearing for §G's fetch-time notice. Move the downloader rewrite to its own commit, landable
any time before Phase E, with the Phase A registry rows simply carrying a field nothing yet enforces.
Phase A is already the largest slice in the plan and this is the one piece of it that no other piece
waits on.

With that one move, §K's claim stands and Phase A is still the right first slice.

---

## N3 — "two commits" is honest, but the revert now needs a sequencing rule (SHOULD-FIX)

The dispatch asked whether "two commits, not two lines" still carries the safety argument. **It does**,
and the revision to the wording is the honest one. The decisive property is unchanged and I verified it
independently last round: no migration, `mood_vectors` untouched (`db/schema.rb:93-108`), and the
parity gate asserts the persisted numbers are identical — so a revert leaves nothing to reconcile.
`git revert` over one or two commits is an hour, not a day.

But §J.3's list has grown to 15 items, and **three of them must not be reverted**: item 7 (the
Dependabot `ignore`), item 8 (the `ci.yml` example-count fix), and item 14 (the frozen baseline
fixtures). Those are guardrails and evidence, orthogonal to the behaviour change. If Phase A's app work
lands as a single commit, a blanket revert **removes the Dependabot ignore** — the specific guard
against the gem being re-shipped accidentally, at exactly the moment a botched deploy has just been
rolled back and the gem tag is the thing you least want a bot advancing.

**Fix:** state in §J that Phase A's vibe-doctor work lands as at least two commits — *infrastructure*
(items 7, 8, 14) separate from *behaviour* (items 1–6, 9–13, 15) — and that the rollback reverts only
the behaviour commit. One sentence in the DoD, and it makes the "two commits" claim precisely true
rather than approximately so.

---

## On the disputes

Neither dispute touches my findings — MF-3 part 3 and MF-6 item 2 are both the Test Reviewer's, and
they are re-reviewing them. Two observations offered without adjudicating:

- **MF-3 part 3** — the argument that the empty-models-dir proof belongs in the gem because it is the
  only real-Essentia gate needing **no model fetch** is a genuinely new fact, not a restatement, and it
  inverts the dependency comparison the original recommendation rested on. The keep-a-mirror-in-the-app
  compromise costs little.
- **MF-6 item 2** — "measure first, gate second, and if the margin is thin write down that
  `voice_instrumental` has no automated gate" is the right instinct, and §L risk 2 records the residual
  honestly rather than burying it. A gate that passes for the wrong reason on out-of-distribution input
  is worse than a documented absence.

The self-corrections are all confirmed against source: the `allow_nan` `ValueError` does land in the
generic `except Exception` at `mood_probe_extract.py:127-136` and produce `inference_error` (§D's fix —
wrap `emit()` in its own `try` — is correct); Bug 1 is fixed (`app/models/album.rb:12`,
`spec/models/album_spec.rb:30`); and S10's zero-constructor claim holds.

`tonal_atonal` as `["atonal", "tonal"]` brings the tally to four of ten inverted, which strengthens §0
and makes M4's mandatory upstream-JSON gate more clearly load-bearing, not less.

---

## Summary of what remains

| # | Item | Level |
| --- | --- | --- |
| **N1** | `required.subset?(@verified_files)` is vacuously true for algorithm-only requests, so preflight is skipped; memoize on the descriptor-id set instead, and add the `preflight!`-call-count gate | **MUST-FIX** |
| N2 | Move §C.3's streaming-downloader rewrite out of Phase A; keep the `byte_length` field | SHOULD |
| N3 | Land Phase A's app work as ≥2 commits (infrastructure vs behaviour) so the revert does not remove the Dependabot ignore | SHOULD |
| N4 | §A.2 credits the clamp mechanism to the identity spec; it is the boundary spec that does the work (identity spec is inert per §E.1's own precondition) | SHOULD |
| N5 | §E.6(a) undercounts the existing negative-contract specs — three, not two (`spec/extractor_spec.rb:145-160` includes `"a non-numeric type"`) | SHOULD |
| N6 | Give Phase B a checkable DoD as §J.4 does for Phase A; its criteria are currently prose across §B, §E.5, §F.4, §I.2 | SHOULD |
| N7 | For `range_kind: :hard`, state whether `native_range` or `sanity_range` is authoritative, or require them equal | SHOULD |

None of these is a reason to hold Phase A. N1 is a one-line fix plus one spec.

---

## Evidence

**Diff range:** none — design-only round, no implementation exists. Both repos re-verified clean and
at the same SHAs as Round 1, so all Round 1 source verifications carry forward unchanged.

**Read this round:** `principal-v2.md` (all 915 lines), diffed against `principal.md` and `spec.md`.

**Source re-verified this round (not taken from any report):**

```text
git -C /Users/lukeolson/projects/vibe-doctor rev-parse HEAD   -> 0499d9cd38e7... ; status --porcelain -> (empty)
git -C /Users/lukeolson/projects/gems/mood_probe rev-parse HEAD -> 5360f8fd8609... ; status --porcelain -> (empty)
cat -n vibe-doctor/spec/fixtures/mood_probe/generate_goldens.rb
cat -n vibe-doctor/.github/dependabot.yml
sed -n '140,165p' mood_probe/spec/extractor_spec.rb
sed -n '6,7p;44,52p' mood_probe/lib/mood_probe/features.rb
```

| Claim checked | Result | Basis |
| --- | --- | --- |
| `generate_goldens.rb:10`, `:15` as cited in §J.3 item 11 | accurate | `:10` `Extractor.new(models_dir:)`; `:15` `analyze(...).to_h` |
| Dependabot still has no `ignore`; M7 finding stands | confirmed | `.github/dependabot.yml:3-7` |
| §A.2's `(-3.0..13.0)` derivation | exact in binary FP | `features.rb:6`, `:44-52`; `mood_probe_extract.py:63-64` |
| Softmax heads get both `range_kind: :hard` and `sanity_range` | confirmed redundant | `principal-v2.md:140` vs `principal.md` §1.2 |
| §E.6(a) "exactly these two" negative specs | **three**, not two | `spec/extractor_spec.rb:145-160` — missing key / unexpected key / non-numeric type |
| `Set[].subset?` semantics behind N1 | vacuously true | Ruby `Set#subset?`; `principal-v2.md:216-217` inline comment confirms `required` can be `[]` |
| §E.1's precondition that the clamp was inert on all fixtures | consistent with N4 | `principal-v2.md:383-387`; `features.rb:19` |
| S10 zero-constructor claim | holds | `principal.md` §2.1 default `registry:`; four sites at `enrich_album_job.rb:5-7`, `mood_grounding_service.rb:9-11`, `enrichment.rake:18-20`, `:31-33` |

**Read-only confirmation:** no file in either repository was created, modified, or deleted. The only
file written this round is this report, outside both repos.
