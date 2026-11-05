# SONANCE 0.3.0 — pre-tag review (SPEC)

**VERDICT: REQUEST-CHANGES — I would BLOCK THE TAG.**

One MUST-FIX, four tokens wide, in the one command the README gives for verifying the gem against real
Essentia. Everything else about the convention landed completely and correctly, and I verified the parts
you asked me to verify by execution rather than by reading.

**Range:** `bb86f29d66ad7b4ae1e0a147b9786f02f010a9d5..77003c5f1796c42fda7807123a56a13c56e71ffe`.
**Baseline challenged — it holds**, with one correction of record: tree clean, `rspec` **192 / 0**,
`rubocop` **48 files, 0 offenses**, tags `v0.1.0` / `v0.2.0` present and unmoved, no `v0.3.0`.

---

## MUST-FIX 1 — the real-Essentia golden spec still requests four retired descriptor ids

**File and line.** `spec/integration/essentia_golden_spec.rb:20-28`:

```ruby
let(:descriptors) do
  %i[
    valence_emomusic
    arousal_emomusic
    danceability        # retired — now danceability_musicnn
    mood_acoustic       # retired — now mood_acoustic_musicnn
    mood_relaxed        # retired — now mood_relaxed_musicnn
    mood_happy          # retired — now mood_happy_musicnn
  ]
end
```

**Why it is wrong.** None of those four ids exists in `Registry.default` at HEAD. The 0.2.1 unknown-id
fix now makes that a hard failure rather than a `KeyError` — verified by execution:

```
danceability  → rejected: unknown descriptor: danceability; valid descriptors: valence…
mood_acoustic → rejected  ·  mood_relaxed → rejected  ·  mood_happy → rejected
plan_for(the spec's exact six) → Sonance::ConfigurationError: unknown descriptor: danceability
```

**Why CI is green anyway — your baseline is not contradicted.** The spec branches on
`SONANCE_ACTUAL_ROOT` (`:38-41`). The `essentia_golden` job sets it and runs in **pure-comparison
mode**, reading captured JSON (`:81-86`, `:143-145`), so the `descriptors` let is never evaluated there.
The live extraction happens in `script/capture_essentia_outputs.rb`, whose identical six-id list **was**
qualified — that is exactly what commit `77003c5` fixed. The spec holds the *second copy of the same
list*, on the branch CI does not take.

**Concrete failure scenario.** `README.md:103-107` documents this command and sets `SONANCE_MODELS_DIR`
but **not** `SONANCE_ACTUAL_ROOT`:

```sh
docker run … -c 'bundle exec ruby -Ilib exe/sonance --models-dir "$SONANCE_MODELS_DIR" models fetch \
  && bundle exec rspec spec/integration/essentia_golden_spec.rb --format documentation'
```

That takes the `else` branch at `:87-91` and `:146-150`, calling
`extractor.analyze_all(…, descriptors:)` and `extractor.analyze(…, descriptors:)`. A maintainer or
consumer following the README after `models fetch` succeeds gets
`Sonance::ConfigurationError: unknown descriptor: danceability` before any audio is read. The message
names a *descriptor* as unknown, so the first diagnosis will be "the registry is broken in 0.3.0" rather
than "the spec is stale" — the error points at the wrong file.

**Severity: MUST-FIX, and it should block the tag.** Not because the gem is broken — it is not — but
because a tag is immutable and this freezes a broken documented verification path into a *breaking*
release, where a consumer's first act is likely to be exactly that command. The fix is four tokens, and
it is the same defect class `77003c5` already repaired once: the id migration updated the script and
missed the spec that shares its purpose, because only the script is on CI's path. `git grep` for the
retired ids in `%i[…]` position would have caught both.

---

## The four items you asked me to verify

### 1. The shipped id table matches the ruling exactly — VERIFIED

`Registry.default.ids` at HEAD, in order, against the ruling's table (`principal-rename.md:18-26`):

```
valence_emomusic · arousal_emomusic · danceability_musicnn · mood_acoustic_musicnn
mood_relaxed_musicnn · mood_happy_musicnn · embedding_musicnn · bpm_rhythm2013
beat_confidence_rhythm2013
```

All nine, exact, including the two deliberately unchanged. **The slug names the architecture family, not
the versioned model**, as ruled: `musicnn` (not `msd_musicnn_1`), `rhythm2013` (the algorithm family,
not a model version), `emomusic` (the head family). `model_version` remains the version carrier —
`Model#model_version` is `"1"` for the backbone and `"2"` for the heads, untouched by the id scheme.
Plan fixtures agree: `emit[].id` is `bpm_rhythm2013`, `valence_emomusic`, `mood_happy_musicnn` across
all four. Golden fixture keys are the six qualified ids.

### 2. Completeness sweep — one stale site (MUST-FIX 1); everything else clean

Swept docs, README, CHANGELOG, NOTICE, gemspec, CI workflow, Dockerfile, fixtures, plan fixtures,
scripts, `exe/`, YARD and error text.

**Packaging and naming, all correct:** `spec.name = "sonance"`, `homepage`/`source_code_uri`
`github.com/Lhosb/sonance`, `spec.executables = ["sonance"]`, `exe/sonance`, `NOTICE:1,7`
(`sonance` / `Sonance::Registry`), `Dockerfile.essentia:13` `WORKDIR /sonance`,
`script/capture_essentia_outputs.rb:12-19` fully qualified.

**Bare old-id tokens that remain, each checked and each legitimate:**

| Site | Token | Why it is correct |
| --- | --- | --- |
| `CHANGELOG.md:15-21` | old ids | the migration table — required |
| `python/sonance_extract.py:448`, `plans/*.json` `take.output`, `registry.rb:236` | `"bpm"` | RhythmExtractor2013's **output name**, not a descriptor id |
| `spec/support/fake_essentia/…/standard.py:63-69` | `danceability` etc. | matched against `graph_filename`, i.e. the `.pb` filename |
| `baseline_v0_1_0/*.json`, `baseline_v0_1_0_parity_spec.rb:39,50` | app column names | the frozen baseline is keyed by app columns — accepted by your dispatch |
| `python_plan_executor_spec.rb:70` | `%w[mood_happy mood_relaxed]` | trace-event label fragments (`TensorflowPredict2D.init:#{head}`); the descriptor list one line above at `:61` is correctly `%i[mood_happy_musicnn mood_relaxed_musicnn]` |

**Correction of record.** Your baseline says "zero `mood_probe` paths remain". Four references remain,
and all four are correct: `baseline_v0_1_0/README.md:1`, `baseline_v0_1_0/PROVENANCE.md:1,3` (frozen,
SHA-pinned, and *historically* accurate — the gem **was** `mood_probe` at v0.1.0), and
`golden/PROVENANCE.md:8`, which records the path move. Rewriting those would falsify a provenance
record. Zero *live* paths remain; the historical ones should stay.

### 3. Duplicate-id rejection — VERIFIED BY EXECUTION, both kinds, with passing controls

```
duplicate DESCRIPTOR ids → rejected: duplicate descriptor id: bpm_rhythm2013
duplicate MODEL ids      → rejected: duplicate model id: msd_musicnn_1
two distinct of each     → OK, ids=2, models=2          (passing control)
Registry.default         → still builds, 9 ids          (passing control)
```

Both kinds covered, both fail loudly with the offending id named, and the controls prove the check does
not over-trigger. This closes the silent last-wins behaviour you verified beforehand.

### 4. CHANGELOG — honest and sufficient for an upgrader

`CHANGELOG.md:3-26` carries the **full nine-row id table** including the two unchanged rows (so a reader
can confirm nothing was missed rather than infer it), states **"No aliases are provided for the previous
ids"** (`:23`), states **"There is no compatibility namespace shim"** (`:8`), and names the old tags as
the compatibility mechanism (`:24-26`). That is the clean-break decision recorded where an upgrader will
find it. Nothing to add.

### 5. README as the stranger — updated consistently; the example is still the right one

Nothing in the prose describes the old naming: the opening cites `[:bpm_rhythm2013]` as the model-free
descriptor, the Ruby example uses `%i[bpm_rhythm2013 embedding_musicnn]`, and the CLI example passes
`--descriptors bpm_rhythm2013,embedding_musicnn`. The example remains the best demonstration for the
same reason it was at 0.2.1 — it is the one pair showing a model-free descriptor and a vector-valued one
— and it happens to use the two *shortest* qualified ids, so the 26-character cost the ruling weighed
never lands on the page. That is fine; the README's job is the shortest correct path, not the worst case.

The one thing the README gets wrong is the golden command, and that is MUST-FIX 1.

---

## Would I block the tag?

**Yes.** One finding, one file, four tokens — but the artifact is immutable, the release is breaking, and
the broken path is the one the README tells a consumer to run first. Fix `essentia_golden_spec.rb:22-27`,
re-run the suite, and I have nothing else: the id convention is complete and correct everywhere else I
looked, the duplicate-id guard works in both directions with controls, the CHANGELOG is honest, and the
frozen baseline and provenance records are intact and correctly historical.

---

## Evidence

All commands `git -C /Users/lukeolson/projects/gems/mood_probe` or run from that directory.

```
$ git status --porcelain                      → (empty)
$ git rev-parse HEAD                          → 77003c5f1796c42fda7807123a56a13c56e71ffe
$ git log --oneline bb86f29..77003c5          → 77003c5, 80a7dd0, 5b919b2, 5a539c1
$ git tag                                     → v0.1.0, v0.2.0   (no v0.3.0)
$ bundle exec rspec                           → 192 examples, 0 failures
$ bundle exec rubocop                         → 48 files inspected, no offenses detected
```

Id table and fixtures:
```
$ ruby -Ilib -rsonance -e 'puts Sonance::Registry.default.ids.inspect'
[:valence_emomusic, :arousal_emomusic, :danceability_musicnn, :mood_acoustic_musicnn,
 :mood_relaxed_musicnn, :mood_happy_musicnn, :embedding_musicnn, :bpm_rhythm2013,
 :beat_confidence_rhythm2013]
$ plans/*.json emit[].id → ["bpm_rhythm2013"] · ["valence_emomusic"] ·
                            ["bpm_rhythm2013","mood_happy_musicnn"] · ["mood_happy_musicnn"]
$ golden/chirp.json keys → the six qualified ids
```

MUST-FIX 1:
```
$ sed -n '20,28p' spec/integration/essentia_golden_spec.rb   → the four retired ids
$ grep -n descriptors spec/integration/essentia_golden_spec.rb → :20 (let), :90, :148 (uses)
$ sed -n '80,96p;140,152p' …                                  → both uses are in the `else`
                                                                 (live-extraction) branch
$ ruby -Ilib -rsonance -e '…fetch/plan_for…'
  danceability/mood_acoustic/mood_relaxed/mood_happy → rejected, unknown descriptor
  plan_for(spec's six) → Sonance::ConfigurationError: unknown descriptor: danceability
$ grep -n -B4 essentia_golden_spec README.md                  → :103-107, no SONANCE_ACTUAL_ROOT
$ sed -n '10,19p' script/capture_essentia_outputs.rb          → same six ids, all qualified
```

Duplicate-id rejection and completeness sweeps are quoted inline in §3 and §2.

**Verified vs believed.** Everything above with a command and its output I **verified**, including the
id table, the rejection of the four retired ids, the duplicate-id behaviour in both directions, and the
branch structure of the golden spec. Two statements are **belief**: that a maintainer following
`README.md:103-107` will misdiagnose the `ConfigurationError` as a registry bug is a judgement about
behaviour, not a measurement (the error text and the code path it comes from are verified); and that CI
run 31744533925 was green I take from your baseline — I verified *why* it can be green despite the stale
ids, which is the part that mattered.

**Read-only confirmed.** No file in either repository was modified, staged or committed except this
report. All probes were reads and `bundle exec ruby -e` against the committed tree.

VERDICT: REQUEST-CHANGES
