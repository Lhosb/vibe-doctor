# VD-23 — Test & Gate Review (test/gate discipline only)

# VERDICT: **REQUEST-CHANGES**

One HIGH finding: **this change breaks the app's Essentia golden CI gate.** The models move to
`/usr/local/essentia-models`, but `spec/integration/essentia_extract_golden_spec.rb:19` hardcodes
`ROOT.join("tmp/essentia_models")` and never reads `ESSENTIA_MODELS_DIR`. That directory no longer
exists in the image. Nobody saw it because the gate is Docker-only, excluded from the local run, and
the branch is unpushed.

**On TRAP 2 — my primary question: the sabotage evidence DOES discriminate.** Not as a matched pair
(the two sabotages are different interventions, and the implementer says so), but the three results
together close the argument. Detail and reasoning in §1. I would not block on the sabotage evidence.

| # | Severity | Finding | Anchor |
|---|---|---|---|
| T1 | **HIGH** | Essentia golden CI gate breaks — spec hardcodes the removed path | `spec/integration/essentia_extract_golden_spec.rb:19` |
| T2 | MEDIUM | Golden generator has the same hardcoded path | `spec/fixtures/sonance/generate_goldens.rb:9` |
| T3 | MEDIUM | Layer-cache comment is factually wrong; fetch re-runs on **every** code deploy | `Dockerfile:68-71` |
| T4 | LOW | Comment claims verify checks "ownership and mode"; it checks digest only | `Dockerfile:87` |
| T5 | LOW | Nothing gates `ESSENTIA_MODELS_DIR` staying consistent between verify and runtime | `Dockerfile:38,89` |

Range reviewed: `5c9dfcc..24e1779`. Scope: test/gate quality. Security → Warden, spec → Plumb.

---

## 1. TRAP 2 — does the sabotage pair discriminate? **YES, with a caveat about how it's framed**

### The two sabotages are NOT the same intervention

Asked directly: is removing models from the build context the same, from verify's point of view, as
the models being absent? **No — and the asymmetry is real:**

- **OLD** delivery channel: build context → `COPY . .` (`Dockerfile:59`), with the models kept alive
  by `.dockerignore:34-35` negations (confirmed present at base, removed at HEAD). The sabotage
  attacks that channel.
- **NEW** delivery channel: `sonance models fetch` over the network (`Dockerfile:71`) → build stage →
  `COPY --from=build` (`Dockerfile:85`). **The build context is not a delivery channel for models at
  all.** `.dockerignore:19` ignores `/tmp/*` with no negation, so `/rails/tmp/essentia_models` does
  not exist in a NEW image.

So the OLD sabotage is **inapplicable** to NEW — not because NEW resists it, but because NEW does not
use that channel. The implementer states this plainly (report lines 77-79) rather than papering over
it, which is the right call.

### Why the evidence still discriminates

The "pair" is really a **three-legged argument**, and it holds:

| Leg | Proposition | Evidence |
|---|---|---|
| Result 1 | OLD has **no build-time gate** — a build-context regression yields exit 0 with zero models | `OLD_BUILD_EXIT=0`, `OLD_PB_IN_IMAGE=0` |
| Result 2 | NEW delivers models **with the negations already absent** — i.e. under the OLD sabotage condition | `CANONICAL_EXIT=0`, 6 `.pb`, runtime verify under `--network none` exit 0 |
| Result 3 | NEW's gate **fires** when a model is absent at the verified path | `missing model: …/msd-musicnn-1.pb`, exit code 1, no image |

Result 2 is the leg that does the real work and it is easy to overlook: because the negations are
*already* removed in NEW, the canonical build **is** the OLD sabotage condition, and it still yields
six models. That is the independence proof. Combined with Result 3 (the gate bites) and Result 1 (OLD
had no gate), the conclusion "NEW prevents the OLD failure mode" follows.

The deeper reason it discriminates is structural, not experimental: **the NEW gate's subject is the
final-stage path, which is downstream of every delivery mechanism.** Any cause of absence or
corruption — failed fetch, bad COPY, wrong digest — lands at the same place the gate looks.

### The genuine weakness in Result 3

`rm` of one model *between fetch and verify* is an artificial state no real regression produces. A
more faithful mutation would break the **fetch** (unreachable host, or a digest mismatch). That path
is in fact **already gated** — `fetch!` calls `verify!` itself
(`model_store.rb:203-206`), so `Dockerfile:71` fails the build on a bad download — but that leg was
not demonstrated. Not a finding, because the code path is verifiable by reading and I confirmed it
below; worth recording as "gated but undemonstrated."

Worth crediting precisely: the two gates cover **different** failure classes, which is good design
rather than redundancy.

- `Dockerfile:71` (`fetch` → implicit verify) catches download failure and digest mismatch at source.
- `Dockerfile:89` (final-stage verify) catches anything the **COPY** did wrong and confirms
  **readability as uid 1000** — a property the build stage cannot establish because it runs as root.

---

## 2. Is there a gap between fetch, verify, and COPY? **No path gap — this is not an F5-class defect**

I looked specifically for the shape I found in SON-17 F5 (a guard validating a different path than the
one that does the work). It is **not present here**. All four references agree on
`/usr/local/essentia-models`:

```
Dockerfile:38   ENV ESSENTIA_MODELS_DIR="/usr/local/essentia-models"   (base stage, inherited by final)
Dockerfile:71   RUN … sonance models fetch  --models-dir /usr/local/essentia-models   (build stage)
Dockerfile:85   COPY --chown=rails:rails --from=build /usr/local/essentia-models /usr/local/essentia-models
Dockerfile:89   RUN … sonance models verify --models-dir /usr/local/essentia-models   (final stage, after COPY)
```

And the four Ruby consumers all read that env with the old path only as a fallback:

```
app/jobs/enrich_album_job.rb:6        ENV.fetch("ESSENTIA_MODELS_DIR", Rails.root.join("tmp", "essentia_models"))
app/services/mood_grounding_service.rb:11   same
lib/tasks/enrichment.rake:19                same
lib/tasks/enrichment.rake:32                same
```

Ordering is correct: `USER 1000:1000` at `:80` precedes both the COPY and the verify, so the gate
really does run as the runtime uid. Nothing after `:89` touches the models (only ENTRYPOINT/EXPOSE/CMD),
so **the image state at verify time is the image state at runtime** for those files.

No deploy-time override exists:

```
$ grep -rn "ESSENTIA_MODELS_DIR" config/ .kamal/ .github/
(no output)
```

### T5 (LOW) — the one residual gap

`ESSENTIA_MODELS_DIR` is set in the image but nothing *gates* that it stays consistent. A future Kamal
`env:` entry pointing it elsewhere would leave the build-time verify passing on a path the runtime no
longer uses — verify would attest to `/usr/local/essentia-models` while enrichment read somewhere else.
Cheap mitigation: have the final-stage verify use `--models-dir "$ESSENTIA_MODELS_DIR"` instead of
repeating the literal, so the gate and the runtime read the same variable by construction.

---

## 3. Is there a gate here that CANNOT FAIL? **No — and I verified the core locally**

The build-time verify is the new gate. Two properties make it non-vacuous:

**(a) Its subject list comes from the registry, not from a directory scan.** `exe/sonance:52-56` calls
`verify!(filenames: registry.models.map(&:filename))`. An empty directory therefore cannot produce a
vacuous pass — it produces a missing-model error on the first expected file. This is exactly the
non-vacuity property four earlier gates on this project lacked, and here it holds **by construction**.

**(b) I ran the mutation locally.** I cannot reproduce Result 3's Docker build on arm64, but the gate's
core is pure Ruby and needs no Essentia, so I exercised it directly:

```
$ bundle exec ruby -e 'store = Sonance::ModelStore.new("/tmp/vd23-scratch/emptymodels",
                         registry: Sonance::Registry.default)
                       store.verify!(filenames: Sonance::Registry.default.models.map(&:filename))'
RAISED: Sonance::ConfigurationError: missing model: /private/tmp/vd23-scratch/emptymodels/msd-musicnn-1.pb
subject list size (from registry, not disk): 6
```

That independently confirms the mechanism the implementer demonstrated on amd64: six expected models,
and absence raises rather than passing. The mutation that makes it red is "remove or corrupt any of the
six," and it is runnable — at the Ruby layer by me, and at the Docker layer as Result 3.

### T4 (LOW) — the comment overstates what the gate checks

`Dockerfile:87` claims *"Verify model digests, ownership, and mode as the runtime user."* The
implementation checks the **digest only**:

```ruby
# model_store.rb
def verify_model!(model)
  return if model_files.digest(model.filename) == model.sha256
  raise ConfigurationError, "model digest mismatch: #{model.filename}"
end
```

There is no `File.stat`, no owner check, no mode check anywhere in `model_store.rb`. What *is* genuinely
established is **readability by uid 1000**, implicitly — computing the digest requires opening the file
as the current user. That is the property that matters, so the gate is sound; the comment simply claims
two checks that do not exist. Reword to "verifies model digests, and thereby readability, as the runtime
user." Left as-is, a future reviewer will credit ownership/mode coverage that is not there.

---

## 4. TRAP 1 — the assets explanation, checked rather than trusted

**The explanation fully accounts for all seven failures.** I verified both directions on a scratch copy
rather than only confirming the number.

```
=== CONTROL: scratch copy WITH built assets ===
298 examples, 0 failures        EXIT=0

=== assets removed (rm app/assets/builds/tailwind.css and app/assets/builds/tailwind) ===
298 examples, 7 failures        EXIT=1
```

Exactly seven, and the identity matches the claim — six in `vibe_map_spec.rb`, one in
`vibe_map_rescale_spec.rb`, nothing else:

```
./spec/system/vibe_map_rescale_spec.rb:22 # inverts a dragged position back into true valence/arousal…
./spec/system/vibe_map_spec.rb:16 # renders a point at the album's valence/arousal position…
./spec/system/vibe_map_spec.rb:25 # posts an override with the new position…
./spec/system/vibe_map_spec.rb:42 # still overrides (not pans) when dragging a point with zoom/pan…
./spec/system/vibe_map_spec.rb:52 # does not create an override when dragging on empty canvas…
./spec/system/vibe_map_spec.rb:61 # lists each distinct genre in the legend…
./spec/system/vibe_map_spec.rb:80 # rescales axes to the remaining points when a genre is filtered out…
```

And the mechanism is the claimed one — the chart never renders, so the point selector finds nothing:

```
1) Vibe Map drag inversion inverts a dragged position back into true valence/arousal…
   Failure/Error: find("[data-album-id='#{album.id}']")
   Capybara::ElementNotFound: Unable to find visible css "[data-album-id='23514']"
   # ./spec/support/vibe_map_helpers.rb:52:in 'VibeMapHelpers#find_vibe_map_point'
```

Same count, same files, same root cause, and it is reversible: rebuilding Tailwind returns the suite to
298/0. **No finding.** The corrected report is accurate, and importantly the failures are unrelated to
this diff — they are a worktree hygiene artefact.

One nuance, not a finding: the correction describes the symptom as `undefined method click for nil`,
whereas the actual surface error is `Capybara::ElementNotFound`. The diagnosis is right; the quoted
message is imprecise.

---

## 5. Is existing test coverage LOST? **YES — T1 is the finding of this review**

Derived from code, not from the report. Every reference to the removed path:

```
$ grep -rn "essentia_models" --include="*.rb" --include="*.rake" .
app/jobs/enrich_album_job.rb:6              ENV.fetch("ESSENTIA_MODELS_DIR", …)   <- reads env, fine
app/services/mood_grounding_service.rb:11   ENV.fetch("ESSENTIA_MODELS_DIR", …)   <- fine
lib/tasks/enrichment.rake:19                ENV.fetch("ESSENTIA_MODELS_DIR", …)   <- fine
lib/tasks/enrichment.rake:32                ENV.fetch("ESSENTIA_MODELS_DIR", …)   <- fine
spec/integration/essentia_extract_golden_spec.rb:19   MODELS_DIR = ROOT.join("tmp/essentia_models")   <- HARDCODED
spec/fixtures/sonance/generate_goldens.rb:9           models_dir = root.join("tmp/essentia_models")   <- HARDCODED
```

The implementer's report enumerates **four** `models_dir` call sites and concludes "No Ruby source
changes needed." That enumeration is correct for `app/` and `lib/` — which is exactly what the grep in
the report was scoped to (`grep -rn … app/ lib/`). **It missed `spec/`, and the two spec-side sites are
the ones that break.**

### T1 (HIGH) — the Essentia golden CI gate breaks

`spec/integration/essentia_extract_golden_spec.rb:19` hardcodes the path and reads no env:

```
$ grep -n "ENV" spec/integration/essentia_extract_golden_spec.rb
13:#     -e ESSENTIA_SPECS=1 -e RAILS_ENV=test vibe-doctor-essentia-goldens \    (a comment)
```

Before/after state, confirmed by execution:

```
$ git ls-tree -r --name-only 5c9dfcc -- tmp/essentia_models/   -> 6 .pb files
$ git ls-tree -r --name-only 24e1779 -- tmp/essentia_models/   -> (empty)
$ git show 5c9dfcc:.dockerignore | grep -n essentia
34:!/tmp/essentia_models/
35:!/tmp/essentia_models/*.pb
$ grep -n tmp .dockerignore   # at HEAD
19:/tmp/*                     # …and no essentia negation remains
```

So **before**: tracked `.pb` files + negations → `COPY . .` placed them at `/rails/tmp/essentia_models`
and the golden spec found them. **After**: not tracked, no negation, `/tmp/*` ignored → that directory
does not exist in the image, and the spec's `MODELS_DIR` points at nothing.

The CI job that runs it builds from **this** Dockerfile:

```yaml
.github/workflows/ci.yml  (essentia job)
  - run: docker build --platform linux/amd64 -t vibe-doctor-essentia-goldens .
  - run: docker run … -e ESSENTIA_SPECS=1 -e RAILS_ENV=test
           vibe-doctor-essentia-goldens /rails/bin/essentia-ci
```

**Predicted failure:** the five model-backed examples raise
`Sonance::ConfigurationError: missing models directory: /rails/tmp/essentia_models` — the exact error I
observed when running that spec without models during the SON-16 investigation — and `bin/essentia-ci`
fails on its `grep -qE "^${expected} examples, 0 failures$"` assertion.

**Why nobody saw it:** the gate is `:essentia`-tagged and excluded locally
(`spec/spec_helper.rb` `filter_run_excluding essentia: true`), so the 298/0 run does not touch it; and
the branch is unpushed, so no CI run exists. This is a Docker-only gate silently broken by a
non-Docker-tested change — the same blind spot that made the models' absence invisible in the first
place.

**Fix:** one line — `MODELS_DIR = Pathname(ENV.fetch("ESSENTIA_MODELS_DIR", ROOT.join("tmp/essentia_models").to_s))`,
matching the pattern the four production sites already use.

### T2 (MEDIUM) — the golden generator has the same defect

`spec/fixtures/sonance/generate_goldens.rb:9` hardcodes the same path. Lower severity because it is a
manually-invoked tool, not a CI gate — but it is the tool that would be used to regenerate goldens, and
it will now fail. (Note this compounds with the SON-16 finding that the goldens need regenerating under
a pinned environment anyway.)

`spec/integration/essentia_empty_models_spec.rb` is **unaffected** — it builds its own directory with
`Dir.mktmpdir` (lines 10, 20), so it has no dependency on the removed path. Checked rather than assumed.

### T3 (MEDIUM) — the layer-cache comment is wrong, and the gate becomes network-dependent every deploy

`Dockerfile:68-70` states:

> This layer caches on Gemfile.lock, so code-only deploys never refetch.

**That is backwards.** The fetch at `:71` sits *after* `COPY . .` at `:59`, plus the bootsnap and
`assets:precompile` layers at `:63` and `:66`. Docker invalidates a layer when any preceding layer is
invalidated, and `COPY . .` invalidates on **any** change in the build context. So a code-only change
invalidates `:59` → `:63` → `:66` → **and the fetch at `:71` re-runs on every code deploy.**

Gate consequence, which is why this is in my discipline rather than only a deploy concern: the
build-time gate now depends on `essentia.upf.edu` egress on **every** build, not occasionally. That
makes a load-bearing gate as flaky as an external host. The egress check in the context file confirms
reachability *today*; it does not make the dependency per-deploy-safe.

**Fix:** move the fetch to immediately after `bundle install` (`:53-56`), which depends only on
`Gemfile`/`Gemfile.lock` copied at `:51`. `sonance models fetch` needs the gem, not the app code, so
nothing blocks the move — and it would then genuinely cache on `Gemfile.lock` as the comment claims.

---

## 6. What I could NOT verify, and why

| Claim | Why not |
|---|---|
| Results 1-3 (the amd64 sabotage builds) | This machine is arm64 and cannot run the Essentia amd64 toolchain. I assessed the pair's **logic** and independently verified the gate's **core mechanism** in Ruby (§3), but I did not re-run the Docker builds. |
| That T1 actually fails in CI | Requires the amd64 image build. The prediction rests on: the spec's hardcoded path (read), the tracked-file removal (verified by `git ls-tree`), and `.dockerignore:19` with no negation (read). I am confident but it is a prediction, not an observation. |
| `essentia.upf.edu` reachability from the builder | Taken as established per the context file; not re-checked. |
| That previously built images still deploy/roll back | Deployment concern, outside my discipline, and not runnable here. |

---

## 7. Evidence — commands run

```
git -C <repo> diff --stat 5c9dfcc 24e1779
git -C <repo> diff 5c9dfcc 24e1779 -- Dockerfile .dockerignore .gitignore
git -C <repo> ls-tree -r --name-only 5c9dfcc -- tmp/essentia_models/     -> 6 files
git -C <repo> ls-tree -r --name-only 24e1779 -- tmp/essentia_models/     -> empty
git -C <repo> ls-tree -r --name-only 24e1779 | grep '\.pb$'              -> empty
git -C <repo> show 5c9dfcc:.dockerignore | grep -n essentia              -> 34,35
grep -rn "essentia_models" --include=*.rb --include=*.rake .             -> 6 sites (4 app/lib + 2 spec)
grep -rn "ESSENTIA_MODELS_DIR" config/ .kamal/ .github/                  -> no output
grep -n "ENV" spec/integration/essentia_extract_golden_spec.rb           -> comment only
sed -n '/^  essentia:/,$p' .github/workflows/ci.yml
cat -n Dockerfile
# gem internals (pinned rev cf8e613, tag v0.3.0):
grep -n "models\|verify" <gem>/exe/sonance
sed -n '/def verify_model!/,/^    end/p' <gem>/lib/sonance/model_store.rb
grep -n "missing model\|def fetch!\|verify!" <gem>/lib/sonance/model_store.rb  -> 54, 132, 198, 203, 206
# local gate mutation:
bundle exec ruby -e '…ModelStore.new("/tmp/vd23-scratch/emptymodels"…).verify!…'
# TRAP 1, scratch copy /tmp/vd23-scratch/app (rsync, .git excluded):
bundle exec rspec                        -> 298 examples, 0 failures   (assets present)
rm -rf app/assets/builds/tailwind.css app/assets/builds/tailwind
bundle exec rspec                        -> 298 examples, 7 failures
bundle exec rails tailwindcss:build ; bundle exec rspec   -> back to 298/0
```

Full logs: `/tmp/vd23-scratch/with-assets.txt`, `/tmp/vd23-scratch/no-assets.txt`.

---

## 8. Required changes

1. **T1 (HIGH)** — make `spec/integration/essentia_extract_golden_spec.rb:19` read
   `ESSENTIA_MODELS_DIR` with the old path as fallback. One line. Without it the Essentia golden gate
   is dead, and it is the only gate that exercises real model inference.
2. **T2 (MEDIUM)** — same one-line fix at `spec/fixtures/sonance/generate_goldens.rb:9`.
3. **T3 (MEDIUM)** — move the fetch layer above `COPY . .` so it caches as the comment claims, or
   correct the comment. Prefer moving it: it removes a per-deploy network dependency from a
   build-blocking gate.
4. **T4 (LOW)** — reword `Dockerfile:87` to claim only what is checked.
5. **T5 (LOW)** — have `Dockerfile:89` verify `"$ESSENTIA_MODELS_DIR"` rather than a repeated literal.

T1 must land before this merges; it converts a working gate into a failing one. T3 is worth doing in
the same pass because the fetch layer is being touched anyway. **The sabotage evidence itself I accept
— it discriminates, and the gate design (two gates covering different failure classes, subject list
derived from the registry) is the strongest gate work I have reviewed on this project.**

## 9. Read-only confirmation

No commits, no edits, no pushes, no PR. Nothing in the repo or the worktree was modified; all
experiments ran in `/tmp/vd23-scratch/`. The `fetch-models-at-build-time` worktree remains at
`24e1779`.
