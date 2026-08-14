# Sonance 0.3.0 — pre-tag review — TEST

**APPROVE**

**I would not block the tag.** No finding. One correction to the stated baseline, below, which is a bookkeeping error and not a defect in the release.

**Range:** `bb86f29..77003c5`, four commits. HEAD verified `== 77003c5` at start and end. All mutation work was done on a `git clone --no-hardlinks` **outside both repositories**, reverted after each run and deleted. Neither repo was modified.

---

## Baseline challenge: the suite went 188 → 192, not 191 → 192

You invited me to challenge the baseline, and one number is wrong. Verified by **real runs**, not dry-run, at both ends:

```
bb86f29 real run: 188 examples, 0 failures
77003c5 real run: 192 examples, 0 failures
```

The delta is **+4**, and it is fully accounted:

| File | Δ | New examples |
|---|---|---|
| `spec/registry_spec.rb` | +3 | `indexes unique model and descriptor ids`, `rejects duplicate descriptor ids`, `rejects duplicate model ids` |
| `spec/release_ci_spec.rb` | +1 | `keeps every capture-script descriptor registered` |

Those are exactly the two behaviours added in this range — the duplicate-id rejection from `5a539c1` and the new capture-script gate from `77003c5`. Nothing else moved. Your HEAD figure of 192 is right; the starting figure of 191 is three low, so anyone reconciling the delta would go looking for one example and find four.

---

## 1. G1 still bites after the fixtures moved directory

The frozen baseline moved `spec/fixtures/mood_probe/baseline_v0_1_0/` → `spec/fixtures/sonance/baseline_v0_1_0/` as `R100` pure renames, and the parity spec's glob at `:4` was updated to match. Both facts are consistent with a gate that now discovers nothing, so I mutated rather than read.

**Mutated a frozen baseline value** (`chirp.mood_happy` × 1.01, ~100× the bound) on the scratch copy:

```
chirp.json mood_happy drifted          ← the parity gate, with attribution
1 example, 1 failure                   ← baseline_v0_1_0_integrity_spec.rb, independently
```

Two independent gates catch it: the parity gate names the fixture and the head, and the SHA-pinned integrity spec fails on the bytes. G1 is finding real files at the new path.

**The ported tolerance controls survived the move and pin the bound both ways:**

```
tolerance=1e-1  -> 6 examples, 1 failure   KILLED
tolerance=1e-3  -> 6 examples, 1 failure   KILLED
tolerance=1e-4  -> 6 examples, 0 failures  green
tolerance=1e-5  -> 6 examples, 1 failure   KILLED
tolerance=1e-6  -> 6 examples, 1 failure   KILLED
```

Only the calibrated value is green. The `0.9e-4` passing control (`:31`) and `1.1e-4` failing control (`:37`) are both present with literal deltas, so loosening reddens the outside control and tightening reddens the inside one — the same two-sided calibration the app carries.

---

## 2. Non-vacuity sweep — the priority. Every discovering gate fails closed.

I replaced discovery with an empty set in each gate that finds files or keys by glob, path or regex, and required a non-zero exit:

| Gate | Discovery replaced with `[]` | Result |
|---|---|---|
| G1 parity (`baseline_v0_1_0_parity_spec.rb:4`) | baseline glob | **killed** — `1 error occurred outside of examples` |
| G10 plans (`python_plan_fixture_spec.rb:4`) | plan glob | **killed** — `1 error occurred outside of examples` |
| golden gate (`integration/essentia_golden_spec.rb:15`) | golden glob | **killed** — `1 error occurred outside of examples` |
| baseline integrity (`baseline_v0_1_0_integrity_spec.rb:15`) | `Dir.children` | **killed** — `1 example, 1 failure` |

The first three carry a **load-time** `raise "no … fixtures discovered" if …empty?`, so they abort before RSpec collects anything rather than reporting a green zero-example run. The integrity spec's floor is different in kind — its file-set equality assertion fails on an empty listing — and it works.

`bin/essentia-ci` is **not in this repository**; it is the app's file and out of this range. I checked rather than assumed (`git ls-files | grep -c essentia-ci` → 0).

**A meta-gate I want to credit, because it is the thing that makes this sweep durable:** `release_ci_spec.rb:33-40` asserts that the *source* of the golden and parity specs contains their floor strings verbatim. Deleting a floor is therefore itself a test failure, not merely a silent weakening. That is the first time on this ticket a non-vacuity floor has been protected by a gate of its own.

---

## 3. The new capture-script regex gate is non-vacuous, by execution

`spec/release_ci_spec.rb:43-47` parses descriptor ids out of the capture script with `capture_source.match(/descriptors = %i\[(.*?)\]/m)` and then `scan`. Both failure modes of a regex gate are guarded, and both guards fire:

```
regex matches NOTHING (nil)          5 examples, 1 failure   killed   ← expect(descriptor_block).not_to be_nil
regex yields an EMPTY id list        5 examples, 1 failure   killed   ← expect(descriptor_ids).not_to be_empty
```

So the gate cannot pass having parsed nothing, and it cannot pass having parsed an empty list. Its positive half then resolves every extracted id through `Sonance::Registry.default.fetch(id)`, which is a real cross-check against the registry rather than a string comparison — an id that no longer exists raises rather than silently matching.

---

## 4. The id rename dropped no coverage on any head

All six mood heads are covered with their **new** ids, not just the two that did not change:

```ruby
%i[valence_emomusic arousal_emomusic]                       # native (1.0..9.0), :nominal, sanity (-3.0..13.0)
%i[danceability_musicnn mood_acoustic_musicnn
   mood_relaxed_musicnn mood_happy_musicnn]                 # native (0.0..1.0), :hard,    sanity (0.0..1.0)
```

Each is asserted on `native_range`, `range_kind` **and** `sanity_range` (`registry_spec.rb`, `declares the required ranges and sanity ranges`). Registry ids at HEAD confirm the rename landed on all nine descriptors:

```
[:valence_emomusic, :arousal_emomusic, :danceability_musicnn, :mood_acoustic_musicnn,
 :mood_relaxed_musicnn, :mood_happy_musicnn, :embedding_musicnn, :bpm_rhythm2013,
 :beat_confidence_rhythm2013]
```

Sanity-range **enforcement** is exercised on both kinds with renamed ids — `valence_emomusic` against `-3.0..13.0` and `danceability_musicnn` against `0.0..1.0` (`value_spec.rb:44-51`, `:68-80`) — so the `:hard` branch is driven by a head whose id changed, not only by one that did not.

There is no clamp in the gem: A8 deleted it, and it lives in the app's mapper. The gem-side equivalent is `Scalar`'s sanity-range enforcement, which is what I checked.

---

## 5. The new duplicate-id rejection bites

Substantive new behaviour deserves a mutation, so I removed the guard:

```
duplicate-id guard removed   24 examples, 2 failures   killed
```

Shipped at `lib/sonance/registry.rb:326-327`:

```ruby
duplicate_id = records.map(&:id).tally.find { |_id, count| count > 1 }&.first
raise ArgumentError, "duplicate #{type} id: #{duplicate_id}" if duplicate_id
```

Both new negatives fail without it, and the guard names the offending id. Given the previous behaviour was `to_h` silently last-wins, this is the right shape: a duplicate is now loud at construction, which is the only place it can be caught before the registry is in use.

---

## Verified vs. believed

**Verified by execution** — all pasted above: the 188/192 counts by real run at both SHAs; G1 reddening on a mutated baseline value with attribution, plus the integrity spec catching it independently; the five-point tolerance sweep; six empty-discovery probes across four gates; both regex-gate failure modes; the duplicate-id guard removal; and the registry ids and range assertions read at HEAD.

**Believed by reading, not executed:** that the golden fixture *values* are bit-identical across the id rename — I read the manager's verification and the `D`/`A` status (content changed because keys changed, so git cannot show them as renames), but I did not re-derive the ordered value comparison. Same for the claim that zero `MoodProbe`/`mood_probe` identifiers remain and that CI is green at `77003c5`; those are the manager's verifications, not mine.

**Not assessed:** anything app-side, which is out of this range; and the GitHub repo rename, which follows the tag.

---

## Evidence

```
$ git -C <gem> rev-parse HEAD            → 77003c5f1796c42fda7807123a56a13c56e71ffe  (start and end)
$ git -C <gem> log --oneline bb86f29..77003c5
  77003c5 fix: qualify release capture descriptors
  80a7dd0 chore(release): prepare sonance 0.3.0
  5b919b2 refactor!: rename MoodProbe to Sonance
  5a539c1 feat: qualify descriptor identifiers
$ git -C <gem> tag                       → v0.1.0  v0.2.0        (no v0.3.0 yet)
  v0.1.0 → 5360f8fd8609eae39edb5dfab8a07f6439a0b137   (unmoved)
  v0.2.0 → 848f6894a6022b5a32ae2b6b0c6898ac84986fa0   (unmoved)
$ git -C <gem> diff --name-status -M bb86f29..77003c5 -- spec/fixtures
  R100 …/baseline_v0_1_0/{chirp,clicks,sine_440,white_noise}.json, README.md, PROVENANCE.md
  R100 …/audio/*, …/essentia/*
  D/A  …/golden/*.json          (content changed: keys qualified, so not a rename)
$ (scratch clone) bundle exec rspec      → 192 examples, 0 failures
$ git ls-files | grep -c essentia-ci     → 0
```

Mutation results, tolerance sweep, empty-discovery sweep, regex probes, per-file count diff and the duplicate-guard probe are quoted inline above with their real output.

**Final state:**
```
gem   branch feat/essentia-gem-v2-phase-a   HEAD 77003c5   status clean
app   status shows only this report's directory, untracked
scratch clone deleted
```

---

Every gate that could have been silently neutered by the move was moved with its floor intact, and the three load-time floors abort before collection rather than reporting a green zero-example run. The one thing I would flag for the record rather than as a finding is the baseline arithmetic: the suite grew by four, not one, and both additions are real new coverage.
