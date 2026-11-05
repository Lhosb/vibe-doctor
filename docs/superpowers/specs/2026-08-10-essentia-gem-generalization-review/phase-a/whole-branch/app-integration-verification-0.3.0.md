# sonance 0.3.0 integration in vibe-doctor — verification

**IS THE INTEGRATION WORKING AS INTENDED — YES.**

Same method as the 0.2.0 pass, repeated against the migrated app. App at `e4ff685` on `docs/essentia-gem-v2-design`, running **sonance 0.3.0**. Read-only throughout; scratch work outside both repos, deleted.

---

## One thing I chased down before starting — resolved, benign

The dispatch says v0.3.0 peels to `6639397`, but `Gemfile.lock:3` records `revision: cf8e613e…`. Those look like a moved tag, which would be serious. They are not:

```
$ git -C <gem> cat-file -t cf8e613e…   → tag       ← the annotated tag OBJECT
$ git -C <gem> log --oneline -1 cf8e613e…  → 6639397 fix: validate descriptor lists repo-wide
$ git -C <gem> rev-parse v0.3.0^{}     → 66393972a8b57ee116afec0fbeb879a0c410dbca
```

Bundler records the **annotated tag object's** SHA for a `tag:` pin; the dispatch quotes the **peeled commit**. Both are correct and they agree. Worth writing down so nobody else spends five minutes on it.

Installed gem confirmed as the pinned one: `bundle info sonance` → `sonance (0.3.0 cf8e613)`, `Sonance::VERSION = 0.3.0`.

---

## 1. Suite and lint — VERIFIED by execution

```
$ bin/rails assets:precompile   → rc=0
$ bundle exec rspec             → 298 examples, 0 failures   (rc=0)
$ bundle exec rubocop           → 207 files inspected, no offenses detected
```

I precompiled first as instructed. **The Vibe Map asset failures did not occur** — clean on the first run after precompile, so there was nothing to misattribute. Your 298/0 and 207/0 figures are confirmed independently.

**Zero surviving old identifiers in active code:** `grep -rn "MoodProbe\|mood_probe\|MOOD_PROBE" app/ lib/ config/ bin/` → none.

---

## 2. The boot initializer still fires — VERIFIED by breaking it

The file was renamed (`config/initializers/sonance_registry.rb`) and its descriptor list changed, so I did not assume it still asserts. I patched `Sonance::Registry.default` *after* the gem loads and *before* `after_initialize`, then called `Rails.application.initialize!`:

```
mode=control  →  BOOTED OK — no raise
mode=range    →  RAISED RuntimeError: valence_emomusic native range 0.0..9.0 does not match mapper range 1.0..9.0
mode=missing  →  RAISED RuntimeError: sonance registry is missing mapped descriptors: mood_happy_musicnn
```

Both clauses have a real failing state and the control boots clean. The missing-descriptor message names the **qualified** id `mood_happy_musicnn`, which proves the clause is reading the migrated list rather than a stale one.

---

## 3. Native in, normalised out — the one number, and it did not move

**VERIFIED by execution. The exact identity from the 0.2.0 pass reproduces on 0.3.0:**

```
golden dir   = spec/fixtures/sonance/golden
baseline dir = spec/fixtures/sonance/baseline_v0_1_0
golden keys  = [:valence_emomusic, :arousal_emomusic, :danceability_musicnn,
                :mood_acoustic_musicnn, :mood_relaxed_musicnn, :mood_happy_musicnn]

golden clicks valence_emomusic = 5.8459882736206055   (NATIVE, inside 1.0..9.0: true)
mapper → valence               = 0.6057485342025757
frozen v0.1.0 baseline valence = 0.6057485342025757
BIT-IDENTICAL: true
0.2.0 pass recorded the same two numbers; unchanged: true
```

And I went further than last time — **all four fixtures × all six heads, mapper output against the frozen baseline:**

```
chirp        max |mapper − baseline| = 0.0   exact: true
clicks       max |mapper − baseline| = 0.0   exact: true
sine_440     max |mapper − baseline| = 0.0   exact: true
white_noise  max |mapper − baseline| = 0.0   exact: true
```

**Zero deviation on all 24 cells.** A gem rename, a module rename and a descriptor-id migration moved not one bit of the chain from native extraction through to the values the app stores. If the app were double-normalising, valence would be `(0.6057 − 1)/8 = −0.049` → clamped to `0.0`; if it were not normalising, `5.846` would fail `MoodVector`'s `0.0..1.0` validation and nothing would save. Neither is happening.

---

## 4. The mapper — VERIFIED by execution

```
keys                   = [:valence, :arousal, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy]
MoodVector::MOOD_HEADS = [:valence, :arousal, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy]
keys == MOOD_HEADS?      true
```

The mapper takes the **new qualified ids in** and emits the app's **unqualified column names out** — the rename stopped at the seam, exactly where it should.

Clamp exercised at boundaries no golden reaches, driven by ids that changed:

```
valence_emomusic       9.4  → 1.0   (unclamped 1.0500)   OK
valence_emomusic       0.6  → 0.0   (unclamped −0.0500)  OK
danceability_musicnn   1.1  → 1.0                        OK
danceability_musicnn  −0.1  → 0.0                        OK
```

The "unclamped" column is the point: each of those four values is outside the range any golden occupies, so the clamp is doing work rather than passing a value through. Golden-only coverage could not have shown this — the clamp was inert on all eight goldens.

---

## 5. Real Essentia, end to end — VERIFIED by execution

**Algorithm-only, no model files:**

```
$ ESSENTIA_SPECS=1 bundle exec rspec spec/integration/essentia_empty_models_spec.rb
  extracts the click-train ground-truth tempo from an empty models directory
  rejects a model-backed request without populating the empty directory
2 examples, 0 failures
```

**Full six-descriptor production path, against the six real `.pb` models** (present at `tmp/essentia_models/`, listed and confirmed):

```
$ ESSENTIA_SPECS=1 bundle exec rspec spec/integration/essentia_extract_golden_spec.rb
  white_noise.arousal_emomusic:      abs 9.537e-07, rel 1.401e-07, tolerance 6.805e-04
  white_noise.danceability_musicnn:  abs 0.000e+00, rel 0.000e+00, tolerance 9.995e-05
  white_noise.mood_acoustic_musicnn: abs 2.260e-12, rel 1.510e-05, tolerance 1.000e-10
  white_noise: max rel dev 1.510e-05 on mood_acoustic_musicnn
  matches the white_noise golden output
  rejects undecodable audio
5 examples, 0 failures
```

Live extraction reproduces the committed goldens within tolerance on all four fixtures under the new descriptor ids, and the undecodable fixture still returns a `TrackError`. The per-head deviations are non-zero and specific, which is what proves real extraction ran rather than a skip.

---

## 6. The error-class control flow — VERIFIED by execution

This was the one control-flow-sensitive spot I identified at 0.2.0: `lib/tasks/enrichment.rake:49` rescues `Sonance::FatalError`. The rename preserved the whole hierarchy:

```
EnrichmentRun::ConsecutiveLlmOnlyError ancestors:
  [EnrichmentRun::ConsecutiveLlmOnlyError, Sonance::FatalError, Sonance::Error, StandardError]

ConsecutiveLlmOnlyError      < Sonance::FatalError   true
SystematicTrackFailure       < Sonance::FatalError   true
Sonance::ConfigurationError  < Sonance::FatalError   true
Sonance::MalformedOutputError< Sonance::TrackError   true
TrackError is NOT a FatalError                       true

rescue Sonance::FatalError at rake:49 would catch ConsecutiveLlmOnlyError:  true
…and would NOT catch a TrackError:                                          true
```

The last two lines are the ones that matter: the rescue still catches what it must and still does not swallow a per-track error. This was resolved against the loaded rake file, not read from source — `Rails.application.load_tasks` ran and the constant resolved, which means the `.rake` file parsed and executed.

---

## 7. Every call site migrated — VERIFIED

All eleven `Sonance` references in active code, and all exercised rather than merely compiled:

| Site | Migration | Exercised by |
|---|---|---|
| `mood_grounding_service.rb:10` extractor, `:114-115` and `:127-128` the **two analyze sites** (each: `analyze(descriptors:)` then **exactly one** mapper call) | ✓ | `mood_grounding_service_spec` **20 examples, 0 failures** |
| `mood_grounding_service.rb:4` `SystematicTrackFailure < Sonance::FatalError`; `:116`, `:129` `rescue Sonance::TrackError` | ✓ | item 6 + the service spec |
| `enrich_album_job.rb:5` extractor, `:8` `verify!` | ✓ | the suite |
| `enrichment.rake` **six sites** — `:5` error class, `:18` and `:31` two extractor constructions, `:21` and `:44` two `verify!` calls, `:49` the rescue | ✓ | `enrichment_rake_spec` **13 examples, 0 failures**, including *"re-raises fatal extractor errors and stops processing later albums"* and *"aborts immediately when preflight fails without making iTunes HTTP calls"* |
| `config/initializers/sonance_registry.rb:2` | ✓ | item 2 |
| `essentia_mapper.rb` `DESCRIPTORS` now qualified, `EMOMUSIC_RANGE` unchanged | ✓ | items 3 and 4 |

The rake spec is the one I want to highlight: it does not merely load the file, it drives the fatal-error re-raise and the preflight abort, which are the two behaviours the rename could have broken silently.

---

## Verified vs. believed

**VERIFIED by execution** — everything above with pasted output: the suite and rubocop; the tag/lockfile SHA relationship; the boot initializer under two injected faults plus a control; the native→normalised identity on all four fixtures × six heads; the mapper's keys and four clamp boundaries; real Essentia on both the algorithm-only and full six-descriptor paths; the full error-class ancestry including both directions of the `rake:49` rescue; and the rake and service specs exercising their call sites.

**BELIEVED by reading, not executed:** that the app's golden *values* are bit-identical across the id rename with only keys changed — I confirmed the golden keys are the new qualified ids and that mapper-versus-baseline is exactly zero on all 24 cells, which is strong corroboration, but I did not re-derive your ordered value comparison against the pre-rename files. Same for "app frozen `baseline_v0_1_0` bytes identical" and gem CI green at v0.3.0 — those remain your verifications.

**Not assessed:** the gem's own 0.3.0 internals beyond what the app exercises, and any production workload, which no local run can speak to.

---

## Final state

```
app   branch docs/essentia-gem-v2-design   HEAD e4ff6859cc7b7e076576131e8f000593503e4a11
      Gemfile:34   gem "sonance", git: "git@github.com:Lhosb/sonance.git", tag: "v0.3.0"   (unchanged)
      Gemfile.lock revision: cf8e613e…  (annotated tag object → commit 6639397)            (unchanged)
      git status   only this report's directory, untracked

gem   branch feat/essentia-gem-v2-phase-a  HEAD 66393972a8b57ee116afec0fbeb879a0c410dbca
      tags v0.1.0  v0.2.0  v0.3.0
      git status   clean

scratch deleted
```

Both repositories are on their branches and unmodified. The only file I created is this report.

**IS THE INTEGRATION WORKING AS INTENDED — YES.**
