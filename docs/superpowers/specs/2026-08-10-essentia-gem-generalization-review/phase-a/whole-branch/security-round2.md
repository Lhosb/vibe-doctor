VERDICT: APPROVE

# mood_probe 0.2.1 security remediation re-review

No findings.

The prior whole-branch security report had zero findings. That posture remains valid after reviewing
only:

`848f6894a6022b5a32ae2b6b0c6898ac84986fa0..036c797f87e8a490dbcc676da0e7bfce8e0fb298`

The remediation closes the previously documented redirect-host residual without weakening model
construction, local verification, path containment, digest enforcement, or the Ruby-to-Python
boundary.

## Host-control move

### Non-allowlisted custom sources

**Verified:** a `Model` with a non-allowlisted HTTPS source can now be constructed. Its filename,
lowercase SHA-256, positive integer `byte_length`, and HTTPS scheme remain construction invariants.
If the matching model file is already present locally, `ModelStore#verify!` succeeds without network
access.

The same model cannot be downloaded: `ModelStore.validate_download_uri!` rejects its host before a
temporary file or HTTP request is created.

Observed:

```text
Model constructed OK with non-allowlisted host: "https://models.example.test/evil.pb"
Local verify! (digest-only, no network) result: true
fetch! raised BackendError as expected: model download host "models.example.test" is not allowed
```

This is the intended public boundary: third parties can distribute and locally provision
digest-pinned models without weakening the built-in downloader's network policy.

### Redirect enforcement

**Verified:** the same URI validator owns the initial download and every redirect target.
`Downloader#request` validates the resolved redirect URI before calling `Net::HTTP.get_response`.

Different-host HTTPS, protocol-relative different-host, HTTP downgrade, suffix-domain, userinfo,
uppercase-host, and trailing-dot redirects all failed closed. In each rejected case the HTTP mock
recorded one call only, proving the second hop was never dispatched. Relative and absolute redirects
to the exact allowed host proceeded.

Representative output:

```text
https-different-host  calls=1 -> rejected: model download host "evil.example.test" is not allowed
protocol-relative     calls=1 -> rejected: model download host "evil.example.test" is not allowed
http-downgrade         calls=1 -> rejected: model downloads require HTTPS
suffix-domain          calls=1 -> rejected: model download host "essentia.upf.edu.evil.test" is not allowed
userinfo-trick         calls=1 -> rejected: model download host "evil.example.test" is not allowed
uppercase-host         calls=1 -> rejected: model download host "ESSENTIA.UPF.EDU" is not allowed
trailing-dot-host      calls=1 -> rejected: model download host "essentia.upf.edu." is not allowed
same-host-relative     calls=2 -> accepted
same-host-absolute     calls=2 -> accepted
```

This closes the round-1 residual where redirects rechecked HTTPS but not host.

### Construction and filesystem invariants

**Verified unchanged:**

- `..`, path separators, absolute paths, nested paths, and non-`.pb` filenames fail construction.
- SHA-256 must be exactly lowercase hexadecimal of the required length.
- `byte_length` must be a positive integer. Enforcement during transfer remains deliberately deferred
  to issue `#1` and was not re-opened.
- Existing symlink/root/path-containment checks remain intact.
- A downloaded digest mismatch leaves no installed file.
- The verify-to-Python-reopen local-writer race remains unchanged, accurately disclosed, and tracked
  by issue `#2`.

Observed controls:

```text
basename with ..: rejected
basename with path separator: rejected
absolute path basename: rejected
non-.pb extension: rejected
sha256 wrong length: rejected
sha256 uppercase hex: rejected
byte_length zero/negative/float: rejected
valid basename+sha+bytelen: accepted
symlink-to-outside-file: rejected
downloaded digest mismatch: rejected
installed file exists after mismatch: false
```

## CLI descriptor parsing

**Verified:** `--descriptors IDS` is parsed by `OptionParser` as a comma-separated array, stripped,
empties removed, and identifiers passed to registry/planner lookup. The values are not interpolated
into shell strings or used with `send`, `const_get`, `eval`, or dynamic Python dispatch.

Unknown descriptors fail before plan construction with a domain `ConfigurationError`. The backend
continues to use an argv array through `Open3.popen3(*command)`.

Shell-looking values were treated as literal descriptor names and produced no side effect:

```text
$ bundle exec ruby -Ilib exe/mood-probe \
    --models-dir /tmp/mp_empty_models \
    --descriptors '$(touch /tmp/mp_probe_marker)' analyze track.wav
unknown descriptor: $(touch /tmp/mp_probe_marker); valid descriptors: ...

$ ls /tmp/mp_probe_marker
ls: /tmp/mp_probe_marker: No such file or directory
```

The `descriptors` subcommand prints only static registry IDs. Missing `--descriptors` fails clearly.
No CLI flag can disable download-host, path, digest, schema, or plan validation.

The `respond_to?(:analyze_all)` backend change is not attacker-selected: backend injection remains a
keyword-only application/test seam, and verification/preflight behavior is unchanged.

## Public-release ruling

The assembled boundary remains sound for public release as 0.2.1:

- custom registry construction is less opinionated without relaxing downloader policy;
- all download hops enforce HTTPS and the exact host;
- SHA-256 remains the model-content trust anchor;
- local files can be verified without forcing the built-in network origin;
- CLI descriptors cannot become code, shell, paths, or arbitrary algorithm dispatch;
- accepted issue `#1` and `#2` residuals remain explicit and unchanged.

Malformed redirect `Location` values can still raise `URI::InvalidURIError` rather than the normalized
gem error. Probes showed they fail before a second request is dispatched. This is a robustness/DoS
detail, not a host-policy bypass or security finding.

## EVIDENCE

Identity and delta:

```text
$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager status
On branch feat/essentia-gem-v2-phase-a
nothing to commit, working tree clean

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager rev-parse HEAD
036c797f87e8a490dbcc676da0e7bfce8e0fb298

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager tag --points-at HEAD
[no output]

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager rev-list -n1 v0.2.0
848f6894a6022b5a32ae2b6b0c6898ac84986fa0

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager diff --shortstat \
    848f6894a6022b5a32ae2b6b0c6898ac84986fa0..036c797f87e8a490dbcc676da0e7bfce8e0fb298
21 files changed, 327 insertions(+), 31 deletions(-)

$ git -C /Users/lukeolson/projects/gems/mood_probe show \
    036c797f87e8a490dbcc676da0e7bfce8e0fb298:lib/mood_probe/version.rb
module MoodProbe
  VERSION = "0.2.1".freeze
end
```

Tests and scanners:

```text
$ bundle exec rspec
184 examples, 0 failures

$ bundle exec rspec spec/model_store_spec.rb spec/registry_spec.rb spec/planner_spec.rb \
    spec/cli_spec.rb spec/extractor_spec.rb spec/baseline_v0_1_0_parity_spec.rb \
    --format documentation
63 examples, 0 failures

$ bundle exec rubocop --no-color
48 files inspected, no offenses detected

$ bundle-audit check --update
ruby-advisory-db: advisories: 1231 advisories
No vulnerabilities found
```

The targeted run included:

```text
verifies a locally supplied model from a non-allowlisted HTTPS source
rejects downloading a model from a non-allowlisted host
rejects an HTTP redirect before following it
uses analyze_all on any backend that provides it
passes comma-separated descriptor ids to analyze
requires --descriptors for analyze
prints available descriptor ids
raises a gem configuration error for an unknown descriptor id
accepts HTTPS model sources outside the download allowlist
requires a SHA-256 digest and positive byte length
raises a gem configuration error for an unknown graph algorithm
```

Changed-file secret scan:

```text
$ grep -rinE "api[_-]?key|secret|password|-----BEGIN|AKIA[0-9A-Z]{16}|Authorization: " \
    $(git -C /Users/lukeolson/projects/gems/mood_probe --no-pager diff --name-only \
      848f6894a6022b5a32ae2b6b0c6898ac84986fa0..036c797f87e8a490dbcc676da0e7bfce8e0fb298)
[no output]
```
