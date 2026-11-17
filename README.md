# TP — Infrastructure as Code locale et CI/CD

Terraform déploie PostgreSQL et une application Nginx dans Docker.

## Fichiers

```text
tp-iac-local/
├── main.tf                    # Provider Docker, deux images et deux conteneurs
├── variables.tf               # Base, utilisateur, mot de passe et ports
├── outputs.tf                 # Nom du conteneur PostgreSQL et URL de l'application
├── Dockerfile_app             # Alpine, Nginx et page HTML
├── nginx.conf                 # Port 80 et répertoire de la page HTML
├── .github/workflows/main.yml # Init → Plan → Apply → HTTP → Destroy
├── .gitignore                 # État, plans et paramètres locaux exclus de Git
├── .dockerignore              # Seuls Dockerfile_app et nginx.conf sont envoyés au build
├── .terraform.lock.hcl        # Version du provider utilisée
├── terraform.tfvars.example   # Exemple de paramètres locaux
├── README.md
└── RAPPORT.md                 # Résultats du TP et réponses aux questions
```

## Déploiement local

Prérequis : Terraform ≥ 1.0, Docker actif et accessible, Git et curl.
Depuis ce répertoire :

```bash
terraform fmt
terraform init
terraform validate
terraform plan -out=deployment.tfplan
terraform apply -auto-approve deployment.tfplan
curl --fail --retry 10 --retry-delay 2 --retry-connrefused "$(terraform output -raw app_access_url)"
```

La page affiche **Application Deployed via Terraform IaC!** sur <http://localhost:8080/>.
Les conteneurs sont `tp-app-web` et `tp-db-postgres`. PostgreSQL est publié sur le port 5432.
L'application sert une page statique et n'a donc pas besoin d'attendre PostgreSQL.

Nettoyer après la démonstration :

```bash
terraform destroy -auto-approve
rm -f deployment.tfplan
```

Les conteneurs sont supprimés. L'image PostgreSQL reste en cache avec `keep_locally = true`, comme dans le sujet.

## Paramètres

Les valeurs se trouvent dans `variables.tf`. Le port HTTP est configurable et vaut 8080 par défaut.
Pour utiliser des paramètres locaux, copier `terraform.tfvars.example` vers `terraform.tfvars`, puis adapter les valeurs.
Le mot de passe par défaut est une valeur de démonstration. `sensitive = true` le masque dans l'affichage ; il peut néanmoins figurer dans l'état et les plans, qui sont ignorés par Git.

Le petit fichier `nginx.conf` définit le serveur et la racine de `index.html` ; le Dockerfile le copie dans la configuration Nginx d'Alpine.

## GitHub Actions

Chaque push vers `main` exécute sept étapes : Checkout, Setup Terraform, Init, Plan, Apply, vérification HTTP et Destroy.
Apply utilise le plan enregistré et ne s'exécute que si Plan réussit. Le test HTTP attend brièvement si Nginx démarre encore.
Destroy utilise `if: always()` pour tenter le nettoyage même après un échec.

Le runner GitHub est temporaire : l'application n'est accessible que dans cette VM pendant le job.
Chaque push crée une infrastructure indépendante ; pour consulter la page sur le poste de travail, utiliser le déploiement local.

Pour la Partie II du TP, modifier une valeur dans `variables.tf`, puis commiter et pousser vers `main` pour observer l'exécution du pipeline avec les nouveaux paramètres.
