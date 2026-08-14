VERDICT: APPROVE

# Phase A whole-branch security review

No MUST-FIX, SHOULD-FIX, or NIT findings.

I reviewed the assembled public-release boundary at
`55d85fb246e45581172d58066c24e41c8970ac9b..848f6894a6022b5a32ae2b6b0c6898ac84986fa0`,
including the full plan executor, Ruby planner/backend, model store, registry, CLI, release files,
fixtures, and the security records from all five slices. Previously accepted risks remain accurately
documented and tracked; I found no closure that was invalidated by assembly.

## 1. Ruby-to-Python boundary

### Static dispatch and parameter control

**Verified:** `python/mood_probe_extract.py` contains no `getattr`, `eval`, `exec`, dynamic import,
subprocess, or shell dispatch. Algorithm construction compares against literal allowlisted names and
raises `PlanValidationError` otherwise (`python/mood_probe_extract.py:392-398`).

The plan has a closed key set (`:88-107`), an exact integer schema-version handshake (`:109-118`),
and per-algorithm parameter key/type/domain validation. Unknown kwargs cannot reach an Essentia
constructor. Tempo booleans, non-integers, non-finite values, values outside native ranges, and the
20-BPM interval violation are rejected before import or construction.

### Model paths

**Verified:** model filenames must be bare `.pb` basenames. Validation rejects `..`, separators,
absolute paths, nonexistent files, and symlinks, then performs `resolve(strict=True)` and
`relative_to(models_root)` containment (`python/mood_probe_extract.py:307-324`). Direct adversarial
probes rejected dot-dot traversal and a basename symlink to a file outside the models root.

This protects against plan-controlled traversal. It does not bind Python's later open to the inode
Ruby verified; that separate local-writer TOCTOU is disclosed and tracked under `mood_probe#2`.

### Schema and pre-import capabilities

**Verified:** a mismatched or boolean `schema_version` fails closed. Unknown top-level keys, unlisted
algorithm names, traversal filenames, and unknown algorithm parameters all fail validation.

The `--capabilities` path returns before importing Essentia. The import-tripwire suite proves both
halves: hostile plans fail without setting the import sentinel, while an otherwise valid plan
activates the tripwire. The relevant plan/security suites passed.

### What hostile inputs can reach

**If an attacker controls only the plan:** with a trusted, non-attacker-writable models root, they can
select only the fixed executor operations, allowlisted parameter domains, existing regular
non-symlink `.pb` basenames, and tensor/output names in those already-present graphs. They can cause a
validation or inference failure and consume inference resources; they cannot select Python functions,
inject shell syntax, traverse the filesystem through model filenames, or bypass the schema handshake.
If they also control the models root, the threat changes to the explicitly excluded local-writer
class tracked by `mood_probe#2`.

**If an attacker controls only audio bytes:** they reach Essentia/FFmpeg decoding and the fixed
allowlisted inference pipeline for the descriptors the trusted Ruby caller requested. They do not
control model paths, algorithm names, kwargs, Python executable selection, or shell commands. They can
cause decode/inference errors or resource consumption; malformed/non-finite outputs are converted to
typed per-file errors rather than executable instructions or valid values.

## 2. Model supply chain

### Verification timing

**Verified:** model lookup is descriptor-demand-driven. Before backend preflight or analysis,
`ModelStore#verify!` checks the required files against the registry SHA-256. Downloads go to a random
exclusive temporary file, are hashed, inode-checked, and atomically installed only after the digest
matches (`lib/mood_probe/model_store.rb:214-215` and surrounding `Files` implementation).

The normal application path therefore verifies before use. SHA comparison need not be constant-time:
the expected digest is public registry metadata, not a secret.

### Unenforced `byte_length`

**Verified accepted residual:** `byte_length` is recorded but not enforced. A compromised upstream or
redirect target can make an explicit `models fetch` consume excessive transfer, memory, temporary
disk, or time before the final digest rejects the body. Analysis does not fetch automatically.

This is accurately disclosed and tracked by `mood_probe#1`, which includes bounded streaming,
timeouts, and redirect-host policy. Keeping it deferred is still acceptable for a public v0.2.0
release because fetching is an explicit operator action from fixed registry URLs and SHA-256 still
prevents untrusted bytes from being installed as a valid model. It is an availability/resource risk,
not silent model substitution.

### Verify-to-reopen TOCTOU

**Verified accepted residual:** Ruby verifies a pathname/inode and Python later reopens by pathname.
A local actor able to write or replace the models root between those operations can race the verified
file. The README accurately states that pathname checks do not bind Python's later open to Ruby's
verified inode and requires the models root not be attacker-writable. Matching warnings also exist in
`model_store.rb` and the Python executor.

The public-release posture does not change that conclusion: the assumption is clear and actionable
for operators, and `mood_probe#2` tracks the stronger descriptor/inode-binding design. I did not
re-open this accepted-by-design item.

## 3. Registry host pin

**Verified:** `Model#source_url` must parse as `URI::HTTPS` and have
`uri.host == "essentia.upf.edu"` exactly (`lib/mood_probe/registry.rb:41-51`). Userinfo confusion,
suffix domains, path confusion, encoded authority tricks, HTTP, file URLs, malformed authorities,
uppercase host spelling, and trailing-dot spelling all fail closed. The check uses the parsed
authority host, not string-prefix matching.

The pin buys a narrow initial origin for all built-in registry models and prevents ordinary custom
URLs, HTTP downgrade, and common URI-authority bypasses. Redirects currently recheck HTTPS but not the
same host; a compromised pinned upstream could redirect an explicit fetch to another HTTPS origin.
The final SHA-256 prevents redirected bytes from being installed, while resource/SSRF-like GET risk is
part of the already-filed `mood_probe#1` downloader closure.

`allow_custom_models` does not exist in this release. When it lands, it must define an explicit
opt-in trust policy rather than weakening or implicitly bypassing this built-in-model invariant.

## 4. Public release posture and licensing

**Verified:** no credentials, private keys, API keys, authorization headers, passwords, or tokens were
found in the diff. The only secret-pattern match was a test variable named `token` used to inject
non-finite JSON literals.

The 44.1-kHz WAV is a synthetic mono PCM click train generated by the committed ffmpeg script with
metadata removed. The introspection JSON and `.sha256` contain public Essentia API facts and a public
digest, not host details, PII, or secrets. The gemspec packages release code/docs only; the `spec/`
fixture tree is public in the repository but is not shipped inside the gem.

**G21 verified:** `NOTICE` names the CC BY-NC-ND 4.0 compliance floor, records the ShareAlike/NoDerivatives
conflict, does not contain the obsolete “depending on the model” claim, and names
`MoodProbe::Registry`. The real CLI subprocess prints manifest-derived licence and attribution
information before the first download. Its suppression control proves the ordering assertion can fail.

## Accepted risks retained

| Risk | Status |
| --- | --- |
| Bounded/streaming download, timeouts, redirect-host closure | Accepted Phase A residual; tracked by `mood_probe#1` |
| Verify-to-Python-reopen local-writer race | Accurately disclosed; tracked by `mood_probe#2` |
| Essentia development version string not uniquely identifying a build | Accurately disclosed; tracked by `mood_probe#3` |

These remain reasonable at public release because none is silent: the model digest prevents
substitution, fetch is explicit, the local-writer assumption is stated, and each closure has a named
issue with scoped acceptance work.

## EVIDENCE

Exact range:

```text
55d85fb246e45581172d58066c24e41c8970ac9b..848f6894a6022b5a32ae2b6b0c6898ac84986fa0
```

Repository and release identity:

```text
$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager status
On branch feat/essentia-gem-v2-phase-a
Your branch is up to date with 'origin/feat/essentia-gem-v2-phase-a'.
nothing to commit, working tree clean

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager rev-parse HEAD
848f6894a6022b5a32ae2b6b0c6898ac84986fa0

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager tag --points-at HEAD
v0.2.0

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager diff --shortstat \
    55d85fb246e45581172d58066c24e41c8970ac9b..848f6894a6022b5a32ae2b6b0c6898ac84986fa0
65 files changed, 4716 insertions(+), 653 deletions(-)
```

Dynamic-dispatch search:

```text
$ grep -n "getattr\|globals\[\|eval(\|exec(\|__import__\|importlib\|subprocess\|os.system\|Popen" \
    /Users/lukeolson/projects/gems/mood_probe/python/mood_probe_extract.py
[no output]

$ grep -n "algorithm\[" /Users/lukeolson/projects/gems/mood_probe/python/mood_probe_extract.py
392:        if algorithm["name"] == "RhythmExtractor2013":
393:            instance = es.RhythmExtractor2013(**algorithm["params"])
396:                f"algorithm is not allowed: {algorithm['name']!r}"
431:        if algorithm["name"] == "RhythmExtractor2013":
```

Host-pin parser matrix:

```text
$ ruby -ruri -e '
urls = [
  "https://essentia.upf.edu/models/x.pb",
  "https://essentia.upf.edu.evil.com/x.pb",
  "https://evil.com/essentia.upf.edu/x.pb",
  "https://essentia.upf.edu%2F@evil.com/x.pb",
  "https://user@essentia.upf.edu:443@evil.com/x.pb",
  "http://essentia.upf.edu/x.pb",
  "https://ESSENTIA.UPF.EDU/x.pb",
  "https:///essentia.upf.edu/x.pb",
  "file:///etc/passwd",
  "https://essentia.upf.edu@evil.com/x.pb"
]
urls.each do |source_url|
  begin
    uri = URI.parse(source_url)
    ok = uri.is_a?(URI::HTTPS) && uri.host == "essentia.upf.edu"
    puts "#{ok ? "ACCEPT" : "reject"} host=#{uri.host.inspect} #{source_url}"
  rescue URI::InvalidURIError => e
    puts "reject parse_error=#{e.message.inspect} #{source_url}"
  end
end'
ACCEPT host="essentia.upf.edu" https://essentia.upf.edu/models/x.pb
reject host="essentia.upf.edu.evil.com" https://essentia.upf.edu.evil.com/x.pb
reject host="evil.com" https://evil.com/essentia.upf.edu/x.pb
reject host="evil.com" https://essentia.upf.edu%2F@evil.com/x.pb
reject parse_error="bad URI ..." https://user@essentia.upf.edu:443@evil.com/x.pb
reject host="essentia.upf.edu" http://essentia.upf.edu/x.pb
reject host="ESSENTIA.UPF.EDU" https://ESSENTIA.UPF.EDU/x.pb
reject host="" https:///essentia.upf.edu/x.pb
reject host="" file:///etc/passwd
reject host="evil.com" https://essentia.upf.edu@evil.com/x.pb
```

Direct model-path validation:

```text
$ WORKDIR=$(mktemp -d) && mkdir -p "$WORKDIR/models" "$WORKDIR/outside" \
  && echo secret > "$WORKDIR/outside/secret.pb" \
  && ln -s "$WORKDIR/outside/secret.pb" "$WORKDIR/models/link.pb" \
  && git -C /Users/lukeolson/projects/gems/mood_probe show \
       848f6894a6022b5a32ae2b6b0c6898ac84986fa0:python/mood_probe_extract.py \
       > "$WORKDIR/mood_probe_extract.py" \
  && python3 - "$WORKDIR/models" "$WORKDIR" <<'PYEOF'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[2])
import mood_probe_extract as m
root = Path(sys.argv[1]).resolve()
for filename, label in [
    ("link.pb", "symlink-to-outside-file"),
    ("../outside/secret.pb", "dotdot-traversal"),
    ("legit.pb", "nonexistent-file"),
]:
    try:
        m.validate_model_path(filename, root, "plan.graphs[0].file")
        print(f"{label} -> ACCEPTED")
    except m.PlanValidationError as error:
        print(f"{label} -> rejected: {error}")
PYEOF
symlink-to-outside-file -> rejected: plan.graphs[0].file must identify a regular non-symlink file
dotdot-traversal -> rejected: plan.graphs[0].file must be a bare .pb basename
nonexistent-file -> rejected: plan.graphs[0].file must resolve inside the models directory
```

Test and scanner runs:

```text
$ git -C /Users/lukeolson/projects/gems/mood_probe \
    -c safe.directory=/Users/lukeolson/projects/gems/mood_probe status --short
[no output]

$ cd /Users/lukeolson/projects/gems/mood_probe && bundle exec rspec
173 examples, 0 failures

$ cd /Users/lukeolson/projects/gems/mood_probe && \
    bundle exec rspec spec/python_plan_security_spec.rb \
      spec/python_plan_fixture_spec.rb spec/python_script_spec.rb
41 examples, 0 failures

$ cd /Users/lukeolson/projects/gems/mood_probe && \
    bundle exec rspec spec/license_notice_spec.rb --format documentation
model fetch license notice
  prints manifest-derived licenses before the first download in one ordered stream
  proves the ordering contract fails when the notice is suppressed
  states the compliance floor without the obsolete per-model claim
  verifies every registered model through the real CLI subprocess
4 examples, 0 failures

$ cd /Users/lukeolson/projects/gems/mood_probe && bundle exec rubocop --no-color
Inspecting 46 files
46 files inspected, no offenses detected

$ cd /Users/lukeolson/projects/gems/mood_probe && bundle-audit check --update
ruby-advisory-db:
  advisories: 1231 advisories
No vulnerabilities found
```

Public-content checks:

```text
$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager diff \
    55d85fb246e45581172d58066c24e41c8970ac9b..848f6894a6022b5a32ae2b6b0c6898ac84986fa0 \
    -- . ':(exclude)*.wav' \
  | grep -inE "api[_-]?key|secret|password|token|-----BEGIN|AKIA[0-9A-Z]{16}|Authorization: "
5495:+  %w[minTempo maxTempo].product(%w[NaN Infinity -Infinity 1e309]).each do |key, token|
5496:+    it "rejects #{token} for the #{key} algorithm parameter before importing Essentia" do
5499:+        payload = plan_json_with_raw_param(key, token)
5707:+  def plan_json_with_raw_param(key, token)
5710:+    JSON.generate(plan).sub(JSON.generate(marker), token)

$ file /Users/lukeolson/projects/gems/mood_probe/spec/fixtures/mood_probe/audio/clicks_44100.wav
RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 44100 Hz
```
