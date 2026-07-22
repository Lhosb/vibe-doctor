#!/usr/bin/env python3
"""Extract Essentia mood features for one audio file."""

import argparse
import json
import sys
from pathlib import Path

_EMBEDDING_MODEL_FILENAME = "msd-musicnn-1.pb"
_EMBEDDING_OUTPUT_NODE = "model/dense/BiasAdd"
_HEAD_MODELS = {
    "danceability": ("danceability-msd-musicnn-1.pb", 0),
    "mood_acoustic": ("mood_acoustic-msd-musicnn-1.pb", 0),
    "mood_relaxed": ("mood_relaxed-msd-musicnn-1.pb", 1),
    "mood_happy": ("mood_happy-msd-musicnn-1.pb", 0),
}
_HEAD_OUTPUT_NODE = "model/Softmax"
_VALENCE_AROUSAL_MODEL_FILENAME = "emomusic-msd-musicnn-2.pb"
_VALENCE_AROUSAL_OUTPUT_NODE = "model/Identity"


def analyze(audio_path: Path, models_dir: Path) -> dict:
    import essentia.standard as es

    audio = es.MonoLoader(filename=str(audio_path), sampleRate=16000, resampleQuality=4)()
    embeddings = es.TensorflowPredictMusiCNN(
        graphFilename=str(models_dir / _EMBEDDING_MODEL_FILENAME),
        output=_EMBEDDING_OUTPUT_NODE,
    )(audio)

    result: dict = {}
    for key, (filename, positive_index) in _HEAD_MODELS.items():
        predictions = es.TensorflowPredict2D(
            graphFilename=str(models_dir / filename), output=_HEAD_OUTPUT_NODE
        )(embeddings)
        result[key] = float(predictions.mean(axis=0)[positive_index])

    va_predictions = es.TensorflowPredict2D(
        graphFilename=str(models_dir / _VALENCE_AROUSAL_MODEL_FILENAME),
        output=_VALENCE_AROUSAL_OUTPUT_NODE,
    )(embeddings)
    va_mean = va_predictions.mean(axis=0)
    result["valence"] = float((va_mean[0] - 1.0) / 8.0)
    result["arousal"] = float((va_mean[1] - 1.0) / 8.0)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("audio_path")
    parser.add_argument("--models-dir", required=True)
    args = parser.parse_args()

    try:
        result = analyze(Path(args.audio_path), Path(args.models_dir))
    except Exception as exc:
        print(f"essentia_extract failed: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
