# Runbook - Image Airflow avec DAGs embarqués

## Objectif
Construire une image Docker contenant les DAGs/plug-ins du dépôt puis la déployer via le chart Helm Airflow (sans git-sync). Cette méthode garantit des releases immuables et simplifie la promotion (dev → prod).

## 1. Préparer les sources
1. Ajoutez vos DAGs dans `apps/airflow-dags/dags/` et, si besoin, vos plug-ins dans `apps/airflow-dags/plugins/`.
2. Déclarez les dépendances Python propres aux DAGs dans `apps/airflow-dags/requirements-dags.txt`.

## 2. Builder et pousser l'image
Le `Dockerfile` situé dans `apps/airflow-dags/Dockerfile` copie automatiquement les DAGs/plug-ins et installe `requirements-dags.txt`.

```bash
# Exemple de versionnage (timestamp)
export AIRFLOW_DAGS_TAG=$(date +%Y%m%d%H%M)

# Construire l'image
docker build -f apps/airflow-dags/Dockerfile \
  -t k3d-data-stack-lab-registry:5000/airflow-dags:${AIRFLOW_DAGS_TAG} apps/airflow-dags

# Pousser vers le registry k3d
docker push k3d-data-stack-lab-registry:5000/airflow-dags:${AIRFLOW_DAGS_TAG}
```

> Remarque : `k3d-data-stack-lab-registry:5000` est créé par `bootstrap_k3d.sh`. Remplacez-le par votre registre (GitLab, ECR, …) si besoin.

## 3. Mettre à jour la release Airflow
1. Modifiez `infra/apps/airflow/chart/values.yaml` :
   ```yaml
   airflow:
     images:
       airflow:
         repository: k3d-data-stack-lab-registry:5000/airflow-dags
         tag: ${AIRFLOW_DAGS_TAG}
   ```
   (Optionnel : supprimez `dags.gitSync` si vous n'en avez plus besoin.)
2. Validez la modification Git et publiez-la dans le dépôt GitOps.
3. Synchronisez l'application : `argocd app sync airflow`.

Les pods `scheduler`, `webserver`, `triggerer` redémarrent automatiquement sur l'image contenant les nouvelles DAGs.

## 4. Nettoyage / bonnes pratiques
- Le Secret `airflow-git-credentials` n'est plus requis une fois git-sync désactivé.
- Gardez un changelog des tags déployés (ex. via GitLab CI artifacts) pour tracer quelle version tourne.
- Pour des tests rapides, vous pouvez conserver un namespace "dev" avec git-sync actif, mais gardez la production sur l'image immuable.

## 5. Publier le dépôt applicatif sur GitLab
1. Les sources prêtes à être versionnées se trouvent dans `apps/airflow-dags/`.
2. Utilisez le script de publication en pointant sur ce dossier :
   ```bash
   APPS_DIR=apps APP_REPO_SUFFIX=app ./infra/scripts/publish_git_repos.sh
   ```
   (mettez `APP_REPO_SUFFIX=` pour garder exactement le nom `airflow-dags`).
