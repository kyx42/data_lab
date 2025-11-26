# Runbook ? GitLab avec PostgreSQL externe & Vault (Lab)

## Objectif
- Fournir GitLab via un conteneur Docker externe tout en conservant la base PostgreSQL hors Kubernetes (tous deux contr?l?s par Terraform).
- Centraliser les secrets dans Vault (mode dev) pour ?viter de stocker les mots de passe dans Git.
- Pousser le d?p?t `data_stack` dans cette forge avant de rebrancher Argo CD.

## D?marrer les services Docker (Postgres, Vault, GitLab)
1. Ex?cutez le script d?di? :
   ```bash
   ./infra/scripts/start_lab_services.sh
   ```
2. Ce script lance trois conteneurs : `gitlab-postgres` (port h?te 5433), `vault-dev` (port 8200) et `gitlab-ce` (ports 8081/8444/2224). Le premier d?marrage GitLab peut prendre ~10 minutes.
3. Ajoutez `127.0.0.1 gitlab.lab.local` dans `/etc/hosts` pour acc?der facilement ? l?interface.

## Configuration GitLab (mot de passe + PAT)
1. Le script applique automatiquement le mot de passe `root` d?fini via `GITLAB_ROOT_PASSWORD` (par d?faut `ChangeMe123!`). Connectez-vous ? `http://gitlab.lab.local:8081` avec `root` et ce mot de passe si vous souhaitez v?rifier/configurer l?instance.
2. Un Personal Access Token est g?n?r? automatiquement (scopes `api`, `read_api`, `write_repository`) et stock? dans `docker/gitlab/root_pat.txt` (modifiable via `GITLAB_ROOT_TOKEN_FILE`). Conservez-le pour vos `git push`/appels API manuels.

## Publier les d?p?ts GitOps
1. Ajustez si besoin `infra/apps/<component>` (valeurs Helm) et `infra/gitops/platform` (AppProject/Applications).
2. Exportez le PAT GitLab :
   ```bash
   export GITLAB_TOKEN=$(cat docker/gitlab/root_pat.txt)
   ./infra/scripts/publish_git_repos.sh
   ```
3. Le script cr?e/pousse automatiquement `traefik-helm`, `cert-manager-helm`, etc., ainsi que `platform-gitops` (app-of-apps).
4. Pour Terraform/ArgoCD, exportez aussi l'URL joignable depuis le cluster (via `host.k3d.internal`) et les identifiants utilisés par `platform-gitops` :
   ```bash
   export TF_VAR_argocd_platform_repo_url="http://host.k3d.internal:8081/root/platform-gitops.git"
   export TF_VAR_argocd_platform_repo_username=root
   export TF_VAR_argocd_platform_repo_password=$(cat docker/gitlab/root_pat.txt)
   ```
5. Préparez les exports additionnels (à lancer juste après le bootstrap Docker, avant Terraform) :
   ```bash
   export GITLAB_TOKEN=$(cat docker/gitlab/root_pat.txt)
   export TF_VAR_argocd_platform_repo_url="http://host.k3d.internal:8081/root/platform-gitops.git"
   export TF_VAR_argocd_platform_repo_username=root
   export TF_VAR_argocd_platform_repo_password=$(cat docker/gitlab/root_pat.txt)
   export TF_VAR_spark_operator_namespace=spark-operator
   export TF_VAR_spark_jobs_namespace=spark-jobs
   ```

## ?tapes Terraform
1. Lancez Terraform :
   ```bash
   cd infra/terraform
   terraform init
   terraform apply \
     -var kubeconfig_path=$HOME/.kube/config \
     -var kube_context=k3d-data-stack-lab
   ```
2. Terraform installe Argo CD via Helm, g?n?re le certificat TLS (provider `tls` + IngressRoute Traefik) et cr?e l'Application `platform-gitops` pointant vers le d?p�t GitOps publi? plus haut.
3. Pour d'autres projets (ex. `data_stack`), ajoutez un remote GitLab et poussez-les manuellement :
   ```bash
   git remote add gitlab http://gitlab.lab.local:8081/root/data_stack.git
   git push gitlab main
   ```

## Synchronisation Argo CD
1. Une fois `terraform apply` termin?, Argo CD dispose d'un certificat TLS et de l'application `platform-gitops`. Depuis l'UI, v?rifiez que `platform-gitops` pointe sur `platform-gitops.git` puis lancez un Sync : les Applications `cert-manager` et `traefik` seront cr??es automatiquement.
2. Pour ajouter une nouvelle brique, mettez ? jour `infra/apps/<component>` et `infra/gitops/platform`, relancez `publish_git_repos.sh` puis synchronisez `platform-gitops`.

### Port-forward + CLI Argo CD
Si Traefik n'est pas encore disponible ou que l'UI HTTPS ne r?pond pas, on peut tout de m?me piloter Argo CD :
1. R?cup?rer le mot de passe admin :
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret \
     -o jsonpath='{.data.password}' | base64 -d && echo
   ```
2. Ouvrir un port-forward local :
   ```bash
   kubectl -n argocd port-forward svc/argocd-server 8080:443
   ```
3. Se connecter avec la CLI :
   ```bash
   argocd login localhost:8080 --username admin --password <motdepasse>
   ```
4. Synchroniser les applications :
   ```bash
   argocd app sync platform-gitops
   argocd app sync traefik
   ```
Le port-forward peut rester actif dans un terminal pendant que la CLI ex?cute les synchronisations.

## Debug pods / init containers
1. Listez l’état des pods : `kubectl -n <namespace> get pods`.
2. Inspectez un pod bloqué (sections *Init Containers* et events) : `kubectl -n <namespace> describe pod <nom-pod>`.
3. Lisez les logs d’un init container : `kubectl -n <namespace> logs <nom-pod> -c <init-container>` (ajoutez `--previous` si le conteneur redémarre en boucle).

> 💡 **Argo CD & Jobs Helm**  
> Quand un chart (ex. Airflow) s’appuie sur des hooks Helm (`post-install`) pour lancer ses jobs (migrations, création d’utilisateur…), Argo CD ne les déclenche pas. Deux stratégies possibles : désactiver les hooks (`useHelmHooks=false`) pour que les Jobs deviennent des ressources normales, ou annoter les Jobs critiques (ex. `migrateDatabaseJob.jobAnnotations["argocd.argoproj.io/hook"]=Sync`) afin qu’Argo CD les exécute à chaque `app sync`.

## Nettoyage
1. Arr?tez/supprimez les services Docker :
   ```bash
   docker rm -f gitlab-ce gitlab-postgres vault-dev || true
   ```
2. Sauvegardez ou supprimez les volumes (`docker/postgres-data/`, `docker/gitlab/`) selon vos besoins.
3. D?truisez le cluster k3d et les ressources Kubernetes :
   ```bash
   cd infra/terraform
   terraform destroy -var kubeconfig_path=... -var kube_context=...
   ```

> **IMPORTANT (prod)** : cette approche repose sur un Vault dev (non chiffr?, token statique). Pour un environnement plus s?rieux :
> - passez ? un cluster Vault HA (ou service manag?) ;
> - utilisez le Vault Agent Injector ou External Secrets Operator pour projeter les secrets directement dans les pods ;
> - stockez les secrets sensibles dans Vault (ou un autre KMS) plut?t que dans des fichiers/scripts locaux.
EOF
