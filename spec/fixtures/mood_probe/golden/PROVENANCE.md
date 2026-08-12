# mood_probe v0.2.0 golden provenance

- Source: live extraction by `spec/fixtures/mood_probe/generate_goldens.rb`, which calls `MoodProbe::Extractor#analyze`; the values were extracted, not derived from the frozen baseline or copied from another golden directory.
- Isolation: the only host directory mounted was `spec/fixtures/mood_probe/golden/`, at `/rails/spec/fixtures/mood_probe/golden`. Before extraction, the image's copy of `baseline_v0_1_0/` was moved outside `/rails` and its absence was verified, so the generator could not read it. The generator also has no baseline read or inverse-formula path.
- Generating commit: `5354b2928aa4bcd9f404e4ef90ae3effbd339ab1`.
- Image: local image `vibe-doctor-essentia-slice5b-isolated`, built from the generating commit.
- Measurement host and environment: an Apple Silicon arm64 Mac running an amd64 Linux Docker container through Docker Desktop emulation.
- Emulated CPU: `VirtualApple @ 2.50GHz`; `uname -m`: `x86_64`; Ruby host CPU: `x86_64`.
- Essentia package: `essentia-tensorflow==2.1b6.dev1389` (`essentia.__version__ == "2.1-beta6-dev"`).
- This intentionally holds the baseline's original measurement environment constant, isolating the pipeline version as the variable under test instead of confounding pipeline and execution-environment changes. That controlled experiment is why G1 reads exactly zero: the live v0.2.0 pipeline deterministically reproduced the v0.1.0 measurements byte-for-byte through the new API.
- Native x86_64 CI separately exercises the deployment-target environment against these goldens; its tolerance-based comparison measures cross-environment agreement rather than G1's same-environment pipeline parity.
- Not recorded at generation time: Docker Desktop version, whether Rosetta 2 or QEMU TCG performed translation, host CPU model, TensorFlow kernel selection, oneDNN state, and a CI run ID. Generation was local, so there is no CI run ID.
