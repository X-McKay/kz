# kz

`kz` is a small, event-driven Kubernetes reliability controller under active development. It keeps deterministic cluster observation, safety policy, execution, and verification outside the model; an LLM is only a constrained diagnosis and planning component.

## What is implemented

The current `0.1.0-dev` vertical slice contains:

- a dependency-free Zig 0.16 native CLI;
- deterministic detectors for high-value Pod, workload, node, storage, Service, and Job failures;
- incident correlation keys, lifecycle transition rules, and bounded attempt budgets;
- typed remediation plans with deterministic risk and fail-closed policy decisions;
- hard denials for secrets, RBAC, network policy, persistent storage, and namespaces;
- stale-cache/stale-plan gates, mandatory dry-run capability, and mandatory verification;
- bounded secret redaction and model evidence-citation validation;
- an OpenAI-compatible multi-model evaluation runner;
- a provider-neutral native interface with an initial `llm.almckay.io` OpenAI-compatible profile;
- a minikube fault-injection suite for real CrashLoop, image-pull, and Service endpoint failures;
- startup, command-latency, RSS, and binary-size benchmarks;
- CI for Zig linting and ReleaseSafe tests, workflow and repository security, strict Kubernetes manifests, unit/safety invariants, eval smoke tests, build targets, performance budgets, and minikube chaos objectives.

The live Kubernetes LIST/WATCH transport, cache/graph population, persistent incident manager, model gateway inside the Zig controller, and approval-gated mutation executor remain subsequent milestones. The minikube suite currently injects and observes real cluster failures, then evaluates the native deterministic detector over reduced observations; it does **not** claim that a live autonomous mutation path exists yet. See [the roadmap](docs/roadmap.md).

## Quick start

Install [mise](https://mise.jdx.dev/), then:

```bash
mise trust
mise install
mise run check
mise run benchmark
mise run manifest-check
mise run security
```

The repository pins Zig, Python, minikube, kubectl, ZLS, ZLint, actionlint, ShellCheck, zizmor, kubeconform, and Trivy in `.mise.toml`. No project or development runtime should need to be installed globally.

Try the read-only CLI:

```bash
mise exec -- zig build
./zig-out/bin/kz version
./zig-out/bin/kz doctor --json
./zig-out/bin/kz detect oom --json
./zig-out/bin/kz policy --auto-risk 1
```

## Compare models

The initial development profile targets `https://llm.almckay.io/v1` with `Qwen3.6-35B-A3B-NVFP4`. The eval runner speaks the OpenAI-compatible `/chat/completions` protocol while keeping scoring provider-neutral.

Run the configured live endpoint:

```bash
mise run model-benchmark
```

`mise run eval` is retained as a short alias. The benchmark writes full JSON and Markdown artifacts under `.artifacts/evals/` and atomically refreshes only the generated section below.

To compare other endpoints/models, copy `tests/evals/models.example.json`, edit its profiles, provide keys through the named environment variables, and run:

```bash
python tests/evals/run.py \
  --config tests/evals/models.example.json \
  --repeat 3 \
  --expected-cases 50 \
  --output .artifacts/evals/results.json \
  --markdown .artifacts/evals/results.md \
  --update-readme README.md
```

For a credential-free smoke run:

```bash
mise run eval-smoke
```

The reviewed corpus contains exactly 50 basic, intermediate, advanced, and adversarial objectives. Results include per-case records, per-complexity breakdowns, objective success, diagnosis and caution accuracy, unsafe-action rate, hallucinated-evidence rate, schema validity, evidence precision, confidence calibration, token totals, throughput, and mean/p50/p95/max latency. Details are in [docs/evaluations.md](docs/evaluations.md).

<!-- kz-model-benchmark:start -->
## Latest model benchmark

Generated 2026-08-19 01:44:30 UTC from 50 cases × 1 repetition(s) at concurrency 4. 50 requests completed in 428.4s (0.12 requests/s).

### Outcome metrics

| Provider | Model | Runs | Objective | Request | Schema | Root cause | Caution | Unsafe | Hallucinated |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| almckay-llm | Qwen3.6-35B-A3B-NVFP4 | 50 | 68.0% | 100.0% | 100.0% | 88.0% | 88.0% | 14.0% | 0.0% |

### Latency and usage metrics

| Provider | Model | Runs | Mean ms | p50 ms | p95 ms | Max ms | Input tokens | Output tokens |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| almckay-llm | Qwen3.6-35B-A3B-NVFP4 | 50 | 33274.7 | 33582.1 | 44486.4 | 52035.6 | 14391 | 75412 |

### Results by complexity

| Provider | Model | Complexity | Runs | Objective | Root cause | Caution | Unsafe | p50 ms | p95 ms |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| almckay-llm | Qwen3.6-35B-A3B-NVFP4 | advanced | 10 | 80.0% | 90.0% | 90.0% | 10.0% | 33596.1 | 43082.7 |
| almckay-llm | Qwen3.6-35B-A3B-NVFP4 | adversarial | 10 | 70.0% | 80.0% | 90.0% | 10.0% | 33582.1 | 38848.5 |
| almckay-llm | Qwen3.6-35B-A3B-NVFP4 | basic | 15 | 60.0% | 86.7% | 86.7% | 13.3% | 30272.4 | 44288.0 |
| almckay-llm | Qwen3.6-35B-A3B-NVFP4 | intermediate | 15 | 66.7% | 93.3% | 86.7% | 20.0% | 36170.2 | 52035.6 |

`Caution` measures whether the model correctly decided that more evidence was needed.
<!-- kz-model-benchmark:end -->

## Run minikube chaos objectives

A working minikube driver is required. The suite uses a dedicated `kz-eval` profile and namespace and reserves 4 GiB for the cluster so a 6 GiB host VM retains enough overhead.

On macOS with Podman, initialize the dedicated VM once, start it, and select its root connection as required by Minikube's Podman driver:

```bash
podman machine init --cpus 4 --memory 6144 --disk-size 20 kz-eval
podman machine start kz-eval
podman system connection default kz-eval-root
export KZ_MINIKUBE_DRIVER=podman
export KZ_MINIKUBE_CONTAINER_RUNTIME=cri-o
```

If the VM already exists, omit `podman machine init`. Docker, vfkit, and other supported drivers can instead set the two `KZ_MINIKUBE_*` variables appropriately or leave them unset for Minikube auto-detection.

```bash
mise run minikube-up
mise run build
mise run e2e
mise run minikube-down
```

The harness applies bounded failure fixtures, waits for observable cluster state, invokes the native detector, writes a machine-readable report, and removes the namespace unless `--keep` is passed. EndpointSlice observation handles Kubernetes' explicit `endpoints: null` encoding and waits for slice creation before declaring an empty Service backend.

## AI-assisted development and usage

The repository includes matching project skills for both Codex and Claude:

- `kz-development` guides implementation, review, safety-boundary testing, documentation, and handoff.
- `kz-operations` guides mise tasks, provider/model comparisons, benchmark interpretation, and isolated minikube objectives.

Codex discovers them under `.agents/skills/`; Claude discovers matching copies under `.claude/skills/`. Invoke them explicitly as `$kz-development` or `$kz-operations`, or let the descriptions activate them for matching work. `mise run skill-check` prevents the two copies from drifting.

## Safety stance

Fresh installations are read-only. Model output cannot issue Kubernetes requests. Every future mutation must cross typed schema validation, cache freshness, UID preconditions, local policy, rate budgets, SelfSubjectAccessReview, server-side dry-run, audit-start persistence, and deterministic verification. See [docs/safety.md](docs/safety.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Development and mise tasks](docs/development.md)
- [Evaluation and regression methodology](docs/evaluations.md)
- [Model providers and the initial endpoint](docs/providers.md)
- [Safety model](docs/safety.md)
- [Implementation roadmap](docs/roadmap.md)

## License

Apache-2.0. The initial implementation is clean-room code based on the supplied specification; no source from `vercel-labs/fx` is currently included.
