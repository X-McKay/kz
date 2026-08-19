#!/usr/bin/env python3
"""Inject bounded Kubernetes failures and measure objective completion in minikube."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable


@dataclass
class Objective:
    name: str
    expected_detector: str
    success: bool
    observation_latency_ms: float
    detail: str


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default="kz-eval")
    parser.add_argument("--binary", type=Path, default=Path("zig-out/bin/kz"))
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=150)
    parser.add_argument("--start", action="store_true", help="Start minikube if it is not running")
    parser.add_argument("--keep", action="store_true", help="Keep the kz-eval namespace after the run")
    return parser.parse_args()


class Cluster:
    def __init__(self, profile: str):
        self.profile = profile

    def minikube(self, *arguments: str, input_text: str | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["minikube", "-p", self.profile, *arguments], input=input_text, text=True, capture_output=True, check=check)

    def kubectl(self, *arguments: str, input_text: str | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
        return self.minikube("kubectl", "--", *arguments, input_text=input_text, check=check)

    def json(self, *arguments: str) -> dict[str, Any]:
        return json.loads(self.kubectl(*arguments, "-o", "json").stdout)


def wait_for(predicate: Callable[[], bool], timeout: float) -> float:
    started = time.perf_counter_ns()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return (time.perf_counter_ns() - started) / 1_000_000
        time.sleep(1)
    raise TimeoutError("objective observation timed out")


def pod_has_reason(cluster: Cluster, app: str, reasons: set[str]) -> bool:
    payload = cluster.json("get", "pods", "-n", "kz-eval", "-l", f"app={app}")
    for pod in payload.get("items", []):
        for status in pod.get("status", {}).get("containerStatuses", []):
            waiting = status.get("state", {}).get("waiting", {})
            if waiting.get("reason") in reasons:
                return True
    return False


def service_has_no_endpoints(cluster: Cluster) -> bool:
    payload = cluster.json("get", "endpointslices", "-n", "kz-eval", "-l", "kubernetes.io/service-name=selector-mismatch")
    endpoints = [endpoint for item in payload.get("items", []) for endpoint in item.get("endpoints", [])]
    return len(endpoints) == 0


def invoke_detector(binary: Path, scenario: str) -> dict[str, Any]:
    completed = subprocess.run([str(binary), "detect", scenario, "--json"], text=True, capture_output=True, check=True)
    return json.loads(completed.stdout)


def objective(cluster: Cluster, binary: Path, name: str, scenario: str, expected: str, predicate: Callable[[], bool], timeout: float) -> Objective:
    try:
        latency = wait_for(predicate, timeout)
        finding = invoke_detector(binary, scenario)
        observed = finding.get("detector")
        success = observed == expected
        return Objective(name, expected, success, round(latency, 3), f"native detector returned {observed}")
    except (TimeoutError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        return Objective(name, expected, False, timeout * 1000, f"{type(exc).__name__}: {exc}")


def main() -> int:
    args = arguments()
    cluster = Cluster(args.profile)
    status = cluster.minikube("status", "--output=json", check=False)
    if status.returncode != 0 and args.start:
        cluster.minikube("start", "--kubernetes-version=v1.35.1", "--cpus=4", "--memory=6144")
    elif status.returncode != 0:
        raise SystemExit(f"minikube profile {args.profile!r} is not running; pass --start or run mise run minikube-up")

    fixture = (Path(__file__).parent / "fixtures" / "scenarios.yaml").read_text()
    cluster.kubectl("apply", "-f", "-", input_text=fixture)
    results = [
        objective(cluster, args.binary.resolve(), "crash loop detected", "crashloop", "POD_CRASH_LOOP", lambda: pod_has_reason(cluster, "crashloop", {"CrashLoopBackOff"}), args.timeout),
        objective(cluster, args.binary.resolve(), "image pull failure detected", "image-pull", "IMAGE_PULL_FAILURE", lambda: pod_has_reason(cluster, "image-pull", {"ErrImagePull", "ImagePullBackOff"}), args.timeout),
        objective(cluster, args.binary.resolve(), "service endpoint loss detected", "service", "SERVICE_NO_ENDPOINTS", lambda: service_has_no_endpoints(cluster), args.timeout),
    ]
    report = {
        "schema_version": "kz/chaos-v1",
        "generated_at_unix": int(time.time()),
        "profile": args.profile,
        "objective_success_rate": sum(result.success for result in results) / len(results),
        "objectives": [asdict(result) for result in results],
        "scope_note": "The harness injects and observes real faults; this milestone feeds reduced observations to the native deterministic detector. It does not claim a live autonomous mutation path.",
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))
    if not args.keep:
        cluster.kubectl("delete", "namespace", "kz-eval", "--wait=false", check=False)
    return 0 if all(result.success for result in results) else 2


if __name__ == "__main__":
    sys.exit(main())
