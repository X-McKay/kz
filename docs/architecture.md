# Architecture

`kz` places a narrow probabilistic reasoning step inside a deterministic reliability controller.

```text
Kubernetes LIST/WATCH
        |
        v
 synchronized cache ---> resource graph
        |                       |
        +----------+------------+
                   v
       normalize -> detect -> correlate
                              |
                              v
                    bounded evidence packet
                              |
                    deterministic diagnosis
                              |
                    optional model proposal
                              |
                              v
 typed schema -> risk/policy -> RBAC -> dry-run -> approval
                                                |
                                                v
                                          live mutation
                                                |
                                                v
                               deterministic verification
```

The model has no reference to the Kubernetes transport or mutation executor. It receives evidence IDs, reduced resource summaries, an allowed-action vocabulary, and policy context. Its result is data that the host may reject.

## Current module map

| Module | Responsibility |
|---|---|
| `src/types.zig` | Stable resource, finding, incident, and remediation types |
| `src/detectors.zig` | Ordered deterministic failure classification |
| `src/incidents.zig` | Correlation keys, lifecycle graph, attempt budget |
| `src/cache.zig` | Bounded cache partitions and atomic relist freshness gates |
| `src/graph.zig` | Bounded resource relationship traversal and root-owner queries |
| `src/model_schema.zig` | Evidence and target validation at the model boundary |
| `src/model_provider.zig` | Protocol-neutral completion interface and capabilities |
| `src/providers/openai_compatible.zig` | OpenAI-compatible endpoint/auth adapter primitives |
| `src/policy.zig` | Risk scoring, hard denies, freshness and availability gates |
| `src/redaction.zig` | Allocation-free credential-canary removal |
| `src/verification.zig` | Runtime-owned workload success contracts |
| `src/kube/client.zig` | Safe resource paths and LIST/WATCH freshness state |
| `tests/evals` | Provider-independent model corpus and scoring |
| `tests/chaos` | Real minikube fault injection and objective measurement |

## Planned controller data flow

Each watched group/version/resource performs LIST, atomically replaces its cache partition, records the collection resource version, then begins WATCH. A 410 or untrusted stream state marks the partition stale. Detectors may continue reporting against explicitly identified stale evidence, but mutation authorization remains disabled until a successful relist.

Signals correlate by cluster, namespace, root-owner UID, and failure family. This keeps replacement Pods and repeated Events inside one logical incident. Evidence is bounded and secret-safe before an optional model call.

The executor will accept only a validated `RemediationPlan`; free-form text, arbitrary JSON Patch paths, and direct provider tool calls cannot reach it.

## Dependency policy

The native binary currently depends only on Zig's standard library. Python tools use only the Python standard library. This keeps bootstrap, SBOM, binary-size, and supply-chain surfaces small while the foundational APIs stabilize.
