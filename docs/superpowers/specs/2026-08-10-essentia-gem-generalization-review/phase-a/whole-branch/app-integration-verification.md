# mood_probe integration in vibe-doctor — verification

**IS THE INTEGRATION WORKING AS INTENDED — YES.**

**What each result came from.** Everything in Parts 1 and 2 was run against the app **as it stands**, on `mood_probe 0.2.0` at `848f689` — the tag the app pins, which I confirmed still peels to that SHA. Part 3's evidence came from a **scratch clone outside both repositories** repinned to `036c797` (0.2.1), which I deleted afterwards. Neither repository was modified.

---

## Call sites — the dispatch's list was incomplete

I found a fourth production surface not named in the brief:

| File | Use |
|---|---|
| `app/services/mood_grounding_service.rb:10, 114-115, 127-128` | constructs the extractor; the only production **analyze** sites; `SystematicTrackFailure < MoodProbe::FatalError` at `:4`; rescues `MoodProbe::TrackError` at `:116` and `:129` |
| `app/jobs/enrich_album_job.rb:5-8` | constructs the extractor; `verify!(descriptors:)` |
| `app/models/mood_vectors/essentia_mapper.rb` | `(v − 1.0) / 8.0` and `.clamp(0.0, 1.0)` |
| `config/initializers/mood_probe_registry.rb` | boot assertion |
| **`lib/tasks/enrichment.rake:5, 18-21, 31-33, 44, 49`** | **not in the brief** — constructs the extractor in two places, calls `verify!`, defines `ConsecutiveLlmOnlyError < MoodProbe::FatalError`, and **rescues `MoodProbe::FatalError` at `:49`**. That rescue is the one place where an error-class change could alter control flow, so it matters for Part 3. |

---

## Part 1 — green as it stands, on v0.2.0

```
$ bin/rails assets:precompile     → rc=0
$ bundle exec rspec               → 298 examples, 0 failures   (rc=0)
$ bundle exec rubocop             → 207 files inspected, no offenses detected
```

I precompiled first as instructed. **The Vibe Map asset failures did not occur** — the suite was clean on the first run after precompile, so there was nothing to misattribute. Zero failures is the gate; the count is reported, not relied on.

Installed gem confirmed as the pinned one:

```
$ bundle info mood_probe          → mood_probe (0.2.0 848f689)
$ bundle exec ruby -e '…'         → MoodProbe::VERSION = 0.2.0
Gemfile:34                        → tag: "v0.2.0"
Gemfile.lock:3-6                  → revision: 848f689…, tag: v0.2.0, mood_probe (0.2.0)
```

---

## Part 2 — does it actually work, not just compile?

### 2a. The boot initializer fires. **Verified by breaking it.**

I did not assume it runs. I loaded `config/application`, patched `MoodProbe::Registry.default` *after* the gem loads but *before* `after_initialize`, then called `Rails.application.initialize!`:

```
mode=control  →  BOOTED OK — no raise
mode=range    →  RAISED RuntimeError: valence_emomusic native range 0.0..9.0 does not match mapper range 1.0..9.0
mode=missing  →  RAISED RuntimeError: mood_probe registry is missing mapped descriptors: mood_happy
```

Both clauses of the initializer have a real failing state, and the control boots clean. The assertion is live at every app boot, not decorative.

### 2b. Mapper: keys, rescale, and clamp — all exercised. **Verified by execution.**

```
keys                   = [:valence, :arousal, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy]
MoodVector::MOOD_HEADS = [:valence, :arousal, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy]
keys == MOOD_HEADS?      true

rescale (v−1)/8:   9.0 → 1.0 OK    5.0 → 0.5 OK    3.0 → 0.25 OK    1.0 → 0.0 OK

clamp, on values OUTSIDE the nominal range — where the goldens cannot reach:
  valence_emomusic 9.4  → 1.0   (unclamped would be 1.0500)  OK
  valence_emomusic 0.6  → 0.0   (unclamped would be -0.0500) OK
  danceability     1.1  → 1.0   OK
  danceability    -0.1  → 0.0   OK
```

The point about the clamp being **inert on all eight goldens** is exactly right, and it is why those four boundary values matter: each one is outside the range any golden occupies, and the "unclamped would be" column shows the clamp is doing work rather than passing a value through. The mapper's own spec carries the same boundary controls plus an arousal pair added after my slice-5a review found the clamp unexercised on three of six heads.

### 2c. Native in, normalised out — no double-normalisation, no missing normalisation. **Verified by execution.**

This is the architectural claim of Phase A, and one number settles it:

```
gem native_range(valence_emomusic)  = 1.0..9.0
golden clicks valence_emomusic      = 5.8459882736206055   (NATIVE, inside 1.0..9.0: true)
mapper → valence                    = 0.6057485342025757
frozen v0.1.0 baseline valence      = 0.6057485342025757   equal: true
```

The gem hands the app a native 1..9 value; the app divides by eight itself; the result is **bit-identical** to what v0.1.0 stored before the refactor. If the app were double-normalising, valence would be `(0.6057 − 1)/8 = −0.049` → clamped to `0.0`. If it were not normalising at all, `5.846` would fail `MoodVector`'s `0.0..1.0` validation and no album would save. Neither is happening.

The mapper is called **exactly once per track**, at `mood_grounding_service.rb:115` and `:128` — one call each, on the two and only analyze sites.

### 2d. Real Essentia, end to end, on this machine. **Verified by execution.**

Algorithm-only path (no model files):

```
$ ESSENTIA_SPECS=1 bundle exec rspec spec/integration/essentia_empty_models_spec.rb
  extracts the click-train ground-truth tempo from an empty models directory
  rejects a model-backed request without populating the empty directory
2 examples, 0 failures
```

And the **actual production path** — the six descriptors the app requests, against the six real `.pb` models, through the app's installed v0.2.0:

```
$ ESSENTIA_SPECS=1 MOOD_PROBE_MODELS_DIR=~/.spin_doctor/essentia_models \
  bundle exec rspec spec/integration/essentia_extract_golden_spec.rb
  …
  white_noise.valence_emomusic: abs 3.099e-06, rel 1.104e-06, tolerance 2.809e-04
  white_noise.mood_acoustic:    abs 2.260e-12, rel 1.510e-05, tolerance 1.000e-10
  white_noise: max rel dev 1.510e-05 on mood_acoustic
5 examples, 0 failures
```

Live extraction reproduces the committed goldens within tolerance on all four fixtures, and the undecodable fixture still returns a `TrackError`. The integration is not merely compiling — it is extracting.

---

## Part 3 — would repinning to 0.2.1 be safe? **YES.**

I assessed each change against the app's call sites, then **verified the conclusion by running the app's own suite against 0.2.1** in a scratch clone.

| 0.2.1 change | Reaches an app call site? | Verdict |
|---|---|---|
| `Registry#fetch` raises `ConfigurationError`, not `KeyError` | The app reaches `fetch` only with its six hardcoded `DESCRIPTORS`, all validated at boot. **The app rescues `KeyError` nowhere** in `app/`, `lib/` or `config/` | **No change.** See the note below. |
| Host enforcement moved from `Model` construction to the download path | The app **never constructs `Model` rows and never calls `fetch!`** — zero references to `ModelStore`, `Model.new` or `fetch!` anywhere. Models are provisioned out-of-band via `ESSENTIA_MODELS_DIR` | **No change**, and stronger where it does apply — see below |
| `respond_to?(:analyze_all)` replaces the concrete class check | The app **never injects a backend** — it passes only `models_dir:`, so the real `Backends::EssentiaPython` is always selected, and it responds to `analyze_all` | **No change** |
| New CLI flag, YARD docs, new specs, version bump | No app surface; the `errors.rb` delta is comments only | **No change** |

**On the `KeyError` → `ConfigurationError` change, one nuance worth recording.** `ConfigurationError < FatalError`, and `enrichment.rake:49` rescues `MoodProbe::FatalError` specifically. So *if* an unknown descriptor were ever requested, the classification would move from "generic `StandardError`, counted and continued" to "`FatalError`, counted and re-raised". That path is unreachable in the app — the six descriptors are literals, and the boot initializer asserts every one of them exists before any request is made — and the new classification is the more correct one for a bad descriptor id. I mention it because it is the only place in the app where an error-class change could alter control flow, and it is worth knowing that it was checked rather than overlooked.

**On the host-enforcement move, one improvement the app doesn't consume but should be recorded.** In 0.2.0 the redirect loop checked only that each hop was HTTPS; the host was enforced once, at `Model` construction. In 0.2.1 `ModelStore.validate_download_uri!` runs **per hop**, so a redirect to a different HTTPS host is now rejected. For an app that never downloads models this is neutral; for anyone who does, it is strictly stronger.

**The verification, not just the reasoning.** Scratch clone of the app at its current HEAD, repinned to `036c797` against the local gem repo (no network), assets precompiled, full suite:

```
$ bundle install                  → mood_probe (0.2.1)
$ bundle exec rspec               → 298 examples, 1 failure

  1) mood_probe dependency loads the v0.2.0 release commit
       expected: "0.2.0"
            got: "0.2.1"
```

**One failure, and it is the pin assertion itself** — `spec/mood_probe_dependency_spec.rb`, the gem-identity floor, doing precisely the job it was built for: noticing that the pin moved. Every other example passes, including the mapper, the parity gate, the registry contract, the grounding service, and the boot initializer (which runs in every `rails_helper` example).

Real extraction under 0.2.1 as well:

```
$ ESSENTIA_SPECS=1 MOOD_PROBE_MODELS_DIR=… rspec <golden + empty-models>  → 7 examples, 0 failures
$ RAILS_ENV=test ruby -e 'require "./config/environment"'                 → BOOTED OK under mood_probe 0.2.1
```

**Repin verdict: YES, safe.** The work is: bump `Gemfile:34` to the 0.2.1 tag or SHA, `bundle install`, and update the two literals in `spec/mood_probe_dependency_spec.rb`. Nothing in `app/`, `lib/` or `config/` needs to change.

---

## Verified vs. believed

**Verified by execution** — everything above with pasted output: the suite and rubocop on 0.2.0; the initializer firing under two distinct injected faults plus a control; the mapper's keys, four rescale points and four clamp boundary points; the native-in/normalised-out identity against the frozen baseline; real Essentia on both the algorithm-only and full six-descriptor paths; and the full app suite plus real extraction under 0.2.1 in a scratch clone.

**Believed by reading, not executed:** that `respond_to?(:analyze_all)` selects identically for the app — I verified the app injects no backend and read both code paths, but I did not construct a backend double to force the branch. And the redirect-host improvement in 0.2.1 is read from the diff, not exercised, because the app never downloads models.

**Not assessed:** anything in the gem's 0.2.1 work beyond the four named changes and the `lib/` diff; and the app's behaviour under a production workload, which no local run can speak to.

---

## Final state

```
app  branch docs/essentia-gem-v2-design   HEAD 89cd303c842fe7b2f1da73c5b5e64bc27792363d
     Gemfile:34      tag: "v0.2.0"        (unchanged)
     Gemfile.lock:3  revision: 848f689…   (unchanged)
     git status      only this report's new directory, untracked

gem  branch feat/essentia-gem-v2-phase-a  HEAD 036c797f87e8a490dbcc676da0e7bfce8e0fb298
     v0.2.0 peels to 848f6894a6022b5a32ae2b6b0c6898ac84986fa0   (unmoved)
     git status      clean

scratch clone deleted
```

Both repositories are on their original branches and unmodified. The only file I created is this report.

**IS THE INTEGRATION WORKING AS INTENDED — YES.**
