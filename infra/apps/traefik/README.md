# Traefik Helm Wrapper

Ce dossier contient un mini chart Helm (`chart/`) qui depend du chart officiel Traefik et expose les valeurs standardisees pour le lab.

## Contenu
- `Chart.yaml` : declare la dependance vers `traefik/traefik`.
- `values.yaml` : override des ports, du Service `LoadBalancer` et des arguments HTTP->HTTPS.

## Utilisation locale
```bash
cd infra/apps/traefik/chart
helm dependency update
helm template traefik .
```

Lors de la publication vers GitLab (via `infra/scripts/publish_git_repos.sh`), les dependances Helm sont resolues automatiquement avant le commit.
