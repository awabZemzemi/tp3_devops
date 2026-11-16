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

Les valeurs par défaut sont `devops_db_v2`, `devops_user`, HTTP `8080` et PostgreSQL `5432`. Le nom de la base a été modifié après le premier commit pour déclencher un deuxième pipeline, conformément à la Partie II. Le mot de passe par défaut est exclusivement une valeur de démonstration. On peut aussi injecter une variable sans l'écrire dans les fichiers suivis :

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

Le workflow s'exécute sur chaque push vers `main`, ainsi que manuellement avec `workflow_dispatch`. Il réalise, dans un seul job, Setup Terraform, Init, Validate, Plan, Apply du **plan enregistré**, puis les vérifications HTTP et SQL. Toute erreur de Plan empêche Apply. Les déploiements concurrents sont sérialisés.

Le runner est **self-hosted**, Linux x64, avec le label `iac-local`, et tourne sur la machine Docker cible. Ce choix permet de retrouver les mêmes conteneurs et le même état entre deux pushes. Un runner GitHub hébergé créerait les conteneurs sur une autre machine temporaire ; son `localhost` ne serait pas celui du poste de travail.

### Activation

1. Créer ou choisir un dépôt GitHub privé et y pousser ce dossier comme racine du dépôt, pour que `.github/workflows/main.yml` soit détecté.
2. Dans **Settings → Actions → Runners → New self-hosted runner**, sélectionner Linux x64 et suivre les commandes affichées par GitHub. Pendant la configuration, ajouter le label `iac-local` ; démarrer le runner avec `./run.sh` ou le service proposé par GitHub.
3. Vérifier que le compte exécutant le runner peut utiliser `docker info`, Bash et curl. Le runner doit rester sur la même machine et conserver son répertoire de travail entre les exécutions.
4. Facultativement, ajouter **Settings → Secrets and variables → Actions → New repository secret**, nommé `TF_VAR_DB_PASSWORD`. Sans ce secret, le pipeline utilise le mot de passe de démonstration. Cette variable d'environnement a priorité sur le défaut de `variables.tf`.
5. Effectuer un push vers `main` et consulter l'onglet **Actions**.

L'état du pipeline est situé dans `${RUNNER_WORKSPACE}/../tp-iac-state/${GITHUB_REPOSITORY}/terraform.tfstate`, hors du répertoire effacé par checkout. Son répertoire est créé avec des droits `700`. Le runner doit être sauvegardé si l'on veut conserver cet état. En cas de perte du runner, conserver et restaurer l'état avant tout nouveau déploiement.

Le workflow garde les conteneurs actifs après Apply. Le script local du cycle complet, lui, les détruit pour terminer la Partie I. Ne pas gérer les mêmes noms de conteneurs depuis deux états différents : terminer le cycle local par Destroy avant le premier déploiement du pipeline.

### Validation d'un deuxième push

Le deuxième commit du TP modifie le défaut de `db_name` dans `variables.tf`, de `devops_db` vers `devops_db_v2`. Pour reproduire un nouveau changement, passer de `devops_db_v2` à `devops_db_v3`, puis :

```bash
git add variables.tf
git commit -m "Change demo database name to validate IaC redeployment"
git push origin main
```

Après un premier déploiement réussi, le Plan doit annoncer le remplacement du conteneur PostgreSQL, car ses variables d'environnement changent. Apply utilise le même état persistant, puis `verify.sh` vérifie la nouvelle base. Pour tester un changement de mot de passe, modifier le secret `TF_VAR_DB_PASSWORD`, puis relancer ou déclencher le workflow.

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

### Destruction après le pipeline

Sur le runner, depuis le checkout utilisé par Actions, le backend configuré par Init pointe déjà vers l'état persistant :

```bash
terraform destroy -auto-approve
terraform state list
```

Fournir les mêmes variables/secrets que pendant le déploiement. Si le checkout a disparu, refaire `terraform init -backend-config="path=/chemin/absolu/vers/terraform.tfstate"` avec le chemin exact de l'état du pipeline avant Destroy.

## Références

- [Provider Docker : image_id et construction](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image).
- [Provider Docker : conteneurs et contrôles de santé](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container).
- [GitHub : ajouter un runner self-hosted](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners).
- [Terraform : rôle de l'état](https://developer.hashicorp.com/terraform/language/state/purpose).
