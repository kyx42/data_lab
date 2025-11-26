# Infrastructure Roadmap (Local Lab)

## Objectif et hypotheses
- Valider une stack data/ML/GenAI end-to-end sur une workstation locale (32 Go RAM, RTX 4070 Ti, Ubuntu/WSL).
- Prioriser la couverture fonctionnelle (ingestion, orchestration, tracking, monitoring, auth, agents) avec des ressources limitees.
- Vault est retenu pour la gestion des secrets; pas besoin de cartographie materielle detaillee.
- Deploiement base sur Kubernetes local (k3s/k3d/kind) sans viser la production.

## Preparation du socle
- **Dependances OS** : automatiser l'installation de Docker, containerd, kubectl, helm, terraform, kustomize, argocd CLI. Option : activer le support GPU via NVIDIA container toolkit.
- **Structure du depot** : organiser `infra/terraform/`, `infra/scripts/` (ou ansible) et documenter le runbook dans `infra/README.md`.
- **Automatisation locale** : prevoir des cibles Makefile (`make lab-up`, `make lab-down`, `make lab-refresh`) pilotant la creation/suppression du cluster et les deployments, en s'appuyant sur `infra/scripts/bootstrap_k3d.sh`.

## Couche Kubernetes (lab)
- **Distribution** : k3s (ou k3d/kind) pour simuler un cluster multi-noeuds sur la machine locale.
- **Bootstrap** : script shell/Makefile qui installe k3s, configure kubeconfig, cree un registre Docker local, et expose les ports utiles.
- **Reseau et stockage** : Cilium ou Calico pour le CNI; Longhorn ou NFS + CSI pour le stockage persistant selon la consommation attendue.
- **Services generiques** : cert-manager, ingress controller Traefik (choix par defaut), monitoring de base (Prometheus Operator, Grafana, Loki) deployes via Helm ou ArgoCD.
- **Mode GitOps** : utiliser ArgoCD pour declarer les charts/operators a decrire dans Git, tout en conservant la possibilite d'un `terraform apply` manuel.
- **Vault (dev)** : Terraform déploie une instance Vault (mode dev, docker) exposée sur `127.0.0.1:8200` pour stocker les secrets applicatifs (mot de passe Postgres GitLab, futurs tokens). À terme, remplacer par une installation HA si nécessaire.
- **Base de donnees externe** : preparer un cluster PostgreSQL hors Kubernetes (VM, Docker Compose, Mini cluster géré par les DBA). Terraform doit pouvoir provisionner cette base (users + base `gitlab`) avant l'installation GitLab. Exporter les variables de connexion (host, port, user, password) dans Vault/Secret pour que GitLab (deployé via Terraform ou ArgoCD) s'y connecte.

## Briques data/ML/GenAI
- **Stockage lakehouse** : MinIO pour les zones `data/raw`, `data/intermediate`, `data/processed`.
- **Orchestration** : Airflow pour les DAG ETL/ML; deploiement via l'operator officiel ou chart Helm maintenu.
- **Suivi ML** : MLflow (tracking + registry), DVC pour versioning des datasets, MCP pour les agents LLM, gestion des prompts dans `prompts/`.
- **Catalog et lineage** : OpenMetadata pour documenter tables, pipelines, lineage Airflow; integration Superset/Trino via connecteurs.
- **Moteur SQL pour BI** : Trino (prioritaire) ou DuckDB/ClickHouse selon les ressources; Superset connecte a ce moteur pour la visualisation et le monitoring metier.
- **Qualite de donnees** : Great Expectations ou Soda Core pour les tests de Data Quality Control, relie aux DAG Airflow et au lineage OpenMetadata.
- **SecOps** : Keycloak pour l'IAM, Vault pour secrets, integration logs/metriques dans Grafana/Prometheus/Datadog. Ajouter une brique de gouvernance data (Apache Ranger – souvent confondu avec Rancher) couplée à Open Policy Agent pour appliquer des contrôles d'accès row/column-level sur Trino et centraliser les politiques d'autorisation.
- **Tests LLM** : workflows LoRA/QLoRA pour fine-tuning et boucle de feedback utilisateur instrumentee.
- **Streaming temps réel** : prévoir un chantier dédié pour tester un pipeline streaming (Airflow + Spark Structured Streaming, voire Flink/Kafka + K8s). L’idée est de valider ingestion temps réel, orchestration et supervision (métriques, alertes) dans le lab. TODO : définir l’architecture cible (Airflow trigger + Spark operator, ou alternative type Flink) et documenter le runbook.

## Scenarios de lancement (mode lab)
- **Scenario ETL minimal** : k3s + MinIO + Airflow + DVC/MLflow legers. Permet de valider ingestion -> transformation -> tracking.
- **Scenario Data serve** : scenario ETL minimal + Trino + Superset + OpenMetadata + Great Expectations. Vise la partie post-ETL (BI, lineage, DQC).
- **Scenario GenAI** : scenario ETL minimal + MCP + Keycloak + Vault + monitoring complet. Oriente sur les agents et le fine-tuning.
- **Activation incremental** : utiliser des variables Terraform, des `terragrunt.hcl` ou des manifs ArgoCD distincts pour activer un scenario; eviter le lancement de toutes les briques simultanement.

## Automatisation et pipelines
- **Terraform** : modules `cluster`, `platform_base` (cert-manager, Traefik, monitoring, ArgoCD), `platform_data` (MinIO, Trino, Airflow, MLflow, Superset, OpenMetadata), `platform_security` (Vault, Keycloak), `platform_genai` (MCP, composants LLM). Execution via `terraform apply` avec variables de scenario.
- **Terraform (impl?ment?)** : `infra/terraform` se limite au socle (cluster k3d + installation Argo CD via Helm) ainsi qu'au bootstrap d'infra externes (cluster PostgreSQL hors k8s pour GitLab). Les controllers (Traefik, cert-manager) proviennent de `infra/apps/<component>` et sont synchronis?s via le d?p?t GitOps `infra/gitops/platform`. Workflow type :
  ```bash
  cd infra/terraform
  terraform init
  terraform apply -var kubeconfig_path=$HOME/.kube/config -var kube_context=k3d-data-stack-lab
  ```
- **GitOps/CI** : pipeline GitLab/GitHub qui build les images Docker, pousse dans un registre local ou distant, puis applique Terraform; ArgoCD synchronise les charts/operators depuis le repo. Terraform prend en charge la base PostgreSQL externe et le conteneur GitLab CE (hors k8s) afin de disposer d’une forge locale.
- **Operators Kubernetes** : privilegier les operators officiels (Airflow Helm Chart + KubernetesExecutor, OpenMetadata Operator, Vault Helm/Operator, ArgoCD) pour se rapprocher des pratiques state-of-the-art.
- **Observabilite** : dashboards preconfigures pour services critiques, alertes de base (CPU/RAM pods, jobs Airflow, checks Great Expectations, metrics MLflow, latence Trino). Connecter Datadog si besoin de monitoring externe.
- **Exposition ArgoCD** : Terraform (`argocd_tls.tf`) g?n?re un CA auto-sign?, le certificat `argocd.lab.local` et l'IngressRoute Traefik associ?e (aucune Application d?di?e).
- **Dashboard Traefik** : sera ajout? dans le d?p?t GitOps (`platform-gitops`) en compl?ment du chart Traefik publi? via `infra/apps/traefik`.

### Flow GitLab + PostgreSQL externe
1. **Services Docker (Postgres + Vault + GitLab)** : `infra/scripts/start_lab_services.sh` lance PostgreSQL, Vault (mode dev) et GitLab CE (volumes `docker/postgres-data/`, `docker/gitlab/`). Les identifiants Postgres consommés par GitLab sont définis via les variables du script.
2. **Initialisation forge** : lancer GitLab CE via `infra/scripts/start_lab_services.sh`, accéder à `http://gitlab.lab.local:8081` et configurer l’utilisateur `root`. Une fois GitLab opérationnel, exécuter :
   ```bash
   cd infra/scripts
   export GITLAB_TOKEN=$(cat ../docker/gitlab/root_pat.txt)
   ./publish_git_repos.sh
   ```
   Cela crée/pousse automatiquement les dépôts Helm (`<component>-helm`) et le dépôt GitOps (`platform-gitops`).
3. **Connexion ArgoCD** : exporter `TF_VAR_argocd_platform_repo_username=root` et `TF_VAR_argocd_platform_repo_password=$(cat docker/gitlab/root_pat.txt)` avant `terraform apply`. Terraform crée le secret repository et l'Application `platform-gitops` (app-of-apps). Un simple Sync dans Argo CD déploie ensuite les Applications filles (Traefik, cert-manager…) depuis leurs dépôts GitLab.

> Strategie : demarrer par le scenario ETL minimal, ajouter ensuite les composants BI/lineage, puis le scenario GenAI. Chaque palier doit pouvoir etre rejoue via Terraform + ArgoCD pour rester reproductible.
