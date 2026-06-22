import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SERVER_PATH = ROOT / "scripts" / "qwen3_asr_server.py"
SPEC = importlib.util.spec_from_file_location("qwen3_asr_server", SERVER_PATH)
server = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(server)


class GemmaRuntimePromptTests(unittest.TestCase):
    def setUp(self):
        self.runtime = server.GemmaRuntime("gemma4:e4b", "http://127.0.0.1:11434/api/generate")

    def test_prompt_combines_dictionary_and_customization(self):
        prompt = self.runtime._build_prompt(
            "敬語にしてください",
            "くえんのモデルを使う",
            [{"source": "くえん", "target": "Qwen"}],
        )

        self.assertIn("辞書:", prompt)
        self.assertIn("- くえん => Qwen", prompt)
        self.assertIn("指示: 敬語にしてください", prompt)
        self.assertIn("絶対に要約しない", prompt)
        self.assertIn("絶対に文を削除しない", prompt)
        self.assertIn("指示の範囲外の文字は保持してください。", prompt)
        self.assertIn("入力: くえんのモデルを使う", prompt)

    def test_prompt_allows_dictionary_only(self):
        prompt = self.runtime._build_prompt(
            "",
            "あくあぼいすを使う",
            [{"source": "あくあぼいす", "target": "AquaVoice"}],
        )

        self.assertIn("- あくあぼいす => AquaVoice", prompt)
        self.assertNotIn("指示:", prompt)

    def test_dictionary_entries_are_sanitized(self):
        entries = self.runtime._normalized_dictionary_entries([
            {"source": " くえん ", "target": " Qwen "},
            {"source": "", "target": "empty"},
            "invalid",
        ])

        self.assertEqual(entries, [("くえん", "Qwen")])

    def test_customize_calls_gemma_once_with_dictionary_only(self):
        runtime = FakeGemmaRuntime("gemma4:e4b", "http://127.0.0.1:11434/api/generate")
        runtime.generated_text = "Qwenのモデルを使います。"

        actual = runtime.customize(
            instruction="",
            text="くえんのモデルを使います。",
            timeout=1,
            dictionary_entries=[{"source": "くえん", "target": "Qwen"}],
        )

        self.assertEqual(actual, "Qwenのモデルを使います。")
        self.assertEqual(runtime.generate_call_count, 1)
        self.assertEqual(runtime.last_dictionary_entries, [{"source": "くえん", "target": "Qwen"}])

    def test_customize_calls_gemma_once_with_dictionary_and_customization(self):
        runtime = FakeGemmaRuntime("gemma4:e4b", "http://127.0.0.1:11434/api/generate")
        runtime.generated_text = "Qwenのモデルを使用いたします。"

        actual = runtime.customize(
            instruction="敬語にしてください",
            text="くえんのモデルを使う。",
            timeout=1,
            dictionary_entries=[{"source": "くえん", "target": "Qwen"}],
        )

        self.assertEqual(actual, "Qwenのモデルを使用いたします。")
        self.assertEqual(runtime.generate_call_count, 1)
        self.assertEqual(runtime.last_instruction, "敬語にしてください")
        self.assertEqual(runtime.last_dictionary_entries, [{"source": "くえん", "target": "Qwen"}])

    def test_customize_with_metrics_returns_timing_fields(self):
        runtime = FakeGemmaRuntime("gemma4:e4b", "http://127.0.0.1:11434/api/generate")
        runtime.generated_text = "ログのテストをしています。\nログのテストをしています。"

        actual = runtime.customize_with_metrics(
            instruction="改行という語を改行コードにしてください",
            text="ログのテストをしています。改行。ログのテストをしています。",
            timeout=1,
            dictionary_entries=[],
        )

        self.assertEqual(actual["text"], "ログのテストをしています。\nログのテストをしています。")
        self.assertIn("modelCheckDuration", actual)
        self.assertIn("generationDuration", actual)
        self.assertEqual(runtime.generate_call_count, 1)


class FakeGemmaRuntime(server.GemmaRuntime):
    generated_text = ""
    generate_call_count = 0
    last_instruction = None
    last_dictionary_entries = None

    def _ensure_model(self, model, timeout):
        return None

    def _generate(self, instruction, text, timeout, model, backend_url, dictionary_entries):
        self.generate_call_count += 1
        self.last_instruction = instruction
        self.last_dictionary_entries = dictionary_entries
        return self.generated_text


if __name__ == "__main__":
    unittest.main()
