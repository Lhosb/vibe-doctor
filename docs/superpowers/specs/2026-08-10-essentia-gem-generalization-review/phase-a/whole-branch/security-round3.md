VERDICT: APPROVE

# Narrow parameter-validation security re-review

No findings.

Reviewed only:

`036c797f87e8a490dbcc676da0e7bfce8e0fb298..bb86f29d66ad7b4ae1e0a147b9786f02f010a9d5`

The parameter-rule refactor preserves the previously approved default-deny boundary. No crafted plan
tested was newly accepted for the shipped `RhythmExtractor2013` executor.

## Per-key default deny

**Verified:** `_ALGORITHM_PARAMS`, `_ALGORITHM_PARAM_DOMAINS`, and
`_ALGORITHM_PARAM_DEFAULTS` are unchanged between the old and new revisions. The per-key loop in
`validate_params` is unchanged:

- unknown keys are rejected;
- exact value types are enforced, including rejecting booleans where integers are required;
- non-finite values, including JSON `1e309`, are rejected before domain checks;
- numeric ranges and enum domains are enforced.

The new `_ALGORITHM_MINIMUM_SPANS` lookup runs only after those checks. An algorithm absent from the
table skips only the cross-parameter span rule; it does not skip key, type, finiteness, or domain
validation.

## RhythmExtractor2013 minimum span

**Verified:** the 20-BPM rule still applies with explicit values and defaults:

```text
explicit min=100 max=119        old=reject new=reject
explicit min=100 max=120        old=accept new=accept
default min=40, explicit max=59 old=reject new=reject
default min=40, explicit max=60 old=accept new=accept
both defaults (40, 208)         old=accept new=accept
```

The targeted subprocess spec also replaces the defaults with a 19-BPM pair and confirms the plan
fails closed. Therefore the refactor did not silently drop the rule when parameters are omitted.

## Crafted-plan differential

**Verified:** exhaustive differential testing compared old and new `validate_plan` behavior across
30,704 combinations of:

- `minTempo` from 35 through 185;
- `maxTempo` from 55 through 255;
- each key explicit or omitted.

Result:

```text
total combinations: 30704
mismatches: 0
new-only accepted combinations: 0
old-only accepted combinations: 0
```

`build_pipeline` is unchanged and still constructs only the literal allowlisted
`RhythmExtractor2013`. The new table is a module constant defined once and read with `.get`; plan
content cannot add, remove, or alter its entries.

## Host-confusion controls

**Verified:** the restored suffix and userinfo specs use a downloader double with
`expect(downloader).not_to receive(:download)`. Both pass, proving rejection occurs before downloader
invocation.

The production control remains exact parsed-host equality:

```ruby
uri.host == DOWNLOAD_HOST
```

Direct results:

```text
https://essentia.upf.edu.evil.test/model.pb
  rejected: host "essentia.upf.edu.evil.test" is not allowed

https://essentia.upf.edu@evil.test/model.pb
  rejected: host "evil.test" is not allowed

https://essentia.upf.edu/model.pb
  accepted
```

## EVIDENCE

Identity and scope:

```text
$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager status
On branch feat/essentia-gem-v2-phase-a
Your branch is up to date with 'origin/feat/essentia-gem-v2-phase-a'.
nothing to commit, working tree clean

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager rev-parse HEAD
bb86f29d66ad7b4ae1e0a147b9786f02f010a9d5

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager tag --points-at HEAD
[no output]

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager rev-list -n1 v0.2.0
848f6894a6022b5a32ae2b6b0c6898ac84986fa0

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager diff --stat \
    036c797f87e8a490dbcc676da0e7bfce8e0fb298..bb86f29d66ad7b4ae1e0a147b9786f02f010a9d5
README.md                         | 30 ++++++++++++++------
lib/mood_probe/errors.rb          | 15 +++++-----
python/mood_probe_extract.py      | 23 ++++++++++++---
spec/model_store_spec.rb          | 17 +++++++++++
spec/python_plan_security_spec.rb | 59 +++++++++++++++++++++++++++++++++++++++
5 files changed, 124 insertions(+), 20 deletions(-)

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager log --oneline \
    036c797f87e8a490dbcc676da0e7bfce8e0fb298..bb86f29d66ad7b4ae1e0a147b9786f02f010a9d5
bb86f29 docs: clarify backend extension contracts
a22270a test: pin download host confusion cases
6d2d495 fix: scope standalone parameter rules
```

Functional Python diff:

```text
$ diff \
  <(git -C /Users/lukeolson/projects/gems/mood_probe show \
    036c797f87e8a490dbcc676da0e7bfce8e0fb298:python/mood_probe_extract.py) \
  <(git -C /Users/lukeolson/projects/gems/mood_probe show \
    bb86f29d66ad7b4ae1e0a147b9786f02f010a9d5:python/mood_probe_extract.py)
[adds only _ALGORITHM_MINIMUM_SPANS and replaces the hardcoded minTempo/maxTempo tail with its
 declarative lookup; the per-key validation loop and parameter/domain/default tables are unchanged]
```

Programmatic table comparison:

```text
PARAMS equal: True
DOMAINS equal: True
DEFAULTS equal: True
old has _ALGORITHM_MINIMUM_SPANS: False
new minimum span owner: RhythmExtractor2013
new minimum span distance: 20 BPM
```

Non-finite controls:

```text
minTempo: 1e309, NaN, Infinity, -Infinity -> old reject, new reject
maxTempo: 1e309, NaN, Infinity, -Infinity -> old reject, new reject
message: <parameter> must be finite
```

Targeted and full validation:

```text
$ bundle exec rspec
188 examples, 0 failures

$ bundle exec rspec spec/python_plan_security_spec.rb spec/model_store_spec.rb \
    --format documentation
50 examples, 0 failures

$ bundle exec rubocop --no-color
48 files inspected, no offenses detected

$ ruff check .
All checks passed!

$ bundle-audit check
No vulnerabilities found

$ git -C /Users/lukeolson/projects/gems/mood_probe --no-pager diff \
    036c797f87e8a490dbcc676da0e7bfce8e0fb298..bb86f29d66ad7b4ae1e0a147b9786f02f010a9d5 \
  | grep -inE "api[_-]?key|secret|password|-----BEGIN|AKIA[0-9A-Z]{16}|Authorization: "
[no output]
```
