# MOOD-SCALE — gem-side completion audit (sonance) · READ-ONLY

**Author:** Keystone (Principal Engineer) · **Date:** 2026-08-15
**Gem checkout:** `/Users/lukeolson/projects/gems/mood_probe` (directory name stale; gem is **sonance**,
remote `git@github.com:Lhosb/sonance.git`)
**App pin:** `Gemfile` tag `v0.3.0`, `Gemfile.lock` revision `cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6`

> ## VERDICT
>
> **The gem does NOT block app completion. Option E requires ZERO gem changes.**
>
> **#30 is decidable by the app ALONE, today.** Its emomusic half is entirely app-side and always
> was. Its musicnn half is a decision about a code path that only becomes live when gem **#15**
> lands — and #15's own issue text requires the app-side work to land **first**. **The dependency
> runs app → gem, not gem → app. The app is the blocker for the gem, not the reverse.**

---

## 0. Corrections to the stated ground truth

| claim | verdict |
|---|---|
| App pins `v0.3.0`, lock revision `cf8e613e…` | ✅ **confirmed** — `git rev-parse v0.3.0` = `cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6` |
| Sixteen gem issues open, incl. #15 with that title | ✅ **confirmed** |
| "Gem main has moved well ahead: 52ddf16, 65d095f, b0463ff, 967709b, 5647a12, d514137" | ⚠️ **partly wrong.** `origin/main` HEAD is **967709b**. `52ddf16`, `65d095f`, `b0463ff` are **not on main** — they are on the branch `fix/cli-output-and-bounded-subprocess-reads` (which happens to be the checked-out branch). I diffed that branch against main: **content-identical**, i.e. already squash-merged as `967709b`. **There is no unmerged gem work.** |
| "THE APP IS NOT ON GEM MAIN" | ✅ true, but ⚠️ **the gap is far smaller than "well ahead"** — see §1 |
| "issues #5, #6, #17, #19 landed after the pin" | ✅ confirmed — `967709b` (#5, #6), `5647a12` (#17, #19), `d514137` (CI) |

**Why the commit lists disagree, and it is not an error either of us made:** the gem squash-merges
PRs, so commits on the tag line and on main have different SHAs for the same content. `git log
v0.3.0..origin/main` therefore reports commits that *are* present by content. This is **gem issue
#13, "Release tags are not ancestors of main"** — a known, filed defect in the gem's own tagging
order. **Compare v0.3.0 and main by `git diff`, never by `git log`.** I made this mistake first and
caught it; anyone auditing this repo will make it too.

---

## 1. The actual v0.3.0 → main delta (content, not commits)

`git diff --stat v0.3.0 origin/main` — **13 files, and only three are library code:**

| path | change | moves a stored value? |
|---|---|---|
| `lib/sonance/backends/essentia_python.rb` | +140 — bounded stdout/stderr reads (#6), stderr truncation in exception messages, `kill_group` EPERM/ESRCH portability | **No.** Comment in the diff is explicit: *"The byte sequence for any output under the ceiling is identical, so the happy path is unchanged."* |
| `lib/sonance/value.rb` | +38 — **purely additive** `as_json`/`to_json` on `Value`/`Scalar`/`Categorical`/`Vector`/`Series` (#5) | **No.** `Scalar#as_json` returns `value` unchanged. No validation, no numeric handling, no rounding touched. |
| `lib/sonance/extractor.rb` | +13 — **comment only** (batch chunking guidance) | **No.** Zero behaviour. |
| `Dockerfile.essentia`, `constraints.txt`, `NOTICE` | base image pinned by digest; numpy pinned; licence URIs (#17, #19) | **No** — and see below |
| 7 spec/support files | test-only | n/a |

**Byte-identical between v0.3.0 and main:** `python/` (the entire extraction script), `registry.rb`,
`plan.rb`, `model_store.rb`, `result.rb`, `errors.rb`, `version.rb` (still `0.3.0`).

**`registry.rb` unchanged is the load-bearing fact of this audit.** Descriptor ids, `native_range`,
`sanity_range`, `range_kind`, and `reduction` are all identical. The six ids the app maps
(`valence_emomusic`, `arousal_emomusic`, `danceability_musicnn`, `mood_acoustic_musicnn`,
`mood_relaxed_musicnn`, `mood_happy_musicnn`) are unchanged, so
`config/initializers/sonance_registry.rb`'s boot-time assertions still hold.

**`python/` unchanged is the second.** The Essentia graph, the reduce, and the numbers are
bit-identical. Issue #5's "serialize as JSON" was a **Ruby-side** `as_json` for the CLI, **not** a
change to the extraction protocol. The NaN guard `allow_nan=False` is present in **both** revisions.

**`constraints.txt` is value-*protective*, not value-changing.** It pins numpy to **2.5.2**, which
the file documents as the version already resolved unpinned on 2026-08-14 — the version that
produced every stored value. `essentia-tensorflow==2.1b6.dev1389` is unchanged.

---

## 2. Does Option E require any gem change? — **NO. Confirmed, not merely consistent.**

Traced end to end:

1. `HeadCalibration.album_coordinate(mood_vector, head)` reads `mood_vector.public_send(head)` — a
   **stored `mood_vectors` column**. It never calls the gem, and never writes.
2. It is invoked at **scoring time** from `Recommendations::CandidateRetrieval`, which is nowhere
   near `MoodGroundingService` or `EnrichAlbumJob`.
3. The gem is reached only through `MoodGroundingService#analyze_remote_track` / `#analyze_local_track`
   (`:114`, `:127`), on the **write** path, which Option E does not touch. The Option E diff
   containment list already forbids `mood_grounding_service.rb` and `essentia_mapper.rb`.

**Option E and the gem do not share a code path.** The gem produces stored values; Option E is a
pure function of stored values.

**What would change the answer:** only moving Layer 1 into `MoodVectors::EssentiaMapper` — the
rejected alternative in Option E §4.2. That would put the band on the write path, and then a gem
repin, a descriptor rename, or a reduce change could all interact with it. **This is a third,
previously unstated reason to refuse the mapper placement: it would create a cross-repo coupling
that does not currently exist.**

---

## 3. The #30 seam — worked through

### 3.1 The two halves behave completely differently, and only one is gem-coupled

| | musicnn (4 heads) | emomusic (2 heads) |
|---|---|---|
| `range_kind` | `:hard` | `:nominal` |
| `native_range` / `sanity_range` | `0.0..1.0` / `0.0..1.0` | `1.0..9.0` / **`-3.0..13.0`** |
| gem behaviour on out-of-range | **vetoes** → `MalformedOutputError` (a `TrackError`) → app rescues at `mood_grounding_service.rb:116`/`:129` → **track skipped** | **admits** anything in −3..13; only −3/13 is vetoed |
| app clamp | `essentia_mapper.rb:24-27` — **unreachable dead code today** | `essentia_mapper.rb:44` — **live, silent, today** |
| is #30 live right now? | **No** — gated behind gem #15 | **Yes** — and always has been |

### 3.2 The interaction with #15 — read from #15's own text

Gem **#15** proposes making `sanity_range` report rather than veto. Its issue body states the
required ordering explicitly:

> *"vibe-doctor **depends on this rejection today** … the app's four softmax clamps are currently
> unreachable dead code precisely because this gem-side veto fires first. … **Required ordering —
> do not invert:** 1. Land `Lhosb/vibe-doctor#24` first (both-direction clamp coverage). 2. Only
> then land this."*

And it names the second-order effect: stop raising `MalformedOutputError` and a bad value stops
being a **skipped track** and becomes a **`MoodVector` numericality failure at save** — later,
quieter, and in a different place.

**Consequences:**

- **The musicnn half of #30 is a decision about what the app does when #15 lands.** It must be
  decided and implemented *while the clamp is still dead code* — which is exactly the window #15
  asks for. It does **not** require #15 to land first; it requires #15 **not** to have landed yet.
- **The emomusic half of #30 has no gem dependency at all.** The gem already admits −3..13 and the
  app already clamps in `rescale_emomusic`. It is decidable and fixable today with no gem change.
- **#15 landing as its option 2 ("report, don't veto, carrying an out-of-range flag") would *help*
  the app**: it supplies the saturation signal that Option E's deferred item 7 (persist raw +
  saturation counters) currently has to infer from nothing.

### 3.3 The Option E amplification — verified arithmetically, and stated more precisely

Claim: Layer 1 multiplies the emomusic scale by exactly 2.0 (declared span 8 ÷ band span 4), so a
clamp error carries twice the weight. **Confirmed by worked example:** true raw 10 → stored
`(10−1)/8 = 1.125` → clamped to `1.0`; stored-space error **0.125**. Calibrated: true
`(10−3)/4 = 1.75`, clamped-derived `(9−3)/4 = 1.5`; calibrated error **0.25**. Exactly ×2.

**Precision point worth carrying into the #30 thread:** this is not a special property of clamping.
Layer 1 doubles the weight of *every* emomusic difference — that is its purpose. Clamp error is one
instance. The correct framing is: **Option E promotes emomusic from ~3 % of mood distance to a head
that matters, and any pre-existing damage to emomusic values is promoted with it.**

### 3.4 **Two-repo answer**

> **#30 can and should be settled by the app alone, now.**
> Its emomusic half is purely app-side. Its musicnn half is app-side too — it is the app's policy
> for a path that gem #15 will make live — and #15 explicitly requires the app to move first.
> **The only genuine cross-repo obligation runs the other way: the app must decide #30 before #15
> can safely land in the gem.** Waiting for the gem inverts the dependency and creates the exact
> window #15 warns about, in which *neither* side guards the range.

---

## 4. The repin — the task-board rule needs restating

**"#30 must be decided BEFORE the gem repin" is, against *current* main, no longer the right rule.**

- A repin from `v0.3.0` to current main **does not remove the veto** — **#15 has not landed on
  main.** `registry.rb` is byte-identical and still declares musicnn `range_kind: :hard`.
- The repin is **value-neutral**: `python/` and `registry.rb` unchanged, `value.rb` additive,
  `extractor.rb` comments, backend explicitly documented as byte-identical below the ceiling.
  **Nothing stored moves — the Option E premise holds across the repin.**

**Restate the rule as:** *#30 must be decided before **#15 lands in a pinned version**.* That is the
real trigger, it is more precise, and it does not needlessly block a benign repin.

### 4.1 What a repin to current main *does* drag in

| change | app exposure |
|---|---|
| `MAX_STREAM_BYTES = 32 MiB` ceiling; overflow raises `BackendError` | **Not reachable.** The app calls `analyze` (single path) at `:114`/`:127`, never `analyze_all`. Gem #22 measures stderr binding at ~40 paths of 3-minute audio; the app analyses one ~30 s preview per call. |
| `BackendError` is a **`FatalError`**, not a `TrackError` | If it ever fired it would **not** be rescued at `:116`/`:129`; it would propagate to `EnrichAlbumJob`'s `rescue StandardError` (`:45`) → logged → `fail_enrichment!` → re-raised. **Loud, which is correct.** |
| `kill_group` ESRCH/EPERM portability fix | Improvement; macOS-relevant. Note gem **#21**: `terminate()` still has the unfixed EPERM exposure. |
| numpy pinned to 2.5.2; base image digest-pinned | **Protective** — freezes the float environment that produced the stored values. |
| `Value#as_json` additive | Unused by the app (it reads `.value`). |

**Cross-repo coupling to watch:** `MoodGroundingService::SystematicTrackFailure < Sonance::FatalError`
(`:4`) subclasses a gem class. `errors.rb` is unchanged between v0.3.0 and main, so this is safe
today — but it is a real API dependency on the gem's exception hierarchy and it is not covered by
the version pin's intent.

---

## 5. Open gem issues — critical path classification

| issue | classification | reasoning |
|---|---|---|
| **#15** sanity_range veto | **Related — and the app is the blocker.** Not on the Option E path. On the #30 musicnn path, but #15 requires the app to move first. | §3.2 |
| **#9** reduce hard-mandated | **Related but independent — and today it is a *guarantee*, not a risk.** `mean_over_frames` is mandated, and it is what produced every stored value. Danger appears only if the gem makes reduce configurable *and* the app changes it. **Recommendation: whatever #9 does, the app must keep `mean_over_frames` explicitly, and that should be asserted at the app's registry initializer.** | `registry.rb` unchanged |
| **#16** no fixture long enough for reduce/take reordering | **Related but independent.** It is the gem's ability to detect a reorder. **Not on the current repin path** — `python/` is byte-identical, so no reorder can have occurred between v0.3.0 and main. It is the gate that would protect a *future* repin touching the Python side. Measured divergence is ~6–8e-08 relative — far below anything that moves a 0..1 stored mean materially, but it is real. | #16 body; `git diff` on `python/` |
| **#10** two descriptors never met real Essentia | **UNRELATED.** `embedding_musicnn` and `beat_confidence_rhythm2013` are **not** in `EssentiaMapper::DESCRIPTORS`. The app requests exactly six ids, none of them these two. | verified against the mapper |
| **#7** descriptor-id gate blind to a wholly stale array | **Related but independent.** A gem-internal gate. It would matter at a **rename migration**; `registry.rb` is identical across the repin, so no rename is in flight. The app has its own independent protection: `config/initializers/sonance_registry.rb` raises at boot on any missing mapped descriptor. | |
| **#8** NaN seam guard has zero coverage | **Related — worth raising, not blocking.** `allow_nan=False` (`python/sonance_extract.py:506`) is present in both revisions but untested. All six mood descriptors are scalars crossing that seam. Defence in depth exists: a non-finite value that got past it would hit `Value#validate_numeric!` → `MalformedOutputError` → `TrackError` → track skipped. **Two layers, both untested.** | |
| #21, #22 | Repin-adjacent, not reachable by the app's single-path call pattern (#22) / macOS timeout path only (#21). | §4.1 |
| #13 tags not ancestors of main | **Meta — but read it before any repin.** It is why commit-log comparison misleads here. | §0 |
| #1, #2, #3, #11, #12, #14, #18 | Unrelated to the mood path. | |

---

## 6. Anything that could invalidate the 3.0..7.0 band?

Band premise: emomusic realized **raw album-mean** output stays well inside 1..9. Observed
3.1973..6.6632 (span 3.47). Pre-registered falsifier: **any real collection with raw span > 6.0**.

| candidate mechanism | verdict |
|---|---|
| model version / weights | **No change.** `registry.rb` identical; `emomusic_msd_musicnn_2` and its SHA-256 unchanged. |
| reduce semantics | **No change.** `reduction: :mean_over_frames` unchanged; `python/` byte-identical. Note the *direction* of the mean: averaging over frames **narrows** spread, so the mandated reduce is what keeps the band tight. #9 relaxing it (e.g. `max`) **would widen the realized band** — the single clearest mechanism that could break the band. |
| numpy / Essentia float environment | **Now pinned** (2.5.2 / `2.1b6.dev1389`), and pinned to the versions already in use. Drift risk *reduced* by the repin. |
| reduce/take reordering (#16) | ~6–8e-08 relative. **Orders of magnitude too small** to move a band boundary. |
| serialization (#5, #8) | `Scalar#as_json` returns `value` unmodified; NaN guard present in both. No precision loss on the wire. |
| album-mean vs per-track | **The real caveat, and it is app-side, not gem-side.** The band is measured against **album means over ~4 tracks**; per-track raw values spread roughly 2× wider. Layer 1 only ever sees the stored album mean, so this is correct as designed — but it means the falsifier must be evaluated on **album means**, not per-track values. |

**Conclusion: nothing in the gem, at v0.3.0 or at main, threatens the 3.0..7.0 band. The one future
mechanism that would is gem #9 relaxing `mean_over_frames` combined with the app adopting a
different reduce.**

---

## 7. DONE / NOT DONE / NOT REQUIRED — gem side

| item | status |
|---|---|
| Gem change required for Option E | **NOT REQUIRED** — no shared code path (§2) |
| Gem change required to decide #30 | **NOT REQUIRED** — both halves are app-side decisions (§3.4) |
| Gem repin required for Option E | **NOT REQUIRED** — Option E reads stored columns only |
| Gem repin *safe* for Option E if desired | **DONE / SAFE** — value-neutral across v0.3.0 → main (§1, §4) |
| Descriptor ids, ranges, `range_kind`, reduction stable across repin | **DONE** — `registry.rb` byte-identical |
| Extraction numerics stable across repin | **DONE** — `python/` byte-identical |
| Float environment pinned | **DONE on main, NOT in the pinned v0.3.0** — `constraints.txt` + digest-pinned base arrived after the pin. This is the one genuine *improvement* a repin would buy the mood path. |
| App decides #30 (both halves) | **NOT DONE** — app-side, unblocked, and it gates gem #15 |
| Gem #15 | **NOT DONE, and must not be done first** (§3.2) |
| Unmerged gem work affecting the app | **NONE** — the open branch is content-identical to main (§0) |
| App asserts `mean_over_frames` explicitly | **NOT DONE** — recommended before gem #9 lands (§5) |

---

## 8. Recommendations, in priority order

1. **Decide #30 now, in the app, both halves.** It is unblocked, and gem #15 is waiting on it. My
   standing recommendation is unchanged: musicnn → option (a) with a float-tolerance epsilon;
   emomusic → treat as real signal, and note it is **live today** and still missing from #30's scope.
2. **Restate the task-board rule** from *"decide #30 before the repin"* to *"decide #30 before #15
   lands in a pinned version."* The current repin does not open the hazard.
3. **Do not repin as part of Option E.** It is unnecessary and it enlarges the diff of a change whose
   entire premise is that nothing stored moves. Repin separately, on its own merits — chiefly the
   float-environment pinning, which is a real win.
4. **Add an explicit app-side assertion that the six mapped descriptors carry
   `reduction: :mean_over_frames`**, in `config/initializers/sonance_registry.rb` alongside the
   existing `native_range` check. That is the one gem-side change (#9) that could move stored values,
   and the app currently has no guard against it.
5. **Fix the stale checkout directory name** `gems/mood_probe` → `gems/sonance`. It cost time in this
   audit and will cost it again.
