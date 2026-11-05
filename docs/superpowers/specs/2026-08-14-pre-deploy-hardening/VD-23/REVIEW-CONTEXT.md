# VD-23 REVIEW CONTEXT — read this first, then your discipline-specific dispatch

TIER 1. The only genuinely deploy-blocking issue on the Pre-deploy hardening milestone.

REPO: /Users/lukeolson/projects/vibe-doctor  — use `git -C`, do not `cd`
BASE_SHA: 5c9dfccda17ccf26af5267d099a391e3b2e882a8  (origin/main)
HEAD_SHA: 24e17798dc386d794c8dc032360a31e754350e33
BRANCH: fix/fetch-models-at-build-time — worktree at .worktrees/fetch-models-at-build-time. NOT pushed.
Diff: git -C /Users/lukeolson/projects/vibe-doctor diff 5c9dfcc...24e1779

Implementer report: /tmp/maestri-reviews/VD-23/implementer.md
READ IT FIRST, including the appended CORRECTION section. Absence from the diff is not absence
of evidence.

Issue: `gh issue view 23 --repo Lhosb/vibe-doctor --comments`
It has FOUR comments and only the LATEST state is true. Earlier claims — that models are
re-downloaded every deploy, or that the models directory is empty in production — are BOTH WRONG
and corrected in place. Read to the end before forming a picture.

## What changed

- The six Essentia `.pb` model binaries removed from the tracked tree via `git rm --cached`.
  The blobs REMAIN in git history, deliberately. No history rewrite is authorized.
- The `.gitignore` / `.dockerignore` negation blocks that re-included them are removed.
- The Dockerfile fetches models at BUILD time via the gem CLI into `/usr/local/essentia-models`,
  and runs models verify in the FINAL stage as uid 1000 — validating digests, ownership and mode
  exactly as the runtime user sees them.
- Root LICENSE (MIT) and NOTICE added; NOTICE reworded so it remains TRUE now that the files are
  out of the working tree but still in history.

## Established, verified, do not re-litigate

- The models ARE in the production image today and enrichment works. This change moves where they
  come from; it does not fix a broken runtime.
- The builder 5.78.177.23 HAS egress to essentia.upf.edu — confirmed `HTTP/1.1 200 OK`.
- `ConfigurationError` stays FATAL and unrescued. Accepted decision.
- Corrected suite: 298 examples, 0 failures. I re-ran it myself and confirm 298/0.

## TRAP 1 — already sprung once, do not repeat it

The implementer first reported 7 system-spec failures as "pre-existing on origin/main". They were
NOT. The cause was an empty `app/assets/builds/` in a fresh worktree: with no built Tailwind the
chart JS never renders and every `vibe_map` spec fails with element-not-found.

If you see those 7, run `bundle exec rails tailwindcss:build` rather than labelling them.
More generally: never label a failure "pre-existing" without running the base yourself and pasting
both results side by side.

## TRAP 2 — the judgement that matters most in this review

The OLD configuration PASSES models-verify under `--network none`, because the models really are
present in the image today. **So a passing build proves nothing.**

The discriminating evidence is the SABOTAGE PAIR the implementer produced on the real amd64
builder — with the `.dockerignore` negations removed:

- OLD: build exits 0, image contains ZERO models, fails only at first enrichment.
- NEW: build exits NON-ZERO, no image produced.

Scrutinize that pair. **If you think it does not discriminate, say so** — that is the single most
important judgement here.

## Rules for all reviewers

- Review from YOUR discipline only. Three of you run in parallel; I do not want three copies of
  the same report.
- Read-only. Do not fix anything. Do not commit. Do not push. Do not open a PR.
- EVIDENCE SECTION MANDATORY: diff range, commands run, output pasted. A verdict without evidence
  is rejected.
- State plainly what you could NOT verify and why. This machine is arm64 and cannot run the
  Essentia toolchain — say so rather than guessing.
- VERDICT: APPROVE or REQUEST-CHANGES, findings rated, each tied to file:line.
- Write your report EARLY and append section by section. A partial file on disk beats a complete
  one that never lands.
- Reply via ask-back ONLY, one report, no duplicate summary.
