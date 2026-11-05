# VD-29 Implementer Report — Model Attribution Notice

## Status: DONE

---

## Identifiers

- BASE_SHA: `5c9dfccda17ccf26af5267d099a391e3b2e882a8`
- HEAD_SHA: `339796fce22fa7df997bb21f043bb0bd1597ae00`
- Branch: `fix/model-attribution-notice`

---

## What was implemented

**Issue #29 — partial scope: attribution only, no binary removal.**

Three files changed in one commit (`339796f`):

| File | Change |
|------|--------|
| `LICENSE` | Created (new) — MIT licence, copyright Luke Olson 2026, 21 lines |
| `NOTICE` | Created (new) — model + Essentia attribution, 29 lines |
| `README.md` | Appended `## Licences` section, 6 lines |

### LICENSE filename rationale

Gem uses `LICENSE.txt`. GitHub license detection recognises both `LICENSE` and `LICENSE.txt`.
Plain `LICENSE` (no extension) was chosen — more conventional for Ruby/Rails applications and
GitHub displays it prominently in the repo sidebar either way.

### NOTICE — key wording decisions (per addendum)

- Opening sentence explicitly scopes MIT to "this repository's own application code only".
- Explicitly names the two other licences: CC BY-NC-ND 4.0 (models) and AGPL-3.0 (Essentia).
- States plainly that MIT does NOT relicense those components.
- States as architectural fact (not legal opinion): "Essentia is invoked as a separate subprocess
  at runtime; it is not linked into or bundled with the application."
- Records that this application is non-commercial — owner's decision (addendum).
- Retains gem NOTICE language about MTG page conflict between ShareAlike and NoDerivatives terms,
  with compliance floor CC BY-NC-ND 4.0 under either reading.

---

## Six model file paths — derived from git, not transcribed

Command:
```
git -C <wt> ls-tree -r --name-only origin/main | grep '\.pb$'
```

Output:
```
tmp/essentia_models/danceability-msd-musicnn-1.pb
tmp/essentia_models/emomusic-msd-musicnn-2.pb
tmp/essentia_models/mood_acoustic-msd-musicnn-1.pb
tmp/essentia_models/mood_happy-msd-musicnn-1.pb
tmp/essentia_models/mood_relaxed-msd-musicnn-1.pb
tmp/essentia_models/msd-musicnn-1.pb
```

These six paths appear verbatim in NOTICE. No manual transcription.

---

## .pb confirmation

```
git diff --stat HEAD -- '*.pb'
```
(empty — no .pb file added, removed, or modified)

---

## Verification

### Full app suite (committed HEAD, post-addendum):
```
298 examples, 0 failures
```
Exit code: 0

### RuboCop:
```
207 files inspected, no offenses detected
```
(Ruby files only — `--only-recognized-file-types`. README.md produces 73 pre-existing
parse errors when passed to RuboCop directly; that is unchanged from `origin/main` and
is a pre-existing condition unrelated to this task. No new offenses introduced.)

### Brakeman: 0 warnings (verified on prior run; no code was changed in this task)

### No Dockerfile or deploy.yml changes:
```
git diff --stat HEAD -- config/deploy.yml Dockerfile
```
(empty)

---

## RISK TRIGGERS TOUCHED

NONE — no schema migration, no auth logic, no money/binding documents, no new data-exposure
surface, no destructive operations, no security config changes, no new Ruby dependencies.
New files are plain text (LICENSE, NOTICE) and a README section.

---

## Follow-up: Licence URIs + source URLs + #23 coupling note

**HEAD_SHA (after follow-up):** `a046b69f3fdbcc5a31427f1c07bb3026ba78acae`
Commit: `a046b69` — "Add licence URIs and per-model source URLs to NOTICE; note #23 coupling"

### Changes made to NOTICE

1. **CC BY-NC-ND 4.0 URI added:** `https://creativecommons.org/licenses/by-nc-nd/4.0/`
2. **AGPL-3.0 URI added:** `https://www.gnu.org/licenses/agpl-3.0.html`
3. **Per-model source URLs added** — derived from registry (see below)
4. **"committed to this repository" wording replaced** with a sentence that explicitly flags the #23 coupling — states the list must be revisited when issue #23 lands and the tracked binaries are removed
5. "model binaries" → "model files" (more neutral; survives the download-at-build model too)

### source_url derivation

Command:
```
grep -A 2 'source_url:' /Users/lukeolson/projects/gems/mood_probe/lib/sonance/registry.rb
```

The six `source_url` values extracted (all under `https://essentia.upf.edu/models/`):
```
msd-musicnn-1.pb
  → https://essentia.upf.edu/models/feature-extractors/musicnn/msd-musicnn-1.pb

danceability-msd-musicnn-1.pb
  → https://essentia.upf.edu/models/classification-heads/danceability/danceability-msd-musicnn-1.pb

mood_acoustic-msd-musicnn-1.pb
  → https://essentia.upf.edu/models/classification-heads/mood_acoustic/mood_acoustic-msd-musicnn-1.pb

mood_relaxed-msd-musicnn-1.pb
  → https://essentia.upf.edu/models/classification-heads/mood_relaxed/mood_relaxed-msd-musicnn-1.pb

mood_happy-msd-musicnn-1.pb
  → https://essentia.upf.edu/models/classification-heads/mood_happy/mood_happy-msd-musicnn-1.pb

emomusic-msd-musicnn-2.pb
  → https://essentia.upf.edu/models/classification-heads/emomusic/emomusic-msd-musicnn-2.pb
```
All six paths differ — no two models share a common leaf path — so each is cited individually in NOTICE alongside the common base URL `https://essentia.upf.edu/models/`.

### Verification (all three gates)

- **bundle exec rspec:** 298 examples, 0 failures
- **bin/rubocop --only-recognized-file-types:** 207 files inspected, no offenses detected
- **bin/brakeman:** No warnings found
- **git diff --stat HEAD~ -- '*.pb':** (empty — no .pb files touched)
- **git diff --stat HEAD~ -- config/deploy.yml Dockerfile:** (empty)

### Process note acknowledged

Brakeman was omitted from the previous report despite being a required gate. Understood — all three gates (rspec, rubocop, brakeman) will be reported with numbers going forward.

RISK TRIGGERS TOUCHED: NONE

---

## ROUND 3 — NOTICE bundling disclosure (2026-08-14)

**New HEAD_SHA: 847178b** (pushed to origin/fix/model-attribution-notice — PR #31 updated)
**Previous HEAD: a046b69**

### The fix

Derived from Dockerfile:28-29:
- Install path: `/usr/local/essentia-venv` (created by `python3 -m venv /usr/local/essentia-venv`)
- Version: `essentia-tensorflow==2.1b6.dev1389`

NOTICE:12-13 changed from:
> Essentia is invoked as a separate subprocess at runtime; it is not linked into
> or bundled with the application. This is an architectural fact…

To:
> Essentia is invoked as a separate subprocess at runtime; it is not linked into
> the application. The essentia-tensorflow distribution (version 2.1b6.dev1389,
> AGPL-3.0) is installed into the deployed image at /usr/local/essentia-venv.
> This is an architectural fact…

Accurate part retained; false "not bundled with" removed; plain disclosure added.
Only file changed: NOTICE.

### Gates

**RSpec:** 298 examples, 0 failures  
**RuboCop:** 207 files inspected, no offenses detected  
**Brakeman:** No warnings found  

### Note for sequencing

The #23 branch (`fix/fetch-models-at-build-time`, tip 6df28b9) is stacked on the old attribution branch tip (a046b69). It will need rebasing onto 847178b before merge. Per dispatch instructions, I am NOT doing that rebase — flagging for sequencing.

