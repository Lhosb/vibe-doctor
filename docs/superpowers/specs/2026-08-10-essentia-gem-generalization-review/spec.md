# Spec Review — ESSENTIA-GEM-V2

**Reviewer:** Spec Reviewer (Plumb). Design-phase review. **Read-only — no repo file was created, edited, or deleted.**
**Date:** 2026-08-10

| Repo | HEAD reviewed | Tree |
| --- | --- | --- |
| vibe-doctor (`/Users/lukeolson/projects/vibe-doctor`) | `0499d9cd38e7009eccbc6f75e50e93bd4800bc3e` | clean |
| mood_probe (`/Users/lukeolson/projects/gems/mood_probe`) | `5360f8fd8609eae39edb5dfab8a07f6439a0b137` | clean |

Artifacts reviewed: the brief (`/Users/lukeolson/Downloads/mood_probe_gem_brainstorm_prompt.md`),
`principal.md` (74 KB, read in full), `security.md` (read in full), `inventory.md` (read in full).
Every current-behaviour claim below was re-derived from source at the SHAs above, not taken from
those reports.

---

## VERDICT: **APPROVE-WITH-CHANGES**

The design is strong and it is not a relabel. §0 (class order is inconsistent upstream, so
`positive_index` must die) is a genuine find that nothing in the brief anticipated, and §6.5 Rule 2
(algebraic invariance against the *old* goldens, asserted before any golden is regenerated) is the
single best idea in either document — it is the only proposed gate that cannot be satisfied by
regenerating the thing it checks. The Model/Descriptor split, the Ruby-side planner, and the
schema-free Phase A are all correctly argued.

It does not ship as written. Eight MUST-FIX items follow. Two of them (M1, M3) mean the design's own
headline claims — "Phase B is gem-only" and "Phase A is a two-line revert" — are currently false as
specified. One (M2) is the boundary conflict the dispatch asked me to adjudicate.

---

## THE CONFLICT — adjudicated

**Question.** Principal §3.1 puts the planner in Ruby and ships a fully-resolved plan (model
filenames, output nodes, algorithm names, tensor indices) across the boundary. Security hard
constraint 1 (`security.md:170`) says "Only descriptor IDs cross the Ruby/Python request boundary,"
and `security.md:45` recommends resolving the same ID independently on both sides.

**Ruling: the Principal's Ruby-side planner stands. Constraint 1's *letter* gives way; its *intent*
must be honoured by three Python-side changes the Principal does not currently propose. Do not
duplicate the manifest in Python.**

Three reasons the letter must give way:

1. **"Independent registries" would not be independent.** The Python script ships inside the gem and
   is resolved relative to `__dir__` (`mood_probe/lib/mood_probe/backends/essentia_python.rb:10`).
   Two manifest copies inside one tarball, released and pinned as one artifact, are not two trust
   domains — they are one registry with a consistency bug waiting to happen. The duplication buys no
   security and costs exactly the drift the ticket exists to remove (brief:22 — "Adding any Essentia
   capability means editing the gem"; duplication makes it two edits, in two languages, one of which
   is only testable in Docker).
2. **ID-only cannot express settled decision 1.** The brief (line 30) requires runtime custom
   registration. A Python side that resolves IDs from its own frozen manifest cannot resolve a
   consumer-registered ID at all — so either custom descriptors are dropped (breaking an agreed
   decision), or the custom rows cross the wire anyway, which is the plan under another name.
   Security half-concedes this at `security.md:46` by making registration operator-trusted.
3. **The real trust boundary is authorship, not transmission.** Security's own failure scenario
   (`security.md:38`) is a malicious *registration* — `filename: "../../config/..."`, an arbitrary
   `source_url`, an attacker-chosen class name. That attack is identical whether the row is resolved
   in Ruby or in Python. Moving resolution does not close it; validating the resolved values does.

But constraint 1 is protecting something real, and Principal §4.1 currently violates it outright by
proposing `getattr(es, name)(**params)`. That is a native-code-selection primitive driven by wire
data, and `security.md:47` names it explicitly. Three additions, all Python-side, all cheap:

- **(a) Static algorithm enum, no `getattr`.** `plan["algorithms"][i]["name"]` must be a key in a
  hardcoded dict (`{"RhythmExtractor2013": es.RhythmExtractor2013, "KeyExtractor": …}`);
  `plan["graphs"][i]["algorithm"]` must be in `{"TensorflowPredictMusiCNN", "TensorflowPredict2D"}`.
  An enum of six class names is a *capability list*, not a manifest: it carries no filenames, no
  ranges, no classes, no provenance, and adding to it is a deliberate two-sided change — which is
  exactly the friction you want on a native-code surface.
- **(b) Path containment.** `plan["graphs"][i]["file"]` must match `\A[A-Za-z0-9._-]+\.pb\z`, be
  joined under `--models-dir`, canonicalised, asserted inside the root, and asserted a regular
  non-symlink file. Today Python joins a *constant* under `models_dir`
  (`mood_probe/python/mood_probe_extract.py:27`); the moment the filename is wire data, that join
  needs the check. Satisfies `security.md:50` with zero manifest knowledge.
- **(c) Per-algorithm param whitelist.** Each enum entry declares its permitted `params` keys and
  value types. Otherwise `params` is arbitrary kwargs injection into native code.

**What stops Ruby and Python drifting — three named mechanisms, not intentions:**

1. **Single artifact.** `SCRIPT_PATH` is `__dir__`-relative (`essentia_python.rb:10`), so a correctly
   installed gem physically cannot hold mismatched halves. (Principal §4.2 point 2 — verified true
   today; it must be stated as a *preserved property*, not assumed.)
2. **`schema_version` handshake, already fatal.** Python rejects an unknown plan version with exit 2;
   `raise_for_fatal_exit!` maps exit 2 to `ConfigurationError` (`essentia_python.rb:140`), a
   `FatalError` (`errors.rb:12`) that aborts the whole run at preflight
   (`enrichment.rake:49`) before a single album is written. Verified.
3. **A capability cross-check spec — this is the piece the design is missing.** Add
   `mood_probe_extract.py --capabilities`, printing the enum's algorithm names as one JSON line
   *before* importing Essentia (the script already defers `import essentia.standard` into
   `load_models`, `mood_probe_extract.py:24`, so this runs on a Mac). Then a pure-Ruby spec asserts
   every `FromAlgorithm#name` and every `Model#algorithm` in `Registry.default` appears in that list.
   Drift becomes a red spec on a laptop instead of an exit-2 in production. Same shape as the golden
   plan fixture the Principal already proposes (§4.2 point 3), and it composes with it.

**Cost of this ruling:** roughly 40 lines of Python validation, one enum table, one `--capabilities`
flag, one Ruby spec. **It does not cost a duplicated manifest, and it does not cost the planner.**

Tracked as **MUST-FIX M2**.

---

## MUST-FIX

### M1. `verify!` is specified two contradictory ways, and the reading that survives makes "Phase B is gem-only" false

**Design:** §2.1 introduces `extractor.verify!(descriptors: [...])` — "preflights only what the set
needs." §5.3's compatibility table lists `#verify!` as a surface that **must not change in 0.2.0**.
These cannot both hold.

**Current behaviour, verified.** `Extractor#verify!` takes no arguments
(`mood_probe/lib/mood_probe/extractor.rb:19`) → `backend.verify!`
(`essentia_python.rb:89-101`) → `model_store.verify!`, which iterates **every** row in the registry
(`model_store.rb:41-44`) and raises `ConfigurationError, "missing model: …"` on the first absent file
(`model_store.rb:58`). vibe-doctor calls it with no arguments at three sites:
`app/jobs/enrich_album_job.rb:8`, `lib/tasks/enrichment.rake:21`, `lib/tasks/enrichment.rake:44`.
vibe-doctor commits exactly six `.pb` files (`git ls-tree -r -l HEAD tmp/essentia_models` — the six
existing models, 3,610,291 bytes total).

**What breaks if this is not fixed.** Take §5.3's reading (`verify!` unchanged, whole-registry).
Phase B adds five `Model` rows to `Registry.default` (§6.2). vibe-doctor bumps the gem tag and
changes nothing else — which §6.2 explicitly says is safe ("Must land together? No. Gem-only. That
decoupling *is* the payoff of the whole ticket"). On the next enrichment, `enrich_album_job.rb:8`
raises `ConfigurationError: missing model: .../mood_sad-msd-musicnn-1.pb`, `EnrichAlbumJob` rescues,
marks the album failed and re-raises (`enrich_album_job.rb:45-52`), and `run_enrichment` re-raises on
`MoodProbe::FatalError` (`enrichment.rake:49-51`), aborting the batch. **Every album fails from a
gem-only bump — the exact outcome the ticket exists to prevent.**

**Fix.** Make `verify!(descriptors:)` a required keyword, exactly as `analyze` is (§2.1's own
argument applies verbatim), make `ModelStore` verification demand-driven off the plan (§3.3 step 8
already computes the required file set — this is the right mechanism and it subsumes most of Security
constraint 5's "explicit packs"), delete `#verify!` from §5.3's frozen-surface table, and add the
three app call sites to Phase A's scope. Then add a Phase B acceptance criterion that is currently
missing: *a vibe-doctor spec that Phase B's registry, with only the six `.pb` files present,
preflights and analyses successfully.* That is the assertion that makes "gem-only" true rather than
asserted.

### M2. The Ruby→Python boundary must be a constrained instruction set, not free-form (the CONFLICT)

Full adjudication above. Concretely: §4.1's `getattr(es, name)(**params)` must become a static enum;
`plan["graphs"][i]["file"]` must be basename-validated and root-contained; `params` must be
whitelisted per algorithm; add `--capabilities` plus the cross-check spec.

**What breaks otherwise.** A registry row — gem-authored today, consumer-authored under §2.4 —
becomes a direct selector for an arbitrary Essentia/TensorFlow class and an arbitrary path under a
native parser. `security.md:38` and `:47` describe this; `model_store.rb:57` (`models_dir.join(...)`)
shows the join that currently has no containment check because its input is a constant.

### M3. The clamp is *intended* to land with the deletion. Nothing *mechanizes* it — and the design also silently deletes a second guard

**Verified current behaviour — there are three guards, not one.** `MoodProbe::Features` applies, in
order (`mood_probe/lib/mood_probe/features.rb:14-20, 44-52`):

- `SANITY_RANGE = (-0.5..1.5)` for **all six** heads → `MalformedOutputError` outside it (`:6`, `:45-47`);
- `OUTPUT_RANGE = (0.0..1.0)` as a **hard raise** for the four classification heads only (`:7`, `:48-51`);
- `value.clamp(OUTPUT_RANGE)` for the two regression heads, valence and arousal (`:19`).

`MalformedOutputError` is a `TrackError` (`errors.rb:7`), so today an emomusic output far off scale
produces a **skipped track with a logged warning** (`app/services/mood_grounding_service.rb:94-96`),
not a bad number. `MoodVector` validates every head into `0.0..1.0`
(`app/models/mood_vector.rb:9`), and the plan doc records Bug 2 as closed *by that clamp*
(`docs/superpowers/plans/2026-08-07-essentia-ruby-gem-extraction.md:43-45` — verified verbatim).

**§4.5 deletes all three** (rescale, clamp, and the `SANITY_RANGE`/`OUTPUT_RANGE` constants) and
replaces emomusic's protection with `range_kind: :nominal` = **finiteness only** (§1.2). Two distinct
problems:

**(a) Nothing asserts the mapper clamps.** The only cross-repo assertion the design proposes (§4.5
item 2) checks `Registry.default.fetch(:valence_emomusic).native_range == EMOMUSIC_RANGE`. A mapper
that declared the right range and omitted `.clamp` passes it. That is intent, not mechanism.

**(b) An out-of-scale value that is skipped today is silently saturated tomorrow.** Raw emomusic of
500 → today `(500-1)/8 = 62.4` → outside `SANITY_RANGE` → `MalformedOutputError` → track skipped.
Under the design → mapper clamps → `1.0` → persisted, aggregated, indistinguishable from a genuine
maximum. This regression appears nowhere in `principal.md`.

**What breaks.** Without (a): the mapper ships without the clamp in some later refactor,
`mood_vector.update!` (`enrich_album_job.rb:26`) raises `RecordInvalid`, the album is marked failed.
Recoverable (see S8) but noisy and delayed. Without (b): silent data corruption with no error at
all — strictly worse, because §6.5 Rule 2's parity gate runs on four synthetic fixtures whose
emomusic values are in range, so it passes while production behaviour has changed.

**Fix, three parts:**
1. A vibe-doctor spec on `MoodVectors::EssentiaMapper` feeding a synthetic `Analysis` with
   `valence_emomusic = 9.4` → asserts exactly `1.0`, and `= 0.6` → asserts exactly `0.0`, **plus a
   passing control just inside the bound** (`9.0 → 1.0`, `1.0 → 0.0`). Runs on a Mac, no Docker.
2. Make §4.5 item 2's range agreement a **boot-time initializer**, not "at boot or in a spec". The
   "or" is what makes it useless for the failure it exists to catch: a spec does not run in
   production, and the failure mode being guarded is a mis-paired *deploy*.
3. Preserve the two-tier behaviour rather than collapsing it: give the emomusic descriptor a declared
   sanity window in addition to its `:nominal` native range, so wildly-off values still raise
   `MalformedOutputError` (skippable track) and only near-boundary values are clamped. Otherwise the
   design trades a detected failure for a silent one.

### M4. Phase B's five new heads have no gate that can catch a class-name inversion

§0 establishes that three of the five Phase B heads (`mood_sad`, `mood_party`, `voice_instrumental`)
have inverted or axis-free class order, and Risk 6 rates this "the highest-consequence
silent-correctness area." §6.2's defence is one watch-item sentence: a spec asserting `classes`
matches upstream "**ideally** a checked-in copy of each `.json`."

**"Ideally" is not a gate, and nothing else covers it.** §6.5 Rule 4 says Phase B's gate is that the
*Phase A* goldens re-run unchanged — that protects the six existing heads and says nothing about the
five new ones. A golden for a new head cannot catch inversion either: it would pin `1-p` as the
expected value forever. The **only** thing that catches it is a verbatim comparison against upstream
`classes`.

**What breaks.** `mood_sad` ships as `P(non_sad)` — a "sadness" score that is a plausible 0..1 float,
monotonically wrong, with no failing test, feeding `MoodVector`-adjacent product decisions
indefinitely.

**Fix.** Promote it to a hard Phase B acceptance criterion: check in each upstream `.json` alongside
each `.pb` checksum, and a **non-network** spec asserting `Model#classes == JSON.parse(file)["classes"]`
row-by-row. Reviewers must check each row against its own JSON, never against the neighbouring row.

### M5. Collapse the two selector forms into one — `{ class: "<name>" }`

§1.2 defines `FromModel#select` as `{ class: "happy" } | { output: :valence } | nil`, and §1.5/§2.3
use `{ output: :valence }` for emomusic. But §0 records that upstream declares emomusic's
`classes: ["valence", "arousal"]` — the *same* mechanism as the classification heads. Two selector
spellings for one upstream concept re-introduce exactly the "two ways to say it, they can disagree"
hazard that §0's class-name rule exists to remove.

**What breaks.** emomusic's two descriptors resolve through a code path that the nine classification
heads never exercise — and emomusic is the model whose output ordering is *least* checked by anything
that exists today: `mood_probe_extract.py:63-64` hardcodes `va_mean[0]`/`va_mean[1]` with no upstream
cross-reference, and no spec asserts index 0 is valence. If upstream ever reorders, only a name-based
selector notices.

**Fix.** One selector: `{ class: "valence" }`, resolved against `Model#classes`. Keep `nil` for
whole-output Vector. Drop `{ output: … }`.

### M6. Phase A's vibe-doctor scope omits five files that hard-depend on the deleted API

§6.1 lists the app-side Phase A work as: the mapper, two `analyze` call sites, and `Gemfile:34`.
Verified files that break and are not listed:

| File | Line | Breaks because |
| --- | --- | --- |
| `spec/services/mood_grounding_service_spec.rb` | `:19` | constructs real `MoodProbe::Features` — deleted in Phase A. Also `:193`. |
| `spec/support/phase3_parity.rb` | `:33` | `extractor.analyze(audio_path).to_h` — wrong arity and wrong return type. Also compares against a script deleted at `96e546f` (`:2`); the harness is already vestigial. |
| `spec/fixtures/mood_probe/generate_goldens.rb` | `:10` | constructs `Extractor`, calls `analyze` with no descriptors. |
| `spec/integration/essentia_extract_golden_spec.rb` | `:20`, `:38-39` | `MOOD_HEADS` constant + `features.to_h`. §6.5 Rule 3 addresses the constant but not the arity. |
| `spec/jobs/enrich_album_job_spec.rb` | `:99-114` | real `Extractor` + zero-arg `verify!` expecting `/missing model/`; interacts with M1. |

**What breaks.** `mood_grounding_service_spec.rb` is the app's only unit coverage of aggregation,
track-error skipping, and fatal propagation (`:26-244`). It will not load. Phase A's `test` CI job
(`ci.yml:103`) goes red and someone triages a spec failure in the middle of a lockstep deploy — the
one deploy where the diff needs to be boring.

**Fix.** Enumerate these five in Phase A's scope with the intended replacement for each. In
particular, decide `phase3_parity.rb`'s fate explicitly: it compares against a deleted script and
§6.5 Rule 2's algebraic gate supersedes it. Deleting it is defensible; leaving it broken is not.

### M7. Dependabot defeats the one lockstep constraint the design depends on

§6.1 makes Phase A "the one phase where they must land together." §5.4 recommends tag pinning and
claims it "removes failure modes 1 and 2 outright."

**Verified.** `.github/dependabot.yml:3-7` enables the whole `bundler` ecosystem on a weekly schedule
with **no `ignore` entry**. `Gemfile:34` is a git-sourced gem in that ecosystem. Dependabot's bundler
support updates git dependencies, including tag-pinned ones (it opens PRs advancing to newer tags).
The Principal flagged this as unchecked at Risk 7 ("I did not check `.github/dependabot.yml`") — it is
checked now, and the answer is that the mitigation §5.4 proposes does not cover it.

**What breaks.** A merged bot PR ships gem `v0.2.0` into an app without the mapper. Best case
(required keyword, §2.1) `analyze(path)` raises `ArgumentError` at
`mood_grounding_service.rb:93` — **not** a `MoodProbe::TrackError`, so `:94` does not rescue it —
propagating to `enrich_album_job.rb:45`, marking every album failed. Loud, but it is a routine
maintenance PR that takes production enrichment down.

**Fix.** Add an explicit `ignore` for `mood_probe` in `.github/dependabot.yml` as part of Phase A,
and keep the tag pin from §5.4 (which is right for the force-push and `bundle update` cases). State in
the phase DoD that the gem tag is advanced by hand, in the order §5.4 already specifies.

### M8. `:musicnn_embedding` is registered in Phase A with nothing that ever constructs a `Vector`

§6.1 registers `:musicnn_embedding` in Phase A. §6.1's acceptance criteria contain no spec that
requests it. Meanwhile §4.4 identifies the vector path as where the non-finite guard matters most
("the guard surface grows by ~200× the moment `:musicnn_embedding` is requested"), and Security
constraint 4 (`security.md:173`, detail at `:75`) requires exact-declared-dimension validation for
`Vector`. §2.2's `Vector` class and §1.2's `Descriptor#shape` exist; nothing in §4.3 or §2.2 says Ruby
asserts `values.length == descriptor.shape`.

This is the same criticism the Principal correctly levels at himself for `FromAlgorithm` — and it is
why "register `:bpm` but do not consume it" is a good instinct applied inconsistently.

**What breaks.** The first real request for the embedding — Phase E, or an operator experimenting —
is the first execution of `Vector` construction, the 200-element recursive finiteness walk, the
`allow_nan=False` path on a list, and a ~4 KB NDJSON record. All untested, in the code path §4.4 calls
highest-risk.

**Fix — pick one, do not leave it as-is:** either (a) register it *and* exercise it — a fake-double
fixture returning a 200-element vector, a spec asserting `kind == :vector`, `values.length == 200`,
and a NaN-in-vector fixture asserting `malformed_output` (the existing `nan-audio` /
`infinity-audio` fixtures at `spec/support/fake_essentia/essentia/standard.py:52-55`, exercised at
`spec/integration/python_seam_spec.rb:41-53`, are the template); or (b) do not register it in
Phase A. Also add the Ruby-side `values.length == descriptor.shape` assertion either way.

---

## SHOULD-FIX

**S1. `reduction` is declared but not enforced.** §8.1's challenge is correct and the design acts on
it (`Model#reduction`, `Provenance#reduction`) — but Python takes `predictions.mean(axis=0)`
unconditionally (`mood_probe_extract.py:59`, `:62`). A future row declaring
`:median_over_frames` would be silently ignored, making the declaration a document that can lie. Put
`reduce: "mean_over_frames"` in the plan's `emit` entry and have Python assert it is the one
supported value (exit 2 otherwise). ~3 lines, and it closes the gap the challenge opened.

**S2. Add `byte_length`, `license`, `attribution`, and `pack` to `Model` in Phase A.** Security asks
for all four (`security.md:116`, constraints 3/5/7). Adding a field to `Data.define` is free while the
struct is being authored in Phase A and is a registry-wide edit later. `byte_length` in particular
pairs with the bounded-download requirement (`security.md:118`).

**S3. Name the bounded-reader obligation instead of passing over it.** `CommandRunner` retains full
stdout/stderr strings (`essentia_python.rb:33-34`); `security.md:68` wants bounded readers.
For Phase A the largest payload is ~4 KB and the risk is negligible — Security should give way here.
But Phase A is where a 200-float `Vector` becomes reachable, so put bounded readers in **Phase E's**
DoD (persisted embeddings) as a scheduled obligation with a stated threshold, rather than leaving the
constraint silently unmet.

**S4. State Phase A's answer to open question 6 explicitly: no backfill is required.** §6.5 Rule 2
asserts four heads bit-identical and two algebraically identical to the pre-change goldens — that
*is* the evidence that no re-enrichment is needed, and the design never says so. Without it someone
will run `rake enrichment:reground_all` "to be safe," which loads **every** album and resets each one
unconditionally (`lib/tasks/enrichment.rake:23-24`), re-enriching the whole catalogue for zero
benefit.

**S5. The `llm_only` fallback for new descriptors was silently dropped.** brief:51 asks to "define
behavior when audio grounding is unavailable for the new descriptors (no BPM/key without audio)."
It is not one of the seven numbered questions, and `principal.md` never mentions it. Phase A does not
need it (`default_attrs` at `mood_grounding_service.rb:45-46` is untouched, since no new descriptor is
consumed), but it must be named as deferred-to-Phase-C rather than omitted.

**S6. Harden §2.4 registration per Security constraint 2.** §2.4's four rules are good (copy-on-base,
duplicate detection, freeze-on-inject, mandatory sha256) but do not make custom models opt-in
(`security.md:49` asks for an `allow_custom_models` capability, default off) and do not validate
`filename` as a bare basename at `add_model` time. Both are cheap and both are "fail at registration,
not at inference," which is §2.4's own stated principle.

**S7. The gem has no CI at all.** Verified: `/Users/lukeolson/projects/gems/mood_probe/.github` does
not exist. Every gem-side gate the design leans on — the golden spec
(`spec/integration/essentia_golden_spec.rb`), `python_seam_spec.rb`, the §3.4 planner assertions, the
§4.2 golden plan fixture, the M2 capability cross-check — runs only when someone remembers. The
Ruby/fake-double ones need no Docker and would run on a plain `ubuntu-latest` runner. Add a gem
workflow in Phase A; it is the cheapest durability win available.

**S8. Correction to §4.5 item 1 — "recovery via `rake enrichment:backfill` is a dead end" is false at
this HEAD.** `ENRICHMENT_TRANSITIONS["failed"] = %w[matching_audio grounded]`
(`app/models/album.rb:12`), `Album.needing_enrichment` includes `failed` (`app/models/album.rb:24`),
`enrichment:backfill` sends exactly that scope through the job (`lib/tasks/enrichment.rake:10-12`),
and `spec/models/album_spec.rb:30` is a round-trip spec ("recovers from failed through matching_audio
to grounded"). The plan doc the Principal cites says the same
(`docs/superpowers/plans/2026-08-07-essentia-ruby-gem-extraction.md:42-43`: "Bug 1 fixed in Phase 3").
The clamp risk is real and M3 stands; its blast radius is "loud, recoverable" rather than
"unrecoverable," and the spec should say so accurately.

**S9. Correction to Risk 4 — the amd64 image job does run on PRs.** `.github/workflows/ci.yml:105-123`
defines an `essentia` job that builds the image with `--platform linux/amd64` and runs the golden
specs with `ESSENTIA_SPECS=1`, asserting the exact example count. Commit `0d6ed39` ("Fix CI: green the
test, essentia and scan_ruby jobs") confirms it was made to pass. Risk 4's "whether that image job
will actually run" is resolved **yes** on the app side — which means §6.5 Rule 2's algebraic parity
gate is automated, and that is the strongest single fact in favour of this plan. It remains **no** on
the gem side (S7), and §3.4's empty-models-dir proof is specified as a gem-side spec.

**S10. §9 correction 1 overstates the Phase A construction-site churn.** It says all four `Extractor`
construction sites (`enrich_album_job.rb:5`, `mood_grounding_service.rb:9`, `enrichment.rake:18`,
`:31` — all verified) "must move to the new `registry:`-aware constructor in Phase A." But §2.1 gives
`registry:` a default of `Registry.default`, so none of them need to change. What actually changes is
two `analyze` sites (`mood_grounding_service.rb:93`, `:107`) and — per M1 — three `verify!` sites
(`enrich_album_job.rb:8`, `enrichment.rake:21`, `:44`; note `:21`, not `:20` as §5.3 states). Getting
this right matters because the size of the revert is the whole argument for Phase A being safe.

**S11. §1.4's note and Risk 1 disagree on when the sample-rate measurement happens.** The `:bpm`
registry row says the `RhythmExtractor2013` rate "MUST be settled by measurement in the amd64 image
before Phase C"; Risk 1 says "it should be done in Phase A, while `:bpm` is being added." Phase A is
right (that is when the row lands). Align the note, since the row is what an implementer reads.

---

## The dispatch's eight questions, answered

**1. Does Phase A generalize, or relabel? — It generalizes.** Behaviourally it is "the same six
numbers"; structurally it is not. Measured against the brief's own list of couplings to remove
(brief:19-26): the frozen `HEADS` + missing-or-extra `SchemaError` goes (`features.rb:3`, `:29-35`);
the hardcoded `MODELS` constant becomes data rows (`model_registry.rb:12-60`); the Python hardcoded
`_HEAD_MODELS` and baked-in rescale go (`mood_probe_extract.py:12-17`, `:63-64`); the flat
`{head => float}` that "structurally cannot represent most useful Essentia output" (brief:24) becomes
a polymorphic `Value` hierarchy; and the discarded embedding (brief:26) becomes a registered
descriptor. That is five of six couplings removed in the first slice. The sixth — no abstraction for
DSP I/O shapes (brief:25) — is exactly what the `:bpm` row addresses.

The falsifiability instrument is right and I want it kept verbatim: §6.2's "if Phase B requires
touching `mood_probe_extract.py` or any `lib/` file other than the registry, Phase A's design failed."
Note that M1 currently makes that criterion unmeetable for reasons unrelated to the registry.

**Is "register `:bpm` but do not consume it" sufficient, or a token gesture? — Sufficient, and well
argued, but applied inconsistently.** It genuinely exercises the `FromAlgorithm` branch, the
empty-`graphs` path, the two-sample-rate `loads` path, and (if `:beat_confidence` is registered too)
the `uniq_by` dedupe — and it buys the empty-models-dir proof, the only assertion in the design that
cannot be faked. That is not a gesture. The inconsistency is that the identical argument demands a
`Vector` exercise and the design does not provide one (M8), and that `Categorical` remains
defined-never-constructed until Phase C with no equivalent discriminating row — which is defensible
(Risk 8 admits the type may be wrong) but should be stated as a deliberate acceptance of untested
surface, not left implicit.

**2. Is Phase A genuinely shippable and revertible? — Yes on the data question, no as currently
scoped.**

*The data claim holds.* No migration, `mood_vectors` untouched (`db/schema.rb:93-108`), and §6.5
Rule 2 asserts the persisted numbers are identical to five significant figures. Albums enriched under
0.2.0 are indistinguishable from albums enriched under 0.1.0, so a revert leaves nothing to reconcile.
That is a real property and it is the strongest argument for this sequencing. One caveat: per M3(b),
an album whose emomusic output fell outside the old sanity window would today have had that track
*skipped* and under 0.2.0 has it *clamped and averaged in* — a narrow, real divergence that a revert
does not undo.

*The "two-line revert" is under-scoped.* Per S10 and M6, Phase A's app diff is two `analyze` sites,
three `verify!` sites, the new mapper, a boot initializer, `Gemfile` + `Gemfile.lock`, and five
spec/support files. That is still a clean two-commit revert — but call it two commits, not two lines,
because the difference is whether someone budgets an hour or a day for the rollback rehearsal.

*One repo deployed without the other.* Both directions fail loudly, which is the right outcome and is
a direct consequence of §2.1's required-keyword decision:
- Gem ahead: `analyze(path)` → `ArgumentError` (missing keyword `:descriptors`), which is **not** a
  `MoodProbe::TrackError`, so `mood_grounding_service.rb:94` does not swallow it; it reaches
  `enrich_album_job.rb:45`, the album is marked failed, and the batch aborts. Recoverable via
  backfill (S8). The realistic trigger is a bot PR (M7).
- App ahead: gem 0.1.0 has no `MoodProbe::Registry`, so the M3(2) boot initializer raises `NameError`
  at boot — a failed deploy rather than a per-album failure. That is strictly better, and it is the
  reason M3(2) insists on an initializer rather than "at boot **or** in a spec."

**3. The clamp risk — intended, not mechanized.** See M3. The dispatch's suspicion is correct, and
the situation is one notch worse than the dispatch framed it: §4.5 deletes the `SANITY_RANGE` guard
(`features.rb:6`, `:45-47`) as well as the clamp (`:19`), and only the clamp has a proposed
replacement.

**4. Coverage of the seven open questions.**

| Q | Status | Note |
| --- | --- | --- |
| 1 — API surface, types, embedding dependency | **Answered** (§1, §2) | Thorough. M5 is the one internal inconsistency. |
| 2 — versioning, deprecation, pinning | **Answered** (§5) | 0.2.0, no shim, tag pin. M7 is the gap. |
| 3 — Python generalization | **Answered** (§4) | M2 revises the mechanism, not the direction. |
| 4 — persistence **and aggregation** | **Deferred, half-rationalised** | Persistence deferral is *well* argued (§6.1: schema-free ⇒ nothing to reconcile). Aggregation (brief:50 — tempo median+stability, key distribution, embedding mean-pool, `match_confidence` weighting) is only *pointed at* in §6.3, with no rationale. Acceptable because Phase A consumes no non-scalar descriptor and `MoodGroundingService#aggregate` (`mood_grounding_service.rb:140-148`) therefore stays untouched — but say that, since it is what keeps the diff small. |
| 5 — model distribution | **Answered by Security** | Correctly scoped out at §"Scope covered here". S2 is the Principal-side hook. |
| 6 — backfill | **Deferred, and the premise corrected** | Best-handled item in the doc (§9 final paragraph). S4 adds the missing Phase A answer. |
| 7 — sequencing | **Answered** (§6) | Confirmed with three changes, one load-bearing. |

Nothing silently dropped except brief:51 (`llm_only` for new descriptors — S5) and brief:52's
parity-spec half (`phase3_parity.rb` — M6). Both are Phase-C concerns; both need naming.

**5. The two CHALLENGES.**

*(a) `predictions.mean(axis=0)` — right, and acted on.* Verified at `mood_probe_extract.py:59`
and `:62`. Decision 2's "no normalization in the gem" is literally false while an undeclared
time-axis reduction stands, and the reduction is invisible in the payload, the README, and the
registry. The proposal is proportionate: declare it (`Model#reduction`, §1.2), carry it
(`Provenance#reduction`, §2.2), do not expose the frame axis. The design is internally consistent
about it — `reduction:` appears in every worked `Model` row (§1.3, §1.5). **One gap: declared but not
enforced (S1).** Minor semantic note: `FromAlgorithm` descriptors have no `Model` row and therefore
no `reduction`, so `LoudnessEBUR128#integratedLoudness` (Phase D) will report `reduction: nil` while
the algorithm does reduce internally. §1.2's comment scopes the field to "the gem's declared time-axis
collapse," which makes that correct as written — but it is worth a sentence so nobody reads `nil` as
"no reduction occurred."

*(b) "load audio once" → "once per required sample rate" — right, and acted on.* Verified:
`MonoLoader` hardcodes `sampleRate=16000` (`mood_probe_extract.py:47-49`) and MusiCNN requires it.
The design acts consistently: `Plan#loads` is an array (§3.2), step 6 dedupes rates (§3.3), and §3.4's
contrast case shows `loads = [16_000, 44_100]`. This is a factual correction, not a disagreement, and
the correction is necessary — the literal wording would mislead whoever implements `plan_for`. The
residual (whether `RhythmExtractor2013` is acceptable at 16 kHz) is honestly flagged as UNVERIFIED and
has a named measurement; only the timing is inconsistent (S11).

**6. The class-order finding — applied almost everywhere it must be.**

Applied correctly to the **existing** heads: §1.3 works `mood_happy` (`classes: %w[happy non_happy]`,
`select: {class: "happy"}`) and `mood_relaxed` — the inverted one — in full, and §0's table covers
`danceability` and `mood_acoustic`. This is the right migration of
`model_registry.rb:23, :31, :39, :47`, where `positive_index: 1` at `:39` is correct-but-unexplained,
exactly as §0 says.

**The existing six are also mechanically protected**, and this deserves credit: §6.5 Rule 2 asserts
the four softmax heads bit-identical against the *unmodified* pre-Phase-A goldens, so a
`positive_index → classes` transcription error would surface as `p` vs `1-p` — many orders of
magnitude outside the `1e-4` relative tolerance
(`spec/integration/essentia_extract_golden_spec.rb:24-25`, `:53`, `:68`) — and it runs automatically
in `ci.yml:105-123`. That is a real gate, not a hoped-for one.

Two gaps: **emomusic escapes the rule entirely** via the second selector form (M5), and **the five new
heads have no equivalent gate at all** (M4).

**7. Compatibility with all seven Security hard constraints.**

| # | Constraint | Verdict |
| --- | --- | --- |
| 1 | ID-only boundary | **Conflict — adjudicated above.** Constraint's letter gives way; intent enforced via M2 (a)(b)(c) + the capability cross-check. Manifest duplication rejected. |
| 2 | Registration is full-trust operator extension | **Partially met.** §2.4's four rules are sound; missing default-off (`security.md:49`) and basename validation → **S6**. |
| 3 | Every default model an exact verified artifact | **Met in substance.** `ModelStore#verify_model!` (`model_store.rb:56-62`) preserved unchanged and §2.4 rule 4 forbids routing around it. Missing `byte_length` on the struct → **S2**; bounded download / HTTPS allowlist / symlink rejection (`security.md:117-120`) are Security's scope but must be owned somewhere in the combined plan. |
| 4 | Every output bounded and typed | **Mostly met.** `allow_nan=False` adopted (§4.4) — a genuinely good catch that converts a misleading `BackendError: invalid NDJSON` (`essentia_python.rb:162-163`) into a proper `malformed_output`; recursive finiteness adopted; exact-requested-ID-set adopted (§6.5 Rule 3, the load-bearing replacement for the deleted `SchemaError`); NDJSON cardinality preserved (`essentia_python.rb:151-152`). Missing: `Vector` exact-dimension assertion → **M8**; bounded readers → **S3**. |
| 5 | Model packs are explicit | **Met by a better mechanism, but say so.** §6.2's Phase B list correctly excludes `timbre`/`approachability`/`engagement` — Security is right that those need the 1280-d Discogs-EffNet embedding (`security.md:86-90`), and the brief (line 38) was wrong to list them as MusiCNN candidates. More importantly, §3.3 step 8 verifies only the graph files **the plan requires**, which is demand-driven and strictly better than static packs — provided M1 lands. Add `pack:` to `Model` (S2) for the ~21 MiB Discogs case, where opt-in still matters (`security.md:104`). |
| 6 | No new embedding exposure by default | **Met.** `:musicnn_embedding` is registered but unrequested by vibe-doctor and Phase A adds no persistence (§6.1). Note M8 is about *testing* it, not exposing it. |
| 7 | Non-commercial licensing visible | **Aligned, incomplete.** §5.4's "no RubyGems release" is the right call and cites licensing. Missing from the combined plan: the `NOTICE` correction Security asks for (`security.md:25` — the current `mood_probe/NOTICE` "depending on the model" claim is unsupported) and `license`/`attribution` on `Model` → **S2**. Add both to Phase A's DoD; Phase A is when the struct and the gem release both exist. |

**8. The Q6 premise error — correctly handled; the design does not lean on it.** I searched
`principal.md` for any dependence on versioned invalidation and found none: §6.1's rollback story is
schema-free, §6.3 mentions a migration but not invalidation. The Principal independently reached the
same conclusion as the inventory (§9 final paragraph vs `inventory.md:164-198`) and both match what I
verified: `Album.needing_enrichment` is status-only (`app/models/album.rb:24`),
`Album#reset_enrichment!` sets only `enrichment_status: "pending"` (`:45-50`), and
`enrichment:reground_all` loads `Album.all` and resets every one
(`lib/tasks/enrichment.rake:23-24`). The inventory adds the origin the Principal did not have — an
unmerged branch, commit `72bb8fc`, time-based rather than version-keyed (`inventory.md:190-197`). The
only remaining action is S4: state that Phase A needs no backfill, so nobody reaches for
`reground_all`.

---

## Observations

1. **§6.5 Rule 2 is the best idea in the document and its ordering must be a hard DoD step, not a
   suggestion.** "Never regenerate goldens and change behaviour in the same commit," with the
   algebraic check `(new_raw - 1.0) / 8.0 ≈ old_golden` run against the *unmodified* files, is
   unfakeable and free. If someone regenerates first the evidence is unrecoverable. The Principal says
   this; I am seconding it as strongly as I can.
2. **§6.5 Rule 6 is right to refuse to harmonise the two golden gates.** They test different things:
   the gem's plain `eq` (`spec/integration/essentia_golden_spec.rb:34`) asserts determinism in a fixed
   image; the app's relative-tolerance gate (`spec/integration/essentia_extract_golden_spec.rb:24-25`)
   asserts cross-environment reproducibility, and it carries a real calibration control in a comment
   (`:23`: 0.900e-04 passed, 1.100e-04 failed). Rule 5's demand that every new tolerance ship with
   *both* a passing and a failing control is the correct generalisation of that comment.
3. **§6.3's fixture warning is easy to lose and expensive to lose.** The four existing fixtures
   (`chirp`, `clicks`, `sine_440`, `white_noise`) are adversarial for tempo and key; goldens generated
   from them would pin garbage and the Phase C gate would be decorative. Put "add one deterministic
   synthetic musical fixture" in Phase C's DoD, not in prose.
4. **Risk 8's uncertainty about `Categorical` is well-placed and the resolution is right.** One
   nullable-`distribution` type now, revisit at Phase C when `KeyExtractor` lands. Speculative
   splitting for one known case would be the over-engineering the brief (line 58) rules out.
5. **The design's treatment of the error taxonomy is correct and should not be softened.** §4.4 keeps
   whole-file atomicity and explicitly records partial-per-descriptor results as a *deferred* decision
   with a named trigger. That is how a deferral should read.
6. **The Principal's own uncertainty labelling is unusually good** — the UNVERIFIED markers on
   `RhythmExtractor2013`'s sample rate, `beat_confidence`'s range, and the emomusic `1..9` scale
   (Risk 5) are exactly the places I would otherwise have flagged as unsourced. Risk 5 is worth
   acting on cheaply: emit raw emomusic for the four fixtures during Phase A and see where they fall.

---

## Ambiguities escalated to dispatcher

None blocking. The one genuine ambiguity — Security constraint 1 vs the Ruby-side planner — the
dispatch explicitly asked me to adjudicate rather than escalate, and I have (M2).

---

## Evidence

**Diff range reviewed:** none. This is a pre-implementation design review; no code exists.
Both repos verified clean at the SHAs in the header.

**Design documents read in full:** `/Users/lukeolson/Downloads/mood_probe_gem_brainstorm_prompt.md`;
`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/principal-draft.md` (all 1,278 original lines, in two reads; repository copy has a +4-line supersession header);
`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/security.md` (all 247 lines);
`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/inventory.md` (all 407 lines).

**mood_probe source read (at `5360f8f`):** `lib/mood_probe/features.rb`,
`lib/mood_probe/model_registry.rb`, `lib/mood_probe/errors.rb`, `lib/mood_probe/version.rb`,
`lib/mood_probe/extractor.rb`, `lib/mood_probe/model_store.rb`,
`lib/mood_probe/backends/essentia_python.rb`, `python/mood_probe_extract.py`,
`spec/integration/essentia_golden_spec.rb`, `spec/integration/python_seam_spec.rb`,
`spec/support/fake_essentia/essentia/standard.py`.

**vibe-doctor source read (at `0499d9c`):** `app/models/mood_vector.rb`, `app/models/album.rb`,
`app/jobs/enrich_album_job.rb`, `app/services/mood_grounding_service.rb`, `lib/tasks/enrichment.rake`,
`Gemfile` (28-40), `.github/workflows/ci.yml` (full), `.github/dependabot.yml`,
`Dockerfile` (essentia region), `spec/integration/essentia_extract_golden_spec.rb`,
`spec/support/phase3_parity.rb`, `spec/services/mood_grounding_service_spec.rb` (1-30 + grep),
`spec/jobs/enrich_album_job_spec.rb` (95-115), `CLAUDE.md`,
`docs/superpowers/plans/2026-08-07-essentia-ruby-gem-extraction.md` (Bug 1 / Bug 2 region).

**Commands run (all read-only):**

```text
git -C /Users/lukeolson/projects/vibe-doctor rev-parse HEAD          -> 0499d9cd38e7...
git -C /Users/lukeolson/projects/vibe-doctor status --porcelain      -> (empty)
git -C /Users/lukeolson/projects/gems/mood_probe rev-parse HEAD      -> 5360f8fd8609...
git -C /Users/lukeolson/projects/gems/mood_probe status --porcelain  -> (empty)
git -C /Users/lukeolson/projects/vibe-doctor ls-tree -r -l HEAD tmp/essentia_models
grep -rn "MoodProbe" app lib spec        (vibe-doctor)
grep -rn "verify!"  app lib spec         (vibe-doctor)
grep -rn "Bug 1\|Bug 2" docs/superpowers/plans/2026-08-07-essentia-ruby-gem-extraction.md
grep -rn "failed" spec/models/album_spec.rb
ls -la /Users/lukeolson/projects/gems/mood_probe/.github   -> No such file or directory
cat -n <each cited source file>
```

**Key command outputs load-bearing for findings above:**

- `git ls-tree -r -l HEAD tmp/essentia_models` → exactly **six** `.pb` files (danceability,
  emomusic, mood_acoustic, mood_happy, mood_relaxed, msd-musicnn-1). Basis for **M1**.
- `ls -la mood_probe/.github` → `No such file or directory`; `find . -path "*workflow*" -name "*.yml"`
  → no results. The gem has **no CI**. Basis for **S7**.
- `grep -n "essentia:" -A2 .github/workflows/ci.yml` → job at **`:105`**, amd64 image build at
  `:112`, golden run at `:115-123`. Basis for **S9**.
- `.github/dependabot.yml:3-7` → `package-ecosystem: bundler`, `directory: "/"`, weekly, **no
  `ignore`**. Basis for **M7**.
- `app/models/album.rb:12` → `"failed" => %w[matching_audio grounded]`;
  `spec/models/album_spec.rb:30` → "recovers from failed through matching_audio to grounded".
  Basis for **S8**.
- `grep -rn "verify!" app lib spec` → three production call sites: `app/jobs/enrich_album_job.rb:8`,
  `lib/tasks/enrichment.rake:21`, `lib/tasks/enrichment.rake:44`. Basis for **M1** and **S10**.
- `grep -rn "MoodProbe" app lib spec` → four `Extractor.new` sites (`enrich_album_job.rb:5`,
  `mood_grounding_service.rb:9`, `enrichment.rake:18`, `enrichment.rake:31`) and the five
  Features/arity-coupled spec files listed in **M6**.

**Not verified (and stated as such above):** upstream Essentia model metadata (I did not re-fetch the
`classes` arrays, digests, or sizes — I reviewed the Principal's and Security's transcriptions for
internal consistency and they agree with each other where they overlap); Dependabot's exact behaviour
on tag-pinned git gems (M7's mitigation — an `ignore` entry — is correct either way and costs
nothing); no database access, so no claim about production `mood_source` values.

**Files created by this review:** this file only. No file in either repository was created, modified,
or deleted.
