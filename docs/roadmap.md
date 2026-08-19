# Roadmap

The specification describes a complete v0.1 product; this repository currently contains the tested foundation and evaluation infrastructure, not the final controller.

| Milestone | State | Exit criterion |
|---|---|---|
| Native kernel and `kz` CLI | Complete | Builds with no generic-agent behavior |
| Deterministic safety kernel | Complete | Detectors, typed actions, policy, redaction, verification tests pass |
| Evaluation/benchmark harness | Complete | Multi-model, native performance, and minikube reports are machine-readable |
| Kubernetes read client | In progress | In-cluster and kubeconfig auth; discovery and GET/LIST without kubectl |
| LIST/WATCH cache | In progress | Reconnect, 410 relist, atomic partitions, stale-state mutation gate |
| Resource graph | In progress | Bounded traversal/root ownership exist; Kubernetes edge builders remain |
| Incident/evidence manager | Planned | Correlation, debounce, bounded evidence, append-only persistence |
| Zig model gateway | In progress | Agnostic interface/profile exist; native HTTP completion transport remains |
| Planning and dry-run | Planned | Patch allowlist, risk, policy, exact diff, no live writes by default |
| Approval-gated execution | Planned | SSAR, audit-start, optimistic concurrency, verification, rollback |
| Bounded autonomy | Planned | Narrow Pod eviction objective, cooldown and cluster budgets |
| Hardening/release | Planned | 100+ incident corpus, chaos/security suite, SBOM and signed artifacts |

The implementation order is deliberate: graph and evidence quality precede model integration; eval evidence precedes any autonomous mutation.
