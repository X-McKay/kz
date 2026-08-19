# Development

## Reproducible runtimes

`.mise.toml` pins:

- Zig 0.16.0 for the native core;
- Python 3.14.7 for dependency-free test/report tooling;
- minikube 1.38.1 for isolated cluster objectives;
- kubectl 1.35.1 for test-harness setup and observation only.

The `kz` product must not invoke kubectl. The chaos harness may use it to arrange and independently observe test state.

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
| `mise run build` | Build a debug binary |
| `mise run test` | Run deterministic Zig tests |
| `mise run eval-smoke` | Run safe and adversarial fixture models |
| `mise run model-benchmark` | Evaluate the configured model and refresh README metrics |
| `mise run benchmark` | Record local size/RSS/latency metrics |
| `mise run skill-check` | Validate mirrored Codex and Claude skills |
| `mise run minikube-up` | Start the dedicated eval cluster |
| `mise run e2e` | Execute real fault-injection objectives |
| `mise run ci` | Run the fast local CI equivalent |

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
