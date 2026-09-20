# OPTION-E — owner-facing GitHub drafts + instrumentation sizing

**Author:** Keystone (Principal Engineer) · **Date:** 2026-09-20
**Branch reviewed:** `feat/mood-scale-option-e` @ `bc6bc5d` (worktree `.worktrees/mood-scale-option-e`)
**DRAFT ONLY — nothing posted to GitHub.**

---

## 0. Your summary re-derived from the shipped code — correct, with two refinements

Re-derived from code, not from the summary. Composing the two transforms:

- `MoodVectors::EssentiaMapper#rescale_emomusic` — `clamp((raw - 1.0) / 8.0)` → **stored**
- `MoodVectors::HeadCalibration.album_coordinate` — `(stored * 8.0 + 1.0 - 3.0) / 4.0` → **calibrated**

```
calibrated = 2 · stored − 0.5
```

**The scale factor is exactly 2.0** — it is the derivative of the composition, so it applies to every
emomusic difference, not only to a damaged one. `HeadCalibration` reads
`mood_vector.public_send(head)` (a stored column) and `MoodDistance.term` calibrates the **album**
side only (`query_mood.public_send(head)` is used raw), so the asymmetry is as designed. ✅ **Your
summary is correct.** Two refinements worth carrying into the comment:

1. **It is not a property of clamping.** Option E doubles the weight of *all* emomusic error. Clamp
   error is one instance. The honest framing: emomusic goes from ~2.8 % of mood distance to ~10.3 %,
   and any pre-existing damage is promoted along with the head.
2. **The clamp is per-track; the stored value is an album mean.** `MoodGroundingService#aggregate`
   averages ~4 tracks, so one clamped track contributes `2 · e / n_tracks`, not `2 · e`. The ×2 is
   exact at the coordinate level; the album-level magnitude is diluted. Stating it without the
   dilution would overstate the case to the decider, and this issue needs to survive scrutiny.

**Worth adding, and it is the sharpest decision-relevant fact:** because there is no scoring-time
clamp, a stored `1.0` calibrates to **+1.5** and a stored `0.0` to **−0.5**, while real albums
occupy only **0.049 … 0.916**. A saturated value therefore lands *outside the entire range any
genuine album can reach*. `candidate_retrieval.rb:4-6` already records the consequence: no-clamp
emomusic extremes permit a mood term of `1.190238` against a nominal bound of 1.0 (I verified:
`√(2·1.5² + 4·1²)/√6 = 1.190238`).

---

## 1. DRAFT — comment for vibe-doctor issue #30

> Verified before drafting: #30 is **open with 0 comments**; the amplification is not mentioned anywhere on it.

```markdown
## Option E changes the cost of the emomusic half of this decision

Option E (branch `feat/mood-scale-option-e`) has landed the scoring-time band recalibration. It does
not change what the mapper writes, but it changes what a clamped emomusic value *costs*, so this
decision is no longer cost-neutral on that half.

### The mechanism, from the code

`MoodVectors::EssentiaMapper#rescale_emomusic` stores `clamp((raw - 1.0) / 8.0)`.
`MoodVectors::HeadCalibration.album_coordinate` then reads that stored value at scoring time and
maps it `(stored * 8.0 + 1.0 - 3.0) / 4.0`. Composed:

    calibrated = 2 · stored − 0.5

**The emomusic scale factor into recommendation space is exactly 2.0.** That applies to every
emomusic difference — it is the point of the band correction, which lifts emomusic from ~2.8 % of
mood distance to ~10.3 %. It also applies to error. A value this mapper clamps now carries **twice**
the coordinate error it used to, and any damage already in an emomusic value is promoted along with
the head.

### Why that matters more than the factor of two suggests

There is deliberately **no scoring-time clamp**. So a stored `1.0` calibrates to **+1.5** and a
stored `0.0` to **−0.5**, while real albums occupy only **0.049 … 0.916** in that space. A saturated
value does not merely become inaccurate — it lands outside the range any genuine album can reach.
`candidate_retrieval.rb:4-6` records the bound this permits: a mood term of `1.190238` against a
nominal maximum of `1.0`.

Two things keep this proportionate, and they should be stated plainly:

- The clamp fires **per track**; the stored column is an album mean over ~4 tracks
  (`MoodGroundingService#aggregate`), so one clamped track moves the album value by `2 · e / n`.
- Worst case the gem currently admits is `sanity_range` `-3.0..13.0`. A raw `13` with one track in
  four yields a calibrated album error of `0.25` — a quarter of the head's usable range. Not fatal,
  not negligible.

### What this changes about the decision

**The emomusic half only.** It does not change the musicnn half, which remains: **option (a) with a
float-tolerance epsilon** (a softmax above 1.0 is a fault, not an extreme), **plus persisting
`contributing_track_count`** so a silent shrink in contributing tracks is visible.

For emomusic, note that this issue as written does not currently cover those two heads at all. It
describes "the app's four softmax clamps", which are `range_kind: :hard` and therefore unreachable
dead code under the pinned gem. The **emomusic clamps are the ones that are live today** — sonance
marks them `range_kind: :nominal` with `native_range 1.0..9.0` but `sanity_range -3.0..13.0`, so the
gem does *not* veto a value of 10 and `rescale_emomusic` clamps it silently, with no trace.

**Suggested scope change: widen this issue to name the emomusic clamps explicitly.** Option E raises
their cost; it does not create the exposure, which has been live all along.

### Sequencing

This does not block Option E, and Option E does not block this. But sonance issue
[#15](https://github.com/Lhosb/sonance/issues/15) ("sanity_range rejection is fatal") is waiting on
*this* decision — its own required ordering is that the app-side work lands first. **The dependency
runs app → gem.** Deciding here unblocks the gem; waiting for the gem inverts it and opens the
window #15 warns about, in which neither side guards the range.
```

---

## 2. DRAFT — new issue for the §4.1 re-embed ticket

**Title:**

```
Align MoodDescriptor and VibePhraseBuilder thresholds with the Option E band (requires full re-embed)
```

**Body:**

```markdown
## What

Apply the Option E emomusic band (`3.0..7.0`) to the **display and embedding-text** thresholds, so
both channels that consume mood agree about what "sunny" means.

Recorded in `docs/superpowers/specs/2026-08-14-mood-scale/principal-optionE.md` §4.1 as a separate,
cost-bearing follow-on. It is filed now so the cost is never discovered mid-implementation.

## Why

Option E recalibrated mood **only in the Euclidean channel**, at scoring time. Mood reaches the
blended score through a second channel that was deliberately left alone:

`MoodDescriptor.render` (`mood_descriptor.rb:10-13, 18-19, 23-24`) →
`AlbumEmbeddingService#emotional_text` (`album_embedding_service.rb:41-45`) → the `emotional` facet
(`candidate_retrieval.rb:3`, weight `0.15`).

That channel still applies **absolute 0.6/0.4 thresholds to compressed stored values**. Measured
over the 321-row fixture, a valence phrase fires on **32 of 321 albums (10 %)**. So the two channels
disagree for albums in roughly the 60th–95th percentile of the compressed heads: the Euclidean
channel now treats such an album as clearly sunny, while the embedding text says nothing about
valence at all.

`MoodVectors::VibePhraseBuilder` has the same shape (`NEUTRAL 0.5`, `DISTINCTIVE_THRESHOLD 0.1`,
high/low split at `0.6`), so the two most human-legible adjectives — somber/sunny and
hushed/driving — are effectively disabled for most of the catalogue.

**This is pre-existing, not a regression from Option E.** Option E did not widen the gap; it left it
where it was, deliberately, because closing it is not free.

## Why it is not free — the cost, stated up front

Changing `MoodDescriptor`'s thresholds changes `emotional_text`, which changes the **emotional facet
embedding for every album**. That means:

- A **full-catalogue re-embed**: ~321 albums × 4 facet embeddings via `text-embedding-3-small`.
- One complete enrichment pass.
- **Every album's emotional facet moves at once**, so recommendation output shifts catalogue-wide in
  a single step — with no per-album way to stage or A/B it.

Monetary cost is small; the *risk* is that it is an all-at-once change to a live ranking input.

## Scope

- [ ] Apply the `3.0..7.0` band (or a percentile equivalent — decide first) to `MoodDescriptor`'s
      valence/arousal thresholds
- [ ] Decide whether `VibePhraseBuilder` moves with it, or stays absolute for display
- [ ] Decide whether `VibeOverride` rows, entered by users against the old display scale, need a
      version marker — they currently have none
- [ ] Re-embed the catalogue and confirm the emotional facet moved as intended
- [ ] Before/after comparison of recommendation output on the fixed 12-query set, so the
      catalogue-wide shift is measured rather than assumed

## Explicitly out of scope

Moving the band into `MoodVectors::EssentiaMapper`. Option E §4.2 refuses that: it would require a
migration, a backfill, this re-embed, a redefinition of every display threshold, and a silent break
in already-stored `VibeOverride` rows. **The band stays at scoring time.**

## Not urgent

The emotional facet is `0.15` of `FACET_WEIGHTS`, and `MoodDescriptor` output is only part of
`emotional_text`, so the magnitude is bounded. The measured defect that motivated the mood-scale
work lives in the Euclidean channel, which Option E has fixed.

## Provenance

`docs/superpowers/specs/2026-08-14-mood-scale/principal-optionE.md` §4, §4.1, §4.2, on branch
`feat/mood-scale-option-e`.
```

---

## 3. The `mood_head_shares` instrumentation — size, and can it follow?

**It can and should follow. It is roughly a half-day, and the arithmetic is the least of it.**

The computation itself is trivial — six accumulators of `HeadWeights.for(head) * delta**2` over the
candidate set, which `MoodDistance.term` already computes and discards, so it is a few lines and no
extra query. The real work is three small structural things, none hard: the migration and column
(`recommendation_events` already has the `blended_scores` / `rerank_scores` jsonb pattern to copy);
**threading the value out of `CandidateRetrieval`, whose `#call` returns a bare `Array` of
`Candidate` structs that `GenreAdmissionFilter` and `RankedCandidate.rank` both consume** — do this
by retaining the instance in `Pipeline` (`retrieval = CandidateRetrieval.new(…)`, then
`retrieval.call` and later `retrieval.head_shares`) rather than changing the return type, which
would ripple into every downstream consumer and their specs; and deciding *which* set the shares are
computed over — I would use all scored `candidate_ids`, not the `first(@limit)` slice or the
post-`GenreAdmissionFilter` set, because the question it answers is about the user's collection, not
about what survived filtering. One inconsistency in my own plan to fix while you are in there: §6
specifies "six keys" but also says the column records the max observed mood term, which is a seventh
value — put it in the same jsonb under a distinct key and say so, or it will get dropped.

**On sequencing: it must follow, not ship with Option E.** It is a migration and therefore a
Tier-1 trigger in its own right, and migrations are not cheaply revertable — whereas Option E's
entire rollback story is a single revert of the wiring commit. Sharing a commit would forfeit that.
It is also not on the critical path for anything: it answers a question Option E deliberately does
not depend on (per-collection variation), and it only starts producing data once real traffic
arrives. **Next thing after Option E merges, not part of it.**

---

## Evidence

Read on `feat/mood-scale-option-e` @ `bc6bc5d`: `head_calibration.rb`, `head_weights.rb`,
`mood_distance.rb`, `candidate_retrieval.rb`, `essentia_mapper.rb`, `mood_grounding_service.rb`,
`mood_descriptor.rb`, `album_embedding_service.rb`, `vibe_phrase_builder.rb`, `pipeline.rb`,
`db/schema.rb`, and `principal-optionE.md` §4/§4.1/§4.2/§6. Re-derived `calibrated = 2·stored − 0.5`
and the `1.190238` term bound by hand. Confirmed via `gh issue view 30` that the issue is open with
**0 comments**. Nothing was posted.
