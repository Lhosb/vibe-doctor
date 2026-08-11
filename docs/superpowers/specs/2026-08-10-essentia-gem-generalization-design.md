Provenance: This is the round-4 amended ESSENTIA-GEM-V2 design; Phase A is its first shippable slice.
The superseded first draft is retained in the companion review directory. The four-round review record is in
`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/`, and every MUST-FIX is closed.
At writing, no implementation existed: vibe-doctor was at `0499d9c` and mood_probe at `5360f8f`,
both clean. The Tier-1 human checkpoint in section J.4 had not passed, so implementation was not authorized.

# Principal design v2 — ESSENTIA-GEM-V2 (Round 3 revision)

Supersedes `docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/principal-draft.md`, retained for
line-cited review context and diffing. **Design only — no production code, no commits, no source-file change in either repo.**
Date: 2026-08-10. Reviewer/author: Keystone (Principal Engineer).

| Repo | HEAD at time of reading |
| --- | --- |
| vibe-doctor | `0499d9cd38e7009eccbc6f75e50e93bd4800bc3e` (clean) |
| mood_probe | `5360f8fd8609eae39edb5dfab8a07f6439a0b137` (clean) |

**This is a delta.** Sections of `principal.md` not named here are unchanged and still authoritative —
in particular §0 (class-order finding), §1.6 (embedding dependency on the `Model` row), §3.1–3.3
(planner placement and algorithm), §5.1–5.3 (0.2.0, no shim, compat surface), §6.5 Rules 1–6, and
§8.1–8.2 (the two challenges). §7 risks are re-issued in §L below because three of them changed.

**Headline:** 16 MUST-FIX accepted outright, 2 accepted with one sub-item disputed on evidence.
Phase A's scope grew — materially, and in the right direction. It is still the right first slice, and
§J restates its definition of done as a checkable list.

---

## 0. CHANGELOG — Round 4 amendments (this revision)

Both reviewers returned **RESOLVED-WITH-RESIDUAL** (spec: 8/8 closed, 11/11 SHOULD located; test:
10/10 closed, 9/9 SHOULD landed, **both disputes conceded**). Eight amendments, plus three cheap
residuals folded in. Nothing else in this document changed.

| # | Amendment | Sections touched |
| --- | --- | --- |
| **1** | **NEW MUST-FIX (N1 / NF-1), found independently by both reviewers and verified by me.** §B's `required.subset?(@verified_files)` is **vacuously true** for algorithm-only requests, so preflight was skipped entirely — MF-9's defect relocated from a boolean to a file set, not eliminated. Fixed by taking **both** proposed halves: split environment preflight from file/plan verification, and memoize on the **descriptor-id set**. Two new gates, one of which is red under the old pseudocode. | §B (rewritten), §J.4 |
| **2** | **The sample rate is no longer unknown.** Essentia's reference page states `RhythmExtractor2013` requires **44100 Hz** outright; I re-fetched and confirmed it verbatim. The `loads` gate is **pinned now at two entries**, Risk 1 downgrades from an unknown to a cost question, and the measurement reframes to "does resampling change the answer?". | §E.7, §L Risk 1, §M.2 |
| **3** | **Misattribution corrected.** §A.2 credited the clamp mechanization to §E.2's *identity* spec. It is the **boundary** spec that does the work — E.1's own precondition records the clamp was inert on all eight goldens, so the identity spec cannot exercise it. | §A.2 |
| **4** | **Streaming-downloader rewrite moved out of Phase A.** It is the one piece of Phase A's growth that is genuinely new work and that nothing else waits on. `byte_length` (and `license`/`attribution`/`pack`) stay in Phase A. | §C.3, §J.2, §K |
| **5** | **Phase A's app work lands as ≥2 commits.** Three of the fifteen items are guardrails that must survive a rollback. Rollback reverts the *behaviour* commit only. | §J.3, §J.5 |
| **6** | **Three test-side residuals closed:** R1 freeze the baseline in **both** repos and name which owns the invariance claim; R2 put the 44.1 kHz fixture in the **gem**, where its gate runs; R3 give the baseline a **retirement procedure**. | §E.1, §E.7, §J.2 |
| **7** | **Both dispute outcomes recorded**, including the condition attached to dispute 2 and the Phase C offer that lets `voice_instrumental` earn a real gate. | §M.1, §J.6 |
| **8** | **Readiness statement** and a **standalone Phase A definition of done** that does not require holding this document in context. | §M.3, §J.4 |
| +A | N5: the existing negative-contract specs number **three**, not two — the third is `"a non-numeric type"`. Undercounting it is how it gets dropped. | §E.6 |
| +B | N7: for `range_kind: :hard`, `sanity_range` must **equal** `native_range`; stated rather than left as two fields with one meaning. | §A.2 |
| +C | N6: Phase B gets a checkable DoD of its own, since it is the phase whose purpose is to falsify Phase A. | §J.6 |

---

## 1. DISPOSITION TABLE — 18 MUST-FIX

| # | Source | Finding, one line | Disposition | Resolved in |
| --- | --- | --- | --- | --- |
| **M1** | spec.md:107 | `verify!` specified two ways; whole-registry reading makes "Phase B is gem-only" false | **ACCEPTED** | §B |
| **M2** | spec.md:140 | Ruby→Python boundary must be a constrained instruction set | **ACCEPTED** | §C |
| **M3** | spec.md:151 | Clamp not mechanized; `SANITY_RANGE` silently deleted; detected failure becomes silent saturation | **ACCEPTED** | §A.2, §E.2, §J.2 |
| **M4** | spec.md:197 | Phase B has no gate that can catch a class-name inversion | **ACCEPTED** | §E.5 |
| **M5** | spec.md:218 | Two selector forms; collapse to `{ class: "<name>" }` | **ACCEPTED** | §A.1 |
| **M6** | spec.md:235 | Five app files hard-depend on the deleted API and are missing from Phase A scope | **ACCEPTED** | §J.2 |
| **M7** | spec.md:257 | Dependabot has no `ignore` for `mood_probe`; defeats the lockstep constraint | **ACCEPTED** | §J.3 |
| **M8** | spec.md:278 | `:musicnn_embedding` registered in Phase A with nothing that constructs a `Vector` | **ACCEPTED** (option a) | §A.3, §E.6 |
| **MF-1** | test.md:44 | Rule 2's parity gate deletes itself; freeze the goldens as a permanent baseline | **ACCEPTED** | §E.1 |
| **MF-2** | test.md:68 | Parity spans 1 of the 4 segments the ticket changes | **ACCEPTED** | §E.2 |
| **MF-3** | test.md:95 | Empty-models-dir proof: no value assertion, no failing control, nowhere to run | **ACCEPTED; part 3 DISPUTED-IN-PART** | §F.2 |
| **MF-4** | test.md:121 | Trace measures `__init__`; the claim is about `__call__` | **ACCEPTED** | §E.3 |
| **MF-5** | test.md:138 | Golden plan fixture is regenerated by the spec that asserts it | **ACCEPTED** | §E.4 |
| **MF-6** | test.md:152 | Name what *cannot* catch an inversion; make the upstream-JSON check a hard gate | **ACCEPTED; item 2 DISPUTED-IN-PART** | §E.5 |
| **MF-7** | test.md:186 | `allow_nan=False` yields `inference_error`, not `malformed_output`; nothing crosses the seam | **ACCEPTED** | §D |
| **MF-8** | test.md:216 | No negative tests for either half of the payload-shape contract | **ACCEPTED** | §E.6 |
| **MF-9** | test.md:240 | `verify!` is boolean-memoized; descriptor scoping makes that a hole | **ACCEPTED** | §B |
| **MF-10** | test.md:257 | Sample-rate question has no gate and no fixture can answer it | **ACCEPTED** | §E.7 |

**The two disputes, in one line each.**

- **MF-3 part 3** ("specify the proof as a vibe-doctor spec, because the gem has no CI") — the
  *premise* is now false (user decision 3 gives the gem CI), and the reviewer did not note that this
  particular proof is the **only** real-Essentia gate that needs **no model fetch at all**. It
  therefore has *fewer* dependencies in the gem than the gem's own golden spec. Home: the gem, with a
  mirror in the app. Parts 1 and 2 (value assertion, failing control) accepted in full. §F.2.
- **MF-6 item 2** (`sine_440` → assert `instrumental > 0.5` as a semantic direction control) — a
  440 Hz pure tone is out-of-distribution for a model trained on music, so a red result is ambiguous
  between "the head is inverted" and "the input is meaningless to the model". Committing it as a gate
  before measuring risks a *false inversion signal* on the one finding where a false signal is most
  expensive. Accepted as a **measurement first, gate second**, sequenced behind MF-6 item 3. §E.5.

## 2. DISPOSITION — SHOULD-FIX (21 items, compact)

| # | One line | Disposition |
| --- | --- | --- |
| S1 | `reduction` declared but not enforced → put `reduce:` in plan `emit`, Python asserts | ACCEPTED — §A.4 |
| S2 | Add `byte_length`, `license`, `attribution`, `pack` to `Model` in Phase A | ACCEPTED — §A.4, §G |
| S3 | Bounded readers: obligation at Phase E, stated now | ACCEPTED — §C.3 |
| S4 | State Phase A needs no backfill | ACCEPTED — §H |
| S5 | `llm_only` for new descriptors: name as deferred to Phase C | ACCEPTED — §I.3 |
| S6 | `allow_custom_models` default off; basename validation at registration | ACCEPTED — §C.2 |
| S7 | Gem has no CI | ACCEPTED — §F (user decision 3) |
| S8 | Bug 1 is fixed; my §4.5 "dead end" claim is wrong | ACCEPTED — §A.2, §L |
| S9 | App's amd64 job does run and passed; my Risk 4 is stale | ACCEPTED — §F.1, §L |
| S10 | §9 correction 1 overstated churn — `registry:` has a default, so 0 constructor sites change | ACCEPTED — §J.2 |
| S11 | §1.4 note and Risk 1 disagree on timing; Phase A is right | ACCEPTED — §E.7 |
| SF-1 | `essentia` CI job names one file and hardcodes example count | ACCEPTED — §F.3 |
| SF-2 | Gem CI is the precondition for MF-3/4/5/8 | ACCEPTED — §F |
| SF-3 | Automate §6.2's falsifiability criterion as a CI check | ACCEPTED — §F.4 |
| SF-4 | Write the bounded-reader spec shape now, land at Phase E | ACCEPTED — §C.3 |
| SF-5 | Add a production-format decode fixture; never in the numeric golden set | ACCEPTED — §E.8 |
| SF-6 | Prefer ground truth over goldens (`clicks.wav` = 120 BPM by construction) | ACCEPTED — §E.7 |
| SF-7 | Tolerance controls per unit family, in the app spec's existing comment format | ACCEPTED — §E.8 |
| SF-8 | Decide `phase3_parity.rb`'s fate | ACCEPTED — delete; §J.2 |
| SF-9 | Record *why* the two golden gates differ, in both files | ACCEPTED — §E.8 |
| SF-10 | No TDD finding at design phase; expect MF-1/MF-2 in the first Phase A commit | ACCEPTED — §J.1 |

---

## §A. Type and registry changes

### A.1 One selector form (M5)

`FromModel#select` was `{ class: "happy" } | { output: :valence } | nil`. It becomes
`{ class: "<name>" } | nil`. Verified basis: `emomusic-msd-musicnn-2.json` declares
`classes: ["valence", "arousal"]` — the identical mechanism as the classification heads, so emomusic
needs no second spelling. `nil` still means whole-output (`Vector`).

This matters more than it looks. `mood_probe_extract.py:63-64` hardcodes `va_mean[0]`/`va_mean[1]`
with no upstream cross-reference, and no spec anywhere asserts index 0 is valence. Under a
name-based selector, emomusic's ordering is checked by the same MF-6 upstream-JSON gate as every
other head, instead of being the one model that escapes it.

### A.2 `sanity_range` — restoring the guard I deleted (M3)

`principal.md` §4.5 deleted three guards and replaced one. Verified, the three are
(`mood_probe/lib/mood_probe/features.rb`):

- `SANITY_RANGE = (-0.5..1.5)` for all six heads → `MalformedOutputError` outside (`:6`, `:45-47`);
- `OUTPUT_RANGE = (0.0..1.0)` as a **hard raise** for the four classification heads (`:7`, `:48-51`);
- `value.clamp(OUTPUT_RANGE)` for valence/arousal only (`:19`).

`MalformedOutputError` is a `TrackError` (`errors.rb:7`), so today an off-scale emomusic output
**skips one track with a logged warning** (`app/services/mood_grounding_service.rb:94-96`). Under
`principal.md` as written it would be clamped to `1.0`, persisted, and averaged in — indistinguishable
from a genuine maximum. The reviewer is right that this is strictly worse than the failure it
replaces, and `principal.md` did not mention it.

**Fix — add a fourth field to `Descriptor`:**

```ruby
Descriptor = Data.define(
  :id, :kind, :produced_by,
  :native_range,   # the documented scale — what a consumer rescales against
  :range_kind,     # :hard | :nominal | :unbounded
  :sanity_range,   # NEW. Outside this => MalformedOutputError (a skippable TrackError). nil => finiteness only.
  :units, :shape, :notes
)
```

`native_range` answers "what scale is this on?"; `sanity_range` answers "at what point is this
output broken?". They are different questions and collapsing them is what lost the guard.

The values are **derived, not invented**. Today's window applies to the *rescaled* value; the gem now
emits *raw*. The rescale is `(raw − 1) / 8`, so `raw = 8·rescaled + 1`, and `(-0.5..1.5)` maps to:

```ruby
# emomusic descriptors — behaviour-preserving by construction
native_range: (1.0..9.0),  range_kind: :nominal,  sanity_range: (-3.0..13.0)
#   8 × (-0.5) + 1 = -3.0        8 × 1.5 + 1 = 13.0

# the four softmax heads — unchanged from OUTPUT_RANGE
native_range: (0.0..1.0),  range_kind: :hard,     sanity_range: (0.0..1.0)
```

**Which field is authoritative when `range_kind` is `:hard` (N7).** Neither — they must be equal, and
that is enforced, not conventional: `Descriptor` raises at construction unless
`range_kind != :hard || sanity_range == native_range`. Two fields carrying one value with one
consequence is an invitation for someone to widen one later and be surprised the other still raises.
`principal.md` §1.2 defined `:hard` as "the gem asserts the value is inside `native_range`"; that
sentence now reads "…inside `sanity_range`, which `:hard` requires to equal `native_range`". One
assertion path for all three `range_kind` values, and `:hard` becomes a *declaration that the two
coincide* rather than a second mechanism.

A raw emomusic value of 500 → today `62.375`, outside `(-0.5..1.5)`, `MalformedOutputError`, track
skipped. Under this design → outside `(-3.0..13.0)`, `MalformedOutputError`, track skipped. Bit-for-bit
the same behaviour, expressed as registry data instead of a hardcoded constant. This is contract
validation, not normalization, so settled decision 2 is intact.

The clamp itself moves to `MoodVectors::EssentiaMapper` as designed, and is now **mechanized** —
but **not by the identity spec**, and that correction matters more than it looks.

**§E.2's *boundary* spec is what enforces the clamp. The identity spec cannot.** §E.1's own verified
precondition records that all eight golden `valence`/`arousal` values lie strictly inside `(0, 1)`
(0.226–0.726), so `features.rb:19`'s clamp was **inert on every fixture** — a mapper that dropped the
clamp entirely would produce byte-identical output and pass the identity spec green. What bites is the
boundary spec: `9.4 → exactly 1.0` (unclamped it is `1.05`, so it proves the clamp fires) with the
passing control `9.0 → 1.0` (so it proves the clamp does not over-trigger on a legitimate maximum),
and the mirror pair at the bottom of the range. An implementer who reads only this paragraph must come
away knowing the boundary spec is the one that cannot be skipped.

The boot initializer (§J.3 item 5) covers the third case — a *mis-paired deploy*, which no spec can
catch because specs do not run in production.

Correction to my own §4.5 (S8, verified): `ENRICHMENT_TRANSITIONS["failed"] = %w[matching_audio
grounded]` (`app/models/album.rb:12`), `needing_enrichment` includes `failed` (`:24`),
`enrichment:backfill` runs that scope (`lib/tasks/enrichment.rake:10-12`), and
`spec/models/album_spec.rb:30` is a round-trip recovery spec. **A clamp failure is loud and
recoverable, not a dead end.** The severity of M3 drops; the requirement to mechanize it does not.

### A.3 `Vector` dimension assertion (M8, MF-8b)

Ruby asserts `values.length == descriptor.shape` when constructing a `Vector`, raising
`MalformedOutputError` naming the descriptor and both lengths. Security constraint 4
(`security.md:75`, `:173`) requires it and `principal.md` never said Ruby did it.

`:musicnn_embedding` stays registered in Phase A **and gets exercised** (option (a)) — §E.6. My own
argument for `:bpm` ("a code path that ships untested is not shipped") applies verbatim, and I
applied it inconsistently.

### A.4 Additional `Model` fields (S1, S2)

```ruby
Model = Data.define(
  ..., # as principal.md §1.2
  :byte_length,   # exact upstream size — enables the streaming download bound (§C.3)
  :license,       # "CC-BY-NC-ND-4.0" — the compliance floor per security.md:21
  :attribution,   # upstream attribution string + URL
  :pack           # :core_musicnn | :extended_musicnn | :discogs_effnet
)
```

Free while the struct is being authored in Phase A; a registry-wide edit afterwards. `pack:` and
`license:`/`attribution:` are load-bearing for §G and §I.

`reduction` becomes **enforced**, not merely declared (S1): the plan's `emit` entry carries
`reduce: "mean_over_frames"` and Python asserts it is the single supported value, exiting 2
otherwise. Without this the declaration is a document that can lie — which would hollow out my own
§8.1 challenge.

---

## §B. `verify!` — the top item (M1 + MF-9)

**M1 is correct and it falsifies the ticket's central payoff as `principal.md` specified it.**

Verified chain: `Extractor#verify!` takes no arguments (`extractor.rb:19`) → `backend.verify!`
(`essentia_python.rb:89-101`) → `model_store.verify!`, which iterates **every** registry row
(`model_store.rb:41-44`) and raises `ConfigurationError, "missing model: …"` on the first absent file
(`model_store.rb:58`). vibe-doctor commits exactly six `.pb` files. Three call sites, all zero-arg:
`app/jobs/enrich_album_job.rb:8`, `lib/tasks/enrichment.rake:21`, `:44`.

So under `principal.md` §5.3 (which froze `verify!`), Phase B adds five `Model` rows, vibe-doctor
bumps the tag and changes nothing else — and the next enrichment raises
`ConfigurationError: missing model: …mood_sad-msd-musicnn-1.pb`, which is a `FatalError`
(`errors.rb:12`) that aborts the whole batch (`enrichment.rake:49-51`). **Every album fails from a
gem-only bump.** That is precisely the outcome the ticket exists to prevent.

**MF-9 is the second half of the same defect.** `@verified` is a boolean set once
(`extractor.rb:16`, `:19-24`) and `analyze_all` calls `verify!` unconditionally (`:35`). Making
verification descriptor-scoped while memoizing a boolean means `verify!(descriptors: [:bpm])` — which
requires zero `.pb` files — would satisfy a later `analyze(descriptors: [:mood_happy])`, and the
preflight `ConfigurationError` that `enrich_album_job.rb:8` depends on never fires. That destroys the
"fail before touching a file" property which is reason 3 for the whole Ruby-planner design (§3.1).

### B.1 The v2 resolution was itself defective — N1 / NF-1 (Round 4 MUST-FIX)

Both reviewers found this independently, and I verified it rather than taking it on report:

```text
$ ruby -rset -e 'p Set[].subset?(Set[]); p Set[].subset?(Set["a.pb"])'
true
true
```

The v2 pseudocode opened with `return true if required.subset?(@verified_files)` and its own inline
comment said `required` is `[]` for algorithm-only requests. **An empty set is a subset of
everything**, so `verify!(descriptors: [:bpm])` returned on line one and **neither
`model_store.verify!` nor `backend.preflight!` ever ran**. Three consequences:

1. `verify!(descriptors: [:bpm])` returns `true` **on a machine with no Essentia installed at all** —
   destroying the fail-before-touching-a-file property that §3.1 reason 3 uses to justify the entire
   Ruby-planner design, and which §B invokes two paragraphs above that pseudocode.
2. The file set is a lossy key even for *mixed* requests. I confirmed the case:
   `verify!([:mood_happy])` requires `{msd-musicnn-1.pb, mood_happy-….pb}`; a later
   `verify!([:mood_happy, :bpm])` requires **the same two files**, `subset?` is true, and
   `RhythmExtractor2013` is never preflighted.
3. It defeats MF-3's *positive* case, which exists precisely to exclude "verification was skipped
   entirely" — for algorithm-only requests, verification now genuinely was.

This is MF-9's defect **relocated** from a boolean to a file set, not eliminated. I coarsened the memo
key and did not follow my own comment to its consequence. Phase A's blast radius is nil — vibe-doctor
requests six model-backed descriptors, so `required` is never empty — which is exactly why it would
have shipped unnoticed and surfaced in Phase C, on the first DSP descriptor consumed.

### B.2 Resolution — both halves, because they fix different things

```ruby
def verify!(descriptors:)
  wanted = descriptors.to_set

  # (a) ENVIRONMENT preflight — "does python3 launch, does Essentia import".
  # Precondition-free: no descriptor, no file, no plan. Invariant across every request, so a
  # BOOLEAN memo is correct here, and this is the only place it is correct.
  unless @environment_verified
    backend.preflight_environment!
    @environment_verified = true
  end

  # (b) DESCRIPTOR-SCOPED verification. Memo key is the descriptor-id set — never the file set,
  # which is empty for algorithm-only requests and identical across requests that differ only
  # by a DSP descriptor.
  return true if wanted.subset?(@verified_descriptors)

  plan = plan_for(descriptors:)                          # called once, not twice
  model_store.verify!(filenames: plan.required_files)    # still demand-driven — M1's property intact
  backend.preflight_plan!(plan)                          # graphs loadable, algorithms constructible
  @verified_descriptors |= wanted
  true
end
```

**Why both halves, when (b) alone would fix the reported bug.** (b) is the *correction*: keying on
descriptor ids makes the empty-file-set case verify rather than short-circuit, and makes a request
that adds `:bpm` re-verify. (a) is the *containment*: environment preflight and plan preflight have
different idempotence — one is invariant per process, the other varies with the request — and the
memo key has now been wrong twice in the same method (boolean → file set). Splitting them means the
environment check owns a memo that is correct by construction and **cannot be collaterally skipped by
any future refinement of the descriptor memo**. (b) fixes the bug; (a) makes the bug class unreachable.
The dispatch asked for both and both earn their place.

Unchanged from v2:

- `verify!(descriptors:)` is a **required keyword**, exactly as `analyze` is. `#verify!` is **removed
  from §5.3's frozen compatibility surface** — a breaking change, and 0.2.0 is where it goes.
- `ModelStore#verify!(filenames:)` verifies only what the plan requires, which subsumes most of
  Security constraint 5's "explicit packs": an unrequested pack's absence is simply not an error.
- Three app call sites move to `verify!(descriptors: MoodVectors::EssentiaMapper::DESCRIPTORS)`.

### B.3 Gates — and why the v2 gate does not catch this

**§B's original gate 1 passes under the buggy pseudocode**, so it must not be relied on here:
`verify!([:bpm])` then `analyze(descriptors: [:mood_happy])` still raises, because `analyze`
re-verifies with its own descriptors and `{mood_happy…}` is not a subset of `{}`. It tests the MF-9
hole, not the N1 hole. Both new gates below are pure Ruby, need no Essentia and no models dir, and run
on a Mac.

1. **Preflight call-count** (stubbed backend recording calls):
   `verify!([:bpm])` invokes `preflight_plan!` **exactly once** (it invoked it *zero* times under the
   v2 code); `verify!([:mood_happy])` then `verify!([:mood_happy, :bpm])` invokes it **twice**; and
   `preflight_environment!` is invoked **exactly once** across all of them.
2. **Red under the v2 pseudocode, green under B.2** — this is the one that proves the fix rather than
   describing it: `Extractor.new(models_dir: Dir.mktmpdir, python_executable: "/nonexistent")` then
   `verify!(descriptors: [:bpm])` **must raise `ConfigurationError`**. Under v2 it returned `true`.
   The mechanism already exists — an unlaunchable interpreter is caught as `ConfigurationError` at
   `essentia_python.rb:127-129` — it was simply never reached.
3. **Phase B acceptance criterion, the one that makes "gem-only" true rather than asserted:** a
   vibe-doctor spec that Phase B's registry, with **only the six committed `.pb` files present**,
   preflights and analyses successfully (M1).

The existing app spec at `spec/jobs/enrich_album_job_spec.rb:99-114` ("preflights before matching audio
and makes zero HTTP calls on configuration failure") already builds a real `Extractor` against
`Dir.mktmpdir` and expects `ConfigurationError, /missing model/`. It survives an arity change and is
the natural home for gate 3's app-level mirror.

---

## §C. The wire boundary (M2) and the six other security constraints

The conflict is closed: my Ruby-side planner stands, per `spec.md:40-42`. I adopt every mitigation
without reservation — `principal.md` §4.1's `getattr(es, name)(**params)` was a genuine defect and
`security.md:47` named it correctly.

### C.1 Constraint 1 — constrained instruction set

- **(a) Static algorithm enum, no `getattr`.** `plan["algorithms"][i]["name"]` must be a key in a
  hardcoded dict; `plan["graphs"][i]["algorithm"]` must be in
  `{"TensorflowPredictMusiCNN", "TensorflowPredict2D"}`. Unknown → exit 2.
- **(b) Path containment.** `plan["graphs"][i]["file"]` matches `\A[A-Za-z0-9._-]+\.pb\z`, is joined
  under `--models-dir`, canonicalised, asserted inside the root, asserted a regular non-symlink file.
  Today Python joins a *constant* (`mood_probe_extract.py:27`); the moment the filename is wire data
  the check is mandatory. This is defence in depth against hostile **wire data**, not a guarantee that
  Python opens the inode Ruby verified: canonicalise/check/open is itself pathname-based and has a
  TOCTOU window. Slice 3 must preserve the check without claiming it closes the host-adversary class.
- **(c) Per-algorithm param whitelist.** Each enum entry declares permitted `params` **keys**, value
  **types**, and value **domains** — enumerated values, numeric ranges, and cross-parameter
  constraints. Types alone are insufficient for this constraint's own purpose: `(int, float)` on
  `minTempo` admits `NaN`, `±Infinity` and `1e309` — the last being standards-valid JSON that
  overflows to `inf` — all of which reach native kwargs. Types are pinned to upstream's **declared**
  type, never a permissive superset: Essentia declares `minTempo`/`maxTempo` as **integer** and
  rejects floats only after import. Domains must exclude non-finite values and magnitudes
  unreachable in the declared type. Verification of these declarations is §C.6. Otherwise `params`
  is kwargs injection into native code.
- **(d) `schema_version` handshake** — already in `principal.md` §3.2; restated here as a *security*
  mechanism, since exit 2 → `ConfigurationError` (`essentia_python.rb:140`) → `FatalError`
  (`errors.rb:12`) → batch abort at preflight (`enrichment.rake:49`).
- **(e) `--capabilities` flag** printing the enum's algorithm names as one JSON line **before**
  importing Essentia — feasible because the script already defers `import essentia.standard` into
  `load_models` (`mood_probe_extract.py:24`). A pure-Ruby spec asserts every `FromAlgorithm#name` and
  every `Model#algorithm` in `Registry.default` appears in that list. Drift becomes a red spec on a
  laptop instead of an exit-2 in production.

Anti-drift, restated as three *named mechanisms*: single artifact (`SCRIPT_PATH` is `__dir__`-relative,
`essentia_python.rb:10` — a **preserved property**, now asserted rather than assumed), the
`schema_version` handshake, and the capability cross-check spec.

**Reformulated testable statement of constraint 1** (from `test.md:461`, adopted): for every
descriptor in `Registry.default`, the emitted plan's `graphs[].file` is a bare basename present in
the registry with a matching sha256, `graphs[].output` equals that row's `output_node`, and
`algorithms[].name` is in the static allowlist — plus an adversarial Python unit test where a
hand-written plan carrying `file: "../../etc/passwd"` or an unlisted algorithm name exits 2 with no
import attempted. Both run on a Mac.

### C.2 Constraint 2 — registration is trusted-operator (S6)

`principal.md` §2.4's four rules stand and gain two:

5. **`allow_custom_models` capability, default off** (`security.md:49`). Registering a `Descriptor`
   backed only by already-registered models is always permitted; registering a new `Model` requires
   the capability. Custom URLs are never auto-fetched — an operator supplies a local artifact plus a
   digest.
6. **Validate at `add_model` time**, not at inference (§2.4's own stated principle): `filename` must
   be a bare basename (no `/`, no `..`, not absolute), `source_url` must be HTTPS, `sha256` and
   `byte_length` are mandatory.

### C.3 Constraints 3, 4 — bounded artifacts and bounded output

- **Download (constraint 3): the manifest fields land in Phase A; the downloader rewrite does NOT.**
  *Amended in Round 4 — the Spec Reviewer is right and I over-scoped this.* The design is unchanged:
  HTTPS-only, host allowlist, redirects only to allowlisted HTTPS hosts, explicit connect/read
  timeouts, and **stream to a temp file while hashing, aborting the moment bytes written exceed
  `byte_length`**. The test reviewer's point stands that a post-hoc length check can never
  independently fail — a file with the declared SHA-256 necessarily has the declared length — so the
  bound must be enforced *during* the read to be a gate at all. Testable with a stubbed over-running
  body: assert the abort, that the temp file is removed, and that a previously verified model is
  preserved (`security.md:119`).

  **But nothing in Phase A waits on it.** It replaces `ModelStore::Downloader`
  (`model_store.rb:9-33`), which already fails closed on a digest mismatch (`model_store.rb:69-72`);
  it answers Security constraint 3 rather than any review finding; and it is the **only** part of
  Phase A's growth that is genuinely new work rather than work that was always required and merely
  un-enumerated (§K). My justification — "Phase A is where `byte_length` lands and where the new CI
  first exercises `models fetch`" — is a reason it *can* go there, not a reason it *must*.
  **Moved to its own commit, landable any time before Phase E.**
  **Phase E DoD:** close [mood_probe#1](https://github.com/Lhosb/mood_probe/issues/1) by landing the
  HTTPS host allowlist, explicit timeouts, and streaming `byte_length` bound described above.

  Phase A therefore ships `byte_length` as a **knowingly inert field**: recorded in every `Model` row,
  enforced by nothing until the downloader commit lands. That is stated here rather than left for
  someone to discover, and it is cheap insurance — adding the field while the struct is being authored
  is free, and adding it to a populated registry later is a registry-wide edit. `license`,
  `attribution` and `pack` stay in Phase A on the same reasoning, and `license`/`attribution` are
  *not* inert — §G's fetch-time notice consumes them immediately.
- **Output (constraint 4):** `Vector` exact-dimension (§A.3); recursive finiteness plus
  `allow_nan=False` with the taxonomy corrected (§D); exact requested-ID set (§6.5 Rule 3, with the
  negative tests of §E.6); NDJSON cardinality preserved unchanged (`essentia_python.rb:151-152`).
- **Bounded stdout/stderr readers:** `CommandRunner` retains complete strings
  (`essentia_python.rb:33-34`). For Phase A the largest payload is ~4 KB and the risk is negligible —
  Security gives way here. But Phase A is the release that makes a 200-float `Vector` *reachable*, so
  this becomes a **Phase E DoD item with a stated byte cap**, and the spec shape is written down now
  (SF-4): a fake command emitting `cap + 1` bytes → reader stops, process group killed, specific error
  raised. Home: `spec/backends/command_runner_spec.rb`. Recording it as a scheduled obligation rather
  than leaving the constraint silently unmet.

### C.4 Constraints 5, 6, 7

- **5 — packs are explicit.** `pack:` field (§A.4) plus demand-driven verification (§B), which is
  strictly better than static packs: an unselected pack's absence is not an error at all. Tier
  membership corrected in §I.1.
- **6 — no new embedding exposure by default.** `:musicnn_embedding` is registered but never requested
  by vibe-doctor, and Phase A adds no persistence. M8's exercise is a *test* fixture, not exposure.
  **Phase E DoD gains** a request spec asserting the recommendation and vibe-map JSON payloads contain
  no vector-valued key (`app/controllers/recommendations_controller.rb:4-20`,
  `app/models/albums/vibe_map_builder.rb:31-46`).
- **7 — licensing visible.** §G.

### C.5 Host filesystem threat model

Path attacks reachable from registry data alone are in scope: traversal during path joins, symlinked
final artifacts, and symlinked or swapped predictable temporary paths are closed in
`ModelStore::Files`. The boundary is whether exploitation requires a pre-existing local write
primitive, not whether the vulnerable operation touches the model filesystem.

Phase A excludes a local process or principal with write access to `models_dir` or any ancestor while
verification and analysis run. The admitted adversaries in C.1–C.3 supply registry/wire data, network
responses, upstream artifacts, or backend output; they do not control host filesystem namespace or
model bytes after verification. `ModelStore::Files` therefore treats roots not owned by the current
user, symlinked roots, and group/world-writable roots as **deployment misconfiguration signals**, not
as dirfd-bound containment.

The realistic revocation is a later deployment mounting `models_dir` from a shared volume writable by
another workload. Under that precondition, pathname replacement and mutation through another hardlink
can change what the backend reopens after Ruby verification. Closing that different adversary requires
native `openat`/`renameat`, an immutable snapshot, or descriptor handoff; it is tracked in
[mood_probe#2](https://github.com/Lhosb/mood_probe/issues/2).

**Phase E DoD:** close mood_probe#2 before admitting any deployment where an untrusted local process
can write the model root or its ancestors, and demonstrate that the backend consumes the verified
directory snapshot or file identity rather than reopening an unbound pathname.

### C.6 Upstream facts hardcoded in the gem

At least two upstream facts live in the gem, most visibly `classes` (§E.5) and the §C.1(c) parameter
domains. The registry also hardcodes framework versions, graph node names and `sample_rate: 16_000`.
The node names self-verify at graph construction; the sample rate has no declaration-level check and
would surface only as an undiagnosed golden mismatch. This section states the rule for every instance.

**Pin to a named upstream version and verify against the strongest surface that version exposes.**
Strongest first:

1. **Real construction against the live library** — tests the binary, not a description of it.
2. **Structured introspection** (`parameterNames`, `paramType`, `paramValue`) — machine-checkable,
   but describes declarations rather than behaviour.
3. **Documented text** (`__doc__`) — weakest: not machine-checked, and free to drift from the binary
   it documents.

Use the strongest surface **available for that fact**, and record in the spec **which surface was
used and why anything weaker was chosen**. Naming the surface is what lets a later reviewer tell a
legitimate downgrade from a silent one. Where no surface exists — Essentia's 20 BPM
`maxTempo − minTempo` interval rule has no API and no doc entry — real construction is the only
option and is therefore mandatory, not optional.

**Known weakness, recorded rather than implied.** Essentia is pinned to `2.1-beta6-dev`. That is a
**development version string and does not uniquely identify a build**: two builds can report it and
the cross-check would follow the newer one silently. The domain check is weaker than §E.5's
`classes` gate in four ways — no independent copy of upstream truth in the repo, no SHA-256, a
version string with no fetch date, and it runs only in `essentia_offline`, so drift is invisible on
a laptop. The E.5-shaped closure — a committed introspection snapshot with its digest, a non-Docker
spec asserting the gem's constants against the snapshot, and the Docker spec asserting the snapshot
against the live library — turns drift into a red spec on a developer machine, the same conversion
§C.1(e) makes for the capability cross-check (line 386-388). **Carried by mood_probe#3 and Phase B
DoD item B8**, alongside §E.5's upstream-JSON gate, which is the same pattern on the other fact.

---

## §D. Python error taxonomy correction (MF-7)

**My §4.4 claim was wrong.** Verified: `mood_probe_extract.py:107-136` is one `try` whose
`except Exception` (`:127-136`) emits `inference_error`. `malformed_output` is emitted **only** by the
explicit non-finite branch at `:112-125`, which `continue`s. `emit()` is called at `:126`, *inside*
that try — so a `ValueError` from `json.dumps(..., allow_nan=False)` lands in the generic handler and
produces `inference_error`, not `malformed_output`.

**Decision: it must produce `malformed_output`,** because that is what the value means — the payload
is malformed, not the inference — and because a spec written to `principal.md`'s stated expectation
would otherwise fail. Wrap `emit()` in its own `try` that converts a serialisation `ValueError` into
the `malformed_output` branch. Do not leave the implementer to discover this.

**Test it across the seam, not on either side of it.** Python's default `json.dumps` emits bare `NaN`
and Ruby's `JSON.parse` rejects it (`security.md:212-214`) — a mutation battery only proves what its
seams cross. The existing harness is exactly right: `spec/support/fake_essentia/essentia/standard.py:52-55`
produces `nan-audio`/`infinity-audio`, exercised end-to-end through the real script and the real Ruby
parser at `spec/integration/python_seam_spec.rb:41-53`, with no Essentia and no Docker. Extend with:

- a **nested** non-finite at depth ≥ 2 — `NaN` inside a `Vector`'s element list and inside a
  `Categorical#distribution` value. A top-level-only guard passes a flat test and fails here;
- `-Infinity` as well as `NaN` and `+Infinity`;
- assertions on the **error class and message**, not merely `not_to be_ok`. Today this path yields
  `BackendError: … invalid NDJSON` (`essentia_python.rb:162-163`) — the misleading outcome the change
  exists to fix. Asserting only "it failed" cannot distinguish the fix from the bug.

---

## §E. Test architecture (MF-1 … MF-10, M4, M8)

### E.1 Freeze the baseline (MF-1)

`principal.md` §6.5 Rule 2 treated the algebraic parity check as a *step* — "only once this passes do
you write the new-shape goldens." That consumes the evidence: after regeneration the old values are
gone and Rule 1 and Rule 2 are in direct tension, with Rule 1 winning. Worse, Rule 4 (Phase B's gate)
then inherits a baseline written *after* the change it was meant to check.

**Fix.** Commit the four current golden files unchanged at
`spec/fixtures/mood_probe/baseline_v0_1_0/*.json`, with a header comment stating they are frozen
pre-`v0.2.0` output and must never be rewritten. Keep the algebraic spec **permanently**: four softmax
heads `eq` the baseline; `(raw_emomusic − 1.0) / 8.0` within `max(1e-4·|expected|, 1e-10)` of the
baseline. Cost: ~6 KB. Benefit: a one-shot migration check becomes a standing gate.

**Placement note (SF-1 interaction):** put it in a **sibling** directory, not under `golden/`. The
app's CI job derives its expected example count from
`ls spec/fixtures/mood_probe/golden/*.json | wc -l` (`.github/workflows/ci.yml:121`, verified), and
coupling a new fixture directory to that arithmetic is exactly the kind of thing that goes red during
a lockstep deploy.

**Precondition, verified by the test reviewer and worth recording** (`test.md:517-528`): all eight
golden `valence`/`arousal` values lie strictly inside `(0, 1)` — range 0.226–0.726, implying raw
emomusic 2.81–6.81. So `value.clamp(OUTPUT_RANGE)` (`features.rb:19`) was **inert** for all eight and
the inverse `raw = 8v + 1` is exact. The algebraic gate is well-posed on every fixture. `principal.md`
asserted this gate was achievable without checking it.

This same precondition is why §A.2's clamp mechanization credits the **boundary** spec, not the
identity spec: a clamp that never fired on any fixture cannot be exercised by a fixture-derived
identity assertion.

**Which repo owns it — freeze in BOTH (R1).** The four goldens are currently byte-identical across the
two repos (verified by the test reviewer), and §F.3 makes the gem's `essentia_golden` job **blocking**
— so freezing only app-side would leave the gem's own goldens to be regenerated with no anchor.
Commit `baseline_v0_1_0/` in **both** repos (the same ~6 KB), and state the division of labour, which
follows Rule 6 exactly:

- **vibe-doctor owns the invariance claim.** The algebraic gate — four heads `eq` the baseline,
  `(raw − 1)/8` within tolerance — lives in the app, because the app's gate is the cross-environment
  reproducibility gate and the app is where those numbers reach `MoodVector`.
- **The gem's copy anchors its determinism claim.** The gem's `eq` gate asserts bit-identical output
  *in a fixed image*; a post-refactor baseline would be legitimate for that purpose alone, but
  freezing the pre-refactor bytes costs nothing and lets the algebraic gate run in both places. Run it
  in both.

**Retirement procedure — required, because a permanent gate with no documented exit gets deleted
(R3).** Nothing in this plan should legitimately move these six numbers: Rule 4 forbids it for Phase B,
and Phases C–E add descriptors rather than change these. The first legitimate cause is an upstream
model-version bump. When that happens:

> Retirement is a **new dated baseline directory** (`baseline_<version>/`), the old directory
> **kept**, and the rationale recorded in the commit message — naming the upstream model version, the
> old and new values, and who reviewed the delta. **Never an edit to, or deletion of,
> `baseline_v0_1_0/`.**

Put that sentence in the directory's header comment, not only here. The observed response to an
obstacle with no documented exit is to remove the obstacle.

### E.2 Close the other three segments (MF-2, M3a)

`principal.md` gated only *Python raw → gem typed value*. Three segments were uncovered, and the
mapper's clamp — M3's whole subject — sits in one of them.

**One spec closes two segments, and it runs on the dev Mac with no Docker, no Essentia, no models dir:**

> Build an `Analysis` from the new-shape golden, run it through `MoodVectors::EssentiaMapper#call`,
> assert the result equals the frozen `baseline_v0_1_0` hash — four heads exactly, valence/arousal
> within the existing tolerance — **and** that `result.keys == MoodVector::MOOD_HEADS`.

It fails if the mapper drops the clamp, transposes a head, renames a key, or changes the rescale. It
is the end-to-end parity statement the refactor needs and it is the direct mechanization M3(a) asks
for. Note the key-set half also closes a confirmed pre-existing absence: **nothing today asserts the
gem's head set matches `MoodVector::MOOD_HEADS`** (`test.md:618-621`, corroborated by
`inventory.md:291-300`); the only cross-check is indirect, against a duplicated string constant at
`spec/integration/essentia_extract_golden_spec.rb:20`.

Plus, per M3(1): a boundary spec on the mapper — `valence_emomusic = 9.4 → exactly 1.0`,
`0.6 → exactly 0.0`, with **passing controls just inside** (`9.0 → 1.0`, `1.0 → 0.0`). Per M3(3), the
`sanity_range` of §A.2 gives a raw 500 a `MalformedOutputError` before the mapper ever sees it, so the
"silently saturated" regression is closed at the gem boundary and the mapper's clamp handles only
near-boundary values — which is exactly the two-tier behaviour that exists today.

Per M3(2): the range-agreement check is a **boot-time initializer**, not "at boot or in a spec". The
"or" is what made it useless: the failure being guarded is a mis-paired *deploy*, and a spec does not
run in production. It also gives the app-ahead-of-gem case a clean failure — gem 0.1.0 has no
`MoodProbe::Registry`, so the initializer raises `NameError` at boot: a failed deploy rather than
per-album corruption.

### E.3 Trace invocation, not construction (MF-4)

`spec/support/fake_essentia/essentia/standard.py:26-29` is `__init__`; `:31-34` is `__call__`.
`principal.md` proposed tracing constructions — but §4.1 builds the pipeline once per *process* and
runs graphs per *file*, so a Python rewrite that constructs one MusiCNN and then **invokes it once per
head** — the exact regression the planner exists to prevent, and the one that costs real enrichment
time — passes a construction-count trace unchanged.

**Gate:** trace `__call__` as well as `__init__`. For N MusiCNN heads over M files: the embedding is
constructed **once** and invoked **exactly M times**, and each head is invoked exactly M times. Use
`analyze_all` with 3 paths — the single-file example in `principal.md` is precisely the case where
construction and invocation counts coincide and the bug is invisible.

### E.4 The plan fixture must be able to fail on both sides (MF-5)

`principal.md` had the Ruby spec *generate* the fixture it asserts — a tautology; only Python could
ever go red. **Fix:** two artefacts. A **generator** (`spec/fixtures/plan/generate.rb`, run by hand,
in the manner of the existing `spec/fixtures/mood_probe/generate_goldens.rb`) and a **spec** asserting
`plan_for(descriptors: […]).to_json` `eq`s the committed bytes. Cover three plans: MusiCNN-only,
algorithm-only (`[:bpm]` — the `"graphs":[]` case), and mixed. Same never-regenerate header comment as
E.1. Python parses the identical committed bytes.

### E.5 What catches a class inversion — and what cannot (M4, MF-6)

`principal.md` §6.2's defence was one sentence containing the word "ideally". That is not a gate, and
Risk 6 rates this the highest-consequence silent-correctness area. Promoted to a **hard Phase B
acceptance criterion**.

**What cannot catch it** — stated explicitly so nobody proposes them:

- A range assertion. An inverted 2-class softmax head returns `1−p`, still a plausible `0..1` float.
- A new golden for the new head. It pins `1−p` as expected forever — the canonical tautology.
- A complementarity check (`p(X) + p(non_X) ≈ 1`). It proves the two indices partition and says
  nothing about which is which.
- A `plan_for` unit test asserting `take: {index: 1}` for `mood_relaxed`. It is derived from the same
  `classes` array it would need to check. **This is the trap, and it is the most natural test an
  implementer will write.**
- Rule 4. It protects the six existing heads and is silent on the five new ones.

**What does:**

1. **An independent copy of upstream truth.** Check in each `<head>-msd-musicnn-1.json` next to its
   `.pb` checksum, record its SHA-256 and fetch date in the registry row, and add a **non-network**
   spec asserting `Model#classes == JSON.parse(file)["classes"]` row-by-row. The JSON is fetched from
   `essentia.upf.edu`, never derived from the registry, and each row is reviewed against **its own**
   JSON, never against the neighbouring row.
2. **A one-time reviewable artefact.** In the amd64 image, emit *both* class probabilities for all
   heads over the four fixtures and attach the table to the Phase B PR. This is the only step that
   catches an error correctly transcribed from an upstream mistake.
3. **A semantic direction control — measured first, committed second. DISPUTED-IN-PART.** MF-6 item 2
   proposes asserting `instrumental > 0.5` and `instrumental > voice` on `sine_440.wav`. The
   motivation is exactly right: `voice_instrumental` is `["instrumental", "voice"]` (verified) — no
   positive class, therefore no orientation to transcribe rightly *or* wrongly — so it is the one head
   that mechanism 1 cannot fully protect. But `sine_440.wav` is a 10 s 440 Hz pure tone (verified via
   `generate.sh:6-9` and `ffprobe`: 16000 Hz, 1 channel, 10.0 s), which is out-of-distribution for a
   model trained on music. A red result would be ambiguous between "the head is inverted" and "the
   input is meaningless to the model" — a **false inversion signal on the finding where a false signal
   is most expensive**, and the likely response is to weaken the gate, which destroys it.
   **Resolution:** run it as part of mechanism 2's measurement table first; commit it as a gate only
   if the measured margin supports it, with the observed value recorded in the spec comment. If the
   margin is thin, the honest answer is that `voice_instrumental` has no automated correctness gate
   and ships on human review of the table — which is a fact worth writing down rather than papering
   over with a gate that passes for the wrong reason.

The existing six remain mechanically protected, and this deserves stating: §6.5 Rule 2 asserts the
four softmax heads bit-identical against the frozen baseline, so a `positive_index → classes`
transcription error surfaces as `p` vs `1−p` — orders of magnitude outside the `1e-4` relative
tolerance (`spec/integration/essentia_extract_golden_spec.rb:24-25`, `:53`, `:68`) — and it runs
automatically in `ci.yml:105-123`.

### E.6 Negative tests for both contract halves (MF-8, M8)

**(a) Requested-set enforcement. Three negative specs, not two — I undercounted (N5).** Verified at
`spec/extractor_spec.rb:145-160`: the existing suite iterates a hash of **three** schema-drift cases,
not two — `"a missing key"` (`:146`), `"an unexpected key"` (`:147`), and **`"a non-numeric type"`**
(`:148`, `features.merge(valence: "0.4")`), which exercises `validate_number!` at `features.rb:37-38`.
Since the rule is "they must not be deleted without replacement", undercounting is precisely how the
type-validation case gets dropped on the floor.

So the new contract needs three negatives against a stubbed backend, each of which must raise: a
payload with an **unrequested** id, one **missing** a requested id, and one whose value is of the
**wrong type** for its descriptor `kind` (a `String` where a `Scalar` is declared). All three are the
load-bearing successor to `Features#validate_keys!`/`#validate_number!` (`features.rb:29-38`). Note
that each existing spec also asserts the batch **stops** — `expect(backend).not_to have_received(:analyze)`
on the third path (`:158`) — and that stop-on-schema-drift property must survive too.

**(b) `Vector`.** A fake-double fixture returning a 200-float vector; a **wrong-length** fixture (199)
asserting `MalformedOutputError` naming the descriptor and both lengths; and a nested-`NaN` sibling
(§D). Phase A acceptance criteria gain a spec that actually requests `:musicnn_embedding` — closing
M8 via option (a).

### E.7 The sample-rate question (MF-10, SF-6, S11)

Verified with `ffprobe`: **all four decodable fixtures are 16000 Hz, 1 channel, 10.0 s.** Production
input is an iTunes preview — ~30 s, 44.1 kHz, stereo AAC (`app/services/mood_grounding_service.rb:87-113`).
So running `RhythmExtractor2013` "at 44.1 kHz" against the existing corpus means *upsampling from
16 kHz*, which measures whether the algorithm accepts 44.1 kHz input, not whether a genuine 44.1 kHz
source gives the same answer. `principal.md` proposed the measurement without noticing that no fixture
can support it.

**THE RATE IS NO LONGER UNKNOWN — amended in Round 4.** `principal.md` §1.4 marked
`RhythmExtractor2013`'s required sample rate UNVERIFIED on the grounds that "the Essentia reference
page does not state a required input rate." **That premise is false and the marker is withdrawn.**
The Test Reviewer found it while verifying my dispute-1 ground, and I re-fetched
`https://essentia.upf.edu/reference/std_RhythmExtractor2013.html` to confirm it verbatim — final
sentence of the **Description** section, which is why it is easy to miss if you read only the
parameter table:

> "Note that the algorithm requires the sample rate of the input signal to be 44100 Hz in order to
> work correctly."

Independently corroborated on `std_BeatTrackerMultiFeature.html` (what `method: "multifeature"`
dispatches to). The same fetch confirms my dispute-1 ground (b): the complete parameter list is
`maxTempo`, `minTempo`, `method` — **no filename, no graph, no weights, no TensorFlow** — which is
what makes §F.2's model-free proof possible.

**Three items, all Phase A** (resolving S11: Phase A is right, and `principal.md` §1.4's "before
Phase C" note is superseded — that document is preserved unedited, so this paragraph is the
correction of record):

1. **Fixture — in the GEM (R2).** One click train at a known BPM generated natively at 44.1 kHz via
   `generate.sh`, committed as WAV so it stays bit-reproducible. `principal-v2` listed this as a
   vibe-doctor file while §F.3 put its gate in the gem's `essentia_offline` job — **a gate cannot run
   against a fixture in another repo.** `generate.sh` is byte-identical across the two trees, so
   generate it into **both**; the gem's copy is the one the gate reads. Same applies to MF-3's
   click-train value assertion, which §F.2 also homes in the gem. §J.2 gains the fixture lines.
2. **Measurement — reframed.** Not "what rate does it need?" (answered) but **"does resampling from
   16 kHz change the answer?"** Run `[:bpm]` on the native-44.1 kHz fixture and on `clicks.wav`
   (16 kHz, same construction) in the amd64 image; record both values and the delta. Both have the
   same absolute ground truth, so the comparison is meaningful in a way an accept/reject check is not.
   This is the more useful experiment and it is the one still worth running.
3. **The gate — pinnable NOW, at two entries.** `plan_for(descriptors: [:bpm, :mood_happy]).loads.map { it[:sample_rate] }`
   `eq`s **`[16_000, 44_100]`**. `principal-v2` deferred the value ("one entry if 16 kHz is acceptable,
   two if not") behind a Docker measurement; documentation settles it, so this becomes a **pure-Ruby
   spec writable red on day one of Phase A** — which matters, because §J.1's whole point is which
   specs exist before the code does.

**Ground truth beats a golden (SF-6), and it is free here.** `clicks.wav` is generated as
`if(lt(mod(t, 0.5), 0.008), …)` (`generate.sh:21-24`, verified) — a click every 0.5 s, **120 BPM by
construction**. So MF-3's value assertion and MF-10's measurement are *the same experiment*: the same
construction at two sample rates, both with an absolute expected value that no regeneration can
satisfy. Record an octave error (60 or 240) as a finding, never as a golden to update.
`sine_440.wav` is A4, giving `KeyExtractor` a weaker expected `key == "A"` for Phase C.

### E.8 Fixture and tolerance policy (SF-5, SF-7, SF-9)

- **Production-format decode fixture** (44.1 kHz stereo AAC) for the decode path only — it is the one
  thing that would catch a `MonoLoader`/ffmpeg regression on real input. **Never in the numeric golden
  set**: AAC encoders are not bit-reproducible across versions and the gem's exact-`eq` gate
  (`spec/integration/essentia_golden_spec.rb:34`) would become environment-dependent.
- **Tolerance controls per unit family**, not per descriptor: one set for `:probability`, one for
  `:bpm`, one absolute-tolerance set for `:lufs`/`:lu`. Record in the format the app spec already uses
  (`spec/integration/essentia_extract_golden_spec.rb:22-23`: perturbation size, fixture, head,
  outcome), with **both** a passing and a failing control.
- **Write down why the two golden gates differ**, one line in each file. The test reviewer verified
  the two repos' golden JSONs are currently byte-identical, so the gates look redundant to anyone who
  has not read Rule 6. The gem asserts its own determinism in a fixed image; the app asserts
  cross-environment reproducibility.

---

## §F. CI (user decision 3) and the MF-3 adjudication

### F.1 State of the world, verified

- **vibe-doctor has a working amd64 Essentia job.** `.github/workflows/ci.yml:105-123`, triggers
  `pull_request` and `push` (`:3-6`), builds with `--platform linux/amd64` (`:112`), runs the golden
  specs with `ESSENTIA_SPECS=1` and asserts an exact example count (`:117-123`). Run `31332017915`
  (2026-08-09) passed. **My Risk 4 was stale on the app side and is withdrawn.**
- **mood_probe has never had CI.** `.github` does not exist, and `git log --all --oneline -- .github`
  returns **zero** commits across the repository's entire history (verified independently).

### F.2 The adjudication MF-3 part 3 asked for — one answer

**The empty-models-dir proof lives in the gem's new `essentia` job. The app's job carries a mirror.**

I dispute MF-3 part 3's *placement* recommendation on two grounds:

1. **Its premise is now false.** It was written when the gem had no CI and no prospect of one. User
   decision 3 changes that.
2. **The reviewer did not note the decisive property: this proof needs no models.** Running `[:bpm]`
   exercises `RhythmExtractor2013`, which requires **Essentia** but requires **no `.pb` file at all**.
   So in the gem it can run in an image built from `Dockerfile.essentia` with **no `models fetch`
   step** — making it the *only* real-Essentia gate in the entire plan with no network dependency on
   `essentia.upf.edu`. The gem's own golden spec, by contrast, does require the fetch (README, and
   `spec/integration/essentia_golden_spec.rb:1-8`). Relocating the proof to the app would give it
   *more* dependencies, not fewer.

A third reason, structural: it is gem behaviour, and gating it in the app makes Phase B's "gem-only"
claim harder — a gem change would then be blocked by an app spec.

The mirror in the app is still worth having, because the app image ships the six `.pb` files
(`.dockerignore:34-35`, verified), so an empty directory there must be *created* rather than found —
which is exactly the right shape, and it makes the assertion an integration-level claim as well as a
unit one. Cheap redundancy on the strongest gate in the plan.

**MF-3 parts 1 and 2 accepted in full:**

- Assert a **value**, not success: `analysis[:bpm].value` finite and equal to **120 BPM** within
  tolerance on the click train (ground truth, §E.7).
- Add the **failing control** in the same spec: `analyze(path, descriptors: [:bpm, :mood_happy])`
  against the **same** empty dir must raise `ConfigurationError` naming the missing `.pb`. And assert
  the models dir is **still empty afterwards**, so a silent auto-fetch cannot satisfy the test. A
  green empty-dir run alone is equally consistent with "the planner is demand-driven" and "model
  verification was skipped entirely" — this team's own rule about passing controls applies.

### F.3 The gem's CI — Phase A scope

Mirror the shape of `vibe-doctor/.github/workflows/ci.yml`, triggers `pull_request` + `push`:

| Job | Runner | Needs Docker? | Needs network? | Contents |
| --- | --- | --- | --- | --- |
| `rspec` | `ubuntu-latest` | no | no | `bundle exec rspec` — planner assertions, plan fixture, `python_seam_spec.rb`, registry introspection, `:series` tripwire, capability cross-check, negative contract specs, mapper-adjacent Ruby specs. Blocking. |
| `essentia_offline` | `ubuntu-latest` | yes (`Dockerfile.essentia`, amd64 native) | **no** | The empty-models-dir proof (§F.2) + the sample-rate measurement gate (§E.7). Blocking. |
| `essentia_golden` | `ubuntu-latest` | yes | yes (`models fetch`) | The gem's exact-`eq` golden spec. Blocking, with the upstream-availability dependency stated in the workflow comment. |
| `lint` | `ubuntu-latest` | no | no | `bundle exec rubocop`. |

Splitting `essentia_offline` from `essentia_golden` is the point of the table: it keeps the strongest
gate free of the one dependency that can make it flaky.

**Also in Phase A (SF-1): fix the app's example-count arithmetic.** `ci.yml:121` computes
`expected=$(($(ls spec/fixtures/mood_probe/golden/*.json | wc -l) + 1))` and greps for
`^${expected} examples, 0 failures$` against a single named spec file. The count assertion is a good
anti-silent-skip device and must be kept — but adding examples to that file breaks the arithmetic, and
any new spec file does not run at all. Widen to a `--tag` selector and derive the expected count from
something that does not move when fixtures are added.

### F.4 Automate the falsifiability criterion (SF-3)

`principal.md` §6.2's "if Phase B requires touching `mood_probe_extract.py` or any `lib/` file other
than the registry, Phase A's design failed" is the best instrument in the plan and is currently a
promise. Make it a two-line job on the Phase B branch: `git diff --name-only main...HEAD` must match
only `lib/mood_probe/registry*`, `spec/`, and model-manifest paths.

---

## §G. Licensing (user decision 1)

vibe-doctor is **personal / non-commercial only**. Non-commercial MTG weights are acceptable and there
is **no commercial-use workstream**. Two corrective actions, both Phase A:

1. **Correct `NOTICE`.** Verified, `mood_probe/NOTICE:7-13` says the model metadata "identifies
   Creative Commons BY-NC-SA 4.0 and BY-NC-ND 4.0 terms, **depending on the model**." That claim is
   unsupported — Security found no per-model `license` field, and MTG applies a directory-wide licence
   (`security.md:13`). Replace with: **CC BY-NC-ND 4.0 as the compliance floor**, an explicit note that
   MTG's own pages conflict on SA vs ND, non-commercial under either reading, and no claim of
   per-model variation.
2. **Present licence and attribution before any model fetch.** `exe/mood-probe … models fetch` prints
   the licence identifier, attribution, source URL, and a non-commercial warning **before** downloading,
   generated from the new `license:` / `attribution:` fields on `Model` (§A.4) so the notice is data,
   not prose that can drift from the manifest.

Unchanged and still right: the gem ships no weights; no RubyGems release (§5.4); preserve exact
upstream bytes, never redistribute modified weights.

---

## §H. What the backfill workstream must provide (user decision 2)

Backfill is a separate ticket. I am not designing the mechanism. Three statements the separate ticket
needs:

**1. Phase A requires no backfill, and this must be written down** (S4). §6.5 Rule 2 asserts four heads
bit-identical and two algebraically identical to the frozen baseline — *that is the evidence* that no
re-enrichment is needed. Without saying so, someone will run `rake enrichment:reground_all` "to be
safe," which loads `Album.all` and calls `reset_enrichment!` on **every** album unconditionally
(`lib/tasks/enrichment.rake:23-24`), re-enriching the whole catalogue for zero benefit.

**2. Nothing selective exists today.** Verified: `Album.needing_enrichment` is status-only
(`app/models/album.rb:24`), `reset_enrichment!` sets only `enrichment_status: "pending"` (`:45-50`),
and `reground_all` resets everything. A time-based mechanism exists only on the unmerged
`feat/vibe-doctor-rollout-hardening` branch. There is no versioned invalidation to reuse.

**3. What Phase B (and every phase after it) will need from that ticket:**

- **A per-album record of what produced the stored values** — the descriptor-id set, the gem version,
  and the model versions/digests. Staleness must be *computable*, not guessed. The `Provenance` type
  (§2.2) plus `Model#model_version` are designed to supply exactly this; the backfill ticket decides
  where it is persisted.
- **A scope that selects albums whose recorded set differs from the current one**, replacing the
  status-only `needing_enrichment` for this purpose.
- **It must not be `reground_all`.** Adding five descriptors must re-enrich only albums missing them,
  not reset the catalogue.

Until that ticket lands, adding a descriptor that vibe-doctor *consumes* means a full reground — which
is the practical reason Phase B keeps vibe-doctor consuming nothing new.

---

## §I. Tier corrections

### I.1 Tier 1 membership (verified correction)

**Remove `timbre`, `approachability`, `engagement` from Tier 1.** They require the **1280-d
Discogs-EffNet** extractor, not the 200-d MusiCNN embedding (`security.md:86-90`, with per-model JSON
URLs). The brief (line 38) listed them as near-free MusiCNN candidates and was wrong. They belong to
the opt-in `discogs_effnet` pack — extractor 17.52 MiB + genre head 1.96 MiB + the three heads
≈ **21 MiB**, against the current committed 3.44 MiB.

**Tier 1 is therefore exactly five heads, totalling 0.39 MiB**: `mood_sad`, `mood_aggressive`,
`mood_party`, `mood_electronic`, `voice_instrumental` — plus optionally `tonal_atonal`
(0.08 MiB), which I verified independently takes a `[200]` MusiCNN input, output `model/Softmax`,
version `2`, `classes: ["atonal", "tonal"]`.

**The planner must never substitute one embedding family for another.** `Model#embedding` already
encodes the dependency (§1.6); add an assertion that a head's declared input dimension matches its
embedding's output dimension, so a 1280-d head pointed at a 200-d embedding fails at registration
rather than producing numbers.

`tonal_atonal`'s class order is **positive-second** (`["atonal", "tonal"]`), which brings the verified
inversion tally to **four of ten** MusiCNN heads. §0's conclusion strengthens.

### I.2 Phase B's `pack` consequence

Phase B ships `pack: :extended_musicnn`. Combined with demand-driven verification (§B), an operator
who has not installed the pack simply cannot request those descriptors — no error, no missing-file
abort. That is the mechanism that makes M1's fix and Security constraint 5 the same change.

### I.3 `llm_only` for new descriptors (S5)

The brief (line 51) asks for it and `principal.md` never mentions it. **Phase A does not need it** —
`default_attrs` (`app/services/mood_grounding_service.rb:45-46`) is untouched because no new
descriptor is consumed. **Deferred to Phase C**, named here rather than omitted. Phase C must define
what a `MoodVector`-adjacent record holds for `bpm`/`key` when audio grounding is unavailable.

---

## §J. Phase A — definition of done, as a checkable list

Phase A is unchanged in *concept*: "the same six numbers through new pipes," schema-free, gem and app
landing together. Its scope grew by roughly a third. It is still the right first slice — §K.

### J.1 Order of work (SF-10)

Two specs are writable **before any Phase A code exists**, because they run against the current
goldens and need no Essentia: the frozen baseline (E.1) and the mapper-identity spec (E.2). Expect
them in the first Phase A commit; treat their absence as the flag.

### J.2 Gem changes

- [ ] `Registry` with `Model` + `Descriptor` rows for the six current descriptors + `:musicnn_embedding`
      + `:bpm` + `:beat_confidence`; `classes` verbatim; **one selector form** `{ class: … }` (M5).
- [ ] `Model` carries `byte_length`, `license`, `attribution`, `pack`, `model_version`, `reduction` (S2, A.4).
- [ ] `Descriptor` carries `sanity_range` alongside `native_range`/`range_kind`; emomusic
      `(-3.0..13.0)`, softmax heads `(0.0..1.0)` (M3).
- [ ] `Value` hierarchy (`Scalar`/`Categorical`/`Vector`; `Series` defined, **zero** registry rows).
- [ ] `Analysis`, `Provenance`; `Vector` asserts `values.length == descriptor.shape` (M8/MF-8b).
- [ ] Ruby planner; `Plan` + wire schema v1; `Plan#required_files`.
- [ ] **`verify!(descriptors:)` required keyword. `preflight_environment!` split from
      `preflight_plan!` with its own boolean memo; descriptor-scoped memo keyed on the
      **descriptor-id set**; `ModelStore#verify!(filenames:)` demand-driven** (M1, MF-9, **N1**).
- [ ] **Fixtures (R1, R2):** `spec/fixtures/mood_probe/baseline_v0_1_0/*.json` — the same frozen
      bytes as the app's copy; and a native **44.1 kHz** click train from `generate.sh`, because the
      gate that reads it runs in the gem's `essentia_offline` job.
- [ ] `mood_probe_extract.py` rewritten as a plan executor: **static algorithm enum (no `getattr`),
      basename + root containment, per-algorithm param whitelist, `schema_version` handshake,
      `--capabilities`** (M2).
- [ ] Rescale and clamp deleted from the gem; `Features`/`HEADS` deleted; `allow_nan=False` with the
      serialisation `ValueError` mapped to **`malformed_output`** (MF-7).
- [ ] `reduce:` in plan `emit`, asserted Python-side (S1).
- [ ] `NOTICE` corrected; licence/attribution presented before `models fetch` (§G).
- [ ] **Gem CI: four jobs** per §F.3.
- [ ] Tag `v0.2.0`.

**Explicitly NOT in Phase A** (moved in Round 4): the bounded/streaming model-download rewrite (§C.3).
`byte_length` ships as a recorded-but-unenforced field until that commit lands.

### J.3 vibe-doctor changes — the complete list, split by commit (M6, M7, S10, N3)

`principal.md` listed the mapper, two `analyze` sites, and `Gemfile:34`. The verified full set, with
the Round-4 commit split in the first column:

| # | Commit | File | What changes |
| --- | --- | --- | --- |
| 1 | **B** | `app/models/mood_vectors/essentia_mapper.rb` | **new** — rescale + clamp, `DESCRIPTORS` constant |
| 2 | **B** | `app/services/mood_grounding_service.rb:93`, `:107` | `analyze(path, descriptors:)` → mapper |
| 3 | **B** | `app/jobs/enrich_album_job.rb:8` | `verify!(descriptors:)` (M1) |
| 4 | **B** | `lib/tasks/enrichment.rake:21`, `:44` | `verify!(descriptors:)` (M1) |
| 5 | **B** | `config/initializers/` | **new** — boot-time range-agreement check (M3(2)) |
| 6 | **B** | `Gemfile:34` + `Gemfile.lock` | `branch: "main"` → `tag: "v0.2.0"` |
| 7 | **I** | `.github/dependabot.yml` | **add `ignore` for `mood_probe`** (M7) |
| 8 | **I** | `.github/workflows/ci.yml:117-123` | example-count arithmetic + spec selection (SF-1); app-side mirror of the empty-dir proof (F.2) |
| 9 | **B** | `spec/services/mood_grounding_service_spec.rb:19`, `:193` | builds real `MoodProbe::Features` — replace with an `Analysis` builder |
| 10 | **B** | `spec/support/phase3_parity.rb` | **delete** — compares against a script deleted at `96e546f`; E.1's baseline supersedes it (SF-8) |
| 11 | **B** | `spec/fixtures/mood_probe/generate_goldens.rb:10`, `:15` | `analyze` arity + new payload shape |
| 12 | **B** | `spec/integration/essentia_extract_golden_spec.rb:20`, `:38-39` | `MOOD_HEADS` constant → requested descriptor list; `analyze` arity |
| 13 | **B** | `spec/jobs/enrich_album_job_spec.rb:99-114` | zero-arg `verify!` → `verify!(descriptors:)` (M1, N1) |
| 14 | **I** | `spec/fixtures/mood_probe/baseline_v0_1_0/*.json` | **new** — frozen baseline (MF-1), with the retirement comment from §E.1 |
| 15 | **B** | new specs | mapper identity (E.2), mapper clamp **boundaries** (E.2 — the one that actually enforces the clamp) |

**I = infrastructure commit, B = behaviour commit.** Items 7, 8 and 14 are guardrails and evidence,
orthogonal to the behaviour change, and **must survive a rollback**. Landing all fifteen as one commit
means a blanket revert removes the Dependabot `ignore` — the specific guard against the gem being
re-shipped accidentally — at exactly the moment a botched deploy has just been rolled back and the gem
tag is the thing you least want a bot advancing. Land **I first**, then **B**. Note item 15 no longer
carries the 44.1 kHz fixture: per R2 it belongs in the gem, where its gate runs (§J.2).

**Verified correction to my own §9 (S10): none of the four `Extractor.new` construction sites need to
change**, because `registry:` has a default of `Registry.default` (§2.1). What changes is two `analyze`
sites and three `verify!` sites. `principal.md` §9 said all four constructors must move; that was wrong,
and it matters because the size of the revert is the whole argument for Phase A being safe. Note also
`enrichment.rake:21` (not `:20`, as §5.3 stated).

Item 9 is the one to schedule first: `mood_grounding_service_spec.rb` is the app's **only** unit
coverage of aggregation, track-error skipping, and fatal propagation. If it does not load, the `test`
job goes red in the middle of the one deploy whose diff needs to be boring.

### J.4 Phase A definition of done — STANDALONE

*Written to stand on its own. A reader needs no other section of this document to check it.*

**What Phase A is:** the `mood_probe` gem stops being a mirror of vibe-doctor's six mood columns and
becomes a descriptor registry with typed results and an extraction planner. vibe-doctor produces
**the same six numbers it produces today**, now by asking for six named descriptors and mapping them
itself. No database migration. No new persisted field. Gem `v0.2.0` and the app change deploy together.

**Behaviour that must not change:** the six values written to `mood_vectors` for a given audio file,
to within `1e-4` relative on valence/arousal and bit-identically on the four softmax heads.

#### Structure

- [ ] **A1** Registry of `Model` + `Descriptor` rows: the six current descriptors, `:musicnn_embedding`,
      `:bpm`, `:beat_confidence`. Upstream `classes` transcribed **verbatim**; scalar projection selects
      by **class name**, never by index.
- [ ] **A2** `Model` carries `sha256`, `byte_length`, `license`, `attribution`, `pack`, `model_version`,
      `reduction`, and `embedding`. (`byte_length` is recorded but not yet enforced — the download
      rewrite is a separate commit.)
- [ ] **A3** `Descriptor` carries `native_range`, `range_kind`, and `sanity_range`. emomusic:
      `(1.0..9.0)` / `:nominal` / `(-3.0..13.0)`. Softmax heads: `(0.0..1.0)` / `:hard` /
      `(0.0..1.0)`, with construction raising unless `:hard` implies the two ranges are equal.
- [ ] **A4** `Value` hierarchy — `Scalar`, `Categorical`, `Vector`; `Series` defined with **zero**
      registry rows. `Analysis` and `Provenance`. `Vector` asserts `values.length == descriptor.shape`.
- [ ] **A5** Ruby-side planner: `plan_for(descriptors:)` → `Plan` with `loads`, `graphs`, `algorithms`,
      `emit`, `required_files`, and `schema_version`.
- [ ] **A6** `verify!(descriptors:)` — required keyword. **Environment preflight is separate from plan
      preflight**: `preflight_environment!` runs once per extractor under its own boolean memo;
      the descriptor-scoped path memoizes on the **descriptor-id set** and calls
      `ModelStore#verify!(filenames:)` with only the files the plan requires.
- [ ] **A7** `mood_probe_extract.py` becomes a plan executor: **static algorithm enum (no `getattr`)**,
      plan filenames validated as bare basenames and canonicalised inside the models root,
      per-algorithm parameter whitelist, `schema_version` handshake, `--capabilities` flag that prints
      before importing Essentia.
- [ ] **A8** Gem emits **native** values: the emomusic rescale and the clamp are deleted from the gem;
      `Features` and `HEADS` are deleted; `json.dumps(..., allow_nan=False)` with the serialisation
      `ValueError` mapped to **`malformed_output`**, not `inference_error`.
- [ ] **A9** vibe-doctor gains `MoodVectors::EssentiaMapper` doing `(v − 1.0) / 8.0` **and
      `.clamp(0.0, 1.0)`**, plus a boot initializer asserting the gem's declared emomusic range still
      equals the mapper's.
- [ ] **A10** All 15 app files in §J.3 updated, landed as **infrastructure commit then behaviour
      commit**; `Gemfile` pinned to `tag: "v0.2.0"`; Dependabot `ignore` added for `mood_probe`.

#### Evidence — every gate below must have a state in which it fails

- [ ] **G1** *(the load-bearing one)* Algebraic parity against the **frozen, unmodified**
      `baseline_v0_1_0/` goldens: four softmax heads `eq` the baseline; `(raw_emomusic − 1.0) / 8.0`
      within `max(1e-4·|expected|, 1e-10)`. **Run before any golden is rewritten.** The baseline is
      committed in both repos and never regenerated — retirement is a new dated directory, never an edit.
- [ ] **G2** Mapper identity: golden → `Analysis` → `EssentiaMapper#call` equals the baseline hash, and
      `keys == MoodVector::MOOD_HEADS`.
- [ ] **G3** Mapper clamp **boundaries**: `9.4 → 1.0` and `0.6 → 0.0`, with passing controls `9.0 → 1.0`
      and `1.0 → 0.0`. *(G2 cannot catch a dropped clamp — the clamp was inert on all eight goldens.)*
- [ ] **G4** `plan_for([:bpm]).graphs` is empty, and a `[:bpm]` analysis against an **empty models dir**
      returns **120 BPM ± tolerance** on the click train; the dir is still empty afterwards.
- [ ] **G5** Failing control for G4: `[:bpm, :mood_happy]` against the **same** empty dir raises
      `ConfigurationError` naming the missing `.pb`.
- [ ] **G6** Embedding reuse: `plan_for([:mood_happy, :mood_sad, …])` yields exactly one MusiCNN graph;
      over **three** files the embedding is **constructed once and invoked three times**, and each head
      invoked three times. *(Trace `__call__`, not only `__init__`.)*
- [ ] **G7** Preflight call counts: `verify!([:bpm])` invokes `preflight_plan!` exactly once;
      `verify!([:mood_happy])` then `verify!([:mood_happy, :bpm])` invokes it twice;
      `preflight_environment!` exactly once across all.
- [ ] **G8** `Extractor.new(models_dir: Dir.mktmpdir, python_executable: "/nonexistent")` +
      `verify!(descriptors: [:bpm])` raises `ConfigurationError`.
- [ ] **G9** `verify!([:bpm])` then `analyze(descriptors: [:mood_happy])` on an empty dir raises
      `ConfigurationError`.
- [ ] **G10** Committed plan fixtures (MusiCNN-only, algorithm-only, mixed) asserted `eq` from Ruby
      **and** parsed by Python; generated by a separate hand-run generator, never by the asserting spec.
- [ ] **G11** Capability cross-check: every `FromAlgorithm#name` and `Model#algorithm` in
      `Registry.default` appears in `--capabilities` output.
- [ ] **G12** Adversarial plan rejected: `file: "../../etc/passwd"`, and an unlisted algorithm name →
      exit 2, **with no Essentia import attempted**.
- [ ] **G13** Contract negatives — **three**, matching the three that exist today: unrequested id,
      missing id, wrong value type. Each raises, and each **stops** the batch.
- [ ] **G14** `Vector`: a 200-float payload passes; a 199-float payload raises `MalformedOutputError`
      naming the descriptor and both lengths; a spec actually requests `:musicnn_embedding`.
- [ ] **G15** Nested non-finite at depth ≥ 2 (inside a `Vector` list and a `Categorical` distribution),
      for `NaN`, `+Infinity` and `-Infinity`, crossing the **real** Python→Ruby seam, asserting
      `MalformedOutputError` **and its message** — not merely "it failed".
- [ ] **G16** `plan_for([:bpm, :mood_happy]).loads.map { it[:sample_rate] }` `eq`s `[16_000, 44_100]`.
- [ ] **G17** Registry loads and is fully introspectable with **no Python, no models dir, no Essentia**.
- [ ] **G18** `Registry.default.descriptors.none? { it.kind == :series }`.
- [ ] **G19** Resampling measurement recorded in the phase evidence: `[:bpm]` on the native-44.1 kHz
      click train vs `clicks.wav` (16 kHz, same construction), both values and the delta. An octave
      error is a finding, never a golden update.
- [ ] **G20** Gem CI green on all four jobs (`rspec`, `essentia_offline`, `essentia_golden`, `lint`);
      app CI green on all five.
- [ ] **G21** `NOTICE` corrected — CC BY-NC-ND 4.0 as the compliance floor, the SA/ND conflict noted,
      no "depending on the model" claim — and the fetch-time licence notice demonstrated.

#### Which gates run where

`G1`–`G3`, `G6`–`G18` are **pure Ruby or fake-double**: no Docker, no Essentia, no models dir. They
run on a developer Mac and in the gem's `rspec` job. `G4`, `G5`, `G19` need real Essentia but **no
model files**, so they run in the gem's `essentia_offline` job with no network fetch. Only the gem's
`essentia_golden` job and the app's `essentia` job need models.

### J.5 Rollback procedure

1. Revert the **behaviour** commit in vibe-doctor (§J.3 items 1–6, 9–13, 15). Leave the
   **infrastructure** commit (items 7, 8, 14) in place — reverting it would remove the Dependabot
   `ignore`, the CI fix, and the frozen baseline, all of which are guardrails against exactly the
   situation a rollback implies.
2. `Gemfile` returns to `tag: "v0.1.0"`; `bundle install`; commit the lockfile.
3. **Nothing else.** `mood_vectors` was never migrated and the persisted numbers are identical to
   within `1e-4`, so albums enriched under 0.2.0 are indistinguishable from albums enriched under
   0.1.0. There is no data to reconcile and no backfill to run.

**Two commits, not two lines** — the difference is whether someone budgets an hour or a day for the
rehearsal.

### J.6 Phase B definition of done (N6)

Phase B is the phase whose purpose is to **falsify Phase A's architecture**, so it needs checkable
criteria of its own rather than prose scattered across four sections.

- [ ] **B1** Five `Model` rows + six `Descriptor` rows added (`mood_sad`, `mood_aggressive`,
      `mood_party`, `mood_electronic`, `voice`/`instrumental`; optionally `tonal_atonal`),
      `pack: :extended_musicnn`. **Zero changes to `mood_probe_extract.py` or any `lib/` file other
      than the registry** — enforced by the `git diff --name-only` CI job (§F.4). If this criterion
      cannot be met, Phase A's design failed and that must be raised before Tier 2.
- [ ] **B2** Each head's upstream `.json` checked in beside its `.pb` checksum, with the JSON's own
      SHA-256 and fetch date in the registry row; a **non-network** spec asserts
      `Model#classes == JSON.parse(file)["classes"]` row-by-row. Reviewers check each row against
      **its own** JSON, never the neighbouring row. *(Four of ten heads are positive-second.)*
- [ ] **B8** The E.5-shaped closure — a committed introspection snapshot with its digest, a
      non-Docker spec asserting the gem's constants against the snapshot, and the Docker spec
      asserting the snapshot against the live library — turns drift into a red spec on a developer
      machine, the same conversion §C.1(e) makes for the capability cross-check (line 386-388).
- [ ] **B3** The Phase A goldens re-run **unchanged**. Any movement in the existing six means the
      embedding cache is broken.
- [ ] **B4** A vibe-doctor spec: Phase B's registry, with **only the six committed `.pb` files
      present**, preflights and analyses successfully. This is what makes "gem-only" true rather than
      asserted.
- [ ] **B5** A probability table for all heads over all fixtures, both classes each, attached to the
      PR for human review.
- [ ] **B6** **`voice_instrumental` orientation resolves into an artefact — one of exactly two
      completions, and "we measured and will decide later" is not one of them:**
      **(a)** a committed direction gate carrying its measured margin in the spec comment; **or**
      **(b)** a line in the descriptor's registry `notes` reading, in substance, *"no automated
      correctness gate; orientation verified by human review of the Phase B probability table,
      &lt;date&gt;, &lt;reviewer&gt;"*.
- [ ] **B7** No vibe-doctor change. If vibe-doctor consumes any new descriptor, the backfill ticket
      (§H) is a prerequisite, because the only re-enrichment tool today resets the whole catalogue.

---

## §K. Is Phase A still the right first slice?

**Yes, and the review strengthened the case rather than weakening it.**

The scope grew by roughly a third — `verify!` redesign, the wire hardening, the CI, five more app
files, `sanity_range`, and a materially larger test surface. **With one exception, none of that is
*new work*;** all of it is work that Phase B or a production incident would otherwise have surfaced
later and more expensively. M1 is the proof: without it, Phase B — the phase whose entire purpose is
to be gem-only — takes the catalogue down on a tag bump.

Sorting the growth honestly, as the Spec Reviewer did:

- **Precondition for the payoff:** the `verify!` redesign. Must be in Phase A because 0.2.0 is the one
  breaking release.
- **Zero marginal cost:** the wire hardening. The plan executor is being *written* in Phase A; writing
  it with a static enum instead of `getattr` is the same work done correctly. Deferring means
  deliberately writing the unsafe version first.
- **Behaviour preservation:** `sanity_range` — one field, two derived values. Deferring it ships a
  regression.
- **Always required, merely un-enumerated:** the five extra app files. Missing from the *estimate*,
  not added to the *scope* — the suite does not load without them.
- **A user decision, not review creep:** the gem CI.
- **The exception — genuinely new work, and now moved out (Round 4):** §C.3's streaming-downloader
  rewrite. Nothing else in Phase A waits on it, it answers a Security constraint rather than a review
  finding, and the existing downloader already fails closed on a digest mismatch
  (`model_store.rb:69-72`). `byte_length` stays; the enforcement is its own commit.

With that one move, the claim stands.

The property that made Phase A the right slice is untouched: **no migration, no schema change, nothing
to reconcile on revert.** The Spec Reviewer verified the data claim holds independently
(`spec.md:413-419`). Both mis-paired-deploy directions now fail loudly and early — gem-ahead raises
`ArgumentError` at the first `analyze`; app-ahead raises `NameError` at boot, which is strictly better
and is the reason M3(2) demands an initializer rather than a spec.

And Phase A remains a genuine generalization, not a relabel: five of the brief's six enumerated
couplings (brief:19-26) are removed in the first slice, and the sixth — no abstraction for DSP I/O
shapes — is what the `:bpm` row addresses.

---

## §L. Revised risks

Withdrawn or downgraded:

- **Old Risk 3/4 (CI) — withdrawn on the app side.** The amd64 job exists, runs on both triggers, and
  passed (run `31332017915`). It survives only as a gem-side item, which user decision 3 closes.
- **Old Risk 2 (clamp) — downgraded from "fails later than the change that caused it" to "loud and
  recoverable."** `album.rb:12` permits `failed → matching_audio` and `spec/models/album_spec.rb:30`
  covers the round trip. It stays a MUST-FIX because M3(b)'s *silent saturation* variant was the real
  hazard, and `sanity_range` closes it.

- **Old Risk 1 (sample rate) — downgraded from an unknown to a cost question.** Essentia's reference
  page states outright that `RhythmExtractor2013` **requires 44100 Hz** (§E.7, re-fetched and confirmed
  verbatim this round). So the *design* consequence is settled, not conjectural: settled decision 4's
  "load audio once" is definitively false, §8.2's correction is now verified fact, and the `loads` gate
  pins to two entries as a day-one pure-Ruby spec instead of waiting on Docker. What remains is
  measurement, not risk — see item 1 below.

Still standing, re-ranked:

1. **Cost, not correctness: is the second decode material, and does resampling change the answer?**
   Every DSP descriptor now provably costs a second decode. For 30 s previews that is very likely
   negligible; for the future playlist work on full sides it may not be. Separately, all existing
   fixtures are 16 kHz, so the honest open question is whether upsampling 16 kHz → 44.1 kHz yields the
   same BPM as native 44.1 kHz material — which is what the new fixture and G19 exist to answer.
   Least sure: whether the delta is large enough to matter to anything.
2. **Phase B's `voice_instrumental` may end with no automated correctness gate** (§E.5 item 3). The
   upstream-JSON check cannot protect an axis-free head, and I argued against committing an
   out-of-distribution semantic gate. The honest fallback is human review of a probability table,
   which is weaker than everything else in this plan. **Downgraded from "permanent" to "one phase":**
   the Test Reviewer's Phase C offer (§M.1) gives the head a real gate against the C-major arpeggio
   fixture — instrumental *and* in-distribution — so the exposure is bounded to Phase B rather than
   indefinite, and B6 forces it to be recorded rather than forgotten.
3. **The wire-hardening surface is new code in the least-testable language.** ~40 lines of Python
   validation, an enum, a param whitelist, path canonicalisation. The adversarial-plan spec and
   `--capabilities` both run on a Mac, which is why I accepted the design — but this is the largest
   block of Phase A code with no pre-existing analogue.
4. **`emomusic`'s `1.0..9.0` remains UNVERIFIED at the authoritative source.** `models.html` states
   `[1, 9]`; the per-model JSON does not. §A.2's `sanity_range` is derived from *current behaviour*, so
   it is correct regardless — but if the nominal range is wrong, vibe-doctor's rescale is wrong, and it
   is equally wrong today (`mood_probe_extract.py:63-64`). Emit raw emomusic for the four fixtures
   during Phase A; the frozen baseline already tells you the answer must fall in 2.81–6.81.
5. **Two-repo lockstep, residual after the tag pin and the Dependabot ignore:** someone runs
   `bundle update` by hand. Unmitigated by design; loud by construction.
6. **`Categorical` is still the weakest type** and I still lean toward one nullable-`distribution`
   type, revisited when `KeyExtractor` lands (Phase C). Unchanged from `principal.md` Risk 8.

Not verified by me: the five Tier-1 `.pb` digests and byte lengths (Security measured them —
`security.md:96`); Dependabot's exact behaviour on tag-pinned git gems (the `ignore` entry is correct
either way and costs nothing); production `mood_source` values (no database access).

---

## §M. Dispute outcomes and readiness

### M.1 Both disputes conceded — and one produced better evidence than either side started with

**Dispute 1 — placement of the empty-models-dir proof: CONCEDED on all three grounds.** The Test
Reviewer did not take my ground (b) on assertion; they fetched
`std_RhythmExtractor2013.html` and checked it, and I re-fetched it independently this round. The
algorithm's only input is `signal`; its complete parameter list is `maxTempo`, `minTempo`, `method` —
no filename, no graph, no weights, no TensorFlow — corroborated on `std_BeatTrackerMultiFeature.html`.
The claim is true, and the consequence is stronger than I stated it: because `Dockerfile.essentia:6`
already installs `ffmpeg`, the proof runs from that image with **no `models fetch` step at all**,
making it the only real-Essentia gate in the plan with no runtime dependency on `essentia.upf.edu`.
The gem's own golden spec *does* need the fetch (`spec/integration/essentia_golden_spec.rb:1-8`). So
the `essentia_offline` / `essentia_golden` split (§F.3) was judged the better answer, and the app-side
mirror is kept on its own merits.

**This is the round's best outcome and it is worth naming as a pattern:** verifying a disputed claim
turned up the fact that retired Risk 1 (§E.7). Neither of us would have found it by arguing.

**Dispute 2 — `sine_440` as a semantic direction control: CONCEDED, with one condition I accept in
full.** The reviewer overturned their own item on the symmetric standard to their Round 1 rule: *a
gate that cannot fail is not a gate; a gate whose red does not identify a defect is not a gate either.*
The condition is that "measure first, gate second" must complete into an **artefact**, because
otherwise it decays into a deferred decision that never returns. That is right, and it is now **B6**
in §J.6 with exactly two acceptable completions and an explicit statement that "we measured and will
decide later" is not one of them.

**And I am taking the offer that came with it.** Phase C adds a deterministic C-major arpeggio fixture
(`principal.md` §6.3) which is both genuinely instrumental *and* far closer to in-distribution than a
pure tone — exactly the combination `sine_440` lacks. **Phase C re-runs the direction control against
it.** If the margin holds there, `voice_instrumental` acquires a real automated gate one phase later
instead of never, and §L risk 2 downgrades. Cost: one assertion on a fixture already being added. That
converts my dispute from "this gate is unsafe, so there is no gate" into "this gate is unsafe *here*,
and here is where it becomes safe" — a better outcome than winning the argument.

### M.2 What changed because a premise turned out to be false

`principal.md` §1.4 and Risk 1, `principal-v2` §L Risk 1, and MF-10 all rested on "the Essentia
reference page does not state a required input rate." It does — in the Description prose rather than
the parameter table, which is a plausible way to read the page and miss it. I marked it UNVERIFIED in
Round 1 and did not re-challenge it in Round 3; the marker was mine to clear and I did not. It is
cleared now (§E.7), with three consequences folded in: the `loads` gate pins at two entries as a
day-one spec, Risk 1 becomes a cost question, and the measurement reframes from "what rate?" to "does
resampling change the answer?".

`principal.md` is preserved unedited by dispatch, so §E.7 is the correction of record for its §1.4
note.

### M.3 Is Phase A ready to implement? **YES.**

Every MUST-FIX across three review passes is closed: 18 from Round 3, plus N1/NF-1 from Round 4. Both
reviewers returned RESOLVED-WITH-RESIDUAL with no blocking item, and every residual either landed here
or is scheduled with a named home. §J.4 is a standalone definition of done — 10 structural items and
21 gates, each with a state in which it fails, and each labelled with where it runs.

Three things a reader should carry into implementation rather than discover:

1. **Phase A is large.** ~14 gem items, 15 app files across two commits, 21 gates. It is the largest
   slice in the plan and it will not land in a day. It is still the right slice, because its
   alternative is not "a smaller Phase A" but "the same work discovered during Phase B, in
   production" — which M1 demonstrates concretely. Scale expectations, not scope.
2. **The single biggest execution risk is the Python wire-hardening block** (§L risk 3) — roughly 40
   lines with no pre-existing analogue in either repo, in the language that cannot be run natively on
   the dev Mac. Mitigated by G11 and G12 both running on a laptop, but it is where I would expect
   trouble.
3. **G1 has an ordering constraint that cannot be recovered if violated.** The algebraic parity gate
   must run against the *unmodified* baseline before any golden is rewritten. Regenerate first and the
   evidence is gone permanently. It is checkbox one for a reason.

Nothing is missing. This is ready for user sign-off and dispatch to the Implementer.

---

## §N. Evidence

**HEADs:** vibe-doctor `0499d9cd38e7009eccbc6f75e50e93bd4800bc3e`; mood_probe
`5360f8fd8609eae39edb5dfab8a07f6439a0b137`. Both clean.

**Review artefacts read in full before responding to any finding:**
`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/spec.md` (627 lines),
`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/test.md` (629 lines),
`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/security.md` (247 lines), and my own `principal.md`.
**Round 4 additionally:** `spec-rereview.md` (362 lines) and `test-rereview.md` (307 lines), both in
full before responding to any of their findings.

**Round 4 verification (I did not take either new finding on report):**

| Claim | Method | Result |
| --- | --- | --- |
| N1: an empty file set short-circuits `verify!` | `ruby -rset -e 'p Set[].subset?(Set[]); p Set[].subset?(Set["a.pb"])'` | `true`, `true` — confirmed |
| N1: mixed request skips DSP preflight | same, with `{musd,mood_happy}.subset?({musd,mood_happy})` | `true` — `:bpm` adds no file, so `[:mood_happy, :bpm]` never re-preflights |
| RhythmExtractor2013 requires 44100 Hz | re-fetched `essentia.upf.edu/reference/std_RhythmExtractor2013.html` | verbatim: *"Note that the algorithm requires the sample rate of the input signal to be 44100 Hz in order to work correctly."* |
| Dispute-1 ground (b): no model parameter | same fetch | complete parameter list is `maxTempo`, `minTempo`, `method`; no filename/graph/weights |
| N5: three negative-contract specs, not two | `sed -n '140,162p' spec/extractor_spec.rb` | `:146` missing key, `:147` unexpected key, **`:148` non-numeric type**; batch-stop assertion at `:158` |

**Round 4 commands (all read-only):** the `ruby -rset` one-liner above; `sed -n '140,162p'` on
`mood_probe/spec/extractor_spec.rb`; `grep -n` for section offsets in this document; one WebFetch of
the RhythmExtractor2013 reference page. No repository file was created, modified, or deleted in either
repo this round; the only file written is this one.

**Source re-verified this round (not taken from the reviews):**

| Claim | Verified at |
| --- | --- |
| `verify!` zero-arg; whole-registry iteration; boolean memo | `extractor.rb:16,19-24,35`; `model_store.rb:41-44,58` |
| Three guards in `Features` | `features.rb:6,7,19,44-52`; `errors.rb:7` |
| `allow_nan` ValueError → `inference_error` | `mood_probe_extract.py:68-69,107-136` (single `try`, `emit` at `:126` inside it) |
| Dependabot bundler ecosystem, **no `ignore`** | `.github/dependabot.yml:3-7` (full file read) |
| App `essentia` job at `:105`, example-count arithmetic | `.github/workflows/ci.yml:3-6,105,112,117-123` |
| Bug 1 fixed | `album.rb:12`; `spec/models/album_spec.rb:30` |
| Five M6 files | `mood_grounding_service_spec.rb:19,193`; `phase3_parity.rb:33`; `generate_goldens.rb:15`; `essentia_extract_golden_spec.rb:38,79`; `enrich_album_job_spec.rb:99-114` |
| Old-contract negative specs (the MF-8a template) | `spec/extractor_spec.rb:146,147,150,157` |
| Gem has never had CI | `ls .github` → absent; `git log --all --oneline -- .github` → **0 commits** |
| `NOTICE` "depending on the model" | `mood_probe/NOTICE:7-13` |
| `clicks.wav` = 120 BPM by construction | `spec/fixtures/mood_probe/audio/generate.sh:21-24` (`mod(t, 0.5)`) |
| All four fixtures 16000 Hz / 1 ch / 10.0 s | `ffprobe -show_entries stream=sample_rate,channels,duration` on each |
| `tonal_atonal` is MusiCNN 200-d, `["atonal","tonal"]`, v2 | upstream `tonal_atonal-msd-musicnn-1.json` (fetched this round) |

**Commands run (all read-only):** `git -C <repo> rev-parse HEAD`; `git log --all --oneline -- .github`
(mood_probe); `cat -n` / `sed -n` on each file above; `grep -rn "MoodProbe::Features\|\.analyze("` over
`spec/` and `app/`; `grep -n "missing key\|unexpected key\|SchemaError" spec/extractor_spec.rb`;
`ffprobe` on the four decodable fixtures; one WebFetch of the `tonal_atonal` model metadata JSON.

**Read-only confirmation:** no file in either repository was created, modified, or deleted. The only
file written this round is this report, outside both repos.

**Proposed spec filename (unchanged):**
`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-design.md`
