---
name: kz-development
description: Develop, review, or refactor the kz Kubernetes reliability controller. Use when changing Zig controller logic, detectors, incidents, policy, typed actions, redaction, verification, Kubernetes transport, provider adapters, tests, CI, or architecture documentation in this repository.
---

# Develop kz Safely

Treat model output as untrusted diagnostic input and preserve the deterministic safety boundary while implementing repository changes.

## Start Here

1. Read `AGENTS.md`, `.mise.toml`, and the relevant source and documentation before editing.
2. Inspect the working tree and preserve unrelated user changes.
3. Classify the change as deterministic controller behavior, provider protocol behavior, evaluation behavior, or documentation.
4. State any assumption that would change product scope or mutation authority.

## Preserve the Product Boundary

- Keep `kz` a Kubernetes reliability controller, not a generic agent or kubectl wrapper.
- Never expose shell, arbitrary HTTP, filesystem writes, secret reads, pod exec, port forwarding, or unrestricted deletion to a model.
- Keep observation, planning, and mutation permissions separate.
- Accept only typed remediation actions at executor boundaries.
- Default to read-only and fail closed on stale cache, stale plans, invalid model output, or missing authorization.
- Require local policy and Kubernetes RBAC independently for mutation.
- Require dry-run and durable audit-start before live mutation.
- Treat API acceptance as incomplete until deterministic verification succeeds.
- Keep attempts, concurrency, and mutation rates bounded.

## Implement the Change

- Prefer the Zig standard library. Add a dependency only with measured and documented safety or size justification.
- Keep provider-specific protocols behind `model_provider.Provider`.
- Keep endpoint URLs, model IDs, auth environment names, output limits, and capabilities in configuration.
- Prevent provider response fields from leaking into diagnosis, policy, or mutation modules.
- Preserve redaction before model context construction; never introduce secret values into prompts, logs, reports, or fixtures.
- Use project tasks and pinned runtimes through `mise`.

## Test at the Deterministic Boundary

- Add a deterministic unit test for every action, detector, risk rule, redaction rule, or incident transition.
- Add fake-API coverage for new live Kubernetes behavior.
- Add an isolated minikube objective when behavior depends on a real control-plane transition.
- Keep deterministic tests credential-free and offline.
- Test stale, malformed, out-of-vocabulary, unauthorized, and partially successful paths.
- Never relax safety policy because a model scores well.

## Document and Verify

1. Update public behavior, limitations, configuration, and operator steps in the appropriate docs.
2. Run focused tests while iterating.
3. Run `mise run check` before handing off.
4. Run `mise run manifest-check` for Kubernetes YAML and `mise run security` for dependency, secret, or configuration changes.
5. Run native benchmarks or minikube objectives when the change can affect their measured boundary.
6. Report commands run, objective results, and any verification that could not be completed.
