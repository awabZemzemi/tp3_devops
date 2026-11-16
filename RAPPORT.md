# Rapport — Infrastructure as Code locale et pipeline CI/CD

**Date :** 16 novembre 2026.

**Environnement :** Linux x86_64, Terraform 1.16.0, Docker Engine 29.1.3, provider `kreuzwerker/docker` 4.7.0 verrouillé par `.terraform.lock.hcl`.

**Dépôt :** <https://github.com/awabZemzemi/tp3_devops>.

## 1. Objectif et architecture

Terraform gère quatre ressources : deux images Docker et deux conteneurs. L'application est construite depuis `alpine:latest`, avec Nginx et la page « Application Deployed via Terraform IaC! ». PostgreSQL utilise `postgres:latest` et reçoit son utilisateur, son mot de passe et le nom de la base depuis `variables.tf`.

```text
Navigateur / curl → 127.0.0.1:8080 → tp-app-web:80 → Nginx → index.html
Client SQL       → 127.0.0.1:5432 → tp-db-postgres:5432 → PostgreSQL
```

Les services sont publiés uniquement sur l'interface locale. L'application sert une page statique ; elle n'effectue pas de requêtes à la base. Les deux services utilisent le réseau bridge Docker par défaut. La dépendance Terraform ordonne leur création ; la disponibilité réelle de PostgreSQL est vérifiée par `healthcheck` et `wait = true` avant la création de l'application.

Le fichier `nginx.conf` définit explicitement le port 80 et la racine de la page. Les conteneurs référencent l'attribut `docker_image.*.image_id`, conformément au provider actuel. Les empreintes des fichiers de construction déclenchent la reconstruction de l'image lorsque le Dockerfile ou la configuration Nginx change. Le builder Docker classique est sélectionné explicitement : le poste n'a pas besoin d'une installation séparée de Buildx. Le cycle complet a été revérifié avec cette configuration.

## 2. Cycle de vie du déploiement local

Le script `scripts/run-lifecycle.sh` a terminé avec le code de retour **0**. Il a exécuté les étapes du sujet et enregistré les sorties réelles dans `evidence/`.

| Étape | Commande | Preuve |
| --- | --- | --- |
| Initialisation | `terraform init -input=false` | `evidence/01-init.log` |
| Validation | `terraform validate` | `evidence/02-validate.log` |
| Planification | `terraform plan -out=deployment.tfplan` | `evidence/03-plan.log` |
| Application | `terraform apply -auto-approve deployment.tfplan` | `evidence/04-apply.log` |
| Validation des services | `bash scripts/verify.sh` | `evidence/05-validation.log` |
| Idempotence | `terraform plan -detailed-exitcode` | `evidence/05-idempotence.log` |
| Destruction | `terraform destroy -auto-approve` | `evidence/06-destroy.log` |
| État final | `terraform state list` et contrôle Docker | `evidence/07-cleanup.log` |

Résultats observés :

- Init : provider Docker 4.7.0 installé et backend local initialisé.
- Validate : `Success! The configuration is valid.`
- Plan : **4 à créer, 0 à modifier, 0 à détruire**.
- Apply : **4 ressources ajoutées** ; conteneurs PostgreSQL et Nginx sains.
- HTTP : réponse sur `http://localhost:8080/` contenant le message demandé.
- PostgreSQL : connexion TCP authentifiée et `SELECT 1` réussis.
- Idempotence : `No changes. Your infrastructure matches the configuration.` ; code de retour **0**.
- Destroy : **4 ressources détruites**.
- État final : `terraform.tfstate` existe avec `resources = []` ; aucun conteneur TP restant.

Le plan enregistré est appliqué directement : Apply exécute donc les actions calculées par Plan. Le script vérifie le message HTTP, la santé des deux conteneurs et une connexion TCP PostgreSQL authentifiée exécutant `SELECT 1`. Une seconde planification vérifie l'idempotence : le code de retour attendu est `0`, contre `2` si des changements sont encore nécessaires.

Le nettoyage supprime les conteneurs, leurs volumes anonymes et la ressource image de l'application. L'image PostgreSQL reste en cache avec `keep_locally = true`. Le cache Docker et l'image Alpine peuvent aussi rester : ils ne correspondent pas à des conteneurs applicatifs actifs.

## 3. Automatisation CI/CD

Le fichier `.github/workflows/main.yml` déclenche le pipeline sur chaque push vers `main`. Il peut aussi être lancé manuellement. Il prépare Terraform, initialise le backend, valide la configuration, produit un plan binaire, l'applique, puis vérifie HTTP et PostgreSQL. Il vérifie ensuite l'idempotence et une mise à jour de PostgreSQL, avant de détruire les ressources.

Toutes les étapes utilisent la même VM GitHub hébergée `ubuntu-24.04` et partagent son état local pendant le job. Le poste de travail n'est pas exposé aux workflows du dépôt. Le job termine par Destroy et vérifie l'absence de conteneurs ainsi qu'un état vide. Un nouveau push démarre une VM indépendante : il ne reprend pas les objets d'un run précédent. Le remplacement d'une ressource est donc vérifié dans le même job, avec le même état, avant le nettoyage.

Apply n'utilise aucune condition autorisant une exécution après échec : le comportement normal de GitHub Actions l'empêche de s'exécuter si Plan échoue. Destroy s'exécute après toute initialisation réussie, même si une étape suivante échoue. Les plans contenant potentiellement des données sensibles sont supprimés à la fin du job. Les journaux texte de mise à jour sont publiés comme artefacts.

### Validation d'une modification

Le défaut de `db_name` a été modifié de `devops_db` vers `devops_db_v2` après le premier commit. Après un premier run hébergé réussi avec `devops_db_v2`, un nouveau push modifie ce défaut en `devops_db_v3` pour vérifier à nouveau le déclenchement automatique. Chaque run hébergé déploie la valeur du commit, puis `scripts/verify-ci-update.sh` lui ajoute le suffixe `_ci` et produit un plan de remplacement. Le script vérifie le changement d'identifiant du conteneur, le nom de la nouvelle base avec SQL et l'idempotence après mise à jour.

**Validation locale réellement exécutée :** `bash scripts/verify-update.sh` a terminé avec le code de retour **0**. Le script utilise deux plans successifs avec `-var='db_name=devops_db'`, puis `-var='db_name=devops_db_v2'`. Le second Plan annonce **1 à créer, 0 à modifier, 1 à détruire** ; Apply confirme **1 ressource ajoutée et 1 détruite**. L'identifiant du conteneur PostgreSQL change, `SELECT current_database()` retourne `devops_db_v2`, les contrôles HTTP et SQL réussissent, puis Destroy supprime les quatre ressources.

| Preuve de mise à jour | Fichier |
| --- | --- |
| Déploiement de la base initiale | `evidence/08-update-baseline-apply.log` |
| Plan de remplacement | `evidence/09-update-plan.log` |
| Application du remplacement | `evidence/09-update-apply.log` |
| Identifiants différents et nouvelle base vérifiée | `evidence/09-update-validation.log` |
| Nettoyage après l'essai | `evidence/10-update-destroy.log` |

**Validation GitHub Actions réellement exécutée :** deux pushes successifs ont déclenché et terminé le pipeline avec succès.

| Push | Commit | Base du commit → base testée après remplacement | Run GitHub Actions | Résultat du job |
| --- | --- | --- | --- | --- |
| Déploiement initial hébergé | `1c1aff4` | `devops_db_v2` → `devops_db_v2_ci` | [43847439404](https://github.com/awabZemzemi/tp3_devops/actions/runs/43847439404) | Réussi, 43 s |
| Modification de `variables.tf` | `1ce2039` | `devops_db_v3` → `devops_db_v3_ci` | [43847775404](https://github.com/awabZemzemi/tp3_devops/actions/runs/43847775404) | Réussi, 43 s |

Dans les deux runs, toutes les étapes sont réussies : Init, Validate, Plan, Apply, HTTP/SQL, idempotence, remplacement PostgreSQL, publication des preuves et Destroy avec vérification d'un état vide. Le plan de mise à jour annonce **1 création et 1 destruction** ; Apply confirme ces actions ; SQL confirme le nouveau nom ; le dernier plan annonce **No changes**. Les preuves téléchargées sont conservées sous `evidence/github-run-43847439404/` et `evidence/github-run-43847775404/`, ainsi que dans les artefacts de chaque run.

La suppression du volume anonyme lors du remplacement rend ce test jetable. Aucun volume persistant n'est prévu dans le sujet. En contexte réel, changer une variable d'initialisation PostgreSQL ne suffit pas à modifier une base déjà initialisée conservée sur un volume.

## 4. Questions d'approfondissement

### 1. Quel est l'impact réel de `terraform destroy` sur `terraform.tfstate` ?

`terraform destroy` demande au provider de supprimer les objets gérés, puis actualise l'état pour en retirer les ressources détruites. Il ne supprime normalement pas le fichier d'état : le fichier conserve sa structure et ses métadonnées, avec un ensemble de ressources vide si tout a été détruit. Une destruction partielle conserve les entrées nécessaires pour suivre les objets restants.

L'état associe chaque adresse Terraform à l'identifiant réel de l'objet. Lors d'un plan, Terraform rafraîchit ces informations auprès du provider et les compare à la configuration pour calculer les créations, changements et suppressions. Effacer seulement le fichier d'état ne détruit aucune infrastructure et fait perdre ces associations. Les sauvegardes de l'état peuvent encore contenir les anciens secrets.

### 2. Que signifie l'immuabilité de l'infrastructure ?

Une infrastructure immuable se met à jour en remplaçant ses composants par de nouvelles instances issues d'une définition versionnée. On évite de modifier manuellement une instance en cours d'exécution, car ces modifications ne seraient pas reproductibles depuis le dépôt.

Dans ce TP, une modification du Dockerfile reconstruit l'image grâce à son empreinte, et le conteneur utilise la nouvelle image. Modifier l'environnement du conteneur PostgreSQL provoque également son remplacement. Les données doivent être traitées séparément si elles doivent survivre à ce remplacement.

### 3. Pourquoi Plan est-il une porte de contrôle avant Apply ?

Plan calcule les différences entre la configuration, l'état et les objets observés. Il permet de vérifier les erreurs, les dépendances et les suppressions ou remplacements avant de modifier l'infrastructure. Il fournit ainsi une base de revue, particulièrement pour les changements destructifs en production.

Appliquer le fichier de plan enregistré relie la revue aux actions exécutées. Le pipeline de ce TP impose la réussite du plan, mais n'ajoute pas d'approbation humaine. Un environnement de production peut compléter ce contrôle par une approbation, des règles de politique et une protection de branche. Un plan réussi ne garantit pas qu'Apply réussira : des erreurs d'exécution ou des changements concurrents peuvent encore survenir.

### 4. Quelle ressource ajouter pour connecter les conteneurs à un réseau Docker ?

Ajouter une ressource `docker_network`, puis référencer son nom depuis un bloc `networks_advanced` dans chacun des conteneurs :

```hcl
resource "docker_network" "app_network" {
  name = "tp-iac-network"
}

# À ajouter dans chacune des deux ressources docker_container :
# networks_advanced {
#   name = docker_network.app_network.name
# }
```

Un réseau bridge défini par l'utilisateur permet notamment la résolution DNS entre conteneurs par leur nom. Terraform déduit la dépendance au réseau à partir des références et supprime les conteneurs avant de détruire ce réseau.

## 5. Références

- Sujet fourni : « TP IaC Local .pdf ».
- [Provider Docker : images](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image) et [conteneurs](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container).
- [HashiCorp : rôle de l'état](https://developer.hashicorp.com/terraform/language/state/purpose).
- [GitHub : runners hébergés](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
