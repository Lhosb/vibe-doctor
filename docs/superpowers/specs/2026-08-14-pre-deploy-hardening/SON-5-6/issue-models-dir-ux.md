## Problem

There are **two environment variable names and two defaults** for the same concept, split across
the gem and its consumer.

| Consumer | Env var | Default |
|---|---|---|
| Gem CLI (`exe/sonance:23`) | `SONANCE_MODELS_DIR` | `~/.cache/sonance/models` |
| Golden generator (`spec/fixtures/sonance/generate_goldens.rb:11`) | `SONANCE_MODELS_DIR` | `~/.cache/sonance/models` |
| Gem library (`Extractor`, `EssentiaPython`) | — | **none — required keyword** ✅ correct |
| vibe-doctor (4 call sites) | **`ESSENTIA_MODELS_DIR`** | **`Rails.root/tmp/essentia_models`** |

The library having no default is right for an opinionless binding — the caller must decide. The
problem is entirely in the defaults the *callers* chose.

## Two consequences, both bad for multi-repo use

**1. Setting the documented variable does nothing.** A developer who exports
`SONANCE_MODELS_DIR` — the variable the gem's own CLI and README use — is silently ignored by
vibe-doctor. Someone who exports `ESSENTIA_MODELS_DIR` is silently ignored by the gem CLI. Neither
errors; both just quietly use a different directory. This was already noted during the #23 review:
`SONANCE_MODELS_DIR` appears nowhere in the app, and the explicit `--models-dir` flags are the only
reason the Docker build works at all.

**2. `Rails.root/tmp/` is the wrong home for shared immutable assets.** The models are ~3.4 MB,
digest-pinned, and identical for every project that uses them. Putting them under a repo's `tmp/`
means:

- every clone re-downloads them;
- `rails tmp:clear` wipes them, and `tmp/` is disposable by every convention;
- a second project using sonance keeps its own duplicate copy.

`~/.cache/sonance/models` — which the gem already uses — fixes all three: one download per
*machine*, survives `tmp:clear`, shared across every repo.

## Proposed work

1. **vibe-doctor adopts `~/.cache/sonance/models`** as its development default, replacing
   `Rails.root/tmp/essentia_models` at all four call sites. Production is unaffected: the
   Dockerfile sets the path explicitly.
2. **Unify on one variable name.** Prefer `SONANCE_MODELS_DIR`, since it is the gem's own and is
   already documented. Honour `ESSENTIA_MODELS_DIR` as a deprecated fallback so nothing breaks,
   and log or comment the deprecation rather than removing it silently.
3. **Gem honours `XDG_CACHE_HOME`**: `${XDG_CACHE_HOME:-~/.cache}/sonance/models`. That is the
   actual cross-platform standard and matters on Linux, where `~/.cache` is not guaranteed to be
   the cache root.

## Not a blocker for #23

The Dockerfile sets `ESSENTIA_MODELS_DIR` explicitly, so the deployed image is correct either way.
This is a developer-experience and consistency issue, not a deployment defect. It should be done as
one coordinated change across both repos, since a partial rename would make the two-name problem
worse rather than better.

## Provenance

Raised by the repository owner while reviewing #23, asking whether `/usr/local/essentia-models` was
the right location when thinking about developer experience across different repos. The image path
is correct; investigating the question surfaced that the *local* defaults are not.
