# Infrastructure Runbook

Ce dossier regroupe les scripts et IaC n�cessaires pour d�marrer le lab Kubernetes local (k3d) puis d�ployer le socle GitOps/ArgoCD, Traefik et cert-manager.

## 1. Scripts (`infra/scripts/`)

| Script | R�le | Commandes cl�s |
| ------ | ---- | -------------- |
| `install_cluster_requirements.sh` | Installe Docker, k3d, kubectl, Helm, Terraform sur Ubuntu/WSL. | ```bash
cd infra/scripts
./install_cluster_requirements.sh
./install_cluster_requirements.sh --skip-docker``` |
| `bootstrap_k3d.sh` | Cr�e le cluster k3d + registre local. Peut installer les addons via Helm (Traefik/cert-manager/ArgoCD) ou simplement ajouter les d�p�ts. | ```bash
./bootstrap_k3d.sh up
./bootstrap_k3d.sh up --with-addons-repos-only
./bootstrap_k3d.sh reset``` |
| `start_lab_services.sh` | Lance Postgres, Vault (dev) et GitLab CE via Docker, configure `root` et g�n�re un PAT stock� dans `docker/gitlab/root_pat.txt`. | ```bash
./infra/scripts/start_lab_services.sh
# Variables utiles : POSTGRES_PASSWORD, GITLAB_ROOT_PASSWORD, ...``` |
| `publish_git_repos.sh` | Pousse automatiquement chaque app Helm (`infra/apps/<name>`) et le d�p�t GitOps (`infra/gitops/platform`) vers GitLab. | ```bash
cd infra/scripts
export GITLAB_TOKEN=$(cat ../docker/gitlab/root_pat.txt)
./publish_git_repos.sh            # push r�el
./publish_git_repos.sh --dry-run  # aper�u``` |

> Variables g�n�rales : `CLUSTER_NAME`, `HOST_HTTP_PORT`, `HOST_HTTPS_PORT`, `SERVER_COUNT`, `AGENT_COUNT`. La commande `./bootstrap_k3d.sh kubeconfig` imprime le chemin kubeconfig ensuite utilis� par Terraform/kubectl.

## 2. Provisionner via Terraform (`infra/terraform/`)

Une fois le cluster k3d pr�t et GitLab op�rationnel, Terraform installe Argo CD via Helm, g�n�re l�exposition TLS, et d�clare l�Application �app-of-apps� qui consomme le d�p�t GitOps.

### Pr�requis
- Copier `.env.example` ? `.env` puis renseigner les variables (ou exporter directement).
- `kubeconfig` local (`$HOME/.kube/config`) avec le contexte `k3d-data-stack-lab`.
- Containers Postgres/Vault/GitLab d�marr�s (`./infra/scripts/start_lab_services.sh`) et entr�e `/etc/hosts` pour `gitlab.lab.local`.
- Publier les repos GitLab : `cd infra/scripts && export GITLAB_TOKEN=$(cat ../docker/gitlab/root_pat.txt) && ./publish_git_repos.sh`.
- Exporter l'URL GitOps joignable depuis le cluster (utiliser `host.k3d.internal` pour joindre le GitLab Docker depuis k3d) ainsi que les identifiants avant `terraform apply` :
  ```bash
  export TF_VAR_argocd_platform_repo_url="http://host.k3d.internal:8081/root/platform-gitops.git"
  export TF_VAR_argocd_platform_repo_username=root
  export TF_VAR_argocd_platform_repo_password=$(cat infra/docker/gitlab/root_pat.txt)
  export ARGOCD_CLI_VERSION=v2.9.3     # facultatif, sinon dernière release
  ```

### Workflow standard
```bash
cd infra/terraform
terraform init
terraform plan -var kubeconfig_path=$HOME/.kube/config -var kube_context=k3d-data-stack-lab
terraform apply -var kubeconfig_path=$HOME/.kube/config -var kube_context=k3d-data-stack-lab
```

### Port-forward + CLI ArgoCD (après installation via `install_cluster_requirements.sh`)
Si Traefik ou l'Ingress HTTPS ne sont pas encore disponibles, utilisez la CLI :
```bash
# Mot de passe admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Port-forward local
kubectl -n argocd port-forward svc/argocd-server 8080:443

# Connexion + synchronisation
argocd login localhost:8080 --username admin --password <motdepasse>
argocd app sync platform-gitops
```
Conservez le port-forward actif tant que la CLI est utilisée.

### Fichiers cl�s
- `providers.tf` : providers `kubernetes`, `helm`, `tls` + `locals.repo_root`.
- `argocd.tf` : installation Argo CD via Helm (`helm_release argocd`).
- `argocd_tls.tf` : g�n�ration du CA interne + certificat `argocd.lab.local` + IngressRoute Traefik.
- `argocd_gitops.tf` : secret repo (optionnel) + Application `platform-gitops` (app-of-apps) qui synchronise `infra/gitops/platform` depuis GitLab.
- `variables.tf` : param�tres (versions chart, service type, URL GitOps, identifiants...).
- `archive/` : anciens manifests conserv�s comme r�f�rence historique.

## 3. Structure GitOps

- `infra/apps/<component>/chart/` : mini chart Helm qui wrappe les charts officiels (Traefik, cert-manager...). Chaque dossier devient un d�p�t Git distinct (`traefik-helm`, `cert-manager-helm`, ...).
- `infra/gitops/platform/` : d�p�t GitOps �app-of-apps� (AppProject + Applications Argo CD) consomm� par `argocd_gitops.tf`.

### Workflow recommand�
1. **Bootstrap** : `./bootstrap_k3d.sh up --with-addons-repos-only` puis `./infra/scripts/start_lab_services.sh`.
2. **Publier les d�p�ts** : cf. tableau ci-dessus (`cd infra/scripts && export GITLAB_TOKEN=$(cat ../docker/gitlab/root_pat.txt) && ./publish_git_repos.sh`).
3. **Terraform** : installe ArgoCD, configure TLS, cr�e le secret Git et l�Application `platform-gitops`.
4. **ArgoCD** : ouvrir l�UI (`https://argocd.lab.local:8443`), synchroniser `platform-gitops`, puis les Applications filles Traefik/cert-manager sont d�ploy�es automatiquement.

> Ajouter un nouveau composant = cr�er `infra/apps/<component>`, l�ajouter dans `infra/gitops/platform/applications/`, relancer `publish_git_repos.sh`, puis synchroniser `platform-gitops`.

### Services externes (Docker)
- `infra/scripts/start_lab_services.sh` lance Postgres, Vault, GitLab dans le r�seau `data-stack-lab-net` (volumes `infra/docker/postgres-data/` et `infra/docker/gitlab/{config,logs,data}`).
- Ajouter `127.0.0.1 gitlab.lab.local` dans `/etc/hosts` pour acc�der � l�interface GitLab.

## 4. Ressources suppl�mentaires
- `infra/apps/` & `infra/gitops/platform/` : contenu GitOps/Helm � publier via `publish_git_repos.sh`.
- `docs/INFRA_ROADMAP.md` : roadmap d�taill�e (sc�narios ETL/Data Serve/GenAI, p�rim�tre Terraform/Helm).
- `docs/RUNBOOKS/LAB_BOOTSTRAP.md` : runbook complet (d�marrage Docker + GitLab + publication des d�p�ts + Terraform/ArgoCD).
- `docker/postgres-data/`, `docker/gitlab/` : volumes persistants (sauvegarder/vider selon besoin avant de relancer les services).

Mettez � jour ce runbook au fil de l�eau (ajout de nouvelles apps GitOps, �volutions Terraform, etc.).
