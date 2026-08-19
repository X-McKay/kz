# Deployment manifests

The base currently installs only the `kz-system` namespace, observer ServiceAccount, and read/SSAR RBAC:

```bash
kubectl apply -k deploy
```

It deliberately does not install a Deployment before the native LIST/WATCH controller milestone is complete. It also does not bind `rbac-mutator-unbound.yaml`; merely installing the read-only base cannot grant mutation authority.

Kubernetes RBAC cannot expose only Secret metadata. The future client must discard Secret values immediately and exclude them from cache history, evidence, audit, and model contexts. Clusters that do not require Secret dependency edges should remove `secrets` from the observer role.
