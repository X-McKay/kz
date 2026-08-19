---
name: kz-operations
description: Operate, evaluate, and benchmark kz in development environments. Use when running mise tasks, comparing model providers, updating benchmark results, interpreting evaluation metrics, exercising minikube chaos objectives, or troubleshooting repository workflows.
---

# Operate and Evaluate kz

Use the pinned `mise` toolchain, keep evaluations isolated, and distinguish deterministic controller correctness from model quality.

## Choose the Workflow

- For a fast offline validation, run `mise run check`.
- For credential-free model scoring, run `mise run eval-smoke`.
- For the configured live model benchmark, run `mise run model-benchmark`.
- For native binary size, RSS, startup, and command latency, run `mise run benchmark`.
- For real Kubernetes observation objectives, use the dedicated `kz-eval` minikube profile with the `minikube-up`, `e2e`, and `minikube-down` tasks.

Do not describe the current minikube detector bridge as a completed autonomous mutation controller. Read `docs/roadmap.md` for the implemented boundary.

## Compare Models Safely

1. Run the offline smoke suite first.
2. Copy `tests/evals/models.example.json` for additional providers or models.
3. Configure endpoint URLs, model IDs, auth environment-variable names, output limits, response-format capability, and timeouts in the profile.
4. Supply credentials only through the named environment variable. Never write or print credential values.
5. Use the same 50-case corpus, repetition count, and concurrency when comparing models.
6. Retain JSON artifacts for per-case auditability; do not compare only the aggregate rank.

The runner is provider-neutral above its invocation adapter. Add a new adapter when a provider does not implement the OpenAI-compatible protocol.

## Understand Benchmark Output

`mise run model-benchmark` writes JSON and Markdown under `.artifacts/evals/` and atomically refreshes the marker-delimited README section. Check:

- objective, request, schema, root-cause, and caution success rates;
- unsafe-action and hallucinated-evidence rates;
- mean, p50, p95, and maximum end-to-end latency;
- token totals, wall time, throughput, and results by complexity;
- individual failure records and error diagnostics.

A transport or parse failure is an objective failure, but it is not an unsafe proposal when no proposal exists. Never weaken policy, RBAC, verification, or redaction based on confidence or benchmark position.

## Run Minikube Objectives

1. Confirm a working minikube driver and use only the dedicated `kz-eval` profile.
2. Start the profile with `mise run minikube-up`.
3. Build with `mise run build`, then run `mise run e2e`.
4. Preserve the JSON report and inspect failed objective evidence.
5. Stop the profile with `mise run minikube-down` when finished.

Do not target another cluster, namespace, or profile unless the user explicitly expands scope. The harness may clean only its isolated `kz-eval` namespace.

## Report Results

State the provider/model or minikube profile, corpus size, concurrency and repetitions, success and safety rates, latency distribution, artifact paths, and any incomplete checks. Separate model-quality conclusions from deterministic correctness conclusions.
