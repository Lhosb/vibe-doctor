# ESSENTIA-GEM-V2 Phase A — whole-branch SPEC review

**VERDICT: APPROVE-WITH-FINDINGS**

**Reviewer:** Spec (A1–A10 conformance and API coherence) · read-only on both repositories.
**Repo:** `/Users/lukeolson/projects/gems/mood_probe`, branch `feat/essentia-gem-v2-phase-a`
**Range:** `55d85fb246e45581172d58066c24e41c8970ac9b..848f6894a6022b5a32ae2b6b0c6898ac84986fa0`
(65 files, +4716/−653, 26 commits; `v0.2.0` peels to HEAD).

**Headline:** every structural item in J.4's gem-side scope is **MET**, and I discharged A1's "verbatim"
requirement against the **upstream JSON** for the first time on this ticket — all five class arrays and
all five model versions match, including the inverted `mood_relaxed` row. The architecture is genuinely
de-opinionated. **The front door is not.** `README.md:3-5` still advertises v0.1.0's product — "six
normalized mood features" — and that is the one thing here that would actively mislead a consumer.

Prior-round record read before writing: my own `spec*.md` across slices 1–5 (16 files). I re-litigate
nothing closed there, and I found no finding closed wrongly. Two gem-side carry-forwards from that
record are still open and are re-raised below at whole-branch severity.

---

## 1. Structural conformance — A1 through A10

| Item | Status | Proof |
| --- | --- | --- |
| **A1** | **MET** | 9 descriptor ids, exactly as specified; classes verbatim vs upstream (below); projection by name only |
| **A2** | **MET** | `Model.members` carries all eight named fields; `byte_length` recorded, enforced nowhere |
| **A3** | **MET** | declared values exact; construction raises via keyword **and** `Data#with` |
| **A4** | **MET** | `Scalar`/`Categorical`/`Vector`/`Series` defined; **0** `:series` registry rows; `Vector` asserts shape |
| **A5** | **MET** | `Plan.members` == the six required; `plan_for` populates all six |
| **A6** | **MET** | `descriptors:` required on all three entry points; env preflight split under its own memo |
| **A7** | **MET** | zero `getattr`; basename + canonical containment + non-symlink; per-key param allowlist; `schema_version` handshake; `--capabilities` before import |
| **A8** | **MET** | rescale, clamp, `Features`, `HEADS` **absent from the tree**; `allow_nan=False`; serialisation `ValueError` → `malformed_output` |
| **A9** | app-side | **OUT OF SCOPE** for this gem-only review |
| **A10** | app-side | **OUT OF SCOPE** for this gem-only review |

### A1 — upstream `classes`, verified against upstream rather than assumed

The design assigns the upstream-JSON cross-check to Phase B (§E.5 mechanism 1) and no copy is committed,
so every prior verification on this ticket used in-repo oracles. I fetched the upstream metadata
directly. **All five match, in order, character for character**, and every `model_version` matches:

| Registry row | Registry `classes` (`registry.rb`) | Upstream JSON | Version |
| --- | --- | --- | --- |
| `danceability_msd_musicnn_1` | `%w[danceable not_danceable]` (`:127`) | `["danceable","not_danceable"]` | 2 = 2 ✅ |
| `mood_acoustic_msd_musicnn_1` | `%w[acoustic non_acoustic]` (`:142`) | `["acoustic","non_acoustic"]` | 2 = 2 ✅ |
| **`mood_relaxed_msd_musicnn_1`** | **`%w[non_relaxed relaxed]`** (`:157`) | **`["non_relaxed","relaxed"]`** | 2 = 2 ✅ |
| `mood_happy_msd_musicnn_1` | `%w[happy non_happy]` (`:172`) | `["happy","non_happy"]` | 2 = 2 ✅ |
| `emomusic_msd_musicnn_2` | `%w[valence arousal]` (`:187`) | `["valence","arousal"]` | 2 = 2 ✅ |

`emomusic`'s upstream output node is `model/Identity`, matching `registry.rb:186`. The `mood_relaxed`
row is the load-bearing one — it is the positive-second head, the case a naive `positive_index` gets
backwards, and upstream confirms the registry has it right.

Two precisions on the design's "four of ten inverted" note: that tally (§I.1) spans all ten MusiCNN
heads including Phase B's, of which `tonal_atonal` is another positive-second case. **Of the four
softmax heads registered at v0.2.0, exactly one — `mood_relaxed` — is positive-second**, and it is
correct. I verified this against upstream, not against the registry.

Projection is by **name**, never index (`plan.rb:143-153`): the selector carries `{class: "<name>"}`,
the index is *derived*, and an unknown name raises `ConfigurationError` rather than silently projecting.
`grep -rn positive_index lib python spec exe` returns **nothing** — the legacy index table is gone from
the whole tree, including the rewritten Python.

### A3 — the invariant actually raises

Verified by execution, both `Data` construction routes:

```
keyword: raises ArgumentError      with: raises ArgumentError
valence_emomusic: 1.0..9.0/nominal/-3.0..13.0     danceability:  0.0..1.0/hard/0.0..1.0
arousal_emomusic: 1.0..9.0/nominal/-3.0..13.0     mood_acoustic: 0.0..1.0/hard/0.0..1.0
                                                  mood_relaxed:  0.0..1.0/hard/0.0..1.0
                                                  mood_happy:    0.0..1.0/hard/0.0..1.0
```

### A8 — genuinely deleted, not merely unused

```
$ grep -rn 'HEADS|Features|clamp|8\.0|OUTPUT_RANGE|SANITY_RANGE|REGRESSION' lib python exe
(no output)
```

Zero occurrences across the entire shipped surface. And the §D taxonomy holds **structurally**, not by
clause ordering: the serialisation `try` at `python/mood_probe_extract.py:575` is a **sibling** of the
inference `try`, not nested inside it, so `json.dumps(allow_nan=False)`'s `ValueError` cannot be
captured by the `except Exception → inference_error` handler at `:564-573`. `inference_error` appears
exactly once in the file, on the inference path.

---

## 2. The API as a stranger sees it

I read `lib/mood_probe.rb`, `extractor.rb`, `registry.rb`, `plan.rb`, `value.rb`, `result.rb` and
`errors.rb` as a consumer who is not vibe-doctor.

**The good news, and it is the substance of the user's intent:** the type system carries no vibe-doctor
concepts. `Model`, `Descriptor`, `FromModel`, `FromAlgorithm`, `Plan`, `Scalar`, `Categorical`, `Vector`,
`Series`, `Analysis`, `Provenance` are all domain-general. Nothing in `value.rb` or `plan.rb` knows what
a mood is. `Extractor.new(registry:)` accepts a custom registry — I built an empty one and injected it
successfully — so the default descriptor set is a *default*, not a constraint. The six mood columns
survive only as *data* in `Registry.default`, which is exactly where an opinion belongs.

**The bad news is at the front door.** `README.md:3-5`:

> `mood_probe` extracts **six normalized mood features** from audio using an operator-provided Essentia
> Python installation and six separately licensed TensorFlow model files.

At HEAD this is false in two ways that matter, and it is the first thing anybody reads — see MUST-FIX 1.

**Discoverability.** The contract is *technically* readable from the code — required keywords fail loudly
with `missing keyword: :descriptors`, `Result` enforces exactly-one-of-analysis-or-error, `Data.define`
makes every member introspectable — but there is essentially no prose:

```
lib/mood_probe.rb          comments=0  lines=12
lib/mood_probe/value.rb    comments=0  lines=274      <- the entire object graph a consumer receives
lib/mood_probe/errors.rb   comments=0  lines=15       <- the error contract
lib/mood_probe/result.rb   comments=0  lines=21
lib/mood_probe/extractor.rb comments=3 lines=94
```

With the README's opening inaccurate, a stranger's only reliable contract is ~900 lines of `lib`. For a
wrapper whose value proposition *is* a discoverable contract, that is the gap (SHOULD-FIX 2).

**README claims I checked against behaviour.** `README.md:25-27` says `models verify` "verifies the
registered model files and their digests. It no longer preflights Python or Essentia" — **true** at HEAD:
`exe/mood-probe:46-51` calls `ModelStore#verify!(filenames:)` only, with no backend call. The security
notes and the native-x86_64 golden paragraph are also accurate.

### The misnomer — my honest read, since you asked either way

**Yes, `mood_probe` is a misnomer at v0.2.0, and it will get worse every phase.** `MoodProbe::Extractor`
returns `bpm`, `beat_confidence` and a 200-float `musicnn_embedding` alongside the mood heads; `[:bpm]`
touches no model file at all; Phase C adds DSP descriptors and Phase E adds `lufs`/`lu`. "Mood" names
one application of the thing the gem has become. `MoodProbe::Registry`, `MoodProbe::Plan` and
`MoodProbe::Scalar` all read oddly for a consumer who wants tempo.

**And it is not worth blocking this tag for.** Two facts decide it: there is no RubyGems release (§5.4),
and the sole consumer pins by git tag. So the rename cost today is a `git mv`, a constant, and one line
in a `Gemfile` — and after a public release it is a new gem name plus a migration for every consumer.
**The cheap window is exactly now and it closes at first publication, not at this tag.**

My recommendation: record the decision rather than leaving it implicit — either "rename before first
public release, tracked as an issue" or "keep the name; document in the README that it is historical and
that the gem extracts arbitrary Essentia descriptors". Either is defensible; an unmade decision is the
one option that quietly becomes permanent. Filed as SHOULD-FIX 4, not MUST-FIX, because nothing breaks
and nobody is misled by a name once the README is corrected.

---

## 3. Error contract

Two disjoint subtrees under `MoodProbe::Error`, and the split is the right one — `TrackError` means *skip
this track and continue*, `FatalError` means *stop*:

| Class | Parent | Raised when | Answers |
| --- | --- | --- | --- |
| `UnreadableAudioError` | `TrackError` | backend reports `unreadable_audio` (`essentia_python.rb:236`) | **my input was bad** |
| `MalformedOutputError` | `TrackError` | non-finite value, outside `sanity_range`, `Vector` length ≠ `shape` (`value.rb:53,60,114,150`); backend `malformed_output` (`:240`) | **the model produced garbage** |
| `InferenceError` | `TrackError` | Essentia raised during inference (`:238`) | the model failed to run |
| `TimeoutError` | `TrackError` | per-batch timeout (`:133`) | environment too slow / hung |
| `BackendProcessError` | `TrackError` | subprocess died on a signal (`:196`) | environment broken, one batch |
| `ConfigurationError` | `FatalError` | missing/symlinked/non-regular model file, path escape, temp-file swap (`model_store.rb:35,40,42,74,79,98`); unlaunchable Python; unknown class in a selector | **your environment or manifest is broken** |
| `BackendError` | `FatalError` | download HTTP/redirect/HTTPS failures, secure-tempfile failure, preflight timeout (`model_store.rb:57,158,167,171,174`; `essentia_python.rb:96`) | environment / network broken |
| `SchemaError` | `FatalError` | payload shape wrong — unrequested id, missing id, wrong type (`value.rb:46,50,84,98,111,144`) | the backend violated the contract; **stop** |

The three-way distinction the dispatcher asked about is available and clean: input → `UnreadableAudioError`;
environment → the `FatalError` subtree; garbage output → `MalformedOutputError`. The
`MalformedOutputError`/`SchemaError` split (one value wrong = skip a track; wrong *shape* = abort) is
deliberate and matches §E.6.

**One hole, and it is the most likely caller mistake** — see SHOULD-FIX 1: an unknown descriptor id
escapes the hierarchy entirely.

---

## Findings

### MUST-FIX 1 — `README.md:3-5` advertises the product v0.1.0 was, and would mis-scale a consumer's data

**Why it is wrong.** "extracts six normalized mood features" is false on both adjectives at HEAD.
*Normalized*: A8 deleted the rescale and clamp from the gem (verified: zero occurrences in `lib`,
`python`, `exe`), so `valence_emomusic` and `arousal_emomusic` are emitted **native in `1.0..9.0`**
(`registry.rb:253`). *Six mood features*: `Registry.default.ids` returns **nine** —
`[:valence_emomusic, :arousal_emomusic, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy,
:musicnn_embedding, :bpm, :beat_confidence]` — including a 200-float vector and two rhythm descriptors
that are not moods. The sentence also implies all six `.pb` files are prerequisites, when `[:bpm]`
requires **zero** (`plan_for([:bpm]).required_files == []`, and G4 proves it against an empty models
directory).

**Failure scenario, concretely.** A new consumer reads line 3, calls
`analyze(path, descriptors: [:valence_emomusic])`, receives `5.8459882736206055`, and — told the output
is normalized — either stores it as a 0..1 value or divides by nothing and renders a 585% valence. That
is precisely the mis-scaling the entire phase was built to make impossible on the gem side; the README
reintroduces it in prose. Second scenario: a consumer who only wants tempo reads "six separately
licensed TensorFlow model files", concludes they must fetch 3.4 MB of non-commercial weights and accept
CC BY-NC-ND terms to get a BPM, and abandons the gem — never finding the model-free path that is the
headline capability of the redesign.

**Fix.** Rewrite the opening to describe what v0.2.0 is: a registry of Essentia descriptors (mood heads,
rhythm, embeddings), values emitted in each descriptor's **native** range with the range declared on the
row, and a demand-driven planner that fetches and verifies only the model files the requested
descriptors need. Add one line noting `[:bpm]` needs no model files. The usage example at `:10-14`
should show a descriptor set that is *not* vibe-doctor's six.

This is also the sharpest answer to the user's stated intent: the code stopped being opinionated and the
README did not.

### SHOULD-FIX 1 — an unknown descriptor id escapes `MoodProbe::Error`

`Registry#fetch` uses `@descriptors_by_id.fetch(id.to_sym)`, so a typo raises a bare `KeyError`.
Reproduced:

```
:mood_hapy → KeyError   is_a?(MoodProbe::Error)? false
:tempo     → KeyError   is_a?(MoodProbe::Error)? false
rescue MoodProbe::Error → ESCAPED the gem hierarchy as KeyError
```

**Failure scenario.** A consumer does what the hierarchy invites — wraps calls in
`rescue MoodProbe::Error => e` — because every other failure mode is under it. One misspelled descriptor
in a config file then crashes their enrichment job with an uncaught `KeyError` instead of being handled.
For a wrapper whose job is normalising failures, the single most likely caller mistake is the one it
does not normalise. One line: raise `ConfigurationError` (or a new `UnknownDescriptorError < FatalError`)
naming the id and listing valid ids. (`"bpm"` as a String *is* accepted — `to_sym` coercion — so only
unknown ids are affected.)

### SHOULD-FIX 2 — the public type system carries no documentation

`value.rb` is 274 lines with **0** comment lines and defines every object a consumer receives;
`errors.rb` is the error contract with 0; `mood_probe.rb` has 0. Combined with MUST-FIX 1, a stranger has
no accurate prose description of the contract anywhere. **Failure scenario:** a consumer cannot tell from
`Analysis` whether `[]` raises or returns nil on a missing id, whether `Scalar#value` is always `Float`,
or that `Provenance#essentia_version` is currently always `nil` — all answerable only by reading the
source. A short YARD block on `Extractor#analyze`, `Analysis`, `Scalar`/`Vector` and each error class
would close it; this is the cheapest large win in the API.

### SHOULD-FIX 3 — `Model.new` cannot register a model the consumer hosts

`registry.rb:44-52` rejects any `source_url` whose host is not `essentia.upf.edu`. Verified:

```
Model.new(..., source_url: "https://models.example.org/my.pb") → ArgumentError:
  "source_url must use the essentia.upf.edu host"
```

**Failure scenario.** A consumer with their own fine-tuned MusiCNN head, or an internal mirror of the MTG
weights (a normal response to a non-commercial CDN dependency), cannot construct a `Model` row at all —
so they cannot use `Registry.new` even though it is public. For a gem whose stated purpose is a *less
opinionated* Essentia wrapper, this is the one hard limit on that goal, and it is a constructor
invariant rather than a policy a caller can opt out of. The code acknowledges it (`:46`, "must become
capability-aware when C.2's `allow_custom_models` lands"), and §C.2 rule 5 defers the capability — so
this is correctly *scheduled*, not overlooked. I raise it here because at slice level it read as a NIT
and at whole-branch level it is the boundary of the redesign's central claim.

### SHOULD-FIX 4 — the name, and the decision about it

Substance in §2 above. `mood_probe` / `MoodProbe::Extractor` no longer describes what the gem does. Not
a blocker; the decision is cheap now and expensive after first publication. **Record it.**

### SHOULD-FIX 5 — the gem's own `golden/` still has no provenance record (carry-forward)

`ls -a spec/fixtures/mood_probe/golden/` → four `.json` files and nothing else. The
`principal-golden-provenance.md` Q4 ruling asked for one retroactively, recording honestly that
`c74a15b`'s generation method is unrecorded; the standing rule adopted in slice 5b is that **every**
committed float-fixture directory carries a provenance record. The app now satisfies that in both
directories; the released gem satisfies it in `baseline_v0_1_0/` and not in `golden/`. **Failure
scenario:** the exact one that cost slice 5b a halted round — a reviewer or maintainer looks at these
four files, cannot establish whether they were extracted or derived, and either repeats the
investigation or accepts them on faith. Raised as NIT 5 in my slice-5b review as out-of-scope for an
app-only slice; at whole-branch level it is a gap in the released artifact.

### NIT 1 — `Registry.default` is one application's shopping list

Nine descriptors chosen for vibe-doctor, presented as *the* default. Mitigated because
`Extractor.new(registry:)` accepts a replacement (verified) and demand-driven verification means
unrequested models are never fetched — an unused row costs nothing. Worth one README line telling a
consumer they can supply their own registry.

### NIT 2 — `reduction: :mean_over_frames` is the only supported reduction

Hardcoded on all six models (`registry.rb:200`) and asserted as the sole permitted value Python-side
(`mood_probe_extract.py:196`). Deliberate per §A.4 S1, and the plan's `emit` carries `reduce` so the wire
format is already extensible — but a consumer wanting max-over-frames must change the gem.

### NIT 3 — descriptor-id naming is inconsistent

`valence_emomusic`/`arousal_emomusic` encode their model; `danceability`/`mood_acoustic`/`mood_relaxed`/
`mood_happy` do not, though each is equally model-specific. A consumer cannot predict an id from a head
name. Cosmetic, but ids are public API and cheap to align only before publication.

---

## Prior-round record

No finding in my slice 1–5 spec reports was closed wrongly. Two closures I re-verified at HEAD because
they bear on this review: `A10`'s item count now reads "All 17 app files" (design `:1120`), closing my
slice-5b-round2 SHOULD-FIX 1; and `MoodProbe::ModelRegistry` is absent from the tree, closing the slice-2
deletion-completeness question — with the addition that its *assertions* (host prefix, digest format)
are now constructor invariants rather than spec expectations, which was the slice-2-round-2 repair.

Still open and gem-side: SHOULD-FIX 3 (deferred by design to C.2) and SHOULD-FIX 5 (carry-forward).

---

## Evidence

**Diff range:** `55d85fb246e45581172d58066c24e41c8970ac9b..848f6894a6022b5a32ae2b6b0c6898ac84986fa0`
on `feat/essentia-gem-v2-phase-a`. All commands `git -C /Users/lukeolson/projects/gems/mood_probe`.

Baseline challenged, not assumed — it holds:
```
$ git status --porcelain                 → (empty)
$ git rev-parse HEAD                     → 848f6894a6022b5a32ae2b6b0c6898ac84986fa0
$ git rev-parse 'v0.2.0^{}'              → 848f6894a6022b5a32ae2b6b0c6898ac84986fa0
$ git diff --stat 55d85fb..848f6894 | tail -1 → 65 files changed, 4716 insertions(+), 653 deletions(-)
$ bundle exec rspec                      → 173 examples, 0 failures
$ bundle exec rubocop                    → 46 files inspected, no offenses detected
$ ls lib/mood_probe/features.rb lib/mood_probe/model_registry.rb → No such file or directory (both)
```

A1 upstream verification (WebFetch, four `classification-heads/*.json` plus `emomusic`):
```
danceability   → classes ["danceable","not_danceable"]  version "2"
mood_acoustic  → classes ["acoustic","non_acoustic"]    version "2"
mood_relaxed   → classes ["non_relaxed","relaxed"]      version "2"
mood_happy     → classes ["happy","non_happy"]          version "2"
emomusic       → classes ["valence","arousal"]          version "2"  output "model/Identity"
```
against `registry.rb:127, :142, :157, :172, :187` and `:186` — all identical, in order.

Structural verification by execution (`bundle exec ruby -Ilib -rmood_probe -e …`):
```
A1 ids: [:valence_emomusic, :arousal_emomusic, :danceability, :mood_acoustic, :mood_relaxed,
         :mood_happy, :musicnn_embedding, :bpm, :beat_confidence]
A2 Model.members: [:id, :filename, :sha256, :source_url, :byte_length, :license, :attribution,
         :pack, :model_version, :framework, :sample_rate, :algorithm, :input_node, :output_node,
         :classes, :reduction, :embedding]
A3 keyword: raises ArgumentError   with: raises ArgumentError
A3 emomusic 1.0..9.0/nominal/-3.0..13.0 ; four softmax 0.0..1.0/hard/0.0..1.0
A4 series rows: 0 ; Series defined: constant ; kinds: {scalar: 8, vector: 1}
A5 Plan.members: [:schema_version, :loads, :graphs, :algorithms, :emit, :required_files]
   plan_for([:bpm,:mood_happy]) loads → [16000, 44100] ; schema_version 1 ;
   required_files ["msd-musicnn-1.pb","mood_happy-msd-musicnn-1.pb"]
A6 verify!/analyze/analyze_all without descriptors: → ArgumentError "missing keyword: :descriptors"
```

Greps:
```
$ grep -rn 'HEADS|Features|clamp|8\.0|OUTPUT_RANGE|SANITY_RANGE|REGRESSION' lib python exe → (none)
$ grep -rn positive_index lib python spec exe                                              → (none)
$ grep -c getattr python/mood_probe_extract.py                                             → 0
$ grep -n 'allow_nan|inference_error|malformed_output' python/mood_probe_extract.py
  491: allow_nan=False   556: malformed_output   568: inference_error   582: malformed_output
$ grep -rn byte_length lib/ | grep -v registry.rb                                          → (none)
$ ls -a spec/fixtures/mood_probe/golden/  → chirp.json clicks.json sine_440.json white_noise.json
```

Error-contract and API probes:
```
plan_for(descriptors: [:mood_hapy]) → KeyError, is_a?(MoodProbe::Error) = false, escapes rescue
Model.new(source_url: "https://models.example.org/my.pb") → ArgumentError (essentia.upf.edu host)
Registry.new(models: [], descriptors: []) constructs; Extractor.new(registry:) accepts it
exe/mood-probe:46-51 → models verify calls ModelStore#verify!(filenames:) only (README:25-27 accurate)
```

**Verified vs believed.** Everything above marked with a command and its output I **verified**. Two
statements are **belief**, flagged as such: that renaming the gem is cheap now and expensive later rests
on §5.4's "no RubyGems release" plus the single known consumer, not on a check of every possible
consumer; and my reading of how a new consumer would misinterpret `README.md:3` is a judgement about
human behaviour, not a measurement — though the two false claims it rests on are both verified.

**Read-only confirmed.** No file in either repository was modified, staged or committed except this
report. All probes were `git`/`grep`/`ls` reads, `bundle exec ruby -e` against the committed tree, and
four read-only WebFetch calls to `essentia.upf.edu`.

VERDICT: APPROVE-WITH-FINDINGS
