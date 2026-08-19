# Development

## Reproducible runtimes

`.mise.toml` pins:

- Zig 0.16.0 for the native core;
- Python 3.14.7 for dependency-free test/report tooling;
- minikube 1.38.1 for isolated cluster objectives;
- kubectl 1.35.1 for test-harness setup and observation only;
- ZLS 0.16.0 and ZLint 0.9.1 for Zig editor support and static linting;
- actionlint 1.7.12, ShellCheck 0.11.0, and zizmor 1.29.0 for workflow correctness and security;
- kubeconform 0.7.0 and Trivy 0.74.0 for Kubernetes-schema and repository security scans.

The `kz` product must not invoke kubectl. The chaos harness may use it to arrange and independently observe test state.

Podman, Docker, vfkit, or another Minikube host driver is an operating-system virtualization dependency rather than a kz runtime. On macOS with Podman, use a dedicated machine and Minikube's required root connection:

```bash
podman machine init --cpus 4 --memory 6144 --disk-size 20 kz-eval # one time
podman machine start kz-eval
podman system connection default kz-eval-root
KZ_MINIKUBE_DRIVER=podman KZ_MINIKUBE_CONTAINER_RUNTIME=cri-o mise run minikube-up
```

The task requests 4 GiB because a 6 GiB Podman VM exposes less than 6 GiB after guest overhead. Override `KZ_MINIKUBE_DRIVER` and `KZ_MINIKUBE_CONTAINER_RUNTIME` for another driver/runtime, or leave them unset to use Minikube auto-detection.

```bash
mise trust
mise install
mise tasks
```

## Common tasks

| Task | Purpose |
|---|---|
| `mise run fmt` | Format Zig and compile-check Python files |
| `mise run fmt-check` | Verify Zig formatting without writes |
| `mise run lint` | Run ZLint, actionlint/ShellCheck, and zizmor |
| `mise run build` | Build a debug binary |
| `mise run test` | Run deterministic Zig tests |
| `mise run release-safe-test` | Run Zig tests with optimization and runtime safety checks |
| `mise run eval-smoke` | Run safe and adversarial fixture models |
| `mise run model-benchmark` | Evaluate the configured model and refresh README metrics |
| `mise run benchmark` | Record local size/RSS/latency metrics |
| `mise run skill-check` | Validate mirrored Codex and Claude skills |
| `mise run minikube-up` | Start the dedicated eval cluster |
| `mise run e2e` | Execute real fault-injection objectives |
| `mise run manifest-check` | Strictly validate Kubernetes manifests against the pinned API schema |
| `mise run security` | Fail on high/critical dependency, secret, and configuration findings |
| `mise run ci` | Run the full local CI equivalent, including network-backed gates |

## Quality and security tooling

`mise run check` is the credential-free correctness gate. It includes `zig fmt --check`, ZLint with warnings denied, Python unit tests, skill mirroring, Debug and ReleaseSafe Zig tests, GitHub Actions syntax/ShellCheck analysis, zizmor workflow-security analysis, and the deterministic evaluation smoke suite.

ZLS is pinned for consistent editor diagnostics but is not a CI gate. ZLint complements the compiler by analyzing code that may be hidden by compile-time dead-code elimination. ReleaseSafe tests exercise optimized code while retaining Zig's runtime safety checks. These tools add no dependency to the native binary.

The network-backed gates are separate so the deterministic suite remains runnable after tools are installed:

```bash
mise run manifest-check
mise run security
```

kubeconform uses strict Kubernetes 1.35 schemas and rejects invalid or duplicate fields. Trivy scans dependencies, committed secrets, and configuration, failing on high or critical findings; generated build, cluster-credential, report, and scanner-cache directories are explicitly excluded. GitHub CI runs both gates on every pull request and `main` push. Cache directories are repository-local and ignored.

GitHub Actions are pinned to immutable commit SHAs with update-friendly version comments and weekly Dependabot updates, checkout credentials are not persisted, and workflow-dispatch values enter shell steps only through environment variables. `actionlint` checks workflow structure and embedded shell, while `zizmor` checks Actions-specific security properties.

The experimental Zwanzig analyzer was evaluated but is not yet a required gate. Its current rule set reports false positives for idiomatic comptime type factories and test-only optional unwraps in this codebase; revisit it as its interprocedural analysis and configuration mature. The compiler, ZLint, and ReleaseSafe matrix are the supported Zig gates for now.

## Repository skills

Codex project skills live under `.agents/skills/`; matching Claude project skills live under `.claude/skills/`. Keep each `SKILL.md` pair byte-identical and run `mise run skill-check` after editing. The Codex copies also contain `agents/openai.yaml` interface metadata.

## Release-sized builds

```bash
mise exec -- zig build -Doptimize=ReleaseSmall
python scripts/benchmark.py \
  --binary zig-out/bin/kz \
  --samples 100 \
  --max-size-mib 12 \
  --max-startup-p50-ms 20 \
  --max-detect-p50-ms 20 \
  --output .artifacts/benchmarks/release-small.json
```

Cross-compile Linux artifacts with, for example:

```bash
mise exec -- zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl
mise exec -- zig build -Doptimize=ReleaseSmall -Dtarget=aarch64-linux-musl
```

## Adding a detector

Add the stable enum value, implement a deterministic match after more-specific causes and before broader causes, choose a runtime-owned severity/failure family, and add positive plus false-positive tests. Add a minikube objective if Kubernetes can produce the state reliably.

## Adding an action

An action expands authority. Document its exact target/patch vocabulary, deterministic risk, hard preconditions, RBAC verb/resource/subresource, dry-run semantics, verification contract, rollback constraints, and rate limits. Add allow, approval, denial, stale-state, and failed-verification tests before implementing transport.
