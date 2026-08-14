APPROVE

No security vulnerabilities were identified in the reviewed diff range.

## Scope and method

- Reviewed diff: `5c9dfccda17ccf26af5267d099a391e3b2e882a8..24e17798dc386d794c8dc032360a31e754350e33`
- Security-only review (spec/test behavior not re-reviewed)
- Derived execution path from `Dockerfile` and pinned `sonance` source (`Gemfile.lock` revision `cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6`)

## Findings

✅ **No exploitable security findings** requiring code changes.

### Notes (non-blocking)

1. **Build-time supply chain controls are on-path**
   - `Dockerfile` now runs `bundle exec sonance models fetch --models-dir /usr/local/essentia-models` during build.
   - That path enforces:
     - HTTPS-only source URLs
     - strict host allowlist (`essentia.upf.edu`)
     - SHA-256 digest verification against pinned registry metadata before install
   - These controls are active in the exact fetch path used by this change.

2. **`models verify` as uid 1000 is meaningful but narrower than “digest + ownership + mode per file”**
   - Final stage sets `USER 1000:1000` and then runs `bundle exec sonance models verify`.
   - Verification checks digest and models-dir safety constraints as runtime user (owner-euid match, no writable root, symlink protections).
   - It does not explicitly enforce per-model-file ownership/mode as separate predicates.
   - No concrete exploit path from this in current design.

3. **Model blobs remaining in public git history are not a distinct security issue**
   - They are model artifacts, not credentials/secrets/tokens.
   - This remains a licensing/compliance/repo-hygiene concern (tracked separately), not an access-control/data-exposure vulnerability.

4. **`.dockerignore` negation removal does not expose new secrets**
   - Removed re-inclusion of `tmp/essentia_models/*.pb` from build context.
   - This reduces context content; no new sensitive file exposure found.
   - Nothing required for this new design is now incorrectly excluded.

5. **Secrets/tokens surface**
   - No new secret, token, or credential surface added in the diff.

6. **Runtime network reachability**
   - New external dependency is build-time (`essentia.upf.edu` during image build), not a new runtime egress requirement for the running app.

7. **Control posture**
   - The change adds a build-time fetch+verify gate and does not remove an existing security verification control.

## Verified by execution

```bash
git -C /Users/lukeolson/projects/vibe-doctor --no-pager diff --name-status 5c9dfccda17ccf26af5267d099a391e3b2e882a8..24e17798dc386d794c8dc032360a31e754350e33
```

Observed relevant touched files:
- `M .dockerignore`
- `M .gitignore`
- `M Dockerfile`
- `A LICENSE`
- `A NOTICE`
- `M README.md`
- `D tmp/essentia_models/*.pb` (six model files)

```bash
git -C /Users/lukeolson/projects/vibe-doctor --no-pager show 24e17798dc386d794c8dc032360a31e754350e33:Dockerfile | nl -ba | sed -n '33,96p'
```

Confirmed:
- `ESSENTIA_MODELS_DIR` env set
- build-stage `models fetch` added
- final-stage `USER 1000:1000`
- final-stage `models verify` added

```bash
git -C /Users/lukeolson/projects/vibe-doctor --no-pager show 5c9dfccda17ccf26af5267d099a391e3b2e882a8:.dockerignore
git -C /Users/lukeolson/projects/vibe-doctor --no-pager show 24e17798dc386d794c8dc032360a31e754350e33:.dockerignore
```

Confirmed removal of previous `tmp/essentia_models` negation/re-inclusion entries.

```bash
git -C /Users/lukeolson/projects/vibe-doctor --no-pager show 24e17798dc386d794c8dc032360a31e754350e33:Gemfile.lock | sed -n '1,12p'
```

Confirmed pinned git dependency metadata:
- `remote: https://github.com/Lhosb/sonance.git`
- `revision: cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6`
- `tag: v0.3.0`

## Believed by reading

- `sonance` fetch/verify path is controlled by `exe/sonance`, `lib/sonance/model_store.rb`, and `lib/sonance/registry.rb` at pinned revision `cf8e613...`.
- Host allowlist and HTTPS enforcement are evaluated before requests and on redirect hops in the downloader path.
- Digest verification is mandatory before replacing installed model files.
