#!/usr/bin/env python3
"""Measure kz startup, deterministic detection latency, size, and child RSS."""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import resource
import statistics
import subprocess
import sys
import time
from pathlib import Path


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=50)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-size-mib", type=float)
    parser.add_argument("--max-startup-p50-ms", type=float)
    parser.add_argument("--max-detect-p50-ms", type=float)
    return parser.parse_args()


def percentile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * q) - 1)]


def sample(command: list[str], count: int) -> list[float]:
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    results = []
    for _ in range(count):
        started = time.perf_counter_ns()
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        results.append((time.perf_counter_ns() - started) / 1_000_000)
    return results


def stats(values: list[float]) -> dict[str, float]:
    return {
        "min": round(min(values), 3),
        "p50": round(statistics.median(values), 3),
        "p95": round(percentile(values, 0.95), 3),
        "max": round(max(values), 3),
        "mean": round(statistics.fmean(values), 3),
    }


def main() -> int:
    args = arguments()
    binary = args.binary.resolve()
    if not binary.exists():
        raise SystemExit(f"binary does not exist: {binary}")
    startup = sample([str(binary), "version"], args.samples)
    detection = sample([str(binary), "detect", "oom", "--json"], args.samples)
    child_usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    rss_kib = child_usage.ru_maxrss
    if sys.platform == "darwin":
        rss_kib //= 1024
    report = {
        "schema_version": "kz/benchmark-v1",
        "generated_at_unix": int(time.time()),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "samples": args.samples,
        "binary": {
            "path": str(binary),
            "size_bytes": binary.stat().st_size,
            "size_mib": round(binary.stat().st_size / 1024 / 1024, 3),
        },
        "startup_latency_ms": stats(startup),
        "detector_cli_latency_ms": stats(detection),
        "peak_child_rss_kib": rss_kib,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))

    failures = []
    if args.max_size_mib is not None and report["binary"]["size_mib"] > args.max_size_mib:
        failures.append(f"binary size {report['binary']['size_mib']} MiB exceeds {args.max_size_mib} MiB")
    if args.max_startup_p50_ms is not None and report["startup_latency_ms"]["p50"] > args.max_startup_p50_ms:
        failures.append(f"startup p50 {report['startup_latency_ms']['p50']} ms exceeds {args.max_startup_p50_ms} ms")
    if args.max_detect_p50_ms is not None and report["detector_cli_latency_ms"]["p50"] > args.max_detect_p50_ms:
        failures.append(f"detect p50 {report['detector_cli_latency_ms']['p50']} ms exceeds {args.max_detect_p50_ms} ms")
    for failure in failures:
        print(f"REGRESSION: {failure}", file=sys.stderr)
    return 2 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
