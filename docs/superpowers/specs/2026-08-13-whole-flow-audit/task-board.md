# TASK BOARD — SONANCE-MAIN-AUDIT — COMPLETE

Critical review of the whole flow, OFF MAIN in both repos. Tier 1.
GEM main d514137 · APP main b26cf31 (local 1f8ad78, tree byte-identical — verified).
Suites: gem 194/0, app 298/0 (after assets:precompile). Both repos clean and unchanged at finish.

## THE THREE ANSWERS

Q1 IS ESSENTIA PROPERLY PORTED TO RUBY — PORTED WITH RESERVATIONS (Keystone).
   Reframed honestly: nothing is ported. Zero Ruby DSP. It is a planner + marshaller driving a
   Python subprocess. The answerable question is whether the BINDING is faithful. It is:
   float32 42dd359f widens to float64 405ba6b3e0000000 and round-trips through JSON unchanged.
   No rescale, no rounding, no narrowing anywhere in the gem.

Q2 IS IT PLUGGED INTO VIBE-DOCTOR CORRECTLY — YES (Code Reviewer).
   22-point integration inventory DERIVED from code, method stated and reproducible.
   Normalization applied EXACTLY ONCE. 4 fixtures x 6 columns = 24/24 bit-identical to the
   frozen v0.1.0 baseline. No double-normalization, no dead rescue, no descriptor-id drift.

Q3 IS IT DEPLOYABLE WITHOUT DEPLOYING THE GEM — YES, WITH CONDITIONS (Rivet).
   Proven, not read: real no-cache linux/amd64 build ON THE CONFIGURED HETZNER REMOTE BUILDER,
   then the final image booted under --network none with the registry assertion passing.
   Runtime image has the gem at /usr/local/bundle, no git binary, no .git metadata.

## VERDICTS

| Who | Verdict | File |
|---|---|---|
| Keystone Principal | PORTED WITH RESERVATIONS (F1 dup extractor, F2 reduce lock-in, F3 coverage) | principal.md |
| Plumb Spec | REQUEST-CHANGES (CLI analyze emits inspect strings; its spec cannot see it) | spec.md |
| Code Reviewer | INTEGRATION CORRECT — YES | quality.md |
| Rivet Implementer | DEPLOYABLE — YES WITH CONDITIONS | implementer.md |
| Warden Security | APPROVE-WITH-FINDINGS (unbounded subprocess stdout/stderr) | security.md |
| Litmus Test | PARTIALLY — four gates cannot fail | test.md |

## MY ADJUDICATION OF THE ONE REVIEWER DISAGREEMENT — resolved by my own execution

Litmus F1 rated the half-directional softmax clamp HIGH; Code Reviewer rated the same clamp
INFORMATIONAL, arguing it is structurally unreachable. Both descriptions are correct; the
severities are not both correct. I ran it myself, with a passing control:

  danceability_musicnn range_kind=hard sanity=0.0..1.0
  value -0.1 -> REJECTED Sonance::MalformedOutputError: outside sanity range 0.0..1.0
  value  1.1 -> REJECTED Sonance::MalformedOutputError: outside sanity range 0.0..1.0
  value  0.5 -> ACCEPTED (0.5)                                    <- passing control

mood_grounding_service.rb:115 feeds the mapper analysis.to_h.transform_values(&:value), so every
value has ALREADY passed Scalar validation. Litmus's stated scenario — Essentia emitting a slightly
negative danceability — therefore CANNOT reach the half-clamp; it raises MalformedOutputError, a
TrackError, which the service already rescues at :116/:129. RULING: F1 is a real GATE gap but
MEDIUM, not HIGH. Its risk is entirely contingent on the gem loosening range_kind: :hard.
The mapper's own comment at :16-17 documents exactly this contract.

## MY OWN FINDING — no reviewer was scoped to it

RUNTIME MODEL DOWNLOAD IS UNRECORDED AND EPHEMERAL.
models_dir defaults to Rails.root/tmp/essentia_models (enrich_album_job.rb:6,
mood_grounding_service.rb:11, enrichment.rake:19,32). deploy.yml sets no ESSENTIA_MODELS_DIR and
its only volume is vibe_doctor_storage:/rails/storage — so /rails/tmp is NOT persisted.
ModelStore downloads from essentia.upf.edu (DOWNLOAD_HOST allowlist) with SHA-256 verification.
CONSEQUENCE: every deploy re-downloads ~3.6 MB of models on first enrichment, and THE RUNNING
CONTAINER NEEDS OUTBOUND HTTPS TO essentia.upf.edu — a runtime external dependency nobody recorded.
Rivet's --network none test booted Rails but did NOT run an extraction, so it does not cover this.
Cheap (3.6 MB, digest-verified) but it should be a declared volume + a recorded dependency.

## CROSS-REPO STRUCTURAL FACT

v0.3.0 is NOT an ancestor of gem main (squash merge orphaned it); v0.2.0 likewise — it is the repo
PATTERN, not a one-off. Keystone's ruling: do NOT re-tag, do NOT rewrite history; not a
deployability defect. I confirmed unauthenticated ls-remote returns v0.3.0 -> cf8e613 -> 6639397,
matching Gemfile.lock exactly. Two real hazards Keystone proved: clone --single-branch fetches only
v0.1.0 and checkout v0.3.0 FAILS; --depth 1 fetches no tags.
Remedy: tag AFTER squash-merge from now on; do not delete origin/feat/essentia-gem-v2-phase-a
until repinned; record the v0.3.0 -> 6639397 mapping in CHANGELOG.md.

## RANKED OPEN ITEMS — none blocks the deploy

1. CLI analyze emits object inspect strings at exit 0 (Plumb H1) + its spec structurally cannot
   observe it (H2). Library path unaffected, so the APP is not at risk.
2. Unbounded subprocess stdout/stderr read (Warden) — memory exhaustion driven by the subprocess.
3. Three gates that cannot fail: wholly-stale descriptor array (Plumb 3 == Litmus F2, found
   independently); NaN seam guard deletion (Litmus F3); app has no canonical-environment guard
   (Litmus F4, root cause: gemspec ships lib/exe/python only, so the app cannot reuse the gem's).
4. Directional clamp coverage (Litmus F1, downgraded to MEDIUM by my adjudication above).
5. Duplicate descriptor lists in the app checked by nothing (Litmus F5) — the shipped-twice-in-
   sibling-files mode is STILL LIVE.
6. Declare ESSENTIA_MODELS_DIR + a volume; record the essentia.upf.edu runtime dependency (mine).
7. Keystone F1 duplicate RhythmExtractor2013 instance, 1.67x wall clock — not triggered by the app.

## CARRYOVER

- Prior review record under docs/superpowers/specs/.../whole-branch/ STILL UNTRACKED in the app.
- These reports live in /tmp and will not survive a session clear.
- Local gem directory still named mood_probe. RubyGems publication still a separate decision.

## 2026-08-14 — OWNER DECISION: MAKE THE GEM A THIN BINDING

Owner: "we should also fix 1-3. in the future we can support more algorithms if it makes sense."
The three DOMAIN opinions are being removed. The three SECURITY controls (static algorithm enum,
parameter whitelist, model host allowlist) STAY — a design that weakens them is a failed design.

ISSUES FILED — 16 total, all on milestone "Pre-deploy hardening" in both repos.
  GEM  Lhosb/sonance  #5 CLI inspect strings · #6 unbounded subprocess reads · #7 id-gate blind spot
       #8 NaN guard untested · #9 reduce mandate · #10 two descriptors never met real Essentia
       #11 duplicate RhythmExtractor2013 · #12 ship env guard · #13 tag ancestry + CHANGELOG
       #14 registry extensibility (NEW) · #15 sanity_range fatality (NEW)
  APP  Lhosb/vibe-doctor  #23 models re-downloaded every deploy · #24 directional clamp coverage
       #25 duplicate descriptor lists · #26 no env guard · #27 commit the review record

THE ONE ORDERING THAT CANNOT BE INVERTED — recorded on BOTH issues:
  vibe-doctor#24 MUST land BEFORE sonance#15.
  Today the app's four softmax clamps are unreachable dead code ONLY because the gem vetoes
  out-of-range values first (I verified: -0.1 and 1.1 REJECTED, 0.5 ACCEPTED as control).
  sonance#15 removes that veto. If #15 lands first there is a window where NEITHER side guards
  the range, and the only backstop is MoodVector numericality at save — which fails the record
  rather than clamping, with no DB check constraint behind it.
  I raised #24 from MEDIUM to HIGH and reclassified it from parallel task to hard prerequisite.

SECOND-ORDER EFFECT the design must reckon with: MalformedOutputError is a TrackError the app
rescues at mood_grounding_service.rb:116 and :129. Stop raising it and a SKIPPED TRACK silently
becomes a save-time validation failure — a behaviour change in the consumer caused by a gem change.

TIER 1 PATH: Principal designs BEFORE implementation. Keystone dispatched for the thin-binding
design covering #9/#14/#15 — asked for judgement and a single defended choice per item, not
options side by side, plus the cross-repo landing order and the version. NOT YET IMPLEMENTING.

MY SCOPE FLAG TO THE OWNER: of the 16 issues, only vibe-doctor#23 (models) is genuinely
deploy-blocking. The rest are correct-today-but-unprotected, or CLI-only. He was told this.

vibe-doctor pins tag v0.3.0, so the app is INSULATED from all gem work until deliberately repinned.
