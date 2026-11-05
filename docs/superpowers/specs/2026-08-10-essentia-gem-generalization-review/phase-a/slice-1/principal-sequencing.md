# ESSENTIA-GEM-V2 Phase A — slice sequencing review

**Reviewer:** Principal Engineer (Keystone) · **Scope:** decomposition only, design settled
**Verdict:** **approve-with-changes** — the slice shape is right, the gate-to-slice mapping and the
two-repo ordering are not.

**Blocking before slice 2 is dispatched (four items):**

1. G3 removed from slice 2 — it cannot run there.
2. G6 assigned — it is currently in no slice at all.
3. The tag/pin inversion fixed (Q5). Slice 4 as written cannot `bundle install`.
4. The gem's `rspec` + `lint` CI jobs moved into slice 1, not slice 5.

Nothing here reopens the design. Slice 1 as scoped is correct and should continue.

---

## Q1 — Gates assigned to a slice that cannot run them

**Yes. Three real defects, one omission, two split-gates.**

### (a) G3 in slice 2 — impossible. *(defect)*

G3 is the mapper clamp-boundary gate: `9.4 → 1.0`, `0.6 → 0.0`, with passing controls `9.0 → 1.0`
and `1.0 → 0.0`. `MoodVectors::EssentiaMapper` is **A9 — app-side, slice 4**. Nothing in slice 2 (gem
repo, pure Ruby) can execute it. You already list G3 correctly in slice 4. Delete it from slice 2.

### (b) G6 is assigned to no slice at all. *(omission — the one I care about most)*

G6 is the embedding-reuse gate from §E.3: over three files the MusiCNN embedding is **constructed
once and invoked exactly three times**, and each head invoked three times — tracing `__call__`, not
only `__init__`. It appears in J.4 and in none of your five slices.

This is not a bookkeeping slip. G6 is the only gate that catches the regression the planner exists to
prevent (one embedding constructed, then re-invoked per head), and §E.3 exists specifically because a
construction-count trace passes that bug unchanged. Assign it to **slice 3** — the behaviour it
constrains lives in the Python plan executor (A7).

### (c) G10 in slice 2 — only half of it can run there. *(split-gate)*

§E.4 requires the committed plan fixture to be asserted `eq` **from Ruby and parsed by Python**. The
Python parser is A7, slice 3. Slice 2 can only run the Ruby half. That half is not a tautology (the
generator is hand-run per E.4), so slice 2 is not wasted — but **do not mark G10 done at slice 2**.
Carry its Python-parse half as a slice-3 acceptance item. "Can fail on both sides" is the entire
reason E.4 was written that way.

### (d) G4 in slice 3 — its first clause belongs in slice 2. *(split-gate, optional)*

`plan_for([:bpm]).graphs` is empty is pure planner (A5) and is the natural falsifier for demand-driven
planning in slice 2. Only the second clause — empty models dir → 120 BPM ± tolerance on the click
train, dir still empty afterwards — needs real Essentia. Splitting costs nothing and gives slice 2 a
real assertion instead of a deferred one.

### (e) G4, G5, G19 in slice 3 have nowhere to run. *(consequence of Q4 finding 2)*

All three need real Essentia via the gem's `essentia_offline` job. **The gem has never had CI** —
verified: no `.github` directory in `/Users/lukeolson/projects/gems/mood_probe`, corroborated by §F.1.
If gem CI is first built in slice 5, these three run only on a developer machine during slice 3 and
are enforced nowhere until the end of Phase A. See Q4.

### (f) G19's fixture is unassigned. *(omission)*

G19 needs the **native 44.1 kHz click train from `generate.sh`** (J.2, R2). That fixture appears in no
slice. Put it in slice 3 alongside G19, or in slice 1 with the other fixtures. Without it G19 cannot
be written, let alone run.

### (g) G20 spans both repos and cannot be satisfied at one point. *(see Q5)*

"Gem CI green on all four jobs; app CI green on all five" is one checkbox covering two repos on
opposite sides of the tag boundary. Split into **G20-gem** and **G20-app**.

### Gates I checked and found correctly placed

G7, G8, G9, G13, G14, G16, G17, G18 in slice 2 — all pure Ruby or fake-double, all runnable, all with
a state in which they fail. G8 (`python_executable: "/nonexistent"`) exercises `preflight_environment!`
from A6; G9 exercises the demand-driven `ModelStore#verify!(filenames:)`. G11, G12, G15 in slice 3 —
correct; note G11 (`--capabilities`) prints before importing Essentia, so it runs in the gem's `rspec`
job, not `essentia_offline`. G2 in slice 4 — correct.

---

## Q2 — Does slice 1 actually protect G1's ordering?

**Yes — and it protects the part that is genuinely unrecoverable.**

The unrecoverable asset is the **bytes**, not the spec. Once `baseline_v0_1_0/` exists as a frozen
copy of today's `golden/*.json` in both repos, a wrong regeneration later is a *red gate*, not lost
evidence. That is exactly what §E.1 was written to buy, and slice 1 buys it.

Nothing in slices 2–5 rewrites a golden before slice 1 lands, given the slices are strictly sequential
and slice 1 is first. Three things must stay true:

1. **The gem-side freeze must land in the gem repo in slice 1**, not app-side only. The gem's goldens
   change shape at A8 (slice 3, rescale and `Features`/`HEADS` deleted). An app-only freeze means
   slice 3 destroys the gem's anchor with nothing to compare against. Your slice 1 says "both repos" —
   hold that line; it is load-bearing, per R1 and the fact that §F.3 makes the gem's `essentia_golden`
   job blocking.

2. **The retirement header must be inside the directory in slice 1**, not only in the design doc. §E.1
   says this explicitly and gives the reason: "the observed response to an obstacle with no documented
   exit is to remove the obstacle." Concrete hazard — J.3 item 11 rewrites
   `spec/fixtures/mood_probe/generate_goldens.rb` in slice 4. If that generator globs a directory
   pattern rather than the literal `golden/` path, it takes the baseline with it. **Check the
   generator's write scope explicitly excludes `baseline_v0_1_0/` when item 11 is reviewed.**

3. **Keep `baseline_v0_1_0/` a sibling of `golden/`, never under it.** Verified: `ci.yml:121` computes
   `expected=$(($(ls spec/fixtures/mood_probe/golden/*.json | wc -l) + 1))`. Nesting the new directory
   there breaks the example-count arithmetic inside the one slice that is supposed to be
   behaviour-free — the SF-1 interaction §E.1 warns about.

---

## Q3 — You have not misread E.1. Your reading is correct.

**Verified against the actual fixture.** `spec/fixtures/mood_probe/golden/clicks.json` contains
`"valence": 0.6057485342025757` — already 0..1 rescaled. `(0.6057 − 1.0) / 8.0 = −0.049`. G1's
algebraic clause is a **post-change** assertion and is arithmetically false today. Worse than false:
the payload has no raw-emomusic field at all yet, so the spec errors on a missing key rather than
failing on a value.

The mechanism, stated plainly so nobody re-derives it: **G1 is a fixture-to-fixture gate.** J.4's
"which gates run where" puts G1 in the pure-Ruby set — no Docker, no Essentia, no models dir. It reads
the current `golden/*.json` (which after slice 4 holds native emomusic) and compares it algebraically
against the frozen `baseline_v0_1_0/*.json` (which holds today's rescaled bytes forever). In slice 1
both directories are byte-identical rescaled copies, so there is nothing for the algebra to be true
about.

> **G1 first goes green in slice 4**, in the app repo, in the same commit that regenerates
> `golden/*.json` (J.3 item 11). **A red G1 in slices 1, 2 and 3 is expected, not a defect.**

**But do not commit G1 enabled in slice 1** — that is a knowingly-red app CI for three slices, which
trains the team to ignore it (Q4). J.1's "expect them in the first Phase A commit; treat their absence
as the flag" is about the **fixture freeze and the authorship** — both of which need no Essentia and
no Phase A code — not about a green assertion. The clean split:

- **Slice 1, commit I:** freeze `baseline_v0_1_0/` bytes + retirement header, both repos. The
  irreversible half.
- **Slice 4, commit B:** G1's spec file, in the **same commit** that regenerates the goldens.

Ordering is still fully protected, because the baseline predates the regeneration and is immutable. If
you want G1's spec text reviewed early, review it in slice 1 and land it in slice 4.

**Gem-side G1:** the gem's copy of the algebraic gate cannot go green until A8 lands (slice 3) *and*
the gem's goldens are regenerated — and the gem's golden regeneration needs `essentia_golden`, which
needs models and network. §E.1 says run it in both repos; it does not say simultaneously. Decide in
slice 3 whether the gem's copy lands there or with the tag slice.

---

## Q4 — Knowingly-red boundaries

**Three. One is fine, one is a hole rather than a red, one must change.**

### 1. Slice 2 → slice 3 in the gem: genuinely red, and acceptable if you merge once.

At the end of slice 2 the gem's Ruby side emits a `Plan` and takes `analyze(descriptors:)`, while
`mood_probe_extract.py` is still the v0.1.0 script that knows nothing about plans (A7/A8 are slice 3).
Every spec crossing the Ruby→Python seam is red at that boundary.

Right now this is invisible, because the gem has no CI — which is worse than red, not better.

**Recommendation: do not merge slices 2 and 3** — the two review chains are worth keeping, they cover
genuinely different risk (type/registry design vs. wire-boundary security). Land them as **two commits
on one gem branch, merged once.** Two reviews, one green merge, no red `main`.

### 2. The gem has no CI until slice 5. This is the real problem, and it is not a red — it is a hole.

Verified: `/Users/lukeolson/projects/gems/mood_probe` has no `.github`; §F.1 records zero commits ever
touching it. G20 is the only item in the plan that forces gem CI to exist, and you have scheduled it
last. That means **slices 2 and 3 — the two largest slices, carrying 15 of the 21 gates — land with no
automated enforcement in the gem repo at all.** Every gate in them is a human promise until slice 5.

**Move the gem's `rspec` and `lint` jobs into slice 1.** Per §F.3 both need no Docker and no network;
they are `bundle exec rspec` and `bundle exec rubocop`. They cost nothing, they are pure
infrastructure (so they belong in the I commit by your own I/B split), and they turn slices 2 and 3
into self-verifying slices. Leave `essentia_offline` for slice 3 — that is where G4/G5/G19 actually
need it — and `essentia_golden` for the tag slice. G20 then becomes a confirmation instead of a
discovery.

### 3. Slice 4's app commit cannot install. See Q5.

### Not a finding, stated so you do not worry about it

Slices 2–3 moving gem `main` does **not** break the app. Verified: `Gemfile.lock` pins
`revision: 5360f8fd8609eae39edb5dfab8a07f6439a0b137`, and CI installs from the lock.

The one thing that *could* break it is a weekly Dependabot bundler PR advancing that revision.
Verified: `.github/dependabot.yml` has a `bundler` entry, weekly, **with no `ignore`**. So J.3 item 7
is not hygiene — **it is the thing that stops slices 2 and 3 leaking into the app.** Slice 1 first is
correct and load-bearing. Land item 7 before any gem work merges to `main`.

Also verified: gem tag **`v0.1.0` already exists**. Slice 1's "gem tag v0.1.0" is already satisfied.
Confirm it is not re-pointed — J.5 step 2 rolls back to it.

---

## Q5 — Yes, it is inverted. Here is the correct order.

Slice 4 pins `Gemfile` to `tag: "v0.2.0"` and slice 5 creates the tag. `bundle install` fails outright
in slice 4, so slice 4's own CI cannot be green and **none of G1, G2 or G3 can run** — the three gates
that carry the entire "same six numbers" claim.

The rule: **the gem is finished and tagged before the app looks at it.**

| # | Slice | Repo | Contents | Gates |
| --- | --- | --- | --- | --- |
| 1 | Infrastructure | both | Freeze `baseline_v0_1_0/` + retirement header; dependabot `ignore`; app `ci.yml` fix; **gem `rspec` + `lint` jobs**. J.3 items 7, 8, 14. No behaviour change. | — (G1 *authored*, lands in 5) |
| 2 | Gem core | gem | A1–A6 | G4-planner-half, G7, G8, G9, G10-Ruby-half, G13, G14, G16, G17, G18 |
| 3 | Gem executor | gem | A7, A8, `essentia_offline` job, 44.1 kHz fixture | G4, G5, G6, G10-Python-half, G11, G12, G15, G19 |
| 4 | **Gem release** *(was 5)* | gem | `essentia_golden` job; NOTICE + fetch-time licence notice; **then tag `v0.2.0`** | G21, **G20-gem** |
| 5 | **App behaviour** *(was 4)* | app | A9, A10, the 15 files, `Gemfile` → `tag: "v0.2.0"` | G1, G2, G3, **G20-app** |

Slices 2 and 3 as two commits on one gem branch, one merge (Q4 finding 1).

**Split G20** into G20-gem (step 4) and G20-app (step 5). It is the only gate that spans both repos,
and no correct ordering can satisfy it at a single point.

**If the app work must start before the gem is tagged:** the only safe interim pin is the gem **commit
SHA**, with the flip to `tag: "v0.2.0"` as the final edit in the app's behaviour commit. Do not leave
`branch: "main"` in place while gem `main` is moving — that is the one configuration where an
unrelated `bundle install` silently changes app behaviour, and it is precisely the mis-paired-deploy
failure the boot initializer (A9, M3(2)) exists to catch after the fact.

---

## Summary of required changes

| Change | Slice affected | Why |
| --- | --- | --- |
| Remove G3 from slice 2 | 2 | Mapper does not exist until the app slice |
| Assign G6 to slice 3 | 3 | Currently unassigned; only gate catching per-head re-invocation |
| Mark G10 complete only at slice 3 | 2, 3 | Python half is the point of E.4 |
| Add the 44.1 kHz click-train fixture | 3 | G19 cannot be written without it |
| Move gem `rspec` + `lint` CI to slice 1 | 1 | Slices 2–3 otherwise have zero enforcement |
| Add gem `essentia_offline` to slice 3 | 3 | Where G4, G5, G19 actually run |
| Swap slices 4 and 5; split G20 | 4, 5 | Tag must precede the pin |
| Land G1's spec in the app slice, not slice 1 | 1, 5 | Avoids three slices of knowingly-red CI |
| Split G4 into planner-half / Essentia-half | 2, 3 | Optional; gives slice 2 a real assertion |

---

## Evidence

- Read `docs/superpowers/specs/2026-08-10-essentia-gem-generalization-design.md` §E.1–E.4, §F.1–F.4,
  §J.1–J.5 in full (branch `docs/essentia-gem-v2-design`).
- Read `spec/fixtures/mood_probe/golden/clicks.json` — `valence: 0.6057485342025757`, confirming
  today's goldens are 0..1 rescaled (Q3).
- Read `.github/workflows/ci.yml:105-123` — confirmed the `ls .../golden/*.json | wc -l` example-count
  arithmetic (Q2 finding 3).
- Read `.github/dependabot.yml` — bundler entry present, no `ignore` (Q4).
- Read `Gemfile:34` (`branch: "main"`) and `Gemfile.lock:2-6` (`revision: 5360f8fd…`) (Q4, Q5).
- `git -C /Users/lukeolson/projects/gems/mood_probe tag` → `v0.1.0` only; `ls -a` → no `.github`,
  confirming §F.1's "mood_probe has never had CI" (Q1e, Q4).
- `maestri list` for team composition.
- No file in either repo modified; all commands read-only.
