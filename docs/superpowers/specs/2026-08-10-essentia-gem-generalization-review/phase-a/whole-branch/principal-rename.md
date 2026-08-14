# SONANCE 0.3.0 — Principal rulings: descriptor ids, fixtures, compatibility, sequencing

Four rulings. Effort is concentrated on Ruling 1, per the constraint.

---

## RULING 1 — **ALL PRODUCER-QUALIFIED.** Driven by (a) collision; (c) settled the form.

### The ruling

Every descriptor id is `<quantity>_<producer>`, with **no exemptions**. The producer is the model
family for `FromModel` rows and the algorithm for `FromAlgorithm` rows.

### The full table as it ships

| # | today | **0.3.0** | producer | source row |
| --- | --- | --- | --- | --- |
| 1 | `valence_emomusic` | **`valence_emomusic`** *(unchanged)* | emomusic head | `emomusic-msd-musicnn-2.pb` |
| 2 | `arousal_emomusic` | **`arousal_emomusic`** *(unchanged)* | emomusic head | `emomusic-msd-musicnn-2.pb` |
| 3 | `danceability` | **`danceability_musicnn`** | msd-musicnn head | `danceability-msd-musicnn-1.pb` |
| 4 | `mood_acoustic` | **`mood_acoustic_musicnn`** | msd-musicnn head | `mood_acoustic-msd-musicnn-1.pb` |
| 5 | `mood_relaxed` | **`mood_relaxed_musicnn`** | msd-musicnn head | `mood_relaxed-msd-musicnn-1.pb` |
| 6 | `mood_happy` | **`mood_happy_musicnn`** | msd-musicnn head | `mood_happy-msd-musicnn-1.pb` |
| 7 | `musicnn_embedding` | **`embedding_musicnn`** | msd-musicnn backbone | `msd-musicnn-1.pb` |
| 8 | `bpm` | **`bpm_rhythm2013`** | RhythmExtractor2013 | `FromAlgorithm` |
| 9 | `beat_confidence` | **`beat_confidence_rhythm2013`** | RhythmExtractor2013 | `FromAlgorithm` |

Seven renames, two unchanged. **The two that stay are the two that were already right** — which is
itself evidence this is the convention the design was reaching for and half-applied.

### Why (a) collision decided it

The registry is explicitly extensible: `Registry.new(models:, descriptors:)` is public and is the only
registration door. A third party registering an EffNet-Discogs danceability head is not hypothetical —
it is the advertised use case.

Under **ALL BARE**, the id `danceability` is owned permanently by whichever model claimed it first. The
third party must either shadow it or invent `danceability_effnet` — **producing, on day one, exactly the
mixed convention we are paying a breaking release to remove.** Bare ids do not avoid the rename; they
defer it onto the consumer and guarantee the inconsistency recurs.

Under **ALL PRODUCER-QUALIFIED**, `danceability_musicnn` and `danceability_effnet` coexist. No existing
id moves. That is the whole test the brief posed, and only one convention passes it.

### Why I rejected (b)

Aligning the gem's ids to `MoodVector::MOOD_HEADS` (`:valence`, `:arousal`) is **an app-shaped opinion
leaking back into the gem — the precise thing Phase A spent five slices removing.** Three reasons, the
third decisive:

1. The mapper existing is not a cost, it is **the deliverable**. §A9 exists so the gem emits native,
   gem-named values and the app translates. "Shrink the mapper" argues for re-coupling the gem to
   `mood_vectors` column names.
2. `MOOD_HEADS` are database column names. A gem whose public vocabulary is one consumer's schema is the
   v1 failure with a new spelling.
3. **It creates the collision it claims to avoid, inside the app's own domain.** If the app later adopts
   a better arousal model, the gem's bare `arousal` either lies about which model produced it or must be
   renamed — a breaking gem release caused by an app decision. Qualification makes that a pure addition:
   register `arousal_<new>`, change one line in `DESCRIPTORS`, retire the old row when convenient.

### Why (c) settled the form rather than creating an exception

`bpm` and `beat_confidence` genuinely differ from the model heads: BPM names a **physical quantity with
objective ground truth** (G19 depends on the click train's known 120 BPM), whereas `mood_happy` names a
model's opinion with no ground truth. I considered exempting them and leaving them bare.

**I rejected the exemption, and this is the load-bearing reason for the whole ruling: the rule's value is
that it removes judgment.** "Qualify when the value is definitionally model-dependent" requires a
judgment call at every new descriptor, and judgment calls drift — that is precisely how
`valence_emomusic` and `danceability` ended up in one registry. A mechanical rule cannot drift. Any
exemption reintroduces the failure mode.

And the exemption would not even work: a second BPM estimator (`PercivalBpmEstimator`) wants the id
`bpm` just as much. Objective quantities collide too.

### Ground (d) verbosity — acknowledged and paid

`beat_confidence_rhythm2013` is 26 characters. The call site cost is real:

```ruby
descriptors: %i[valence_emomusic arousal_emomusic danceability_musicnn
                mood_acoustic_musicnn mood_relaxed_musicnn mood_happy_musicnn]
```

Two mitigations that need no id change: the app already binds this list once, in
`MoodVectors::EssentiaMapper::DESCRIPTORS` (`app/models/mood_vectors/essentia_mapper.rb:6-13`), so the
verbosity is paid in exactly one place per consumer; and `Registry.default.ids` remains the discovery
call. I judge the cost worth paying — the alternative is a rename later, which is what this release
exists to prevent.

Note the slug deliberately names the **architecture family** (`musicnn`), not the versioned model
(`msd-musicnn-1`). Version drift is already carried by `Model#model_version`; putting it in the id would
force a rename on every upstream version bump.

### MUST ship with the rename — the registry silently accepts duplicate ids

`registry.rb:302-308` builds `@descriptors_by_id = descriptors.to_h { |d| [d.id, d] }.freeze`. Ruby's
`to_h` is **last-wins on duplicate keys, silently**. So two rows claiming `danceability` produce a
registry where `descriptors` holds both and `fetch(:danceability)` returns only the second — the first
becomes unreachable with no error. *(Verified by reading `Registry#initialize`; I did not execute it.)*

**Failure scenario:** a third party appends their EffNet head to `Registry.default.descriptors` and
reuses the id. `plan_for([:danceability])` silently plans the wrong model, `verify!` fetches the wrong
`.pb`, and the values are wrong with no diagnostic anywhere.

Without this fix the convention is unenforced and the collision it exists to prevent fails *silently*
rather than loudly. Raise `ArgumentError` on duplicate descriptor **or** model ids in
`Registry#initialize`, and document the `<quantity>_<producer>` rule in the README next to the
extension-boundary section that the whole-branch review already requires.

---

## RULING 2 — The tension dissolves. The baseline is not keyed by descriptor ids.

**Verified, and it is the fact that resolves this:** `spec/fixtures/mood_probe/baseline_v0_1_0/clicks.json`
is keyed `danceability, mood_acoustic, mood_relaxed, mood_happy, valence, arousal` — **app column names,
not gem descriptor ids.** The mapping lives in the spec: `spec/baseline_v0_1_0_parity_spec.rb:17`
(`"valence" => "valence_emomusic"`). `golden/*.json` is keyed by descriptor id
(`"valence_emomusic": 5.8459882736206055`).

**Therefore: the id rename does not touch the frozen baseline at all.** It touches `golden/*.json`, the
`head_mapping` table in the parity spec, and the `emit[].id` fields in the committed plan fixtures.

**Do NOT create `baseline_v0_3_0/`.** Retirement exists for when *values* change (an upstream model
version bump). Nothing here changes a value. Creating a dated directory would discard the continuity
claim the baseline exists to make.

### Safe order, with the evidence required at each step

| Step | Action | Evidence that must be captured |
| --- | --- | --- |
| **0** | Run G1 / the parity spec on the **current** tree, before touching anything | Full per-descriptor deviation output, saved verbatim. This satisfies "run before any golden is rewritten." |
| **1** | Rename ids in `registry.rb` only | Suite red — expected and informative |
| **2** | **Pure key rename** of `golden/*.json` — same float bytes, new keys | Per fixture: the ordered value list before and after is **byte-identical**. Command + output committed to the commit message or `golden/PROVENANCE.md`. |
| **3** | Regenerate committed plan fixtures via the hand-run generator (`plans/generate.rb`, per §E.4 — never by the asserting spec) | Diff shows **only `emit[].id` strings changed**; no `ref`, `file`, `output`, `take`, `reduce`, `sample_rate`, or `schema_version` moved |
| **4** | Update `head_mapping` in `baseline_v0_1_0_parity_spec.rb:17` | The four new mappings; `valence`/`arousal` rows unchanged |
| **5** | Re-run G1 / parity | **Per-descriptor deviations identical to step 0** |
| **6** | Confirm the anchor | `git diff --stat` shows **zero** files touched under `baseline_v0_1_0/`; the SHA-256 manifest still matches |

### The proof that only keys changed

**Step 5's bar is exact equality, not tolerance.** Both sides of G1 are committed bytes; no environment
is involved, so the deviations after a pure key rename must be *identical* to before, digit for digit.
If any deviation differs at all, a value moved and the step is rejected.

This deliberately inverts the tolerance rule I set in slice 4 — and correctly. That rule loosened `eq`
because *measurements* crossed environments. Here nothing is measured: two committed files are read and
compared. Exact is the right bar precisely because there is no environment in the comparison.

**Step 2 must be a key rename, not a regeneration.** Regenerating would change keys *and* values in one
step and confound them; there would be no way to prove the rename was value-preserving. This does not
violate my slice-5 causal-provenance ruling: a key rename creates no new measurement, it relabels an
existing one, and `golden/PROVENANCE.md` continues to describe the extraction that produced the values.
Add a line to that file recording the relabelling, its commit, and the step-2 evidence.

**Steps 1–5 must be a single commit**, separate from the module rename (Ruling 4), so the golden diff is
reviewable in isolation. A `MoodProbe → Sonance` diff across 65 files would bury it.

---

## RULING 3 — Clean break. No shim, and **specifically no id aliases**.

§5.1–5.3's no-shim ruling still holds and is **stronger** now, not merely unchanged.

- **A shim protects consumers you cannot coordinate with.** There is one consumer, in the same person's
  control, pinned to an immutable git tag. It cannot break by surprise: `bundle install` resolves
  `tag: "v0.2.0"` until someone edits the Gemfile. There is no RubyGems release, so no third party can
  be mid-upgrade.
- **A `MoodProbe` compatibility namespace would defeat the rename's purpose.** The user chose a name
  tied to nothing that can change. An alias keeps the old name alive in autocomplete, in `grep`, and in
  every file someone copies — it preserves exactly the thing being retired.
- **Id aliases are worse than debt: they undo the fix.** If `Registry.default` answers to both
  `danceability` and `danceability_musicnn`, the bare id is still live and a third party's
  `danceability_effnet` is still fighting it. The aliases would reintroduce the collision ambiguity that
  is the entire justification for Ruling 1.

**The compatibility mechanism already exists and is better than a shim: the tags.** `v0.1.0` and
`v0.2.0` are immutable and remain fetchable after the repo rename. Anything needing the old API pins to
the old tag. That is a cleaner contract than a deprecation path and it costs nothing.

---

## RULING 4 — Sequencing

**GitHub serves a redirect for renamed repositories, so the old git URL keeps resolving.** *(Standard
GitHub behaviour; I did not verify it in this environment — confirm before relying on it.)* That means
the repo rename is not app-breaking, but the sequence below keeps the redirect window to minutes rather
than days, because a redirect breaks permanently if anyone later creates a repo at the old name.

### Gem — three commits on the branch, tag last

| Commit | Contents | Notes |
| --- | --- | --- |
| **A** | **Descriptor ids only** — Ruling 2 steps 1–5, plus duplicate-id rejection in `Registry#initialize` | The value-preservation evidence commit. Must stand alone. |
| **B** | **`MoodProbe` → `Sonance`** — gemspec, `lib/sonance.rb`, `lib/sonance/**`, `exe/sonance`, env prefixes (`MOOD_PROBE_*` → `SONANCE_*`), the Python script name, README, NOTICE, `spec/fixtures/mood_probe/` → `spec/fixtures/sonance/` | See the baseline-move ruling below |
| **C** | Version `0.3.0`, CHANGELOG/README breaking-change note | |

Then **push, CI green on C, then tag `v0.3.0` on C** — the tag points at a commit already proven green
(slice-4 ruling), never at one you intend to fix.

**Baseline directory move — permitted, with proof.** Commit B moves
`spec/fixtures/mood_probe/baseline_v0_1_0/` to `spec/fixtures/sonance/baseline_v0_1_0/`. "Never edited"
governs **bytes**, not path; leaving a `mood_probe` path inside a gem called sonance contradicts the
user's "fix everything with the name." Required evidence: `git log --follow` shows a pure rename, the
SHA-256 manifest still matches all files, and `PROVENANCE.md` gains a line recording the move.

### Repo rename — after `v0.3.0` exists, immediately before the app repin

Tags survive the rename (same repository object), so `v0.1.0` and `v0.2.0` remain fetchable at the new
URL. Doing it after the gem work avoids renaming out from under an in-flight CI run.

### App — two commits, I then B

**Commit D — infrastructure, must survive a rollback:**

- **`.github/dependabot.yml:9`: `dependency-name: mood_probe` → `sonance`.** Verified present today.
  **This is the item most likely to be missed and its failure is silent** — an ignore entry naming a
  package that no longer exists matches nothing, raises nothing, and leaves the pin unguarded against a
  weekly bot bump. It is a guardrail J.5 step 1 keeps through a rollback, so it belongs in the
  infrastructure commit, not the behaviour commit.
- Any CI reference to the gem name.

**Commit E — behaviour.** All fifteen files that reference `MoodProbe` today (verified by
`grep -rln MoodProbe app lib config spec`):

- `Gemfile` (URL **and** `tag: "v0.3.0"`) + `Gemfile.lock`
- `app/models/mood_vectors/essentia_mapper.rb` — `DESCRIPTORS` (`:6-13`) gets the new ids; `EMOMUSIC_RANGE` unchanged
- `config/initializers/mood_probe_registry.rb` — **file renamed too**, module and descriptor id
- `app/services/mood_grounding_service.rb` — the two `analyze` sites and the `rescue MoodProbe::TrackError` handlers
- `app/jobs/enrich_album_job.rb`
- **`lib/tasks/enrichment.rake` — `MoodProbe::FatalError` at `:5` and `:49`, `MoodProbe::Extractor.new` at `:18` and `:31`, `verify!(descriptors:)` at `:21` and `:44`.** Six sites in one file. *(Named explicitly because it was missed once.)*
- `spec/mood_probe_dependency_spec.rb`, `spec/models/mood_vectors/essentia_parity_spec.rb`,
  `spec/models/mood_vectors/essentia_registry_contract_spec.rb`,
  `spec/services/mood_grounding_service_spec.rb`, `spec/tasks/enrichment_rake_spec.rb`,
  `spec/jobs/enrich_album_job_spec.rb`, `spec/integration/essentia_empty_models_spec.rb`,
  `spec/integration/essentia_extract_golden_spec.rb`, `spec/fixtures/mood_probe/generate_goldens.rb`,
  `spec/fixtures/mood_probe/golden/PROVENANCE.md`
- App `golden/*.json`: keyed by descriptor id, so the **same Ruling 2 evidence rule applies** — pure key
  rename, exact-equality proof, app `baseline_v0_1_0/` bytes untouched

**Ordering constraint inside commit E:** `spec/mood_probe_dependency_spec.rb` asserts the gem identity
against the peeled tag SHA (the external oracle from my slice-5 ruling). That SHA does not exist until
`v0.3.0` is cut, so this spec is the **last edit** in commit E and cannot be written earlier.

### Must not move

`v0.1.0` (the J.5 rollback anchor) and `v0.2.0` (the current pin and Phase A's anchor). Neither is
touched by any step above.

### **J.5 must be amended — a blanket revert now produces a stale URL**

J.5 step 1 says revert the behaviour commit; step 2 says the `Gemfile` returns to `tag: "v0.1.0"`.
After the repo rename, reverting commit E restores the **old URL** (`.../mood_probe.git`), leaving the
rollback dependent on a GitHub redirect at exactly the moment you least want a dependency on one.

Amend step 2 to: *"the `Gemfile` returns to `tag: "v0.1.0"` **at the current repository URL**
(`.../sonance.git`); do not restore the pre-rename URL that a blanket revert produces."* Also record
that gem `v0.1.0` and `v0.2.0` still expose the `MoodProbe` namespace, so rolling back to either
requires reverting commit E's call-site changes as well — which the revert does, but which must be
stated so nobody reverts the `Gemfile` alone.

---

## EVIDENCE

**Verified by command, output read:**

- `spec/fixtures/mood_probe/baseline_v0_1_0/clicks.json` — keys `danceability, mood_acoustic,
  mood_relaxed, mood_happy, valence, arousal` (**app column names**)
- `spec/fixtures/mood_probe/golden/clicks.json` — keys `valence_emomusic, arousal_emomusic,
  danceability, mood_acoustic, mood_relaxed, mood_happy` (**gem descriptor ids**)
- `spec/baseline_v0_1_0_parity_spec.rb:17` — `"valence" => "valence_emomusic"` (mapping lives in the spec)
- `spec/fixtures/mood_probe/plans/` — `algorithm_only.json`, `emomusic.json`, `mixed.json`,
  `musicnn_only.json`, `generate.rb`; fixtures carry `emit[]` entries
- `.github/dependabot.yml:9` — `- dependency-name: mood_probe`
- `lib/tasks/enrichment.rake` — `:5`, `:18`, `:21`, `:31`, `:44`, `:49`
- `app/models/mood_vectors/essentia_mapper.rb:6-13` — `DESCRIPTORS`, `:14` `EMOMUSIC_RANGE`
- `grep -rln MoodProbe app lib config spec` → 15 files, listed above

**Verified by reading, not executed:** `Registry#initialize` (`registry.rb:302-308`) uses `to_h`, which
is last-wins on duplicate keys — the basis for the duplicate-id finding.

**Believed, not verified:** GitHub's redirect behaviour for renamed repositories.

**Read-only compliance:** no file in either repository was modified, staged, or committed; the only file
written is this report.
