#!/usr/bin/env python3
"""Local-only Qwen3-ASR runner for Forest.

The runner accepts a WAV path and prints recognized text to stdout.
It intentionally requires a local model directory by default so the
dictation app never performs hidden network access.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


DEFAULT_MODEL_DIR = Path.home() / ".localvoiceinput" / "models" / "Qwen3-ASR-1.7B"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Transcribe one local audio file with Qwen3-ASR.")
    parser.add_argument("audio_file", type=Path, help="Path to a local WAV file.")
    parser.add_argument(
        "--model",
        type=Path,
        default=Path(os.environ.get("LOCALVOICEINPUT_QWEN_MODEL", DEFAULT_MODEL_DIR)),
        help="Local model directory. Defaults to ~/.localvoiceinput/models/Qwen3-ASR-1.7B.",
    )
    parser.add_argument(
        "--language",
        default=os.environ.get("LOCALVOICEINPUT_ASR_LANGUAGE", "Japanese"),
        help='Recognition language passed to qwen-asr. Use "auto" for model language detection.',
    )
    return parser.parse_args()


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 2


def main() -> int:
    args = parse_args()

    if not args.audio_file.is_file():
        return fail(f"Audio file not found: {args.audio_file}")

    if not args.model.is_dir():
        return fail(
            "Qwen3-ASR model directory not found: "
            f"{args.model}\n"
            "Place the model there or set LOCALVOICEINPUT_QWEN_MODEL to a local model directory."
        )

    try:
        import torch
        from qwen_asr import Qwen3ASRModel
    except ImportError as exc:
        return fail(
            "Missing Python ASR dependencies. Install qwen-asr and torch "
            f"in the runner environment. Details: {exc}"
        )

    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        device_map = "mps"
        dtype = torch.float16
    else:
        device_map = "cpu"
        dtype = torch.float32

    try:
        model = Qwen3ASRModel.from_pretrained(
            str(args.model),
            dtype=dtype,
            device_map=device_map,
            local_files_only=True,
            max_inference_batch_size=1,
            max_new_tokens=256,
        )
        language = None if args.language.lower() == "auto" else args.language
        results = model.transcribe(str(args.audio_file), language=language)
    except Exception as exc:
        return fail(f"Qwen3-ASR transcription failed: {exc}")

    text = results[0].text if results else ""

    print(text.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
