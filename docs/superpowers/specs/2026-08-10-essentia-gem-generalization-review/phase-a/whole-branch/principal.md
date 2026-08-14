# VERDICT: APPROVE-WITH-FINDINGS

Phase A whole-branch architectural review — `mood_probe` `55d85fb..848f689` (v0.2.0).
Principal Engineer. I wrote the design; this judges the built thing against it and against the user's
sentence.

---

## The headline: is v2 actually less opinionated, or did the opinions move?

**It is genuinely less opinionated. The opinions did not merely move — most of them were deleted.**
But the generalization stopped at the public boundary, and every finding below sits there rather than
in the structure.

**What was actually removed, verified in the diff:**

- `lib/mood_probe/features.rb` and `lib/mood_probe/model_registry.rb` are **deleted**
  (`git diff --name-status`, `D` on both). `Features`/`HEADS` *was* the six-column mirror; it is gone,
  not relocated. I checked for a successor and there is none — `Analysis` (`value.rb:159-190`) is a
  keyed container over registry ids with no fixed key set.
- **The rescale and clamp left the gem entirely.** This was v1's single most vibe-doctor-specific
  opinion — a normalization chosen because `mood_vectors` wanted `0..1`. `valence_emomusic` now
  declares `native_range: (1.0..9.0)` (`registry.rb:254`) and emits it. The gem stopped deciding what
  the number means.
- **The registry is not a mirror.** Nine descriptors ship (`registry.rb:206-241`); **three of them —
  `:musicnn_embedding`, `:bpm`, `:beat_confidence` — vibe-doctor does not consume.** A mirror would
  have six.
- **Verification became demand-driven.** `verify!` plans first and verifies only
  `plan.required_files` (`extractor.rb:34-35`). `[:bpm]` needs **no** model files at all. v1 required
  all six `.pb` files to do anything.
- **The wire surface is deliberately wider than the default registry.** `_ALGORITHM_PARAMS`
  (`python/mood_probe_extract.py:23-31`) admits `minTempo`/`maxTempo` that `Registry.default` never
  emits, with domains at `:36-45`. I initially read this as a loose end and then checked what it
  enables: a third party can build
  `Descriptor.new(produced_by: FromAlgorithm.new(name: "RhythmExtractor2013", params: {method: "degara",
  minTempo: 60, maxTempo: 200}, …))`, put it in `Registry.new(models: [], descriptors: [it])`, and it
  passes validation end to end — **no `Model` rows, so no host check, no `.pb`, no download.** The
  algorithm axis is fully open to non-vibe-doctor consumers today. That is the redesign working, and I
  am recording it as evidence rather than a finding.

**Where it did not finish.** The internals generalized; the *front door* still describes and constrains
the consumer as if they were vibe-doctor. `README.md:3` still says "six normalized mood features," and
`Model` construction is locked to a single upstream host. Both are at the boundary a third party meets
first, which is why they are graded MUST-FIX even though every gate is green — exactly the case the
brief asked me to catch.

**Neither MUST-FIX requires retagging v0.2.0.** Both are loosening or documentation; they belong in
0.2.1.

---

## 1. The remaining opinions, enumerated

| # | Opinion | Where | Category |
| --- | --- | --- | --- |
| 1 | README describes v1's six normalized features | `README.md:3-5` | **(c) leftover** — FINDING 1 |
| 2 | `Model` construction locked to `essentia.upf.edu` | `registry.rb:41-51` | **(c) leftover** — FINDING 2 |
| 3 | Batching reserved to one concrete backend class | `extractor.rb:58` | **(c) leftover** — FINDING 3 |
| 4 | Algorithm set hardcoded in 3 places, none a registry row | `plan.rb:26-29`, `extract.py:19-31`, `:376-397` | **(a) essential**, undocumented — FINDING 4 |
| 5 | `Registry.default` ships MTG/MusiCNN models only | `registry.rb:99-204` | **(a) essential** — a default manifest is not a constraint; `Registry.new` is public |
| 6 | `byte_length` recorded, not enforced | `registry.rb:54-59` | **(b) deferred** — carrier: issue #1 ✓ |
| 7 | Pathname-based model verification, not dirfd-bound | `model_store.rb`, README:29-38 | **(b) deferred** — carrier: issue #2 ✓ |
| 8 | Essentia version pinned by a non-unique dev string | `extract.py:11-17` | **(b) deferred** — carrier: issue #3 ✓, comment in code ✓ |
| 9 | `sanity_range` raises instead of clamping | `value.rb:56-62` | **(a) essential** — this *is* M3(b)'s fix |
| 10 | Softmax `:hard` forces `native == sanity` | `registry.rb:78-84` | **(a) essential** — a softmax cannot leave `[0,1]` |

Items 6–8 are properly deferred: each has a tracked issue **and** an anchoring comment at the code that
would otherwise overclaim. That is the carrier standard this ticket established, and it was met. Items
1–4 are the findings.

---

### FINDING 1 — README describes the gem v1 was, not the gem that shipped — **MUST-FIX**

`README.md:3-5`: *"`mood_probe` extracts **six normalized mood features** from audio…"*

Two statements about the shipped artifact are false:

1. **Six.** Nine descriptors ship (`registry.rb:206-241`). `:bpm`, `:beat_confidence` and
   `:musicnn_embedding` appear nowhere in the README.
2. **Normalized.** A8 deleted the rescale. `valence_emomusic` carries `native_range: (1.0..9.0)`
   (`registry.rb:254`) and the extractor emits that. Nothing in the README says normalization is now
   the consumer's job — which is *the* architectural change of Phase A.

3. **"using … six separately licensed TensorFlow model files"** (`README.md:4-5`) states the weights as
   a precondition of *using the gem*. They are not. `:bpm` and `:beat_confidence` are `FromAlgorithm`
   rows (`registry.rb:279-297`), so `graph_models_for` filters them out (`plan.rb:53-58`) and
   `plan_for([:bpm]).required_files` is **empty** (`plan.rb:46`) — which is exactly what G4 proves
   against an empty models directory. *(Raised by the Team Manager; I verified it against the planner
   rather than adopting it, and it is correct.)*

This third point may matter most for adoption: the README tells a prospective consumer they must fetch
non-commercially-licensed weights to use the gem at all, when two of the nine descriptors need none.
Demand-driven verification is one of Phase A's genuine generalizations, and the README actively denies it.

The example at `README.md:11` then lists exactly vibe-doctor's six descriptor ids, reinforcing the
wrong model of the gem.

**Failure scenario.** A third party runs `gem install mood_probe`, reads only the README, calls
`analyze`, and reads `analysis[:valence_emomusic].value` expecting `0..1` because the README said
"normalized." They get `5.85`. If they persist it into a `0..1`-constrained column they get a
validation failure at best and a silently out-of-range value at worst; if they feed it to a similarity
metric they get results wrong by a factor of eight with no error anywhere. Nothing in the gem warns
them — `sanity_range` is `(-3.0..13.0)`, so `5.85` is perfectly valid output.

**Why it is the headline opinionation finding.** The README is where the gem states what it is. It
currently states vibe-doctor's opinion — the six normalized mood columns — as the gem's identity. Every
structural change of Phase A is invisible there.

**Fix.** Rewrite `README.md:3-15` to describe a descriptor registry: name all nine ids, state that
values are **native** and that the consumer owns any normalization, show `Registry.default.ids` as the
discovery call, and show `native_range`/`range_kind`/`sanity_range` as how a consumer learns a
descriptor's shape without reading the design doc.

---

### FINDING 2 — the host allowlist was applied at the wrong seam, and it is the hardest constraint on a non-vibe-doctor consumer — **MUST-FIX**

`registry.rb:41-51`:

```ruby
uri = URI.parse(source_url)
raise ArgumentError, "source_url must use HTTPS" unless uri.is_a?(URI::HTTPS)
# This host restriction must become capability-aware when C.2's allow_custom_models lands.
return if uri.host == "essentia.upf.edu"
raise ArgumentError, "source_url must use the essentia.upf.edu host"
```

**This is a departure from the design, not just an opinion.** §C.2 rule 6 — the registration-time
validation I ruled into slice 2 — requires exactly four things: bare-basename `filename`, **HTTPS**
`source_url`, mandatory `sha256`, mandatory `byte_length`. It does **not** contain a host allowlist.
The host allowlist appears in §C.3, as one element of the **deferred downloader rewrite** ("HTTPS-only,
host allowlist, redirects only to allowlisted HTTPS hosts, explicit timeouts, streaming bound"). The
implementation took a control the design assigned to the download path and applied it at
`Data.define` construction instead.

**That relocation is what makes it bite.** At the download seam an allowlist constrains *fetching*. At
the construction seam it constrains *existing*.

**Failure scenario.** A third party has their own fine-tuned MusiCNN head — or an internal mirror, or an
air-gapped copy already on disk. They write:

```ruby
MoodProbe::Model.new(filename: "my-head-1.pb", sha256: "…", source_url: "https://models.example.com/my-head-1.pb", …)
# => ArgumentError: source_url must use the essentia.upf.edu host
```

They cannot construct the row **even when the gem will never download anything** — `ModelStore#verify!`
only digests local files, so `source_url` is unread on that path, yet it still gates construction. There
is no capability flag, no escape hatch, and no `add_model` seam to route around it (I confirmed in slice 2
that `Registry#initialize` is the only registration door; that is still true at HEAD — `registry.rb:302`,
and the public surface is `default`, `new`, `ids`, `fetch`, `model`, `models`, `descriptors`).

**The named home does not exist.** The comment at `:45` defers to C.2's `allow_custom_models`. Verified:
`gh issue list --state all` returns **three** open issues — #1 downloader, #2 dirfd binding, #3
parameter-domain snapshot. **There is no issue for `allow_custom_models`.** By the standard this ticket
established and applied twice (prose in a design document is not a carrier), that moves this from
category (b) to category (c).

**Scope precisely.** This blocks third-party **models** only. Third-party **algorithm** descriptors are
unaffected — they use `FromAlgorithm`, need no `Model`, and work today (see the headline section).

**Fix — one edit, restores the design, loses no security.** Keep HTTPS + basename + `sha256` +
`byte_length` at construction (that is C.2 rule 6, correctly implemented). Move the **host allowlist** to
`ModelStore`'s download path where §C.3 puts it, and fold it into issue #1, which already owns that
rewrite. The digest check (`model_store.rb`, fail-closed on mismatch) is what actually protects the
bytes and is host-independent.

**Doing this now avoids a breaking 0.3.0.** If the check stays at construction, `allow_custom_models`
must eventually arrive as a `Registry.new` keyword that changes *when validation fires* — a
signature-and-semantics change. Moving it to the downloader is pure loosening: no existing caller
breaks, and `allow_custom_models` becomes a downloader policy rather than a constructor flag.

---

### FINDING 3 — the backend seam is capability-blind, and its error contract is undocumented — **SHOULD-FIX**

`extractor.rb:58`: `if backend.is_a?(Backends::EssentiaPython)`

**I verified this rather than taking the reading on faith, and the branch is not redundant.**
`EssentiaPython#analyze(path, plan:)` exists (`essentia_python.rb:119-121`) and delegates to
`analyze_all`, so *either* branch would work for the built-in backend. The branch exists solely to
select **batching** — and it selects on **class identity** rather than on capability.

**Failure scenario.** A third party writes `MyBackends::EssentiaRuby` implementing the full interface —
`preflight_environment!`, `preflight_plan!(plan)`, `analyze(path, plan:)` **and `analyze_all(paths,
plan:)`** — and injects it via `Extractor.new(backend:)`. Their `analyze_all` is **never called**. Every
`analyze_all` of N files silently becomes N separate `analyze` calls (`extractor.rb:64-66`). No error, no
warning, no deprecation. For a Python-subprocess-shaped backend that is N process spawns and N model
loads instead of one. The only route to batching is subclassing `Backends::EssentiaPython`.

**And G6 cannot catch it** — G6 traces embedding construction/invocation counts through the built-in
backend, so it passes while the seam it protects is closed to everyone else.

**Second limb, and it is the part with no documentation at all: the backend error contract is
return-based, not raise-based.** `result_for_outcome` (`extractor.rb:88-91`) tests
`outcome.is_a?(TrackError)`, so a backend must **return** `TrackError` instances inside its result array
rather than raise them — and `EssentiaPython#analyze_all` does exactly that
(`essentia_python.rb:135-137`, `parse_line`/`error_from_payload`). That is an unusual convention, it is
load-bearing, and it appears in no README, no comment, and no doc. A third-party backend that raises
`UnreadableAudioError` — the obvious thing to do — aborts the whole batch instead of failing one track.

**Fix.** `backend.respond_to?(:analyze_all)` in place of the `is_a?`, and a short "Implementing a
backend" README section stating the four methods and the return-errors-as-values rule.

---

### FINDING 4 — adding one Essentia algorithm is a four-site gem patch, and nothing says so — **SHOULD-FIX**

Adding, say, `KeyExtractor` requires edits at:

1. `plan.rb:26-29` — `GRAPH_ALGORITHMS` (Ruby side, graph algorithms)
2. `python/mood_probe_extract.py:19-22` — `_GRAPH_ALGORITHMS`
3. `:23-31`, `:36-45`, `:46-55` — `_ALGORITHM_PARAMS`, `_ALGORITHM_PARAM_DOMAINS`,
   `_ALGORITHM_PARAM_DEFAULTS`
4. `:376-397` — `build_pipeline`, an `if`/`elif` chain naming each Essentia class literally

**This is category (a) and I am not asking for it to be removed.** §C.1(a) requires the static enum
precisely so there is no `getattr`; I verified there is none (`git grep -c getattr` at HEAD on the
executor: no matches). The dispatch chain is the correct implementation of that constraint.

**The finding is that the boundary is nowhere stated.** A reader of the README sees a registry and
reasonably infers "add a row." Their first new algorithm is a four-site patch across two languages,
discovered by trial. For a gem whose stated purpose is to be a less opinionated Essentia wrapper, *where
the registry stops and the gem patch begins* is the single most important thing to document, and it is
undocumented.

**Failure scenario.** A consumer adds a `KeyExtractor` descriptor to their own registry. `plan_for`
raises `KeyError` from `GRAPH_ALGORITHMS.fetch` (`plan.rb:79`) — or, for a `FromAlgorithm` row, the plan
builds fine in Ruby and the Python executor exits 2 with `algorithm is not allowed`, surfacing as
`ConfigurationError` from a subprocess. Neither message tells them the extension procedure exists.

**Fix.** A README section listing the four sites and the order to edit them, plus a `KeyError` rescue in
`plan.rb:79` that names the extension points instead of surfacing a bare fetch failure.

---

## 2. Did the design survive contact?

**A6 (highest-risk item 1) — implemented, with one adaptation I judge an improvement.**

Verified: `@environment_verified = false` and `@verified_descriptors = Set.new` (`extractor.rb:24-25`);
`verify_environment!` under its own boolean memo (`:74-79`) calling `backend.preflight_environment!`;
descriptor-scoped path calling `model_store.verify!(filenames: plan.required_files)` — demand-driven, only
the plan's files (`:35`). Backend halves are genuinely separate: `preflight_environment!` runs
`python -c "import essentia.standard"` (`essentia_python.rb:89-97`); `preflight_plan!` runs the script
with `--verify` (`:99-117`).

**Adaptation:** A6 says the descriptor-scoped path memoizes on "the descriptor-id **set**." The
implementation instead keeps a **cumulative union** and short-circuits on `wanted.subset?`
(`extractor.rb:32`, `:37`). This still satisfies G7 — `[:mood_happy]` then `[:mood_happy, :bpm]` are
each non-subsets, so `preflight_plan!` runs twice — and it is *strictly better*, because a later
`verify!([:bpm])` is correctly skipped where set-keyed memoization would re-run it.

**Ruling: acceptable adaptation, and better than what I specified.** It is sound because plan
requirements are **monotone** in the descriptor set: `required_files` and graph construction for a
subset are contained in those for the superset, so a superset that preflighted successfully implies the
subset would. See NIT 1 — that monotonicity is currently an unstated invariant.

**A7 (highest-risk item 2) — implemented, no departure.** Static enum: `_GRAPH_ALGORITHMS`
(`extract.py:19-22`) for validation and a literal `if`/`elif` in `build_pipeline` (`:376-397`) for
construction; **`getattr` verified absent at HEAD**. Basename regex `:18`, containment via
`validate_model_path` `:307`, per-algorithm param whitelist `:23-31` with domains `:36-45` and the
cross-parameter 20-BPM rule `:353-358`, `schema_version` handshake `:11`/`:109`, `--capabilities`
`:58-64`. All A7 clauses present.

**A1–A5, A8 — present, no departures found.** A2's `Model` carries all required fields
(`registry.rb:4-22`). A3's emomusic `(1.0..9.0)`/`:nominal`/`(-3.0..13.0)` at `:254-256` and softmax
`(0.0..1.0)`/`:hard`/`(0.0..1.0)` at `:271-273`, with the `:hard` invariant enforced in
`Descriptor#initialize` (`:78-84`). A4's `Series` defined at `value.rb:124` with zero registry rows.
A8's native emission confirmed by the absence of any rescale in `value.rb`/`registry.rb`.

**The one real departure is FINDING 2** — a §C.3 control implemented at the §C.2 seam.

---

## 3. Is 0.2.0 coherent as a public release?

**No — a third party reading only the README cannot use this correctly.** FINDING 1 is disqualifying on
its own: the README's first sentence misstates both the descriptor count and, more dangerously, the
value range. Also missing: any mention of `Registry`, `Descriptor`, `plan_for`, how to discover
descriptors, the backend seam (FINDING 3), or the algorithm-extension boundary (FINDING 4). The README's
`Security notes` (`:29-38`) and `Real Essentia verification` (`:40-77`) sections are, by contrast,
excellent — precise, honest about limits, and issue-linked. The gap is entirely in the "what is this and
how do I use it" half.

**Half-landed items that risk a breaking 0.3.0 — one, and a decision now avoids it:** the host allowlist
at construction (FINDING 2). Left where it is, `allow_custom_models` must arrive as a `Registry.new`
keyword that changes when validation fires. Moved to the downloader now, it is pure loosening and
`allow_custom_models` becomes downloader policy. The other deferred items are additive:
`byte_length` enforcement (#1) tightens a field already required; dirfd binding (#2) changes internals;
the introspection snapshot (#3) adds a fixture. FINDING 3's `is_a?` → `respond_to?` is also additive.

---

## 4. Phase B readiness

**Phase B can do its job. Nothing in the branch obstructs it.** I checked the specific path: B1's five
new heads are all `TensorflowPredict2D` over the `msd_musicnn_1` embedding, which
`GRAPH_ALGORITHMS` (`plan.rb:27`) and `_GRAPH_ALGORITHMS` (`extract.py:20`) already contain; the
`probability_descriptor` helper (`registry.rb:262-277`) already produces exactly the right row shape;
and all five source URLs are on `essentia.upf.edu`, so FINDING 2 does not block Phase B — only third
parties. §F.4's falsifiability criterion (diff touches only `lib/mood_probe/registry*`, `spec/`, and
manifest paths) should therefore hold.

**But Phase B as scoped is a *partial* falsification, and that should be recorded rather than
discovered.** Every Phase B descriptor exercises the **easiest** extension axis — one more head on an
already-registered algorithm. Phase B will pass without ever touching FINDING 4's four-site boundary,
which is the architecture's hardest generalization limit. A green Phase B will therefore be weaker
evidence than §J.6 currently implies.

**Recommendation:** add a line to the Phase B DoD stating that Phase B falsifies the *new-head* axis
only, and that the first non-`TensorflowPredict2D` algorithm — `KeyExtractor` in Phase C — is the real
test of whether the registry boundary holds. That is a wording change, not scope.

---

## NITs

**NIT 1 — the subset short-circuit rests on an unstated invariant.** `extractor.rb:32`
(`return true if wanted.subset?(verified_descriptors)`) is sound only because plan requirements are
monotone in the descriptor set. That is true of today's planner and is not asserted anywhere. If a
future descriptor ever made a subset plan require something its superset did not, the short-circuit
would silently skip a needed preflight. Pin it with a one-line comment at `:32` and a spec asserting
`plan_for(subset).required_files ⊆ plan_for(superset).required_files`.

**NIT 2 — `plan.rb:79` `GRAPH_ALGORITHMS.fetch` raises a bare `KeyError`** for an unregistered
algorithm, where every other planner failure raises `ConfigurationError` with a diagnostic message
(`:150`, `:153`). Cheap to align, and it is the first error a consumer extending the gem will hit
(FINDING 4).

---

## Findings summary

| # | Grade | Finding | Location |
| --- | --- | --- | --- |
| 1 | **MUST-FIX** | README describes v1: "six normalized mood features"; nine ship, native | `README.md:3-15` |
| 2 | **MUST-FIX** | §C.3 host allowlist applied at §C.2's construction seam; blocks third-party models; no carrier issue | `registry.rb:41-51` |
| 3 | SHOULD-FIX | Backend batching gated on class identity, not capability; error contract undocumented | `extractor.rb:58`, `:88-91` |
| 4 | SHOULD-FIX | Four-site algorithm extension boundary undocumented | `plan.rb:26-29`, `extract.py:19-55`, `:376-397` |
| 5 | NIT | Subset short-circuit rests on unstated monotonicity invariant | `extractor.rb:32` |
| 6 | NIT | Bare `KeyError` for unregistered algorithm | `plan.rb:79` |

No closed finding from slices 1–5 is re-litigated, and I found none that was closed wrongly. The
carriers agreed in slices 2–5 (issues #1–#3, the `ModelStore::Files` and `_ESSENTIA_VERSION` anchoring
comments, §C.5, the README security notes) are all present at HEAD and are the reason items 6–8 in the
opinion table are category (b) rather than findings.

---

## EVIDENCE

**Diff range:** `55d85fb246e45581172d58066c24e41c8970ac9b..848f6894a6022b5a32ae2b6b0c6898ac84986fa0`,
repo `/Users/lukeolson/projects/gems/mood_probe`, branch `feat/essentia-gem-v2-phase-a`.

**I verified (ran the command, read the output):**

```
$ git -C …/mood_probe rev-parse v0.2.0^{commit}
848f6894a6022b5a32ae2b6b0c6898ac84986fa0

$ git -C …/mood_probe diff --shortstat 55d85fb..848f689
 65 files changed, 4716 insertions(+), 653 deletions(-)

$ git -C …/mood_probe diff --name-status 55d85fb..848f689 -- lib python
M lib/mood_probe.rb          M lib/mood_probe/backends/essentia_python.rb
M lib/mood_probe/extractor.rb  D lib/mood_probe/features.rb
D lib/mood_probe/model_registry.rb  M lib/mood_probe/model_store.rb
A lib/mood_probe/plan.rb      A lib/mood_probe/registry.rb
M lib/mood_probe/result.rb    A lib/mood_probe/value.rb
M lib/mood_probe/version.rb   M python/mood_probe_extract.py

$ git -C …/mood_probe grep -c "getattr" 848f689 -- python/mood_probe_extract.py
(no matches — A7's "no getattr" holds at HEAD)

$ gh issue list --state all --limit 20      # in …/mood_probe
3 OPEN  Pin Essentia parameter-domain introspection snapshot and digest
2 OPEN  Bind model verification to the verified directory or file descriptor
1 OPEN  Rewrite model downloader with bounded HTTPS streaming
(no allow_custom_models issue — basis for FINDING 2's category-(c) ruling)
```

**Files read in full or in cited part:** `lib/mood_probe.rb`; `lib/mood_probe/extractor.rb` (all 94
lines); `lib/mood_probe/registry.rb:1-120`, `:205-338`; `lib/mood_probe/plan.rb` (all 156);
`lib/mood_probe/value.rb` (structure grep, `:13-200`); `lib/mood_probe/backends/essentia_python.rb`
(method index + `preflight_environment!`, `preflight_plan!`, `analyze`, `analyze_all`, `parse_line`,
`error_from_payload`); `python/mood_probe_extract.py:11-60`, `:370-405`, function index;
`README.md` (all 77 lines). Design §J.4 read in full; §C.1, §C.2 rule 6, §C.3, §J.6, §F.4 consulted for
the departure ruling.

**Prior review record read before writing:** `/tmp/maestri-reviews/ESSENTIA-GEM-V2/phase-a/` —
`slice-1/principal-sequencing.md`, `slice-2/principal-scope.md`, `slice-2/principal-threat-model.md`,
`slice-3/principal-preflight.md`, `slice-3/principal-c1c-amendment.md`,
`slice-4/principal-preflight.md`, `slice-4/principal-canonical-environment.md`,
`slice-5/principal.md`, `slice-5/principal-golden-provenance.md`, `slice-5/principal-zero-ruling.md`,
`slice-5/principal-skipped-track.md` (directory listing confirmed; all authored by me this cycle).

**I did not re-derive** the dispatcher's baseline (clean tree, 173 examples / 0 failures). I did
independently re-verify the tag peel and the diffstat, and both match as stated.

**I believe, but did not execute:** FINDING 3's failure scenario (a third-party backend implementing
`analyze_all` being ignored) is read from `extractor.rb:52-68` and `essentia_python.rb:119-137`; I did
not write a stub backend to demonstrate it. FINDING 2's failure scenario follows directly from
`registry.rb:41-51` being called unconditionally in `Model#initialize` (`:24-28`); I did not execute a
`Model.new` with a foreign host.

**Read-only compliance:** no file in either repository was modified, staged, or committed. The only
file written is this report.
