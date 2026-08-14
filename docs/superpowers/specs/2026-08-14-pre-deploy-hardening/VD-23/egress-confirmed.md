## Builder egress confirmed — the plan's one unconfirmed fact is settled

The remote builder at `5.78.177.23` **does** have outbound HTTPS to `essentia.upf.edu`:

```
$ ssh deploy@5.78.177.23 'curl -sI --max-time 15 https://essentia.upf.edu/ | head -1'
HTTP/1.1 200 OK
```

Run by the repository owner, 2026-08-14.

This removes the contingency recorded in the accepted design. The fallback — moving the bytes to
`vendor/essentia_models/`, out of `tmp/`, while keeping the verify gate — is **not** needed and
should not be implemented.

The design proceeds as written:

1. Remove the six `.pb` binaries from the tracked tree.
2. Fetch them at **build time** in the Dockerfile via the gem CLI into `/usr/local/essentia-models`.
3. Run `sonance models verify` in the **final** stage as uid 1000, so it validates digests *and*
   ownership *and* mode exactly as the runtime user sees them.

No volume, no deploy hook, no gem change.

### Two things the implementer must not get wrong

**The obvious check does not discriminate.** The old configuration *passes* models-verify under
`--network none`, because the models really are present today. Reporting that as proof would be
proving nothing.

The real negative control is applying the **same sabotage to both** configurations — delete the
`.dockerignore` negations:

- **OLD**: build exits 0, produces a broken image, fails only at first enrichment.
- **NEW**: build exits **non-zero**, no image is produced.

**Sequencing with #29.** The attribution branch `fix/model-attribution-notice` states that the
model files are redistributed in this repository and explicitly flags that the list must be
revisited when this issue lands. That revisit is part of this issue's scope, not a follow-up —
the NOTICE must be corrected in the same change that removes the binaries, or it becomes untrue
the moment this merges.

Note also that git history retains the blobs. A history rewrite is **not** recommended for
3.44 MiB, so the NOTICE should not claim the models were never distributed here.
