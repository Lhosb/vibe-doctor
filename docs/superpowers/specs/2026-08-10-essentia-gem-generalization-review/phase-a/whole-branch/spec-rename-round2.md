# SONANCE 0.3.0 — tag-block clearance (SPEC)

**VERDICT: APPROVE-WITH-FINDINGS. MY BLOCK IS LIFTED. Cut the tag on `6639397`.**

**Range:** `77003c5f1796c42fda7807123a56a13c56e71ffe..66393972a8b57ee116afec0fbeb879a0c410dbca`,
one commit, three files. Tree clean, suite **192 / 0**, rubocop **49 files / 0**, the new gate green as
its own example.

One SHOULD-FIX, recorded for **after** the tag: the gate is narrower than it reads, and I can say
exactly how narrow.

---

## 1. MUST-FIX — CLOSED

The fix is exactly the four tokens, `valence_emomusic` and `arousal_emomusic` untouched
(`spec/integration/essentia_golden_spec.rb:22-27`).

**I could not run real Essentia** — no models, no image — so I verified the precise point at which the
README path failed. My block rested on `plan_for` raising `ConfigurationError` *before any audio is
read*; that is now gone, and the plan it produces is the right one:

```
plan_for(golden set)  → OK
emit ids              → ["valence_emomusic","arousal_emomusic","danceability_musicnn",
                         "mood_acoustic_musicnn","mood_relaxed_musicnn","mood_happy_musicnn"]
required_files        → 6
golden/chirp.json keys == emit ids  → true
```

The last line matters as much as the first: the live-extraction branch now yields exactly the keys the
comparison consumes, so the README command (`README.md:103-107`, no `SONANCE_ACTUAL_ROOT`) reaches the
numeric assertion rather than dying at planning. The branch structure is unchanged — the `descriptors`
let is still consumed at `:90` and `:148`, on the `else` path CI does not take — so the fix lands where
the defect was.

**What I checked instead of a live run:** the descriptor set resolves through the real `Registry`, the
plan's `required_files` is the full six-model set (so `models fetch` in the README command is still the
right prerequisite), and the emit ids equal the committed golden keys. What remains unexercised by me is
the Essentia call itself, which the `essentia_golden` job covers on the capture path.

## 2. The new gate — real coverage, no false positives, and narrower than it reads

**Does it cover the class? Partly, and the boundary is sharper than the code suggests.** I probed the
detection logic directly with the shipped regexes over synthetic sources.

**Correctly flagged:**

| Shape | Result |
| --- | --- |
| the original defect (`let(:descriptors)`, array mixing valid + retired ids) | **FLAGGED** `["danceability"]` |
| `descriptors: %i[danceability]` inline | **FLAGGED** |
| `descriptors: [ :danceability ]` | **FLAGGED** |
| `descriptors: [ "mood_happy" ]` quoted | **FLAGGED** |

**Correctly ignored — every legitimate site you enumerated, and by construction rather than luck:**

| Legitimate site | Why it cannot false-positive |
| --- | --- |
| CHANGELOG migration table | `.md` is outside the globs |
| `"bpm"` as a Python output name | `python/*.py` outside the globs |
| plan fixtures `take.output` | `.json` outside the globs |
| `fake_essentia` filename matching | `.py` outside the globs |
| frozen baseline app-column keys | `.json`; and `baseline["mood_happy"]` in the parity spec matches neither scanner — **verified, not flagged** |
| trace fragments, `python_plan_executor_spec.rb:70` | `%w[mood_happy mood_relaxed]` with no valid id and no descriptor prefix — **verified, not flagged** |
| `%w[danceable not_danceable]` class array in `registry_spec` | same rule — **verified, not flagged** |

A gate with false positives gets disabled; this one has none that I could produce.

### SHOULD-FIX — the prefix heuristic almost never fires, so the effective rule is narrower than intended

`descriptor_id_integrity_spec.rb:14` is `/(?:\bdescriptors?\b|DESCRIPTORS)\W{0,80}\z/i` — the word must
be followed by **non-word characters only** up to the array. `let(:descriptors) do` fails that, because
`do` is word characters. Verified:

```
let(:descriptors) do
  %i[danceability mood_happy]      → NOT FLAGGED        (all ids retired)
heads = %i[mood_relaxed] … analyze(p, descriptors: heads)  → NOT FLAGGED  (indirection)
```

So the rule the gate actually implements is: **an array is examined only if it already contains a
currently-valid id, or if `descriptors:` sits immediately before it with nothing but punctuation
between.** The prefix clause fires for the inline `descriptors: %i[…]` form and effectively nowhere
else.

**The consequence, stated plainly because it is the sharpest way to size the residual:** had this
migration also renamed `valence_emomusic` and `arousal_emomusic`, the gate would **not** have caught the
defect it was built for — condition (a) would have failed (no valid id left in the array) and
`let(:descriptors) do` never satisfies condition (b). The gate caught the real instance because two ids
survived the rename, which is luck rather than design.

**I did not hand you an untested one-liner.** I tried the obvious repair — `[^\n]{0,80}` in place of
`\W{0,80}` — and it does **not** close the case, because the `%i[` sits on the following line. The right
fix needs to span the newline without swallowing unrelated code, and I would rather report the boundary
precisely than propose a pattern I have not seen work.

**Why this is not a blocker.** Three reasons, in order of weight:

1. **The residual shapes still fail loudly at runtime.** `Registry#fetch` raises
   `ConfigurationError: unknown descriptor: …`. The gate is early warning, not the only defence; the
   original defect escaped because CI never took that branch, and that is unchanged either way.
2. **Nothing in the repository matches the uncovered shapes today** — the suite is green and every call
   site passes `descriptors:` inline or a set containing valid ids.
3. **It is strictly better than what it replaced.** The capture-script gate covered one file;
   `script/**/*.rb` is still globbed, and `capture_essentia_outputs.rb`'s array contains valid ids, so
   that file remains covered — plus `lib`, all of `spec`, `exe` and the workflows.

Worth recording alongside it: the globs exclude `*.md`, `*.json` and `python/`. Excluding `.md` is the
right call — scanning it would false-positive on the CHANGELOG migration table, which is the one place
retired ids *must* appear. Plan-fixture `emit[].id` in `.json` is covered elsewhere, by `planner_spec`
asserting the fixtures `eq` regenerated output.

---

## Decision

**My block is lifted.** The MUST-FIX is closed at the point my argument rested on, the gate is a genuine
net improvement with no false positives, and its residual holes are a reduction of the original class
rather than a new risk. The SHOULD-FIX above is post-tag work: it changes no shipped behaviour, and
recording the gate's true rule matters more than widening it — a gate trusted for more than it does is
how the second copy survived in the first place.

## Evidence

```
$ git -C … rev-parse HEAD                 → 66393972a8b57ee116afec0fbeb879a0c410dbca
$ git -C … log --oneline 77003c5..6639397 → 6639397 fix: validate descriptor lists repo-wide
$ git -C … diff --stat 77003c5..6639397   → 3 files, +63/−16
$ git -C … status --porcelain             → (empty)
$ bundle exec rspec spec/descriptor_id_integrity_spec.rb → 1 example, 0 failures
$ bundle exec rspec                        → 192 examples, 0 failures
$ bundle exec rubocop                      → 49 files inspected, no offenses detected
```

MUST-FIX closure, by execution against the real registry:
```
plan_for(%i[valence_emomusic arousal_emomusic danceability_musicnn mood_acoustic_musicnn
            mood_relaxed_musicnn mood_happy_musicnn]) → OK
emit ids == golden/chirp.json keys → true ;  required_files → 6
grep -n descriptors spec/integration/essentia_golden_spec.rb → :20 (let), :90, :148 (live branch)
```

Gate probe — the shipped regexes (`:14`, `:23`, `:33-35`) applied to synthetic sources; results in the
two tables above. Nine shapes tested: four flagged, two holes found (all-retired array under
`let(:descriptors) do`; descriptor list reached by indirection), three legitimate shapes confirmed not
flagged, plus the class-array case.

**Verified vs believed.** Every table row above is a command result I **verified**. Two statements are
**belief**: that the README command now reaches the numeric assertion — I verified everything up to and
including the plan and the key match, but not the Essentia call itself; and that no current repository
file matches the uncovered shapes — I infer that from the green suite and from reading the call sites,
not from an exhaustive enumeration. Your CI run 31745780173 and your scratch-clone planted-id test I
take from your baseline; I did not reproduce them.

**Read-only confirmed.** Nothing in either repository was modified, staged or committed except this
report; the gate probe ran entirely on synthetic strings in-process.

VERDICT: APPROVE-WITH-FINDINGS — BLOCK LIFTED
