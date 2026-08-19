import importlib.util
import subprocess
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from typing import Any
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("chaos_run", Path(__file__).with_name("run.py"))
assert SPEC is not None and SPEC.loader is not None
chaos_run = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = chaos_run
SPEC.loader.exec_module(chaos_run)


class FakeCluster:
    def __init__(self, payload: dict[str, Any]):
        self.payload = payload
        self.arguments: tuple[str, ...] | None = None

    def json(self, *arguments: str) -> dict[str, Any]:
        self.arguments = arguments
        return self.payload


class ServiceEndpointObservationTests(unittest.TestCase):
    def observe(self, payload: dict[str, Any]) -> tuple[bool, FakeCluster]:
        cluster = FakeCluster(payload)
        return chaos_run.service_has_no_endpoints(cluster), cluster

    def test_null_endpoints_are_an_observed_empty_slice(self) -> None:
        observed, cluster = self.observe({"items": [{"endpoints": None}]})
        self.assertTrue(observed)
        self.assertEqual(
            cluster.arguments,
            (
                "get",
                "endpointslices",
                "-n",
                "kz-eval",
                "-l",
                "kubernetes.io/service-name=selector-mismatch",
            ),
        )

    def test_empty_endpoints_are_an_observed_empty_slice(self) -> None:
        observed, _ = self.observe({"items": [{"endpoints": []}]})
        self.assertTrue(observed)

    def test_populated_endpoints_do_not_match(self) -> None:
        observed, _ = self.observe({"items": [{"endpoints": [{"addresses": ["10.0.0.2"]}]}]})
        self.assertFalse(observed)

    def test_missing_slice_fails_closed_until_controller_reconciliation(self) -> None:
        for payload in ({}, {"items": None}, {"items": []}):
            with self.subTest(payload=payload):
                observed, _ = self.observe(payload)
                self.assertFalse(observed)

    def test_malformed_slice_fails_closed(self) -> None:
        for payload in ({"items": [None]}, {"items": [{"endpoints": {}}]}):
            with self.subTest(payload=payload):
                observed, _ = self.observe(payload)
                self.assertFalse(observed)


class HarnessCleanupTests(unittest.TestCase):
    def test_unexpected_apply_failure_still_cleans_the_isolated_namespace(self) -> None:
        class FailingCluster:
            def __init__(self) -> None:
                self.deleted = False

            def minikube(self, *arguments: str, **_: Any) -> subprocess.CompletedProcess[str]:
                return subprocess.CompletedProcess(arguments, 0, "{}", "")

            def kubectl(self, *arguments: str, **_: Any) -> subprocess.CompletedProcess[str]:
                if arguments[0] == "apply":
                    raise RuntimeError("simulated interrupted apply")
                if arguments[:3] == ("delete", "namespace", "kz-eval"):
                    self.deleted = True
                return subprocess.CompletedProcess(arguments, 0, "", "")

        cluster = FailingCluster()
        with tempfile.TemporaryDirectory() as directory:
            args = Namespace(
                profile="kz-eval",
                binary=Path("zig-out/bin/kz"),
                report=Path(directory) / "report.json",
                timeout=1.0,
                start=False,
                keep=False,
            )
            with patch.object(chaos_run, "arguments", return_value=args), patch.object(chaos_run, "Cluster", return_value=cluster):
                with self.assertRaisesRegex(RuntimeError, "interrupted apply"):
                    chaos_run.main()

        self.assertTrue(cluster.deleted)

if __name__ == "__main__":
    unittest.main()
