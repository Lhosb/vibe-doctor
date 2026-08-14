# ESSENTIA-GEM-V2 Phase A — Whole-Branch Integration Review — TEST

**VERDICT: APPROVE-WITH-FINDINGS**

**Scope:** gem only, `55d85fb..848f689` (65 files, +4716/−653, 26 commits), branch `feat/essentia-gem-v2-phase-a`, tag `v0.2.0` peels to HEAD.
**Prior record read:** all sixteen of my own `test*.md` files across slices 1–5. No closed finding is re-litigated below, and I found none closed wrongly.

Four findings, three of them only visible from the whole branch: two are places where a fix landed in one repo or one file and its twin was never revisited, one is an escape hatch that contradicts its own README, and one is a coverage hole that every per-slice review was individually right to ignore.

---

## 1. Gate inventory

Status assigned by mutation where marked ⚡ — a concrete change to production code that turns the gate red. Everything else is by reading, and I say so.

| Gate | Implementation | Status |
|---|---|---|
| **G1** | `spec/baseline_v0_1_0_parity_spec.rb:20-35` (4 examples, one per discovered baseline file; floor at `:3`) | **IMPLEMENTED-AND-BITES** ⚡ — but its tolerance is pinned by nothing (Finding 1) |
| G2 | app-side mapper identity | **OUT-OF-SCOPE-FOR-GEM** |
| G3 | app-side clamp boundaries | **OUT-OF-SCOPE-FOR-GEM** |
| G4 | `planner_spec.rb:22` (graphs empty) + `essentia_offline_spec.rb:39` (120 BPM, empty dir, dir still empty) | IMPLEMENTED-AND-BITES — mutated in slice 3 (halved BPM → red) |
| G5 | `essentia_offline_spec.rb:53` | IMPLEMENTED-AND-BITES — by reading; slice-3 record shows the fault injection |
| **G6** | `python_plan_executor_spec.rb:41` — 1 init / 3 calls for the embedding, 1 init / 3 calls per head | **IMPLEMENTED-AND-BITES** ⚡ (mutation 2 below) |
| G7 | `extractor_v2_spec.rb:25,34,45,52` | IMPLEMENTED-AND-BITES — mutated in slice 2 (cardinality key) and slice 2 r2 |
| G8 | `extractor_v2_spec.rb:72` | IMPLEMENTED-AND-BITES — mutated in slice 2 (old `subset?` shape → "nothing was raised") |
| G9 | `extractor_v2_spec.rb:84` | IMPLEMENTED-AND-BITES — mutated in slice 2 (no-op `ModelStore#verify!`) |
| **G10** | Ruby: `planner_spec.rb:12` (literal hash of 4). Python: `python_plan_fixture_spec.rb:8` | **Ruby half BITES; Python half IMPLEMENTED-BUT-VACUOUS** ⚡ (Finding 2) |
| G11 | `python_plan_security_spec.rb:9` | IMPLEMENTED-AND-BITES — mutated in slice 3 (empty registry → RSpec refuses zero-arg `include`) |
| G12 | `python_plan_security_spec.rb:33,62` | IMPLEMENTED-AND-BITES — four independent falsifiers run in slices 3 and 3r2/r3/r4 |
| G13 | `extractor_v2_spec.rb:117` (three negatives, each with the positive `one.wav` half) | IMPLEMENTED-AND-BITES — mutated in slice 2 and 2r2 |
| G14 | `value_spec.rb:95,106` + `extractor_v2_spec.rb:135,145` | IMPLEMENTED-AND-BITES — mutated in slice 2 (length check removed) |
| **G15** | `python_plan_executor_spec.rb:82,104,130,184` + `python_seam_spec.rb:38` | **IMPLEMENTED-AND-BITES** ⚡ (mutation 3 below) |
| G16 | `planner_spec.rb:69` | IMPLEMENTED-AND-BITES — mutated in slice 2 (reversed order → `[44100, 16000]`) |
| G17 | `registry_spec.rb:114` | IMPLEMENTED-AND-BITES — mutated in slice 2 (registry coupled to `/nonexistent` Python) |
| G18 | `registry_spec.rb:128` | IMPLEMENTED-AND-BITES — non-vacuity floor added in slice 2 r2 after I proved it passed on an empty registry |
| G19 | `essentia_offline_spec.rb:195` + artefact + CI `if-no-files-found: error` | IMPLEMENTED-AND-BITES — I proved liveness in slice 3 by feeding an 80-BPM train: `delta=40.009, verdict=finding` |
| **G20** | gem half: `release_ci_spec.rb:12` asserts `contain_exactly("rspec","essentia_offline","essentia_golden","lint")` | gem half IMPLEMENTED-AND-BITES (by reading); **app half OUT-OF-SCOPE** |
| G21 | `license_notice_spec.rb:9,16,33,45` | IMPLEMENTED-AND-BITES — mutated in slice 4 (hardcoded literal instead of `Model#license` → red) |

**No gate is MISSING.** All 21 are accounted for: 18 implemented in the gem, 3 out of scope (G2, G3, app half of G20).

### Structural items A1–A10
Verified by reading at HEAD: A1–A8 present in the gem (`registry.rb`, `value.rb`, `plan.rb`, `extractor.rb`, `mood_probe_extract.py`); `features.rb` and `model_registry.rb` are deleted. A9 and A10 are app-side and out of scope for this review.

---

## 2. Findings

### Finding 1 — SHOULD-FIX. The gem's G1 tolerance is pinned by nothing; the app's twin was fixed and the gem's was not.

**File:** `spec/baseline_v0_1_0_parity_spec.rb:29`
**What is wrong:** `tolerance = [1e-4 * expected.abs, 1e-10].max` is a bare literal with no calibration control. The spec has no just-inside passing control and no just-outside failing control, so nothing constrains the bound.

```
rel tolerance=1e-1  -> 4 examples, 0 failures  green
rel tolerance=1e-2  -> 4 examples, 0 failures  green
rel tolerance=1e-4  -> 4 examples, 0 failures  green
rel tolerance=1e-6  -> 4 examples, 0 failures  green
rel tolerance=1e-9  -> 4 examples, 0 failures  green
```

**Green across eight orders of magnitude.** This is the identical defect I found in the app's copy during slice 5b and which was fixed there — the app now carries a `0.9e-4` passing control and a `1.1e-4` failing control, and only `1e-4` is green. The gem's copy was written in slice 4, before I found the problem, and slice 5 reviewed only the app. **No per-slice review could see the asymmetry.**

**Failure scenario:** someone regenerates the gem's goldens on a future Essentia and, to make a stubborn cell pass, widens the constant to `1e-2`. Every example stays green, and the gate that the Principal designated *"a regression tripwire on the next regeneration"* silently stops tripping. It costs nothing today only because deviation is exactly zero — which is itself the reason no other assertion can catch the change.

**Fix:** the two examples the app already has, ported. `with_perturbed_baseline(relative_delta: 0.9e-4)` expecting success and `1.1e-4` expecting the attributed raise — with the literals anchored, not derived from the constant.

### Finding 2 — SHOULD-FIX. G10's Python half is vacuous on empty discovery, and it is the half that carries §E.4.

**File:** `spec/python_plan_fixture_spec.rb:12`
**What is wrong:** `fixture_dir.glob("*.json").sort.each do |fixture|` — a discovered collection with no non-empty floor. If discovery returns nothing, the loop body never runs and the example passes having parsed nothing.

```
discovery replaced with []  ->  3 examples, 0 failures  rc=0   *** VACUOUS ***
```

The Ruby half (`planner_spec.rb:6-19`) iterates a **literal hash of four**, so it cannot go empty. The asymmetry matters because §E.4's entire point is that the *Python* side is what turns "the fixtures are what Ruby produces" into "and Python accepts them" — the half that establishes the property is the vacuous one.

**Failure scenario:** the plan fixtures move directory, or the glob pattern changes to `*.plan.json` during a Phase B refactor. The Ruby half goes red immediately (it names each file). The Python half goes green having validated zero plans, and the "both sides can fail" property is silently lost while CI stays green.

**Fix:** `raise "no plan fixtures discovered" if …empty?` at load time — the pattern already in this repo at `spec/baseline_v0_1_0_parity_spec.rb:3`, one file over.

### Finding 3 — SHOULD-FIX. `MOOD_PROBE_ALLOW_NON_CANONICAL=1` can produce committed goldens, contrary to the README.

**Files:** `spec/support/canonical_essentia_environment.rb:17`, `spec/fixtures/mood_probe/generate_goldens.rb:8`, `README.md:52`
**What is wrong:** the generator is guarded (good — that was my slice-3 finding, closed), but the guard honours the override, and nothing downstream distinguishes a golden made under it.

```
host_cpu=arm64   override=nil  -> refused
host_cpu=arm64   override="1"  -> PROCEEDS (generator would write goldens)
host_cpu=x86_64  override=nil  -> refused        # emulation detector working: VirtualApple ≠ Xeon/EPYC
```

The README says the override *"is available only for deliberate investigation; it must not be used to produce committed goldens."* That is a statement with no failing state. And the gem's golden gate compares with `golden_rel_tol = 1e-4` (`essentia_golden_spec.rb:36`), while the measured emulated-vs-native divergence is ~1e-6 — so goldens generated under the override sail through CI with ~25× margin.

**Failure scenario:** a maintainer on an Apple Silicon Mac sets the override to investigate a golden mismatch, regenerates, and commits. CI is green. The committed goldens are now emulated-environment values presented as native ones, and the only record that would say otherwise is `PROVENANCE.md`, which is written by hand by the same person.

**Fix (cheapest that closes it):** have the generator refuse to write into the committed `golden/` directory when the override is set — write to a scratch path instead, or require an explicit output directory argument alongside the override. That keeps the escape hatch for investigation, which is its stated purpose, while making the README's claim true by construction rather than by intention.

### Finding 4 — SHOULD-FIX (coverage). `:musicnn_embedding` never meets real Essentia; its contract is validated only against a fake that agrees with it by construction.

**Files:** `spec/integration/essentia_offline_spec.rb:45,60`; `spec/integration/essentia_golden_spec.rb:20-28`; `spec/support/fake_essentia/essentia/standard.py:44`
**What is wrong:** of the nine registry descriptors —

```
[:valence_emomusic, :arousal_emomusic, :danceability, :mood_acoustic,
 :mood_relaxed, :mood_happy, :musicnn_embedding, :bpm, :beat_confidence]
```

— real Essentia extracts `:bpm` (in `essentia_offline`) and the six mood heads (in `essentia_golden`). **`:musicnn_embedding` and `:beat_confidence` are never extracted for real anywhere on the branch.**

`:musicnn_embedding` is the one that matters. It is the 200-float `Vector` whose `values.length == descriptor.shape` assertion is A4's contract and G14's subject, and it is the shared embedding the entire planner design exists to reuse (G6). Its only end-to-end exercise is against `fake_essentia`, which returns `[0.25] * 200` — a literal chosen to match the registry's `shape: 200`. **The fake agrees with the registry by construction, so the pair cannot disagree.**

**Failure scenario:** upstream `msd-musicnn-1.pb` emits a 512-wide embedding, or `mean(axis=0)` returns a different rank against real TensorFlow output than against the fake's stub. Every gem spec stays green — G14 passes against the fake, G6 counts calls not shapes, and the golden gate never requests `:musicnn_embedding`. The first failure is in a consumer, after release.

**Fix:** add `:musicnn_embedding` to the `essentia_golden` descriptor list, or one `essentia_golden` example asserting only `analysis[:musicnn_embedding].values.length == 200` against real models. It needs the models the job already fetches, so the marginal cost is one extraction.

*I want to be honest that I expected to find the executor's reduction thin too, and it is not.* I mutated `mean(axis=0)` → `value[0]` and it was killed by **12 failures in the plain `rspec` job** — the fake's `mean` is a real computation, not a stub, so the reduction is genuinely covered without models. That probe is in the evidence.

### Finding 5 — NIT. `Series` exists with no constructor coverage.

**File:** `lib/mood_probe/value.rb` (`Series`), `spec/value_spec.rb:155`, `spec/registry_spec.rb:128-129`
Nothing constructs a `Series`. The only assertions are `be_a(Class)` and `be < MoodProbe::Value`. Its validation logic — array-type check, times/values length mismatch, per-element non-finite check — is dead code today. This is *intended* per A4/G18 (defined with zero registry rows so Phase C has a shape to grow into), and G18 correctly asserts no `:series` row exists. Recording it so nobody mistakes "the class is asserted" for "the class is tested": the first Phase C descriptor to use it will be its first exercise.

### Finding 6 — NIT (against the stated intent). The gem's own regression gate speaks vibe-doctor's vocabulary.

**File:** `spec/baseline_v0_1_0_parity_spec.rb:9-18`

```ruby
"valence" => "valence_emomusic",
"arousal" => "arousal_emomusic"
```

The gem's parity gate is expressed as a mapping *from vibe-doctor's `MoodVector` column names* onto the gem's descriptor ids, and `baseline_v0_1_0/*.json` is keyed by those app column names. The gem is asserting that its output still reconstitutes the app's six columns.

Against the user's stated intent — *"a less opinionated ruby wrapper of essentia"* — this is the clearest place in the test suite where the app's opinion survives inside the gem. It is defensible: the baseline is a frozen historical artefact and re-keying it would breach the never-edited invariant, which is a stronger property than vocabulary hygiene. But the *conclusion* the gem needs from its own regression gate is "my descriptors are stable across the refactor", and that could be asserted in the gem's own ids with the app's mapping living in the app. Not worth doing now — the baseline is immutable and the gate is correct — but worth naming, because a Phase C reader will find `"valence"` in the gem and reasonably wonder whose name that is.

---

## 3. Non-vacuity sweep against the standing lessons

| Lesson | Result |
|---|---|
| Assert the gate ran on something | G1 gem-side **has** the floor (`:3`, added slice 4 r2). G10 Python half **does not** — Finding 2. G17/G18 floors added in slice 2 r2. `essentia_golden` fail-closed on empty discovery (`release_ci_spec.rb:33`). |
| Tolerance needs a passing control just inside | **G1 gem-side has neither control** — Finding 1. The app's twin has both. `essentia_golden_spec` carries the 24-cell matrix with both directions (slice 4 r2). |
| A helper parameterising one axis covers one axis | The gem has no clamp (A8 deleted it — this was the 5a lesson, app-side). Range/sanity assertions cover **all six heads**: `registry_spec.rb` asserts `(1.0..9.0)/:nominal/(-3.0..13.0)` for both emomusic heads and `(0.0..1.0)/:hard/(0.0..1.0)` for all four softmax heads. No per-head gap. |
| Zero deviation within one environment proves nothing | Understood and applied: G1 currently reads exactly zero, which is why Finding 1 is invisible to every other assertion in that file. |
| Environment-dependent gates must fail naming the environment | `CanonicalEssentiaEnvironment` names host CPU **and** CPU model, and the detector correctly rejects `x86_64 + VirtualApple`. The guard sits on the generator (`generate_goldens.rb:8`) **and** the capture script **and** the golden spec. The escape hatch is Finding 3. |
| Test the serialisation seam, not a Ruby-side simulation | **Satisfied, and I checked the specific worry.** G15's non-finite cases cross a real `Open3` subprocess, real `json.dumps(allow_nan=False)` and real Ruby `JSON.parse`; only the *Essentia library* is faked. The fake is what *produces* NaN/±Inf — it cannot be what *transports* them, and transport is where the bug class lives. Depth ≥ 2 is covered for `Vector` (`musicnn_embedding[17]`) and depth 3 for `Categorical` (`beat_category.distribution.unstable`), for NaN, +Infinity and −Infinity, each asserting the message. The fake is not standing in where the real seam was required. |

---

## 4. Whole-branch coverage: where the branch is thinnest relative to risk

**Answer: `:musicnn_embedding` — Finding 4.** It is the highest-value untested behaviour on the branch: a public registry descriptor, the subject of a dedicated shape contract, the object the entire planner exists to construct once and reuse, and the only one of the six model-backed outputs that no real-Essentia gate ever requests.

The Python executor itself is **better covered than its 562 new lines suggest**, and I checked rather than assumed:

- All four emitted error types are asserted, not merely mentioned — `unreadable_audio` (2 sites), `malformed_output`, and `inference_error` at `python_script_spec.rb:52` (real payload) and `python_seam_spec.rb:33` (typed outcome).
- The plan-validation surface carries 33 examples in `python_plan_security_spec.rb` alone, with both-sided domain bounds proven in slice 3 round 4.
- The reduction arithmetic is killed by 12 failures without models (probe above).

The residual risk is not in the executor's logic. It is that **two of nine descriptors have never been run through it against the real library**, and one of them carries a shape contract that its fake satisfies by definition.

---

## 5. Evidence

**Diff range:** `55d85fb246e45581172d58066c24e41c8970ac9b..848f6894a6022b5a32ae2b6b0c6898ac84986fa0` — 65 files, +4716/−653, 26 commits. `v0.2.0` peels to `848f689` (verified).

All mutations were made on a `git clone --no-hardlinks` **outside both repositories**, reverted after each run, and the clone deleted.

```
$ git -C <gem> rev-parse HEAD            → 848f6894a6022b5a32ae2b6b0c6898ac84986fa0
$ git -C <gem> rev-parse v0.2.0^{}       → 848f6894a6022b5a32ae2b6b0c6898ac84986fa0
$ git -C <gem> rev-list --count 55d85fb..848f689 → 26
$ (gem) bundle exec rspec                → 173 examples, 0 failures
$ (gem) ESSENTIA_SPECS=1 … --dry-run     → 187 examples   (the extra 14 = essentia_golden 8 + essentia_offline 6)
```

**Mutation 1 — G1 (mandatory), gem-side tolerance:**
```
rel tolerance=1e-1 -> 4 examples, 0 failures  rc=0 green
rel tolerance=1e-2 -> 4 examples, 0 failures  rc=0 green
rel tolerance=1e-4 -> 4 examples, 0 failures  rc=0 green
rel tolerance=1e-6 -> 4 examples, 0 failures  rc=0 green
rel tolerance=1e-9 -> 4 examples, 0 failures  rc=0 green
```

**Mutation 2 — G6, embedding reuse.** `build_pipeline` moved inside the per-path loop in `python/mood_probe_extract.py`:
```
G6: rebuild pipeline per audio path   12 examples, 1 failure   killed
```

**Mutation 3 — G15, nested non-finite across the real seam.** Two independent faults in the executor:
```
G15: stop recursing into lists      15 examples, 4 failures   killed
G15: message drops the location     15 examples, 8 failures   killed
```

**Finding 2 probe:**
```
python_plan_fixture_spec discovery replaced with []  ->  3 examples, 0 failures  rc=0  VACUOUS
```

**Finding 3 probe** (guard invoked directly, no Essentia needed):
```
host_cpu=arm64   override=nil  -> refused
host_cpu=arm64   override="1"  -> PROCEEDS
host_cpu=x86_64  override=nil  -> refused
$ grep -n GOLDEN/golden_rel_tol spec/integration/essentia_golden_spec.rb → 36: let(:golden_rel_tol) { 1e-4 }
$ grep -n ALLOW_NON_CANONICAL README.md → 52: "…available only for…"
```

**Finding 4 evidence:**
```
$ bundle exec ruby -Ilib -e 'puts MoodProbe::Registry.default.ids.inspect'
[:valence_emomusic, :arousal_emomusic, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy,
 :musicnn_embedding, :bpm, :beat_confidence]
essentia_offline descriptors: [:bpm]  and  %i[bpm mood_happy] (failure case, never extracts)
essentia_golden  descriptors: the six mood heads
fake_essentia standard.py:44 → values = [0.25] * 200
```

**Reduction probe (my hypothesis, refuted):**
```
reduce -> value[0] instead of mean(axis=0)
  without ESSENTIA_SPECS (the rspec job):  173 examples, 12 failures  killed
  with    ESSENTIA_SPECS=1:                187 examples, 18 failures  killed
```

**Final state — verified:**
```
$ git -C <gem> status --short  → (empty)     HEAD 848f6894…  (unchanged, at HEAD)
$ git -C <app> status --short  → only this report's new directory, untracked
$ scratch clone                → reverted and deleted
```

Both repositories are clean at HEAD; the only file I created is this report, at the location the dispatch specified.

**Distinguishing verification from belief:** the four findings and the three mandated mutations are things **I verified by running**, with output pasted above. Gate statuses marked ⚡ are mutation-verified in this pass; the remainder are verified by reading at HEAD plus my own mutation records from slices 1–5, which I cite rather than re-run. I have not run the gem's CI jobs — G20's green status is the manager's verification, not mine.

---

Phase A's gate set is in genuinely good condition: 18 of 18 in-scope gates are implemented, none is missing, and the three I mutated for this pass all bite hard. The findings are not gaps in what the slices built — they are the seams *between* slices, which is the only place a whole-branch pass can look: a bound calibrated in one repo and not its twin, a floor added to one discovered collection and not the next, an escape hatch that outlived the finding that created it, and a descriptor that every individual slice was correct to leave to another.
