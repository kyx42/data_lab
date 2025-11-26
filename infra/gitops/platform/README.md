# Platform GitOps bundle

Ce dossier represente le depot Git qui regroupe les AppProject/Application Argo CD pour les composants de base (cert-manager, Traefik, ...).

## Structure
- `projects/platform.yaml` : AppProject `platform` autorisant les namespaces `traefik` et `cert-manager`.
- `applications/*.yaml` : Applications Argo CD pointant vers les depots Helm de chaque composant.
- `kustomization.yaml` : permet un `kubectl apply -k infra/gitops/platform` ou un sync unique dans Argo CD.

Remplacez les URLs (`https://gitlab.lab.local/root/...`) et les revisions si besoin avant publication.
