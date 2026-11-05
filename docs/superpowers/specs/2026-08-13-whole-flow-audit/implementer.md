DEPLOYABLE WITHOUT DEPLOYING THE GEM — YES WITH CONDITIONS: the image build host must have outbound HTTPS access to `github.com`, the Docker build stage must retain `git`, and `Lhosb/sonance` tag `v0.3.0` plus locked revision `cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6` must remain fetchable.

Status: DONE

- BASE_SHA / HEAD_SHA (read-only audit):
  - App working checkout: `1f8ad788844ba2cd4cd6cccf1491658cf06c5eab` / unchanged
  - App clean-room `main`: `b26cf31c1030d7511ff4696a6ec2bdd205a9672d`
  - Gem `main`: `d514137a09facf8c64519e189aed57c3abaf5635` / unchanged
- Risk triggers touched: external integrations (GitHub dependency fetch); no source changes, migrations, authz, destructive data operations, or new dependencies.

## Answer

The Sonance gem does **not** need a separate publish, vendor, copy, or deployment step. A no-cache build on the configured Hetzner amd64 Docker host fetched the public Git dependency from GitHub, accepted the committed lockfile in deployment mode, built the complete production image, and produced a final container that booted the Rails environment and exercised the Sonance registry assertion with networking disabled.

This proves the gem-specific deployment path and the complete Docker image build. I did not run `kamal deploy`, push to GHCR, start the production service, connect to the production database, or validate production secrets/accessories. Those remain whole-deployment risks unrelated to whether Sonance must be deployed separately.

## Verified by execution

### 1. Clean-room and override neutralization

Scratch path: `/tmp/sonance-main-audit-rivet.jQFrsC`, outside both repositories. It was created with `mktemp`, cloned from public GitHub, and removed after evidence capture.

The clone was performed with an empty `HOME`, no system/global Git config, no interactive credential prompting, and Git HTTP tracing:

```text
$ env -i HOME="$scratch/home" PATH="$PATH" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never \
    GIT_TRACE=1 GIT_TRACE_CURL=1 \
    git clone --branch main --single-branch \
      https://github.com/Lhosb/vibe-doctor.git "$scratch/vibe-doctor"

SCRATCH=/tmp/sonance-main-audit-rivet.jQFrsC
b26cf31c1030d7511ff4696a6ec2bdd205a9672d
Cloning into '/tmp/sonance-main-audit-rivet.jQFrsC/vibe-doctor'...
run_command: git remote-https origin https://github.com/Lhosb/vibe-doctor.git
Couldn't find host github.com in the .netrc file; using defaults
Connected to github.com (172.182.252.133) port 443
OPENED stream for https://github.com/Lhosb/vibe-doctor.git/info/refs?service=git-upload-pack
<= Recv header: HTTP/2 200
```

Host baseline:

```text
$ env | sort | grep '^BUNDLE_' || true
(no output)

$ test -f ~/.bundle/config && cat ~/.bundle/config || echo '(absent)'
(absent)
```

The scratch clone contained no `.bundle/config`. Each install additionally used a separate empty `BUNDLE_APP_CONFIG`, `BUNDLE_USER_HOME`, `BUNDLE_USER_CONFIG`, `BUNDLE_USER_CACHE`, and `BUNDLE_PATH`, with `BUNDLE_GLOBAL_GEM_CACHE=false`. `bundle config list` showed only those explicitly isolated values and no `local.sonance` or `disable_local_branch_check`.

The remote Docker build is the strongest clean-room proof: it ran on the separate Hetzner host (`x86_64`, Docker server `29.3.1`), which has no access to the Mac path `/Users/lukeolson/projects/gems/mood_probe`. It used the scratch clone as build context.

### 2. Public unauthenticated HTTPS install

Normal install from an empty cache:

```text
$ bundle install --verbose
Fetching https://github.com/Lhosb/sonance.git
Using sonance 0.3.0 from https://github.com/Lhosb/sonance.git (at v0.3.0@cf8e613)
Bundle complete! 34 Gemfile dependencies, 148 gems now installed.
```

The command ran under `env -i` with `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, empty `HOME`, `GIT_TERMINAL_PROMPT=0`, and `GCM_INTERACTIVE=never`; its trace contained no authorization header, credential helper, or token pattern. The installed checkout was:

```text
/tmp/sonance-main-audit-rivet.jQFrsC/bundle-normal/ruby/4.0.0/bundler/gems/sonance-cf8e613e9a9b
HEAD=66393972a8b57ee116afec0fbeb879a0c410dbca
```

The actual no-cache remote Docker build independently fetched the same HTTPS URL:

```text
#15 0.453 Fetching https://github.com/Lhosb/sonance.git
#15 41.39 Bundle complete! 34 Gemfile dependencies, 146 gems now installed.
```

No GitHub credential or secret was passed to that build.

### 3. Frozen/deployment lockfile acceptance

A second install used a different empty cache and explicit deployment/frozen settings:

```text
deployment
Set via BUNDLE_DEPLOYMENT: true

frozen
Set via BUNDLE_FROZEN: true

$ BUNDLE_DEPLOYMENT=1 BUNDLE_FROZEN=1 bundle install --verbose
Fetching https://github.com/Lhosb/sonance.git
Using sonance 0.3.0 from https://github.com/Lhosb/sonance.git (at v0.3.0@cf8e613)
Bundle complete! 34 Gemfile dependencies, 148 gems now installed.
```

Negative control: in a second scratch copy only, I changed the Gemfile tag to `v0.2.0` without changing the lockfile. The same frozen command failed:

```text
exit=16
The list of sources changed, but the lockfile can't be updated because frozen
mode is set

Run `bundle install` elsewhere and add the updated Gemfile.lock to version
control.
```

Therefore the committed Gemfile/lock agreement, not an ineffective frozen setting, is what passed.

### 4. App boot and boot-time registry assertion

The app booted from the separately installed frozen bundle and explicitly checked the same descriptor/range invariants as `config/initializers/sonance_registry.rb`:

```text
BOOT_OK initializer_assertion_exercised=true sonance=0.3.0 missing=[] ranges={valence_emomusic: 1.0..9.0, arousal_emomusic: 1.0..9.0} gem_path=/tmp/sonance-main-audit-rivet.jQFrsC/bundle-frozen/ruby/4.0.0/bundler/gems/sonance-cf8e613e9a9b
```

A production-environment runner progressed past Sonance initialization but later attempted a local PostgreSQL connection during eager loading and failed because the scratch machine lacks the configured `vibe_doctor` database role. That is not a Sonance boot failure. The final-image network-disabled test below booted successfully under `RAILS_ENV=test`.

### 5. Actual Docker build on the configured remote amd64 builder

The configured SSH host was reachable and is amd64:

```text
$ ssh ... deploy@5.78.177.23 'uname -m; docker version ...'
x86_64
29.3.1 29.3.1
```

I ran the actual repository Dockerfile on that host, explicitly no-cache:

```text
$ DOCKER_HOST=ssh://deploy@5.78.177.23 \
    BUILDKIT_PROGRESS=plain \
    docker build --platform linux/amd64 --pull --no-cache \
      -t vibe-doctor-sonance-audit:b26cf31 .

#0 building with "default" instance using docker driver
#6 [base 1/4] FROM docker.io/library/ruby:4.0.1-slim@sha256:939bb271...
#15 0.453 Fetching https://github.com/Lhosb/sonance.git
#15 41.39 Bundle complete! 34 Gemfile dependencies, 146 gems now installed.
#18 DONE 3.8s
#19 [stage-2 2/3] COPY --chown=rails:rails --from=build /usr/local/bundle /usr/local/bundle
#19 DONE 1.6s
#20 [stage-2 3/3] COPY --chown=rails:rails --from=build /rails /rails
#20 DONE 1.5s
#21 naming to docker.io/library/vibe-doctor-sonance-audit:b26cf31 done
#21 DONE 61.0s
```

Image result:

```text
id=sha256:7d9e03646bb14c8ef80a8354c3461fd7ddd99dc25446dec66b3c6ab924fe7c17 arch=amd64 os=linux size=762495360
```

This is stronger than a local arm64 substitute: it used the same remote host and architecture configured by `config/deploy.yml`. It did not exercise Kamal's GHCR push, deploy orchestration, secrets, database accessory, or service health checks.

### 6. Runtime independence from GitHub

The final image was run with `--network none`:

```text
git=absent
gem_path=/usr/local/bundle/ruby/4.0.0/bundler/gems/sonance-cf8e613e9a9b
gem_git_dir=absent
gem_version=0.3.0
network_test=unavailable
```

Rails boot plus the registry assertion also passed with networking disabled:

```text
CONTAINER_BOOT_OK network=none sonance=0.3.0 missing=[] ranges={valence_emomusic: 1.0..9.0, arousal_emomusic: 1.0..9.0}
```

The running container does not need GitHub. GitHub and `git` are build-time requirements only. The build stage installs the gem into `/usr/local/bundle`; the final stage copies that directory, strips the git checkout metadata, and contains no `git` executable.

### 7. Current remote object availability

Unauthenticated lookup under the same empty-home/no-config environment:

```text
$ git ls-remote https://github.com/Lhosb/sonance.git \
    refs/tags/v0.3.0 'refs/tags/v0.3.0^{}'
cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6  refs/tags/v0.3.0
66393972a8b57ee116afec0fbeb879a0c410dbca  refs/tags/v0.3.0^{}
exit=0
```

## Believed by reading / structural audit

### Dependency-source assumptions in the app

No committed app file requires a local path, vendored Sonance copy, or published RubyGems package:

- `Gemfile:34` specifies only the canonical HTTPS Git source and `v0.3.0`.
- `Gemfile.lock:1-7` records Sonance in a `GIT` section, not the RubyGems `GEM` source.
- There is no tracked `.bundle/config`.
- `vendor/` contains JavaScript assets and `.keep` files, not Sonance.
- `README.md:152-160` documents `bundle config local.sonance` only as an optional local-development override; it is not active or committed.
- Old `mood_probe` strings remain only in fixture provenance/history prose, not dependency resolution.
- `spec/sonance_dependency_spec.rb:8-12` asserts the installed gem path/version and canonical Git URL.

Repository-wide tracked-file searches found the dependency source only in `Gemfile`, `Gemfile.lock`, the dependency spec, and the optional README development instructions.

## Failure modes and exposure

| Failure mode | Current exposure | Manifestation |
|---|---|---|
| Tag `v0.3.0` disappears or moves | **Real future exposure; healthy now.** The tag exists now. The tagged commit is not on gem `main`, so the tag is the durable advertised ref preserving this orphaned pre-squash history. | A no-cache/fresh builder may fail to fetch/check out locked object `cf8e613...` / peeled commit `6639397...`, producing a Bundler Git error and stopping at `bundle install`. Moving an annotated tag creates a different tag object, while the frozen lock still requests the old object. |
| Repository renamed again and redirect later breaks | **Not currently failing; canonical URL is used now.** It remains an external namespace dependency. | GitHub HTTPS fetch fails (typically repository not found/auth-shaped 404) before gem installation. A rename redirect may work temporarily, but reuse/removal of the old namespace can end it. Update Gemfile and lockfile before that happens. |
| `git` absent at build time | **Not a current exposure in this Dockerfile.** `Dockerfile:39-42` installs `git` in the build stage; the successful no-cache build exercised it. | Bundler cannot clone the `GIT` source and fails during `bundle install`. `git` being absent in the final runtime image is intentional and proven safe. |
| Build host cannot reach GitHub | **Required external dependency; currently available.** The remote no-cache build fetched GitHub successfully. | DNS/TLS/connect timeout or Git transport failure at Docker step `RUN bundle install`; no new image is produced. Existing already-built containers continue to run. |
| Locked revision is no longer fetchable | **Real future exposure; fetchable now.** `git ls-remote` returned both the locked annotated tag object and peeled commit. Orphaned history makes continued tag retention especially important. | Frozen Bundler cannot resolve/check out `cf8e613...`; build fails even if a newer Sonance `main` is healthy. Recovery requires restoring the immutable tag/object or intentionally repinning Gemfile.lock to a new release. |

## Findings

1. **MEDIUM — The deploy is reproducible only while an orphan-history tag/object remains available.**  
   Evidence: `Gemfile:34`, `Gemfile.lock:1-7`; `v0.3.0` resolves now, but its peeled commit is not an ancestor of gem `main`.  
   Scenario: deleting or force-moving `v0.3.0` makes a fresh frozen build unable to obtain the locked revision.  
   Mitigation: protect release tags operationally; do not move/delete `v0.3.0`; consider retaining an additional immutable release ref/archive policy.

2. **LOW / operational — Fresh builds depend on GitHub HTTPS egress.**  
   Evidence: `Dockerfile:39-50` and the no-cache remote build fetch log.  
   Scenario: Hetzner egress/DNS/GitHub outage stops new image construction. Running images are unaffected.  
   Mitigation: monitor build connectivity; optionally add an internal mirror or vendored cache only if the availability requirement warrants it.

No finding indicates a separate Sonance deployment is required.

## Repository final state

- Gem repository: branch `main`, HEAD `d514137a09facf8c64519e189aed57c3abaf5635`, clean and unchanged.
- App repository: branch `docs/essentia-gem-v2-design`, HEAD `1f8ad788844ba2cd4cd6cccf1491658cf06c5eab`, tracked tree unchanged and byte-identical to audited `origin/main`. A pre-existing untracked directory (`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/phase-a/whole-branch/`) was present before the audit and was left untouched under the read-only rule.
- Remote audit image and local scratch directory were removed after verification.

## Self-review

All six requested execution questions were exercised. The conclusion is limited to Sonance dependency acquisition, image construction, and runtime independence; it does not overclaim a completed Kamal production rollout.
