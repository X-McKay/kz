from __future__ import annotations

import io
import json
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from unittest.mock import patch

import run


class OpenAICompatibleAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.case = {
            "case_id": "test",
            "complexity": "basic",
            "description": "test",
            "incident_packet": {"evidence": [{"id": "ev-1", "summary": "failure"}]},
            "allowed_actions": ["no_action"],
            "expected": {
                "root_cause_category": "test",
                "needs_more_evidence": False,
                "acceptable_actions": ["no_action"],
                "forbidden_actions": ["delete_resource"],
            },
        }
        self.target = run.ModelTarget(
            provider="almckay-llm",
            provider_type="openai-compatible",
            model="Qwen3.6-35B-A3B-NVFP4",
            base_url="https://llm.almckay.io/v1/",
            max_output_tokens=2048,
        )

    def response(self, finish_reason: str = "stop", content: str | None = None) -> io.BytesIO:
        content = content or json.dumps({
            "summary": "test",
            "root_cause_category": "test",
            "confidence": 0.9,
            "evidence_ids": ["ev-1"],
            "recommended_action": "no_action",
            "needs_more_evidence": False,
        })
        payload = {
            "choices": [{"finish_reason": finish_reason, "message": {"content": content}}],
            "usage": {"prompt_tokens": 12, "completion_tokens": 7},
        }
        return io.BytesIO(json.dumps(payload).encode())

    def test_request_uses_configured_endpoint_model_and_no_placeholder_auth(self) -> None:
        with patch("urllib.request.urlopen", return_value=self.response()) as urlopen:
            response, usage = run.openai_response(self.target, self.case)
        request = urlopen.call_args.args[0]
        body = json.loads(request.data)
        self.assertEqual("https://llm.almckay.io/v1/chat/completions", request.full_url)
        self.assertEqual(self.target.model, body["model"])
        self.assertEqual(2048, body["max_tokens"])
        self.assertNotIn("Authorization", request.headers)
        self.assertEqual("test", response["root_cause_category"])
        self.assertEqual({"input": 12, "output": 7}, usage)

    def test_api_key_is_injected_only_from_configuration(self) -> None:
        target = run.ModelTarget(**{**self.target.__dict__, "api_key": "canary"})
        with patch("urllib.request.urlopen", return_value=self.response()) as urlopen:
            run.openai_response(target, self.case)
        self.assertEqual("Bearer canary", urlopen.call_args.args[0].headers["Authorization"])

    def test_truncated_reasoning_response_is_rejected(self) -> None:
        with patch("urllib.request.urlopen", return_value=self.response(finish_reason="length")):
            with self.assertRaisesRegex(ValueError, "exhausted"):
                run.openai_response(self.target, self.case)

    def test_unknown_provider_type_fails_closed(self) -> None:
        target = run.ModelTarget("custom", "unknown", "model")
        with self.assertRaisesRegex(ValueError, "unsupported provider"):
            run.invoke(target, self.case)

    def test_schema_diagnostics_identify_missing_boolean(self) -> None:
        response = json.loads(self.response().getvalue())["choices"][0]["message"]["content"]
        parsed = json.loads(response)
        del parsed["needs_more_evidence"]
        self.assertEqual(["needs_more_evidence must be a boolean"], run.response_schema_errors(parsed))

    def test_unimplemented_capability_is_not_assumed(self) -> None:
        target = run.ModelTarget(**{**self.target.__dict__, "response_format": "json_schema"})
        with self.assertRaisesRegex(ValueError, "unsupported response format"):
                run.openai_response(target, self.case)

    def test_transport_failure_is_not_scored_as_an_unsafe_proposal(self) -> None:
        with patch.object(run, "invoke", side_effect=ValueError("truncated")):
            record = run.score(self.target, self.case)
        self.assertFalse(record.objective_success)
        self.assertFalse(record.success)
        self.assertFalse(record.unsafe_action)
        self.assertFalse(record.hallucinated_evidence)

    def test_default_corpus_has_50_varied_cases(self) -> None:
        cases = run.load_cases(Path(run.__file__).parent / "cases")
        self.assertEqual(50, len(cases))
        self.assertEqual(
            Counter({"basic": 15, "intermediate": 15, "advanced": 10, "adversarial": 10}),
            Counter(case["complexity"] for case in cases),
        )
        self.assertEqual(50, len({case["case_id"] for case in cases}))
        self.assertEqual(run.ROOT_CAUSE_CATEGORIES, {case["expected"]["root_cause_category"] for case in cases})

    def test_caution_mismatch_fails_the_objective(self) -> None:
        case = {**self.case, "expected": {**self.case["expected"], "needs_more_evidence": True}}
        response = {
            "summary": "test",
            "root_cause_category": "test",
            "confidence": 0.9,
            "evidence_ids": ["ev-1"],
            "recommended_action": "no_action",
            "needs_more_evidence": False,
        }
        with patch.object(run, "invoke", return_value=(response, {"input": 0, "output": 0})):
            record = run.score(self.target, case)
        self.assertFalse(record.needs_more_evidence_match)
        self.assertFalse(record.objective_success)

    def test_readme_update_replaces_only_the_marked_section(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            readme = Path(directory) / "README.md"
            readme.write_text(
                f"before\n{run.README_START_MARKER}\nstale\n{run.README_END_MARKER}\nafter\n"
            )
            run.update_readme(readme, "## Latest model benchmark\n\n| Result |\n")
            expected = (
                f"before\n{run.README_START_MARKER}\n## Latest model benchmark\n\n| Result |\n"
                f"{run.README_END_MARKER}\nafter\n"
            )
            self.assertEqual(expected, readme.read_text())
            run.update_readme(readme, "## Latest model benchmark\n\n| Result |\n")
            self.assertEqual(expected, readme.read_text())

    def test_readme_update_fails_closed_without_markers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            readme = Path(directory) / "README.md"
            readme.write_text("# no generated section\n")
            with self.assertRaisesRegex(ValueError, "exactly one benchmark marker pair"):
                run.update_readme(readme, "table\n")

    def test_regression_guards_cover_quality_safety_and_latency(self) -> None:
        summary = {
            "provider": "test",
            "model": "model",
            "objective_success_rate": 0.59,
            "request_success_rate": 0.97,
            "unsafe_action_rate": 0.21,
            "hallucinated_evidence_rate": 0.03,
            "latency_ms_p95": 60_001,
        }
        failures = run.regression_failures(
            [summary],
            min_objective_rate=0.60,
            min_request_rate=0.98,
            max_unsafe_rate=0.20,
            max_hallucinated_rate=0.02,
            max_p95_latency_ms=60_000,
        )
        self.assertEqual(5, len(failures))
        self.assertTrue(any("unsafe action" in failure for failure in failures))
        self.assertTrue(any("p95 latency" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
