# mood_probe v0.2.0 golden provenance

- Source: live extraction by `spec/fixtures/mood_probe/generate_goldens.rb`, which calls `MoodProbe::Extractor#analyze`; the values were extracted, not derived from the frozen baseline or copied from another golden directory.
- Isolation: only `spec/fixtures/mood_probe/golden/` was mounted from the host into the generating container. `baseline_v0_1_0/` was not mounted and the generator has no baseline read or inverse-formula path.
- Generating commit: this commit, which records the generator and its outputs atomically; generation ran from the Slice 5b working tree based on `343892659b8cfbbe4c207a6c4d7173314e395068`.
- Measurement environment: an amd64 Linux Docker container running on an Apple Silicon arm64 Mac through Docker Desktop emulation.
- Emulated CPU: `VirtualApple @ 2.50GHz`; `uname -m`: `x86_64`; Ruby host CPU: `x86_64`.
- Essentia package: `essentia-tensorflow==2.1b6.dev1389` (`essentia.__version__ == "2.1-beta6-dev"`).
- This is the same environment as the baseline original measurement, and that is why G1 reads exactly zero: the live v0.2.0 pipeline deterministically reproduced the v0.1.0 measurements byte-for-byte through the new API.
- Not recorded at generation time: Docker Desktop version, whether Rosetta 2 or QEMU TCG performed translation, host CPU model, TensorFlow kernel selection, oneDNN state, and a CI run ID. Generation was local, so there is no CI run ID.
