# gitops/apps/
Argo CD `Application`s (app-of-apps, synced by `gitops/bootstrap/root-app.yaml`).
All in AppProject `default`. Planned set (~8, by sync-wave): cluster-config (incl.
**committed Argo RBAC**), external-secrets, cert-manager, keycloak, scm (in-cluster
Git), postgres (CNPG), coder, model-serving (RHOAI), observability-min, templates.
Each app points at `manifests/<app>/`.
