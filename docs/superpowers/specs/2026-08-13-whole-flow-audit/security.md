APPROVE-WITH-FINDINGS

# SONANCE-MAIN-AUDIT — Security review

## Findings

### Important — subprocess stdout and stderr are read without a size limit

**Files:** `/Users/lukeolson/projects/gems/mood_probe/lib/sonance/backends/essentia_python.rb:37-38,215-216`

`CommandRunner` starts two threads that call `stdout.read` and `stderr.read`, retaining both complete
streams in Ruby strings before protocol parsing. `parse_results` then splits the complete stdout into
another collection of strings. There is a plan-input limit, but no corresponding output limit.

**Concrete failure scenario:** a compromised or malfunctioning Python/Essentia process, including a
native decoder failure reached through hostile remote audio, continuously writes stdout or stderr.
The Ruby parent drains and retains that output until the container exhausts memory and the web/job
process is killed. This is not command execution and I found no current input that directly grants an
attacker control of stdout; it is a resource-exhaustion weakness at the subprocess trust boundary.

**Severity:** Important.

**Execution evidence:** a fake command runner returned progressively larger single protocol values.
Ruby accepted all of them without a protocol or size error:

```text
accepted_feature_bytes=1024
accepted_feature_bytes=1048576
accepted_feature_bytes=8388608
```

### Minor — tracked main-branch documents still dereference the retired repository namespace

**Files:**

- `/Users/lukeolson/projects/vibe-doctor/docs/superpowers/plans/2026-08-07-essentia-ruby-gem-extraction.md:10,250,420`
- `/Users/lukeolson/projects/vibe-doctor/docs/superpowers/specs/2026-08-10-essentia-gem-generalization-design.md:440,490`
- `/Users/lukeolson/projects/vibe-doctor/docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/principal-draft.md:896,916`
- `/Users/lukeolson/projects/vibe-doctor/docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/phase-a/slice-1/security.md:71,73,75`
- `/Users/lukeolson/projects/vibe-doctor/docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/phase-a/slice-1/spec.md:298`

The live Gemfile, lockfile, gem metadata, source comments, and executable instructions point to
`Lhosb/sonance`; the old URL survives only in historical/design material. GitHub currently redirects
the old URL. If the account owner later creates a new `Lhosb/mood_probe` repository, GitHub removes
the redirect and these tracked links and copy/paste Gemfile examples address the new repository.

**Concrete exploit scenario:** an attacker who gains the ability to create a repository under the
`Lhosb` account creates `Lhosb/mood_probe` and publishes malicious gem code. A developer following the
tracked old Gemfile example at line 250 or 420 installs from that attacker-controlled repository. The
production app build is not exposed because `Gemfile:34` and `Gemfile.lock:2` use the new URL.

**Severity:** Minor because creation under the old owner namespace already requires control delegated
by, or compromise of, the owner account.

## Verified by execution

### Repository and revision state

- Gem checkout: `main`, clean, `HEAD == origin/main == d514137a09facf8c64519e189aed57c3abaf5635`.
- App checkout tree at `1f8ad788844ba2cd4cd6cccf1491658cf06c5eab` is byte-identical to merged
  `origin/main` `b26cf31c1030d7511ff4696a6ec2bdd205a9672d`.
- The app had one pre-existing untracked review directory. This audit did not modify either repository.

### Git source authentication and mutable-tag behavior

The app declares:

```text
Gemfile:34 gem "sonance", git: "https://github.com/Lhosb/sonance.git", tag: "v0.3.0"
Gemfile.lock:2 remote: https://github.com/Lhosb/sonance.git
Gemfile.lock:3 revision: cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6
Gemfile.lock:4 tag: v0.3.0
```

The lock revision is the annotated tag object and peels to the expected commit:

```text
$ git cat-file -t cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6
tag
$ git rev-parse 'cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6^{}'
66393972a8b57ee116afec0fbeb879a0c410dbca
```

Remote refs agree:

```text
d514137a09facf8c64519e189aed57c3abaf5635 HEAD
cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6 refs/tags/v0.3.0
66393972a8b57ee116afec0fbeb879a0c410dbca refs/tags/v0.3.0^{}
```

The annotated tag is not cryptographically signed:

```text
$ git tag -v v0.3.0
error: no signature found
tag_verify_exit=1
```

What authenticates a fresh install is therefore:

1. HTTPS authenticates GitHub's server and the requested `Lhosb/sonance` repository endpoint.
2. Git object identity plus the committed lockfile fixes the exact annotated tag object and peeled
   commit. A moved `v0.3.0` ref does not silently substitute different code while this lock revision
   remains committed.
3. Repository/account controls and review of lockfile changes authorize a future revision change.

There is no author/release signature or independent provenance check. Moving the tag can make a fresh
build fail if the locked object becomes unavailable; installing different code requires the lock
revision to change (for example via an explicit dependency update), which is review-visible.

The tag commit is not an ancestor of gem main:

```text
$ git merge-base --is-ancestor 'v0.3.0^{}' origin/main
ancestor_exit=1
```

The installed runtime tree remains identical to gem main:

```text
$ git diff --stat 'v0.3.0^{}'..origin/main -- lib python exe sonance.gemspec
[no output]
```

The non-ancestry makes release discovery and retention more fragile, but it does not create a content
mismatch at present.

### Repository rename derivation

Current tracked-tree searches found no old URL in the gem and no old URL in the app's functional
dependency/build configuration. The old URL appears in the app documents listed in Finding 2.

The old Git URL currently redirects:

```text
HTTP/2 301
location: https://github.com/Lhosb/mood_probe
```

### Credentials and build path

- `Dockerfile:41-55` installs `git` only in the throw-away build stage and runs `bundle install`.
- The gem remote is public HTTPS. No GitHub token, credential, or SSH key is required for the gem
  fetch, and none is passed to the Docker build.
- `config/deploy.yml:96-99` contains only a commented example for a `GITHUB_TOKEN`; it is not enabled.
- `.kamal/secrets:13-14` likewise contains a commented helper for private repositories.
- `config/deploy.yml:101-106` does require the operator's local
  `~/.ssh/id_ed25519_hetzner` to reach the remote Docker builder/deploy host. This key is not copied
  into the image and is unrelated to the public GitHub dependency fetch.
- `KAMAL_REGISTRY_PASSWORD` authenticates GHCR pushes/pulls, not the gem fetch.
- Searches found no tracked private-key material, embedded GitHub credential, or authenticated GitHub
  URL.

### Model download redirect and host attacks

`ModelStore.validate_download_uri!` requires HTTPS and exact `URI#host` equality with
`essentia.upf.edu`. `Downloader#request` calls that validation recursively before every request.

I executed an allowlisted first hop, an allowlisted second hop, and then an evil redirect:

```text
REQUEST https://essentia.upf.edu/start
REQUEST https://essentia.upf.edu/next
CHAIN_FAIL Sonance::BackendError: model download host "evil.test" is not allowed
```

Direct and host-confusion probes failed:

```text
HOST_FAIL https://evil.test/model.pb => model download host "evil.test" is not allowed
HOST_FAIL https://essentia.upf.edu.evil.test/model.pb => model download host "essentia.upf.edu.evil.test" is not allowed
HOST_FAIL https://essentia.upf.edu@evil.test/model.pb => model download host "evil.test" is not allowed
```

The existing HTTP downgrade redirect spec also passed. Downloaded bytes are SHA-256 checked against
registry values before installation.

### Plan-to-Python execution attacks

The Ruby planner maps graph algorithm symbols through the static
`Planner::GRAPH_ALGORITHMS`. Python independently validates graph names against `_GRAPH_ALGORITHMS`,
standalone names against `_ALGORITHM_PARAMS`, parameter names/types/domains, model basenames, plan
keys, references, and required files. `build_pipeline` uses explicit branches rather than `getattr`.

Direct hostile plans failed before Essentia import:

```text
sonance plan invalid: algorithms[0].name is not allowed: 'os.system'
algorithm_exit=2
sonance plan invalid: algorithms[0].params.filename is not allowed
param_exit=2
```

I found no path around those checks: exactly one of `--plan-json`/`--plan-file` is required, both paths
call `validate_plan`, and `build_pipeline` repeats the executable-name branch.

### Subprocess output and non-finite values

Python recursively detects non-finite values and emits a per-track `malformed_output` error.
`json.dumps(..., allow_nan=False)` is a second fail-closed control. Serialization failures are also
converted to `malformed_output`.

If a hostile subprocess bypasses Python and returns bare `NaN`, Ruby rejects it:

```text
OUTPUT_FAIL Sonance::BackendError: Essentia backend returned invalid NDJSON:
unexpected token 'NaN}}' at line 1 column 57
```

Malformed JSON likewise fails:

```text
OUTPUT_FAIL Sonance::BackendError: Essentia backend returned invalid NDJSON:
unexpected token 'not-json' at line 1 column 1
```

Ruby also validates one nonblank NDJSON result per requested path and exact returned path equality.
The outstanding resource bound is Finding 1.

### Audio file paths and command construction

Ruby invokes `Open3.popen3(*command, pgroup: true)` with an argument array. Python receives audio paths
as positional `argparse` values and passes them to `Path`/Essentia `MonoLoader`; neither side
interpolates a shell command.

A hostile-looking path stayed one argv element:

```text
ARGV=["python3", ".../python/sonance_extract.py", "x;touch /tmp/pwn",
      "--models-dir", "/tmp", "--plan-json", "..."]
```

No `/tmp/pwn` command was executed. Absolute paths and traversal in an audio filename can make
Essentia read whatever file the trusted Ruby caller names, but the production caller supplies either
a cryptographically random app temp path or a path returned by `YoutubeClipMatcher`, not a
user-supplied filesystem path. `YoutubeClipMatcher` also invokes `yt-dlp` with argument arrays.

### Tests and scanners

```text
$ bundle exec rspec spec/model_store_spec.rb spec/python_plan_security_spec.rb \
    spec/integration/python_plan_executor_spec.rb spec/backends/essentia_python_spec.rb
80 examples, 0 failures

$ bundle exec rspec spec/sonance_dependency_spec.rb \
    spec/services/youtube_clip_matcher_spec.rb spec/services/mood_grounding_service_spec.rb
26 examples, 0 failures

$ bundle exec brakeman --no-pager -q
Security Warnings: 0
No warnings found

$ bundle exec bundler-audit check
No vulnerabilities found
```

## Believed by reading

- The current fixed descriptor registry bounds ordinary successful feature output, so an attacker
  cannot use the plan API to request an arbitrary unbounded Essentia object.
- The main practical impact of moving/deleting the unsigned tag is availability, because the lockfile
  pins the tag object. A reviewed lockfile revision change is needed to install replacement code.
- GitHub namespace redirect behavior means the old-name documents become unsafe only if the old name
  is re-created under the same owner; an unrelated GitHub user cannot claim `Lhosb/mood_probe`.

## Security-posture change that should have been recorded

Yes. Adding the git-sourced gem changed the app's posture and the current README statement that GitHub
resolution is "for reproducible builds" records only one benefit.

The unrecorded tradeoffs are:

- every clean image build now depends on GitHub availability and continued reachability of an
  orphaned annotated tag object;
- release authenticity rests on GitHub account/repository control, TLS, Git object hashes, and
  lockfile review, not a signed tag, signed gem, RubyGems MFA/release record, or independent
  provenance;
- automated RubyGems advisory/update tooling does not provide the same release-channel coverage for
  this git source;
- a dependency update can follow a moved tag only by changing the committed lock revision, so that
  review point is security-sensitive.

These facts were discussed in historical review artifacts, but I found no current operator-facing
security/ADR record that states the accepted supply-chain and availability assumptions.

## Evidence commands

```sh
git -C /Users/lukeolson/projects/gems/mood_probe status --short --branch
git -C /Users/lukeolson/projects/gems/mood_probe rev-parse HEAD origin/main 'v0.3.0^{}' v0.3.0
git -C /Users/lukeolson/projects/vibe-doctor status --short --branch
git -C /Users/lukeolson/projects/vibe-doctor rev-parse HEAD origin/main
git -C /Users/lukeolson/projects/vibe-doctor diff --quiet 1f8ad78 b26cf31
git ls-remote https://github.com/Lhosb/sonance.git HEAD refs/tags/v0.3.0 'refs/tags/v0.3.0^{}'
git -C /Users/lukeolson/projects/gems/mood_probe cat-file -t cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6
git -C /Users/lukeolson/projects/gems/mood_probe rev-parse 'cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6^{}'
git -C /Users/lukeolson/projects/gems/mood_probe tag -v v0.3.0
git -C /Users/lukeolson/projects/gems/mood_probe merge-base --is-ancestor 'v0.3.0^{}' origin/main
git -C /Users/lukeolson/projects/gems/mood_probe diff --stat 'v0.3.0^{}'..origin/main -- lib python exe sonance.gemspec
git -C /Users/lukeolson/projects/vibe-doctor grep -n -E 'Lhosb/mood_probe|mood_probe\.git' b26cf31 -- .
git -C /Users/lukeolson/projects/gems/mood_probe grep -n -E 'Lhosb/mood_probe|mood_probe\.git' d514137 -- .
curl -sSIL --max-redirs 0 https://github.com/Lhosb/mood_probe.git
git -C /Users/lukeolson/projects/vibe-doctor log --all -p -S'GITHUB_TOKEN' -- Dockerfile config/deploy.yml .github
git -C /Users/lukeolson/projects/vibe-doctor grep -n -E 'GITHUB_TOKEN|github_pat|BEGIN .* PRIVATE KEY|id_ed25519|git@github' b26cf31 -- Dockerfile config .github Gemfile Gemfile.lock .kamal
bundle exec rspec spec/model_store_spec.rb spec/python_plan_security_spec.rb spec/integration/python_plan_executor_spec.rb spec/backends/essentia_python_spec.rb
bundle exec rspec spec/sonance_dependency_spec.rb spec/services/youtube_clip_matcher_spec.rb spec/services/mood_grounding_service_spec.rb
bundle exec brakeman --no-pager -q
bundle exec bundler-audit check
```
