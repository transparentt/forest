#!/usr/bin/env python3
"""Local Qwen3-ASR server for low-latency repeated dictation.

The server binds to 127.0.0.1 by default and keeps Qwen3-ASR loaded in memory.
It accepts raw WAV bytes via POST /transcribe and returns JSON.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


DEFAULT_MODEL_DIR = Path.home() / ".localvoiceinput" / "models" / "Qwen3-ASR-1.7B"
DEFAULT_GEMMA_MODEL = "gemma4:e4b"
DEFAULT_GEMMA_BACKEND_URL = "http://127.0.0.1:11434/api/generate"


class ASRRuntime:
    def __init__(self, model_dir: Path):
        self.model_dir = model_dir
        self._lock = threading.Lock()
        self._inference_lock = threading.Lock()
        self._model = None
        self._device_map: str | None = None
        self._dtype_name: str | None = None
        self._warmed = False

    def load(self):
        if self._model is not None:
            return self._model

        with self._lock:
            if self._model is not None:
                return self._model

            if not self.model_dir.is_dir():
                raise RuntimeError(f"Qwen3-ASR model directory not found: {self.model_dir}")

            import torch
            from qwen_asr import Qwen3ASRModel

            if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
                device_map = "mps"
                dtype = torch.float16
            else:
                device_map = "cpu"
                dtype = torch.float32

            self._device_map = device_map
            self._dtype_name = str(dtype).replace("torch.", "")

            self._model = Qwen3ASRModel.from_pretrained(
                str(self.model_dir),
                dtype=dtype,
                device_map=device_map,
                local_files_only=True,
                max_inference_batch_size=1,
                max_new_tokens=256,
            )
            return self._model

    def transcribe(self, audio_path: Path, language: str | None) -> str:
        model = self.load()
        max_new_tokens = self._max_new_tokens_for(audio_path)
        with self._inference_lock:
            previous_max_new_tokens = model.max_new_tokens
            model.max_new_tokens = max_new_tokens
            try:
                results = model.transcribe(str(audio_path), language=language)
            finally:
                model.max_new_tokens = previous_max_new_tokens
        return results[0].text.strip() if results else ""

    def warm_up(self):
        model = self.load()
        if self._warmed:
            return

        with self._inference_lock:
            if self._warmed:
                return

            previous_max_new_tokens = model.max_new_tokens
            model.max_new_tokens = 16
            try:
                import numpy as np

                silence = np.zeros(1600, dtype=np.float32)
                model.transcribe((silence, 16_000), language="Japanese")
                self._warmed = True
            finally:
                model.max_new_tokens = previous_max_new_tokens

    def _max_new_tokens_for(self, audio_path: Path) -> int:
        duration = self._audio_duration(audio_path)
        if duration is None:
            return 256
        if duration <= 3:
            return 64
        if duration <= 10:
            return 128
        if duration <= 18:
            return 192
        return 256

    def _audio_duration(self, audio_path: Path) -> float | None:
        try:
            with wave.open(str(audio_path), "rb") as audio:
                frame_rate = audio.getframerate()
                if frame_rate <= 0:
                    return None
                return audio.getnframes() / float(frame_rate)
        except Exception:
            return None

    def diagnostics(self) -> dict:
        try:
            import torch

            mps_built = bool(getattr(torch.backends, "mps", None) and torch.backends.mps.is_built())
            mps_available = bool(getattr(torch.backends, "mps", None) and torch.backends.mps.is_available())
            torch_version = str(torch.__version__)
        except Exception as exc:
            return {
                "modelLoaded": self._model is not None,
                "modelDir": str(self.model_dir),
                "torchError": str(exc),
            }

        return {
            "modelLoaded": self._model is not None,
            "warmed": self._warmed,
            "modelDir": str(self.model_dir),
            "torchVersion": torch_version,
            "mpsBuilt": mps_built,
            "mpsAvailable": mps_available,
            "device": self._device_map,
            "dtype": self._dtype_name,
        }


class GemmaRuntime:
    def __init__(self, default_model: str, default_backend_url: str):
        self.default_model = default_model
        self.default_backend_url = default_backend_url
        self._available_models: set[str] = set()
        self._lock = threading.Lock()

    def customize(
        self,
        instruction: str,
        text: str,
        timeout: float,
        model: str | None = None,
        backend_url: str | None = None,
        dictionary_entries: list[dict] | None = None,
    ) -> str:
        return self.customize_with_metrics(
            instruction=instruction,
            text=text,
            timeout=timeout,
            model=model,
            backend_url=backend_url,
            dictionary_entries=dictionary_entries,
        )["text"]

    def customize_with_metrics(
        self,
        instruction: str,
        text: str,
        timeout: float,
        model: str | None = None,
        backend_url: str | None = None,
        dictionary_entries: list[dict] | None = None,
    ) -> dict:
        selected_model = model or self.default_model
        selected_backend = backend_url or self.default_backend_url
        ensure_started = time.perf_counter()
        self._ensure_model(selected_model, timeout=max(30, int(timeout)))
        ensure_duration = time.perf_counter() - ensure_started
        generate_started = time.perf_counter()
        generated = self._generate(
            instruction=instruction,
            text=text,
            timeout=timeout,
            model=selected_model,
            backend_url=selected_backend,
            dictionary_entries=dictionary_entries or [],
        ).strip()
        generate_duration = time.perf_counter() - generate_started
        return {
            "text": generated,
            "modelCheckDuration": ensure_duration,
            "generationDuration": generate_duration,
        }

    def _ensure_model(self, model: str, timeout: int):
        if model in self._available_models:
            return

        with self._lock:
            if model in self._available_models:
                return

            ollama = self._ollama_path()
            if ollama is None:
                raise RuntimeError("ollama command not found. Install Ollama or set a different Gemma backend.")

            show = subprocess.run(
                [ollama, "show", model],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
                check=False,
            )
            if show.returncode != 0:
                pull = subprocess.run(
                    [ollama, "pull", model],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=timeout,
                    check=False,
                )
                if pull.returncode != 0:
                    raise RuntimeError(f"Failed to pull Gemma model: {model}")

            self._available_models.add(model)

    def _generate(
        self,
        instruction: str,
        text: str,
        timeout: float,
        model: str,
        backend_url: str,
        dictionary_entries: list[dict],
    ) -> str:
        prompt = self._build_prompt(instruction, text, dictionary_entries)
        body = json.dumps(
            {
                "model": model,
                "prompt": prompt,
                "stream": False,
                "think": False,
                "keep_alive": "30m",
                "options": {
                    "temperature": 0.1,
                    "num_predict": self._num_predict_for(text),
                },
            },
            ensure_ascii=False,
        ).encode("utf-8")

        request = urllib.request.Request(
            backend_url,
            data=body,
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if response.status != 200:
                raise RuntimeError(f"Gemma backend returned HTTP {response.status}")
            decoded = json.loads(response.read().decode("utf-8"))
            return str(decoded.get("response", ""))

    def _build_prompt(self, instruction: str, text: str, dictionary_entries: list[dict]) -> str:
        parts = [
            "入力文を編集します。絶対に要約しない。絶対に文を削除しない。入力にある全ての文を同じ順番で残す。指定された変更だけを反映する。本文だけ返す。",
        ]

        normalized_entries = self._normalized_dictionary_entries(dictionary_entries)
        if normalized_entries:
            parts.append("辞書は必ず適用してください。入力または出力に対象ワードが含まれる場合は、変換ワードの表記に統一してください。")
            parts.append("辞書:")
            for source, target in normalized_entries:
                parts.append(f"- {source} => {target}")

        normalized_instruction = instruction.strip()
        if normalized_instruction:
            parts.append(f"指示: {normalized_instruction}")
            parts.append("指示の範囲外の文字は保持してください。")

        parts.append(f"入力: {text}")
        parts.append("出力:")
        return "\n".join(parts)

    def _normalized_dictionary_entries(self, entries: list[dict]) -> list[tuple[str, str]]:
        normalized = []
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            source = str(entry.get("source", "")).strip()
            target = str(entry.get("target", "")).strip()
            if source and target:
                normalized.append((source, target))
        return normalized[:80]

    def _num_predict_for(self, text: str) -> int:
        length = len(text)
        if length <= 40:
            return 96
        if length <= 100:
            return 160
        if length <= 220:
            return 256
        return 384

    def _ollama_path(self) -> str | None:
        found = shutil.which("ollama")
        if found:
            return found

        for candidate in ("/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"):
            if Path(candidate).is_file():
                return candidate
        return None


class Handler(BaseHTTPRequestHandler):
    runtime: ASRRuntime
    gemma_runtime: GemmaRuntime

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True})
            return

        if self.path == "/asr/health":
            try:
                self.runtime.warm_up()
                self._json(200, {"ok": True})
            except Exception as exc:
                self._json(503, {"ok": False, "error": str(exc)})
            return

        if self.path == "/diagnostics":
            self._json(200, {"asr": self.runtime.diagnostics()})
            return

        self._json(404, {"error": "not found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/customize":
            self._customize()
            return

        if parsed.path != "/transcribe":
            self._json(404, {"error": "not found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            self._json(400, {"error": "empty audio body"})
            return

        language_arg = parse_qs(parsed.query).get("language", ["Japanese"])[0]
        language = None if language_arg.lower() == "auto" else language_arg

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp:
            temp.write(self.rfile.read(length))
            temp_path = Path(temp.name)

        try:
            text = self.runtime.transcribe(temp_path, language)
            self._json(200, {"text": text})
        except Exception as exc:
            self._json(500, {"error": str(exc)})
        finally:
            temp_path.unlink(missing_ok=True)

    def _customize(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            self._json(400, {"error": "empty body"})
            return

        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            customization_enabled = bool(payload.get("customizationEnabled", True))
            dictionary_enabled = bool(payload.get("dictionaryEnabled", False))
            instruction = str(payload.get("instruction", "")).strip() if customization_enabled else ""
            text = str(payload.get("text", "")).strip()
            dictionary_entries = payload.get("dictionaryEntries", []) if dictionary_enabled else []
            timeout = float(payload.get("timeout", 12))
            model = str(payload.get("model", "")).strip() or None
            backend_url = str(payload.get("backendURL", "")).strip() or None
            if not text:
                self._json(200, {"text": text})
                return
            if not instruction and not dictionary_entries:
                self._json(200, {"text": text})
                return

            customized = self.gemma_runtime.customize_with_metrics(
                instruction=instruction,
                text=text,
                timeout=timeout,
                model=model,
                backend_url=backend_url,
                dictionary_entries=dictionary_entries,
            )
            self._json(200, {
                "text": customized.get("text") or text,
                "modelCheckDuration": customized.get("modelCheckDuration"),
                "generationDuration": customized.get("generationDuration"),
            })
        except (TimeoutError, urllib.error.URLError) as exc:
            self._json(504, {"error": str(exc)})
        except Exception as exc:
            self._json(500, {"error": str(exc)})

    def log_message(self, format: str, *args):
        return

    def _json(self, status: int, payload: dict):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a local Qwen3-ASR HTTP server.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.environ.get("LOCALVOICEINPUT_ASR_PORT", "8765")))
    parser.add_argument(
        "--model",
        type=Path,
        default=Path(os.environ.get("LOCALVOICEINPUT_QWEN_MODEL", DEFAULT_MODEL_DIR)),
    )
    parser.add_argument("--gemma-model", default=os.environ.get("FOREST_GEMMA_MODEL", DEFAULT_GEMMA_MODEL))
    parser.add_argument("--gemma-backend-url", default=os.environ.get("FOREST_GEMMA_BACKEND_URL", DEFAULT_GEMMA_BACKEND_URL))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    Handler.runtime = ASRRuntime(args.model)
    Handler.gemma_runtime = GemmaRuntime(
        default_model=args.gemma_model,
        default_backend_url=args.gemma_backend_url,
    )
    server = ThreadingHTTPServer((args.host, args.port), Handler)

    print(f"Forest local server listening on http://{args.host}:{args.port}", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    finally:
        server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())
