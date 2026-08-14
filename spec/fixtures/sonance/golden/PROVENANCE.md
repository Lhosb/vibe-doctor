# Sonance golden fixture provenance

- Original source: live extraction by mood_probe v0.2.0 using the generator now located at `spec/fixtures/sonance/generate_goldens.rb`. The values were extracted, not derived from the frozen baseline or copied from another golden directory.
- Source closure: the measurement inputs are the audio fixtures under `audio/*.wav` and the six model weights under `tmp/essentia_models`; the weight SHA-256 digests were pinned by the mood_probe v0.2.0 registry. The original generator invoked `MoodProbe::Extractor#analyze` and wrote the returned values. Neither the generator nor its extraction path read baseline or golden JSON.
- Generating commit: `5354b2928aa4bcd9f404e4ef90ae3effbd339ab1`.
- Image: local image `vibe-doctor-essentia-slice5b-isolated`, built from the generating commit.
- Measurement host and environment: an Apple Silicon arm64 Mac running an amd64 Linux Docker container through Docker Desktop emulation.
- Emulated CPU: `VirtualApple @ 2.50GHz`; `uname -m`: `x86_64`; Ruby host CPU: `x86_64`.
- Essentia package: `essentia-tensorflow==2.1b6.dev1389` (`essentia.__version__ == "2.1-beta6-dev"`).
- This intentionally holds the baseline's original measurement environment constant, isolating the pipeline version as the variable under test instead of confounding pipeline and execution-environment changes. That controlled experiment is why G1 reads exactly zero: the live v0.2.0 pipeline deterministically reproduced the v0.1.0 measurements byte-for-byte through the new API.
- Native x86_64 CI separately exercises the deployment-target environment against these goldens; its tolerance-based comparison measures cross-environment agreement rather than G1's same-environment pipeline parity.
- Not recorded at generation time: Docker Desktop version, whether Rosetta 2 or QEMU TCG performed translation, host CPU model, TensorFlow kernel selection, oneDNN state, and a CI run ID. Generation was local, so there is no CI run ID.
- Sonance 0.3.0 migration: the behaviour commit containing this line moved `spec/fixtures/mood_probe/` to `spec/fixtures/sonance/` and relabelled the four MusicNN JSON keys without regenerating measurements. Before and after, the ordered-value manifest had SHA-256 `719c5e7e815a80e55c3fa83d6c6b47997ed2ef3d2a7aaa3a5814d9053f1d4828`.
