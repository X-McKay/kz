# Deployment manifests

The base currently installs only the `kz-system` namespace, observer ServiceAccount, and read/SSAR RBAC:

```bash
kubectl apply -k deploy
```

It deliberately does not install a Deployment before the native LIST/WATCH controller milestone is complete. It also does not bind `rbac-mutator-unbound.yaml`; merely installing the read-only base cannot grant mutation authority.

Kubernetes RBAC cannot expose only Secret metadata, so the baseline observer role deliberately omits Secrets. Dependency edges must be derived without Secret reads unless a future, separately reviewed design can preserve the rule that Secret values never enter cache history, evidence, audit records, or model contexts.
