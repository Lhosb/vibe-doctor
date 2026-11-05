# SONANCE-MAIN-AUDIT — SHARED CONTEXT

READ THIS FILE FIRST. It is a plain file — use the Read tool. Do NOT run "maestri note read";
that stalls on a permission prompt while returning exit code 0.

## The user's ask, verbatim

"do a critical review on the entire flow now. both the gem and vibe doctor. do it off of main for
both. determine if essentia is properly ported to ruby. determine if its plugged into vibedoctor
correctly and lastly, determine if it is deployable without deploying the gem"

Three questions. Answer only the ones your dispatch assigns you, but understand all three.

## Repositories — both are MERGED TO MAIN and this audit is off main

GEM: /Users/lukeolson/projects/gems/mood_probe
  The DIRECTORY is still named mood_probe. The gem, the module and the GitHub repo are all
  named sonance. Do not report the directory name as a finding; it is known and deferred.
  Remote: github.com/Lhosb/sonance. Local main == origin/main == d514137.
  Tags present: v0.1.0, v0.2.0, v0.3.0.

APP: /Users/lukeolson/projects/vibe-doctor
  Local branch is docs/essentia-gem-v2-design. PR 17 was SQUASH-MERGED to main as b26cf31.
  I verified by execution that the local branch tree is byte-identical to origin/main
  ("git diff --stat 1f8ad78 origin/main" is empty). So reading the local checkout IS reading main.
  Confirm this yourself before relying on it. Prefer "git -C <repo>" over "cd <repo> &&".

## Facts I established myself by execution — challenge any of them if false

1. The app pins the gem at Gemfile line 34:
   gem "sonance", git: "https://github.com/Lhosb/sonance.git", tag: "v0.3.0"
   HTTPS, not SSH. An earlier SSH URL broke every CI check and was fixed.

2. Gemfile.lock records GIT revision cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6.
   That is the ANNOTATED TAG OBJECT, which peels to commit 6639397. It is NOT a moved tag and
   NOT a mismatch. Bundler records the tag object for a tag: pin. Do not report this as a defect
   without first peeling it yourself.

3. TAG v0.3.0 IS NOT AN ANCESTOR OF GEM MAIN.
   "git merge-base --is-ancestor v0.3.0^{commit} origin/main" returns NO.
   Cause: the gem branch was squash-merged as 7aabc96, so the tagged commit sits on orphaned
   pre-squash history. THIS IS A REAL STRUCTURAL FACT AND PART OF WHAT YOU ARE AUDITING.
   Assess what it means; do not assume I have already judged it.

4. Runtime code at the tag and at main is IDENTICAL. I ran:
   git diff --stat v0.3.0^{commit}..origin/main -- lib python exe sonance.gemspec  -> empty.
   The ONLY difference between the tag and main is in spec/canonical_essentia_environment_spec.rb
   and spec/support/canonical_essentia_environment.rb (a CPU-detection pattern fix).
   CONSEQUENCE: the app runs code identical to main, but main's history does not contain the tag.

## History that should shape your skepticism, not your conclusions

- Descriptor ids are all producer-qualified: valence_emomusic, arousal_emomusic,
  danceability_musicnn, mood_acoustic_musicnn, mood_relaxed_musicnn, mood_happy_musicnn,
  embedding_musicnn, bpm_rhythm2013, beat_confidence_rhythm2013.
- STALE DESCRIPTOR IDS SHIPPED TWICE in earlier rounds, in sibling files, because a gate was
  scoped to one filename. Assume more copies may exist.
- The repo-wide descriptor-id gate has a KNOWN WEAKNESS: its prefix heuristic almost never fires.
  It passed the last migration by luck, not design. Do not treat its green as proof.
- The frozen baseline at spec/fixtures/sonance/baseline_v0_1_0/ is keyed by APP COLUMN NAMES
  (mood_happy, valence, ...), NOT by descriptor ids. That is CORRECT. Do not report it.
- The app does the normalization, not the gem. The gem returns NATIVE Essentia values; the app
  applies (v - 1.0) / 8.0 and a clamp. If either side double-normalized or skipped it, every
  stored mood value would be wrong by a factor of eight.

## THE RULE THAT MATTERS MOST IN THIS AUDIT

DERIVE EVERY LIST FROM THE CODE. Do not transcribe any enumeration from this file, from a prior
report, or from another agent. My enumerations have been WRONG THREE TIMES on this project, and
every time the truth came from an agent deriving the list from the code instead of copying mine.
Treat any authoritative-sounding list as a hypothesis to falsify.

Corollary: before you write that something is absent, missing, or never run, OPEN the artifact
that would contain it. Absence from a diff is not absence of evidence.

## Evidence standard — a bare verdict will be rejected

Every report must contain:
- VERDICT on line one.
- A section separating what you VERIFIED BY EXECUTION from what you BELIEVE BY READING.
- An EVIDENCE section with the exact commands you ran and their real output. Paste output; do not
  paraphrase it. If you claim a gate passes, show it passing AND show it failing when broken.
- Findings need file, line, a concrete failure scenario, and a severity.
- If you find nothing, say what you looked for and why its absence is meaningful.

## Rules

READ-ONLY on both repositories. Do not modify, stage, commit, push, or repin anything. If you need
to run an experiment that mutates state, do it in a scratch copy OUTSIDE both repos and say where.
Both repos must be clean and on their current branches when you finish; verify and state it.
Run long commands in the background. Reply via ask-back ONLY — one report, no duplicate summary.
