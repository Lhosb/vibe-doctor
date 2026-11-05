# Pre-Deploy Hardening Milestone — Review Record (2026-08-14)

This directory holds the raw review reports for the pre-deploy hardening milestone,
executed on 2026-08-14 across two repositories: `Lhosb/vibe-doctor` and `Lhosb/sonance`.

---

## What Shipped

### vibe-doctor (Lhosb/vibe-doctor) — merged to main at ff67619

| Issue | Description | Tier | PR |
|-------|-------------|------|----|
| #27   | Persist pre-deploy review records (docs only) | 3 | #32 |
| #24   | Full softmax clamp coverage — mutation-verified | 2 | #32 |
| #29   | Root LICENSE (MIT) and NOTICE for Essentia model attribution | 2 | #31 |

### sonance gem (Lhosb/sonance) — merged to main at 967709b

| Issue | Description | Tier | PR |
|-------|-------------|------|----|
| #19   | Licence URIs and per-model source URLs in gem NOTICE | 3 | #20 (squash with #17) |
| #17   | Pin Python/numpy stack; build-environment guard | 2 | #20 (squash with #17) |
| #5    | Serialize descriptor values as JSON; fix CLI spec blindness | 2 | #23 |
| #6    | Bound subprocess stdout/stderr reads; document chunking | 2 | #23 |

### In review (Tier 1, awaiting owner sign-off)

- **vibe-doctor issue #23** — Fetch Essentia models at build time; remove binaries from tracked tree.
  Branch: `fix/fetch-models-at-build-time`, HEAD `cdc6dcb`. Draft PR #33. Security, Spec, and Test
  approved. Code Quality approved. Owner sign-off required before merge (Tier 1 policy).

---

## Reviewer Verdicts Per Issue

Derived from the report files in this directory.

### vibe-doctor #27 and #24 (VD-27-24/)

Reviewed together in a single dispatch (two commits, one branch).

- **Spec (Plumb):** APPROVE — both commits. #27 Tier 3 no re-tier needed; #24 Tier 2 approved.
- **Code Quality (Code Reviewer):** APPROVE — both commits.

### vibe-doctor #29 (VD-29/)

Three implementation rounds (attribution, addendum with MIT licence, follow-up adding URIs).
A further correction (AGPL bundling disclosure, round 3) was required after Spec review found
that "not bundled with" was false of the deployed image.

- **Spec (Plumb):** APPROVE on NOTICE and README at `cdc6dcb` (post-rebase tip). All claims true.

### vibe-doctor #23 (VD-23/) — IN REVIEW

Two rounds of REQUEST-CHANGES before approvals.

- **Spec (Plumb):** REQUEST-CHANGES (round 1, five findings) → APPROVE at `6df28b9` (round 2,
  all six findings F1–F6 closed). Further APPROVE at `cdc6dcb` on NOTICE/README.
- **Test (Litmus):** REQUEST-CHANGES (round 1) → APPROVE at `6df28b9` (round 2).
- **Security (Warden):** APPROVE (all findings non-blocking/cosmetic).
- **Code Quality (Code Reviewer):** APPROVE — no critical findings; cosmetic nits listed as
  non-blocking. Merge pending owner sign-off (Tier 1).

### sonance #17 and #19 (SON-17-19/)

Issued together, one branch, two commits.

- **Test (Litmus):** REQUEST-CHANGES (round 1, F1–F6 spec non-vacuity findings) → APPROVE (round 2,
  all mutation batteries RED then GREEN).
- **Code Quality (Code Reviewer):** APPROVE — one informational numeric discrepancy noted, not a
  code defect.
- **Principal (Keystone):** APPROVE — base image digest, layer ordering, and apt-pin rejection all
  endorsed. One must-fix on constraints.txt python3 version record (metapackage vs real interpreter)
  — corrected and re-approved.

### sonance #5 and #6 (SON-5-6/)

Implemented by Keystone. Reviewed after one REQUEST-CHANGES round.

- **Spec (Plumb):** APPROVE — both issues satisfied as written, including literal verification clauses.
- **Test (Litmus):** APPROVE — both mutation batteries reproduce; self-reported failures real, fixed,
  and gated. One numeric discrepancy (194 → 208 count) investigated and explained (one example
  removed and its coverage preserved in new form).
- **Code Quality (Code Reviewer):** APPROVE — finding is informational only; not held.

---

## Corrections

The following premise corrections were made during the work. They are recorded here because they
represent places where the initial brief or an early analysis was wrong, and the error was caught by
execution or reviewer analysis rather than by the original author.

**Issue #23 mechanism — wrong twice.** The initial brief said models were re-downloaded every deploy
and that the models directory was empty in production. Both were false: the six `.pb` files were
tracked in git and reached the production image via `COPY . .` in the Dockerfile; enrichment was
working. The true defect was future brittleness and licence exposure, not a broken current state. The
correction is documented in VD-23/implementer.md and VD-23/correction.md.

**Issue #16 reduce/take frame-count rule.** The original framing of issue #16 described a rule about
frame counts that was incorrect as a general rule. The correction and its sequencing implications are
recorded in SON-17-19/issue16-sequencing.md.

**models_dir call-site enumeration — missed spec/.** The four production call sites were correctly
identified. Two additional call sites in `spec/integration/essentia_extract_golden_spec.rb` and
`spec/fixtures/sonance/generate_goldens.rb` were missed in the initial sweep (grep covered `app/` and
`lib/` only, not `spec/`). The green suite was not evidence that these were correct — the golden spec
is `:essentia`-tagged and excluded from the standard run. Found and fixed in VD-23 round 2.
See VD-23/spec.md (F3) and VD-23/implementer.md (round 2, Fix 2).

**Three reviewer findings withdrawn or self-corrected.** The Dockerfile verify-comment overclaim (Fix 4
in VD-23) was found by Spec, then refined by Litmus's deeper analysis of `model_store.rb` (directory
vs file ownership checks). Litmus corrected the finding in their own report. The VD-23 Spec round-2
approval was issued against the wrong SHA (`29c94bb` vs `6df28b9`) and corrected inline in
VD-23/spec-round2.md and VD-23/spec-round3.md.

---

## Still Open

- **vibe-doctor #23** — Tier 1, owner sign-off pending. PR #33 at `cdc6dcb`.
- **sonance #21, #22** — follow-up issues deliberately left open; not in scope for this milestone.
  See SON-5-6/issue-stderr-drain.md and SON-5-6/issue-terminate-eperm.md.

---

## Earlier Record

The immediately preceding review record (Phase A generalization, 2026-08-13) is at:
`docs/superpowers/specs/2026-08-13-whole-flow-audit/`
