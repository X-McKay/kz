#!/usr/bin/env python3
"""Compare two kz benchmark artifacts and fail on relative regressions."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--latency-regression-percent", type=float, default=20.0)
    parser.add_argument("--size-regression-percent", type=float, default=10.0)
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text())
    candidate = json.loads(args.candidate.read_text())
    metrics = [
        ("startup p50", baseline["startup_latency_ms"]["p50"], candidate["startup_latency_ms"]["p50"], args.latency_regression_percent),
        ("detect p50", baseline["detector_cli_latency_ms"]["p50"], candidate["detector_cli_latency_ms"]["p50"], args.latency_regression_percent),
        ("binary size", baseline["binary"]["size_bytes"], candidate["binary"]["size_bytes"], args.size_regression_percent),
    ]
    failed = False
    print("| Metric | Baseline | Candidate | Change | Limit |")
    print("|---|---:|---:|---:|---:|")
    for name, old, new, limit in metrics:
        change = 0.0 if old == 0 else (new - old) / old * 100
        print(f"| {name} | {old:.3f} | {new:.3f} | {change:+.1f}% | +{limit:.1f}% |")
        if change > limit:
            failed = True
    return 2 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
