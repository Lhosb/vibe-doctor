# VD-23 — Re-review round 2 (test/gate discipline)

# VERDICT: **APPROVE** — applies to **6df28b9c464236d764674cf26182945b679be381**

**T1, T3, T4 and T5 are CLOSED. T2 is CLOSED.** One of my round-1 findings — **T4 — was WRONG, and I
withdraw it**; the current comment is accurate and I verified every claim it makes by execution. No
fix-induced regression found.

**SHA statement, since it determines the T4 verdict:** my verdict applies to **`6df28b9`**, the live
branch tip and worktree HEAD. I detected the `29c94bb`/`6df28b9` divergence independently at the start
of this review — before the dispatch correction arrived — and everything I read came from the worktree,
which is at `6df28b9`. No rework was needed. Details in §0.

Range reviewed: `a046b69...6df28b9`, one commit. Scope: T1/T2/T3/T4/T5 and fix-induced regressions.

| Round 1 | Round 2 |
|---|---|
| T1 HIGH — golden CI gate broken by hardcoded path | **CLOSED** — fix complete; all 8 readers derived repo-wide |
| T2 MEDIUM — generator hardcoded path | **CLOSED** |
| T3 MEDIUM — cache comment backwards; fetch every deploy | **CLOSED** — structurally correct, evidence sound |
| T4 LOW — comment overclaims | **WITHDRAWN — my finding was wrong** |
| T5 LOW — literal vs variable | **CLOSED** |

One scope-routing observation in §6 that is not a finding but needs an owner.

---

## 0. SHA divergence — found independently, and it is load-bearing

Before reading the correction I ran:

```
$ git rev-parse fix/fetch-models-at-build-time
6df28b9c464236d764674cf26182945b679be381
$ git merge-base --is-ancestor 29c94bb 6df28b9
NO
$ git log --format="%H %P" -1 29c94bb   ->  parent a046b69
$ git log --format="%H %P" -1 6df28b9   ->  parent a046b69     # two children, same parent = amend
$ git diff --stat 29c94bb 6df28b9
 Dockerfile | 5 +++--
$ git rev-parse 29c94bb^{tree} 6df28b9^{tree}
6d8d8e6ba28a0d69ec736cd5c4fab0a108a32970
6da67ffbc5efdfe9f453fd6152d6aeaeb039e764      # trees DIFFER
```

The trees differ, and the difference is **in the Dockerfile** — the exact file T3/T4/T5 concern. So the
choice of SHA is not pedantry here, and the dispatch's own read is right. The diff:

```diff
-# Verify model digests by opening each file as uid 1000, exactly as enrichment will.
-# (verify checks digests via SHA-256; readability by uid 1000 is implicitly confirmed.)
+# Verify model digests and the models directory's ownership and mode, as the runtime user.
+# (Individual model files: digest, presence, regular-file, and anti-symlink checks.
+#  Models directory: uid ownership and write-permission checks.)
```

`29c94bb` **underclaims**; `6df28b9` is **accurate** (proven in §3). Reviewing the stale SHA would have
produced the wrong verdict on T4 — in the direction of approving a comment that understates a gate.

---

## 1. T1 — is the fix complete and correct? **YES**

### The fix

```ruby
spec/integration/essentia_extract_golden_spec.rb:19
  MODELS_DIR = Pathname(ENV.fetch("ESSENTIA_MODELS_DIR", ROOT.join("tmp/essentia_models").to_s))
spec/fixtures/sonance/generate_goldens.rb:9
  models_dir = Pathname(ENV.fetch("ESSENTIA_MODELS_DIR", root.join("tmp/essentia_models").to_s))
```

**Fallback is right** — it reproduces the previous literal exactly, so nothing that used to work
locally changes. **Type is preserved**: both were `Pathname` before (`ROOT.join(...)`) and both are
`Pathname` now via the explicit wrapper, so `Sonance::Extractor.new(models_dir:)` sees the same class.
That matters because `ENV.fetch` returns a String and an unwrapped value would have changed the type.
Verified both branches by execution:

```
with ENV set   -> /usr/local/essentia-models (Pathname)
with ENV unset -> …/.worktrees/fetch-models-at-build-time/tmp/essentia_models (Pathname)
```

### Does the golden spec now actually resolve models inside the image? **Yes**

Three links, each checked:

1. `Dockerfile:38` sets `ESSENTIA_MODELS_DIR="/usr/local/essentia-models"` in the **base** stage, so the
   **final** stage inherits it and it is present in the image environment.
2. The CI job does **not** clobber it — it passes only two `-e` flags:
   ```
   .github/workflows/ci.yml:121-124
     docker run --rm --platform linux/amd64 --entrypoint bash \
       -e ESSENTIA_SPECS=1 -e RAILS_ENV=test \
       vibe-doctor-essentia-goldens /rails/bin/essentia-ci
   ```
3. `bin/essentia-ci` neither sets nor unsets it; it runs `bundle exec rspec … --tag essentia`.

So inside the image `MODELS_DIR` resolves to `/usr/local/essentia-models`, which is the path the COPY
at `:86` populates and the verify at `:91` attests. **The gate I predicted would break is restored.**

### Any OTHER reader still missed? **No — derived repo-wide, all 8 sites**

The round-1 miss happened because the derivation was scoped to `app/` and `lib/`. I widened it to every
extension and directory, including `bin/` and `.github/`:

| Site | Mechanism | Status |
|---|---|---|
| `app/jobs/enrich_album_job.rb:6` | `ENV.fetch` + fallback | ✔ |
| `app/services/mood_grounding_service.rb:11` | `ENV.fetch` + fallback | ✔ |
| `lib/tasks/enrichment.rake:19` | `ENV.fetch` + fallback | ✔ |
| `lib/tasks/enrichment.rake:32` | `ENV.fetch` + fallback | ✔ |
| `spec/integration/essentia_extract_golden_spec.rb:19` | `ENV.fetch` + fallback | ✔ **fixed** |
| `spec/fixtures/sonance/generate_goldens.rb:9` | `ENV.fetch` + fallback | ✔ **fixed** |
| `spec/integration/essentia_empty_models_spec.rb:10,20` | `Dir.mktmpdir` — self-contained | ✔ unaffected |
| `spec/jobs/enrich_album_job_spec.rb:100,106` | `Dir.mktmpdir` — self-contained | ✔ unaffected |
| `Dockerfile:62,91` | `$ESSENTIA_MODELS_DIR` | ✔ (T5) |

`bin/` and `.github/` contain no models-dir reference. The two `Dir.mktmpdir` sites I checked rather
than assumed — they build their own directory and never touch the removed path. **No remaining
hardcode.**

---

## 2. T3 — the fetch move, and the question you most wanted answered

### Does the fetch now run before anything it needs? **No — everything it needs precedes it**

Checked each dependency rather than assuming:

| Need | Satisfied at | Verified |
|---|---|---|
| Gems installed (incl. `sonance`) | `:53` `RUN bundle install` | ✔ precedes `:62` |
| `Gemfile` / `Gemfile.lock` for `bundle exec` | `:51` `COPY Gemfile Gemfile.lock ./` | ✔ |
| `vendor/*` | `:50` | ✔ |
| `$ESSENTIA_MODELS_DIR` | `:38`, base-stage `ENV`, inherited by `build` | ✔ |
| `sonance` resolvable as an executable | gemspec `s.bindir = "exe"`, `s.executables = ["sonance"]` | ✔ read from the pinned gem (rev `cf8e613`, tag v0.3.0) |
| App code | **not needed** — the fetch reads the gem's registry only | ✔ that is precisely why the move works |

The `bundle install` at `:53` prunes `"${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git`, which removes only
VCS metadata, not the gem source — so `exe/sonance` survives. Corroborated empirically: the
implementer's cold build shows the fetch step **executing successfully** at its new position.

### Does moving it change what verify at `:91` verifies? **No**

The verify subject is the directory produced by `COPY --from=build` at `:86`, whose source is
`/usr/local/essentia-models` in the build stage. That path is populated by `:62` regardless of where
`:62` sits in the stage. **The subject is unchanged.**

### Is the `USER 1000:1000` ordering guarantee intact? **Yes**

`:81 USER 1000:1000` → `:86 COPY --chown=rails:rails` → `:91 RUN … verify`. The gate still runs as the
runtime uid on files owned by it. This matters more than it looks, because the gate now demonstrably
checks `stat.uid == Process.euid` on the directory (§3): `--chown=rails:rails` sets uid 1000 and verify
runs as 1000, so the two are consistent by construction. Mode is also consistent — `ensure_directory!`
creates the source with `mode: 0o700`, `COPY` preserves modes, and `0700` satisfies the
"not group- or world-writable" check.

Ownership is coherent across stages too: the fetch runs as **root** in the build stage (uid 0 == euid 0,
mode 0700 ✔), then `--chown` retargets to 1000 for the final-stage check.

### The cache evidence — scrutinised

The structural argument is deterministic and I verified the line positions myself: `:62` sits after
`:50`/`:51`/`:53` (which depend on `vendor/*`, `Gemfile`, `Gemfile.lock`) and **before** `:65 COPY . .`.
Docker invalidates a layer only when a preceding layer is invalidated, so a code-only edit invalidates
`:65` onward and cannot reach `:62`. **The fix is correct by reading, independent of the build logs.**

The empirical pair is also well-constructed, and it avoids the misread I was asked to look for:

```
Build 1 (cold, --no-cache):
  #15 [build 5/8] RUN … sonance models fetch …   (executed — NO CACHED label)
Build 2 (code-only: append comment to app/jobs/enrich_album_job.rb, Gemfile.lock unchanged):
  #12 [build 4/8] RUN bundle install …           CACHED
  #15 [build 5/8] RUN … sonance models fetch …   CACHED   ← the claim
  #16 [build 6/8] COPY . .                       (executed — invalidated)
```

The **discriminator is present**: `COPY . .` shows as *executed* in build 2 while the fetch shows
*CACHED*. That rules out the classic false positive — an edit that never registered would have shown
`COPY . .` cached too. And the edit target is an app-tree file, not `Gemfile`/`Gemfile.lock`/`vendor/`,
so it exercises the right axis.

**One leg not demonstrated** (note, not a finding): nobody showed that changing `Gemfile.lock` *does*
invalidate the fetch. That is the positive control for "depends only on Gemfile.lock." It follows from
Docker's COPY semantics and I am satisfied by reading, but the demonstrated claim is strictly "app
changes do not invalidate," not "Gemfile.lock changes do."

**Worth crediting:** the cache key is *semantically* correct, not merely convenient. What should be
fetched is determined by the gem's model registry, which is pinned by `Gemfile.lock`. So a registry
change necessarily changes `Gemfile.lock` and necessarily invalidates the fetch. There is no path by
which expected digests change while the cached models persist. That is a well-chosen key.

---

## 3. T4 — **I WITHDRAW THIS FINDING. My round-1 analysis was wrong.**

Round 1 I reported that `Dockerfile`'s comment overclaimed, on the basis that `verify_model!` checks
"the digest only" with "no `File.stat`, no owner check, no mode check anywhere in `model_store.rb`."
**That was incorrect.** I read `verify_model!` and stopped; my grep covered
`chmod|File.stat|owned?|readable?` and therefore missed checks implemented via `File::NOFOLLOW`,
`stat.file?`, `stat.uid`, and `stat.mode.nobits?`. The checks are not in `verify_model!` — they are one
and two levels below it, in `Files#digest` and `Files#path_for`.

The implementer weakened the comment on my instruction (that is `29c94bb`), then amended to the
accurate stronger wording (`6df28b9`). **The amendment corrects damage my finding caused.**

### The real call chain

```
verify!(filenames:)  →  verify_model!(model)  →  model_files.digest(filename)
                                                    ├─ path_for(filename) → misconfiguration_checked_root
                                                    │     └─ detect_root_misconfiguration!
                                                    │           ├─ detect_root_type_misconfiguration!   (symlink / not-a-directory)
                                                    │           ├─ detect_root_permission_misconfiguration!
                                                    │           │     ├─ stat.uid == Process.euid        (uid OWNERSHIP)
                                                    │           │     └─ stat.mode.nobits?(0o022)        (WRITE-PERMISSION)
                                                    │           └─ detect_root_replacement!              (dev/inode identity)
                                                    └─ File.open(path, RDONLY|NOFOLLOW)
                                                          ├─ Errno::ELOOP  → anti-SYMLINK
                                                          ├─ Errno::ENOENT → PRESENCE
                                                          ├─ stat.file?    → REGULAR-FILE
                                                          └─ digest_io     → DIGEST
```

Crucially, `path_for` is on the **verify** path, so a verify-only invocation performs the directory
checks — it is not limited to `fetch!`/`ensure_directory!`.

### Every claim verified by execution (pure Ruby, runs fine on arm64)

```
missing dir       : ConfigurationError -> missing models directory: /tmp/vd23r2/nope
empty dir 0700    : ConfigurationError -> missing model: …/empty/msd-musicnn-1.pb
dir mode 0777     : ConfigurationError -> models directory misconfiguration: must not be group- or world-writable
dir mode 0770     : ConfigurationError -> models directory misconfiguration: must not be group- or world-writable
dir is symlink    : ConfigurationError -> models directory misconfiguration: path is a symlink
model is symlink  : ConfigurationError -> model path must not be a symlink
model is a dir    : ConfigurationError -> model path must be a regular file
all models bogus  : ConfigurationError -> model digest mismatch: msd-musicnn-1.pb
# uid ownership, using a root-owned directory (my euid is 502):
/usr              : ConfigurationError -> models directory misconfiguration: must be owned by the current user: /usr
```

Mapping to the `6df28b9` comment, which claims *"Individual model files: digest, presence,
regular-file, and anti-symlink checks. Models directory: uid ownership and write-permission checks"*:

| Claim | Demonstrated |
|---|---|
| file digest | ✔ "model digest mismatch" |
| file presence | ✔ "missing model" |
| file regular-file | ✔ "model path must be a regular file" |
| file anti-symlink | ✔ "model path must not be a symlink" |
| dir uid ownership | ✔ "must be owned by the current user" |
| dir write-permission | ✔ 0777 **and** 0770 both rejected |

**All six claims hold. The comment is accurate — arguably still conservative,** since it omits the
directory symlink/type check and the dev/inode replacement check that also fire.

This materially raises my assessment of the gate. In round 1 I called its non-vacuity-by-construction
the strongest gate work on this project; it is stronger than that — it is a hardened gate that runs as
the runtime uid and rejects symlink substitution, non-regular files, and a group- or world-writable
models directory.

---

## 4. Does T3's fix change my view on the undemonstrated fetch-failure path? **Yes — it matters LESS, and it is still not a finding**

Round 1 I noted `fetch!` calls `verify!` itself, so a bad download is gated but undemonstrated. You ask
whether making that path less-travelled changes the assessment. It does, in **degree, not in kind**:

1. **The always-on gate is the final-stage verify at `:91`, and caching does not weaken it.** A
   code-only deploy invalidates `/rails`, so `:85` re-runs, so `:91` re-runs. **Every build verifies
   the models it actually ships**, whatever the cache state of `:62`. That is the property that
   protects production.
2. **The fetch-time gate is redundant with it on the same build.** A corrupted download raises at
   `:62` (`"downloaded model digest mismatch"` in `fetch_model!`); if it somehow did not, the identical
   bytes would be copied at `:86` and rejected at `:91`. Either way the build fails and no image is
   produced.
3. **A cached fetch means no download occurred**, so there is nothing for the fetch-time gate to catch
   on that build. The gate only needs to work on builds that actually fetch — cold builds and
   `Gemfile.lock` changes — and those are exactly the builds where it runs.

The one direction that would have worried me is a stale cached layer surviving a change to expected
digests. That cannot happen: expected digests live in the gem registry, pinned by `Gemfile.lock`, which
is the cache key (§2). So the risk the caching introduces is closed by the same mechanism.

Conclusion unchanged: **not a finding.** The argument is now stronger than in round 1, not weaker.

---

## 5. Fix-induced regressions — none found

- `git diff a046b69...6df28b9 -- '*.pb'` shows only the six deletions; no model bytes modified.
- Suite on the rebased HEAD: see §7. Assets were already built in this worktree, so TRAP 1 does not
  re-apply; I checked for `tailwind.css` before running rather than labelling anything.
- T5 confirmed: both `Dockerfile:62` and `:91` use `$ESSENTIA_MODELS_DIR`, so the fetch, the verify and
  the four Ruby consumers now all derive from one variable. The residual I raised in round 1 — verify
  attesting a path the runtime might not use — is closed for everything inside the image.
- No new `:essentia`-tagged examples, so the Docker-only blind spot is unchanged in size.

---

## 6. Scope observation — needs an owner, and I am not reviewing it

The dispatch says issue 29's LICENSE/NOTICE/README "come from that branch and are NOT this branch's
work." That is accurate for `LICENSE`, but **not** for `NOTICE` and `README.md`, which are modified
**in range**:

```
$ git diff --stat a046b69...6df28b9
 NOTICE    | 23 ++++++++++++---------
 README.md |  9 +++++---
```

And the change is substantive, not cosmetic — `a046b69` deliberately left a to-do that this commit
discharges:

```diff
-The following model files are currently tracked in this repository. When issue
-#23 (remove vendored model binaries from the tracked tree) lands, this sentence
-and the list below must be revisited …
+The following six model files were previously redistributed as tracked objects in
+this repository's git history and remain in that history. … as of issue #23 they are
+fetched at image build time from essentia.upf.edu and are baked into the final
+Docker image (/usr/local/essentia-models/).
```

So a046b69 explicitly deferred this text to #23, and #23 revises it — including correcting a statement
that would otherwise be false once models are baked into the image. **I have not reviewed the
attribution content, per my dispatch.** But "already approved on the other branch" does not cover these
lines, so if nobody is assigned to them they will ship unreviewed. Flagging for routing only; this is
Plumb's or the owner's call, not a test/gate finding.

---

## 7. Evidence

```
git -C <repo> rev-parse fix/fetch-models-at-build-time        -> 6df28b9…
git -C <repo> merge-base a046b69 29c94bb                      -> a046b69
git -C <repo> merge-base --is-ancestor 29c94bb 6df28b9        -> NO
git -C <repo> log --format="%H %P" -1 29c94bb / -1 6df28b9    -> same parent a046b69 (amend)
git -C <repo> diff --stat 29c94bb 6df28b9                     -> Dockerfile only
git -C <repo> rev-parse 29c94bb^{tree} 6df28b9^{tree}         -> differ
git -C <repo> diff 29c94bb 6df28b9 -- Dockerfile
git -C <repo> log --format="%h %s" a046b69..6df28b9           -> one commit
git -C <repo> diff --stat a046b69...6df28b9
git -C <repo> diff a046b69...6df28b9 -- NOTICE
sed -n '40,95p' <worktree>/Dockerfile
grep -rn "essentia_models|ESSENTIA_MODELS_DIR|models_dir|SONANCE_MODELS_DIR|models-dir" \
  --include=*.rb --include=*.rake --include=*.yml --include=*.sh --include=Dockerfile --include=Procfile* .
grep -rn "essentia_models|ESSENTIA_MODELS_DIR|models-dir" bin/ .github/     -> none
grep -n "docker run" -A5 .github/workflows/ci.yml
# fix resolution, both branches:
ESSENTIA_MODELS_DIR=… ruby -rpathname -e 'Pathname(ENV.fetch("ESSENTIA_MODELS_DIR", …))'
# gem internals, pinned rev cf8e613 (tag v0.3.0):
sed -n '1,190p' <gem>/lib/sonance/model_store.rb
grep -n "executable|bindir|files" <gem>/sonance.gemspec
# gate battery — 9 cases, all raising as claimed (pasted in §3):
bundle exec ruby -e '…ModelStore.new(dir).verify!… for 9 sabotaged directories'
# suite on rebased HEAD (worktree, assets confirmed present first):
bundle exec rspec
```

Suite result on `6df28b9` (assets confirmed present first, so TRAP 1 does not apply):

```
$ ls app/assets/builds/tailwind.css   -> present
$ bundle exec rspec
Finished in 9.01 seconds (files took 1.22 seconds to load)
298 examples, 0 failures
```

---

## 8. Could NOT verify, and why

| Claim | Why not |
|---|---|
| The two Docker builds behind the cache pair | arm64; cannot run the amd64 Essentia toolchain. I verified the **structural** cache behaviour by reading the layer order, which is deterministic and is the stronger argument. |
| That the restored golden gate now passes in CI | Requires the amd64 image build. The three links (image ENV, CI flags, `essentia-ci`) are each verified; the end-to-end pass is inferred. |
| That `Gemfile.lock` changes invalidate the fetch layer | Not demonstrated by the implementer; follows from COPY semantics. |
| `essentia.upf.edu` egress from the builder | Taken as established per the context file. |

---

## 9. Findings closed

**T1 (HIGH), T2 (MEDIUM), T3 (MEDIUM), T5 (LOW) are closed. T4 (LOW) is WITHDRAWN as a false finding
of mine** — the comment at `6df28b9` is accurate and every claim in it is verified by execution above.

No open findings from my discipline. The §6 scope observation needs an owner but is not mine to review.

## 10. Read-only confirmation

No commits, no edits, no pushes, no PR. The worktree remains at `6df28b9` and clean
(`git status --porcelain` empty apart from gitignored build artefacts). Gate experiments ran in
`/tmp/vd23r2/`; the suite was run in place, which writes only to gitignored `tmp/` and `log/`.
