# Cert-manager Helm Wrapper

Chart minimal qui depend du chart officiel Jetstack et force l'installation des CRDs pour le lab.

## Utilisation
```bash
cd infra/apps/cert-manager/chart
helm dependency update
helm template cert-manager .
```

Publiez ce dossier vers GitLab via `infra/scripts/publish_git_repos.sh` pour qu'Argo CD le consomme.
