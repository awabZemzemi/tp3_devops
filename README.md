# TP — Infrastructure as Code locale et CI/CD

Déploiement d'une application Nginx et de PostgreSQL avec Terraform et Docker, sans compte cloud. Le projet suit les deux parties du sujet « TP IaC Local ».

## Fichiers

```text
tp-iac-local/
├── main.tf                    # Provider, images, conteneurs et contrôles de santé
├── variables.tf               # Identifiants et ports configurables
├── outputs.tf                 # Noms des conteneurs et URL HTTP
├── Dockerfile_app             # Alpine + Nginx + page demandée
├── nginx.conf                 # Serveur HTTP sur le port 80
├── .dockerignore              # Exclut état, secrets et dépôt du contexte Docker
├── .gitignore
├── .terraform.lock.hcl        # Version et sommes de contrôle du provider
├── terraform.tfvars.example
├── .github/workflows/main.yml # Push main → Init → Validate → Plan → Apply → vérification
├── scripts/verify.sh          # Vérification HTTP et SQL authentifiée
├── scripts/run-lifecycle.sh   # Cycle complet, journaux et nettoyage
├── scripts/verify-update.sh   # Preuve locale de remplacement de PostgreSQL
├── scripts/verify-ci-update.sh # Remplacement vérifié dans le job CI
├── evidence/                  # Journaux réels de l'exécution locale
└── RAPPORT.md                 # Résultats et réponses aux quatre questions
```

## Exécution locale

Prérequis : Terraform ≥ 1.5 et < 2, Docker Engine actif et accessible, Git, Bash et curl. La version utilisée est consignée dans le rapport. Les ports `127.0.0.1:8080` et `127.0.0.1:5432` doivent être disponibles.

Depuis ce répertoire, le cycle complet du TP est reproductible avec :

```bash
bash scripts/run-lifecycle.sh
```

Ce script déploie, valide, vérifie l'absence de changements au second plan, puis détruit les ressources gérées, même en cas d'échec après le début d'Apply. Il conserve les journaux dans `evidence/`. Il ne laisse donc pas l'application ouverte après son exécution.

Pour conserver l'application pendant une démonstration, exécuter les étapes manuellement :

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=deployment.tfplan
terraform apply -auto-approve deployment.tfplan
bash scripts/verify.sh
```

Ouvrir <http://localhost:8080/> ; la page affiche **Application Deployed via Terraform IaC!**. Les conteneurs s'appellent `tp-app-web` et `tp-db-postgres`.

Nettoyer ensuite :

```bash
terraform destroy -auto-approve
rm -f deployment.tfplan
terraform state list
```

La dernière commande ne doit afficher aucune ressource. L'image PostgreSQL reste en cache avec `keep_locally = true`, comme dans le sujet ; les conteneurs et leurs volumes anonymes sont supprimés. L'image de l'application est supprimée par Terraform ; Alpine et le cache de construction Docker peuvent rester disponibles. Aucun `docker system prune` n'est nécessaire.

### Paramètres

```bash
cp terraform.tfvars.example terraform.tfvars
# Adapter les valeurs de terraform.tfvars avant le déploiement.
```

Les valeurs par défaut sont `devops_db_v3`, `devops_user`, HTTP `8080` et PostgreSQL `5432`. Le nom de la base a été modifié pour vérifier le déclenchement automatique du pipeline sur un nouveau push, conformément à la Partie II. Le mot de passe par défaut est exclusivement une valeur de démonstration. On peut aussi injecter une variable sans l'écrire dans les fichiers suivis :

```bash
read -rsp 'Mot de passe PostgreSQL : ' TF_VAR_db_password
echo
export TF_VAR_db_password
terraform plan -out=deployment.tfplan
terraform apply -auto-approve deployment.tfplan
```

Le champ `sensitive` masque le mot de passe dans l'affichage Terraform, mais l'état et le plan binaire peuvent le contenir. Ces fichiers sont ignorés par Git et exclus du contexte Docker. Les journaux ajoutés au dépôt doivent être vérifiés avant publication.

Les tags `alpine:latest` et `postgres:latest` sont imposés par le TP : leur contenu peut évoluer. Pour une livraison reproductible hors TP, utiliser des versions ou digests fixes. Le verrou Terraform fixe quant à lui le provider réellement installé.

## Pipeline GitHub Actions

Le workflow s'exécute sur chaque push vers `main`, ainsi que manuellement avec `workflow_dispatch`. Il réalise, dans un seul job, Setup Terraform, Init, Validate, Plan, Apply du **plan enregistré**, puis les vérifications HTTP et SQL. Il vérifie aussi l'idempotence, remplace PostgreSQL après un changement de variable, et termine par Destroy. Toute erreur de Plan empêche Apply. Les exécutions sont sérialisées.

Le runner est une **VM GitHub hébergée `ubuntu-24.04`**. Docker s'exécute sur cette VM temporaire : son `localhost` désigne le runner. Pour ouvrir l'application sur le poste de travail, utiliser les commandes de la section « Exécution locale ».

### Activation

1. Pousser ce dossier comme racine d'un dépôt GitHub, pour que `.github/workflows/main.yml` soit détecté. Le dépôt du TP est <https://github.com/awabZemzemi/tp3_devops>.
2. Facultativement, ajouter **Settings → Secrets and variables → Actions → New repository secret**, nommé `TF_VAR_DB_PASSWORD`. Sans ce secret, le pipeline utilise le mot de passe de démonstration. Cette variable d'environnement a priorité sur le défaut de `variables.tf`.
3. Effectuer un push vers `main` et consulter l'onglet **Actions**. Le workflow peut aussi être lancé par **Run workflow**.

L'état reste dans le checkout pendant le job ; les étapes le partagent, puis Destroy le vide. La VM est ensuite supprimée par GitHub. Chaque nouveau push redéploie donc une infrastructure indépendante : aucun état ni conteneur ne persiste d'un run au suivant. La preuve d'un remplacement réel est effectuée au sein du même job, avec les mêmes ressources et le même état. Un déploiement durable sur une machine cible demanderait un runner ou un accès distant explicitement configuré, ainsi qu'un état persistant.

### Validation d'un deuxième push

Le test utilise un premier run réussi avec `devops_db_v2`, puis un push qui modifie le défaut de `db_name` en `devops_db_v3`. Pour reproduire un nouveau changement, passer de `devops_db_v3` à `devops_db_v4`, puis :

```bash
git add variables.tf
git commit -m "Change demo database name to validate IaC redeployment"
git push origin main
```

Le nouveau run déploie la valeur modifiée depuis `variables.tf`, puis `scripts/verify-ci-update.sh` ajoute le suffixe `_ci` au nom de cette base et crée un nouveau plan. Ce plan doit annoncer **1 création et 1 destruction**, car l'environnement PostgreSQL change. Après Apply, le script vérifie le nouvel identifiant du conteneur et `SELECT current_database()`, puis un nouveau plan doit annoncer l'absence de changements. Les preuves sont jointes au run sous l'artefact `preuves-ci-N`. Pour tester un changement de mot de passe, modifier le secret `TF_VAR_DB_PASSWORD`, puis relancer ou déclencher le workflow.

La mise à jour peut également être vérifiée localement avec `bash scripts/verify-update.sh`. Ce script déploie une base `devops_db`, la remplace par `devops_db_v2`, vérifie que l'identifiant du conteneur change et que SQL retourne la nouvelle base, puis détruit les ressources du TP. Il utilise des valeurs `-var` explicites et enregistre les preuves dans `evidence/08-*` à `evidence/10-*`.

La base est volontairement jetable : le remplacement supprime son volume anonyme et initialise une nouvelle base. Une base de production demanderait une politique de persistance, des sauvegardes et une rotation SQL du mot de passe ; changer `POSTGRES_PASSWORD` sur un volume déjà initialisé ne modifierait pas le mot de passe existant.

### Publication du dépôt

Ce répertoire est déjà initialisé en Git sur la branche `main`. Après connexion GitHub et choix du dépôt, utiliser :

```bash
gh auth login
git add .
git commit -m "Implement local Terraform Docker IaC lab and deployment pipeline"
git remote add origin https://github.com/VOTRE_COMPTE/VOTRE_DEPOT.git
git push -u origin main
```

Si le commit initial existe déjà, ne pas le recréer. Ne pas publier `terraform.tfstate`, ses sauvegardes, `terraform.tfvars` ou `deployment.tfplan`.

### Nettoyage du pipeline

L'étape Destroy utilise `if: always()` après une initialisation réussie. Elle nettoie donc aussi un déploiement partiellement appliqué ou un échec de validation. Le job vérifie ensuite que l'état est vide et qu'aucun conteneur du TP ne reste. Les plans binaires sont supprimés ; seuls les journaux texte de la mise à jour sont conservés comme artefacts pendant 14 jours.

## Références

- [Provider Docker : image_id et construction](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image).
- [Provider Docker : conteneurs et contrôles de santé](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container).
- [GitHub : runners hébergés](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
- [Terraform : rôle de l'état](https://developer.hashicorp.com/terraform/language/state/purpose).
