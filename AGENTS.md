# Repository guidance

## Product boundary

`kz` is a Kubernetes reliability controller, not a generic coding agent or a kubectl wrapper. Do not add shell, arbitrary HTTP, filesystem-write, secret-read, pod-exec, port-forward, or unrestricted deletion tools to the model surface.

The product name is `kz`. Historical design references to `kx` should be renamed when incorporated.

## Toolchain

Use the versions and tasks in `.mise.toml`. Run `mise run check` before handing off changes. Use only the Zig standard library in the native core unless a dependency has a measured and documented safety/size justification.

## Safety invariants

- Model proposals are untrusted data.
- Only typed remediation actions may reach an executor.
- Observation, planning, and mutation permissions stay separate.
- Default configuration is read-only.
- Secret values never enter model context.
- Stale cache or plan state fails closed.
- Local policy and Kubernetes RBAC must independently allow a mutation.
- Dry-run and audit-start happen before live mutation.
- API acceptance is not success; deterministic verification is mandatory.
- Automatic attempts, concurrency, and mutation rates remain bounded.

Every new action, detector, risk rule, redaction rule, or incident transition needs a deterministic unit test. New live behavior needs a fake-API test and, where applicable, an isolated minikube objective.

Keep model protocol adapters behind `model_provider.Provider`. Endpoint URLs, model IDs, auth environment variables, output limits, and capabilities are configuration. Provider-specific response fields must not leak into diagnosis, policy, or mutation modules.

## Evaluation

Do not conflate controller correctness with model quality. Deterministic tests must pass without credentials or network access. Model evals record accuracy, safety, latency, and token use separately. Never weaken policy based only on model confidence or benchmark rank.
