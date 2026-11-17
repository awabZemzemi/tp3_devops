# Rapport — Infrastructure as Code locale et pipeline CI/CD

**Date :** 17 novembre 2026.

**Environnement :** Terraform 1.16.0, Docker Engine 29.1.3 et provider `kreuzwerker/docker` 4.7.0.

## 1. Infrastructure

Le projet contient quatre ressources Terraform : l'image `postgres:latest`, son conteneur, l'image Nginx construite avec `Dockerfile_app` et son conteneur.
PostgreSQL utilise les paramètres de `variables.tf` et le port 5432. L'application publie son port interne 80 sur le port configurable 8080.
`outputs.tf` affiche le nom du conteneur PostgreSQL et l'URL de l'application.

L'application est une page statique ; elle ne dépend pas de la base. Terraform déduit uniquement les dépendances entre chaque conteneur et son image.
Le Dockerfile installe Nginx sur Alpine, crée le message demandé et démarre Nginx au premier plan.
`nginx.conf` définit le port 80 et le répertoire contenant la page.

## 2. Cycle de vie local

Les commandes utilisées sont `terraform fmt`, `terraform init`, `terraform validate`, `terraform plan`, `terraform apply`, une requête HTTP et `terraform destroy`.

Résultats de la version simplifiée vérifiée le 17 novembre 2026 :

| Étape | Résultat |
| --- | --- |
| Formatage | `terraform fmt` exécuté |
| Init | Initialisation réussie ; ancienne configuration du backend local retirée |
| Validate | Configuration valide |
| Plan | 4 ressources à créer, 0 à modifier, 0 à détruire |
| Apply | 4 ressources créées ; les deux conteneurs démarrent |
| HTTP | Page accessible sur `http://localhost:8080/`, avec le message demandé |
| Destroy | 4 ressources détruites |

L'image PostgreSQL reste en cache avec `keep_locally = true`. Les conteneurs sont supprimés.

## 3. Pipeline CI/CD

Le workflow se déclenche sur chaque push vers `main` :

1. Checkout récupère le dépôt.
2. Setup Terraform installe la CLI.
3. Init initialise le projet et installe le provider verrouillé.
4. Plan enregistre les actions dans `deployment.tfplan`.
5. Apply exécute ce plan, uniquement si Plan réussit.
6. curl vérifie que la page est accessible.
7. Destroy nettoie les ressources avec `if: always()`, même après un échec.

Le runner GitHub est temporaire. Chaque push crée une nouvelle infrastructure sur cette VM ; il ne met pas à jour les conteneurs du poste local.
Pour valider la Partie II, modifier une variable et observer le pipeline déclenché par le push suivant.
La syntaxe YAML et les commandes shell du workflow ont été vérifiées localement, ainsi que la séquence Terraform et HTTP ci-dessus.
La version simplifiée n'a pas été commitée ou poussée : aucune nouvelle exécution GitHub Actions n'est donc revendiquée.

## 4. Questions d'approfondissement

### 1. Quel est l'impact réel de `terraform destroy` sur `terraform.tfstate` ?

`terraform destroy` demande au provider de supprimer les objets gérés, puis actualise l'état pour en retirer les ressources détruites. Il ne supprime normalement pas le fichier d'état : le fichier conserve sa structure et ses métadonnées, avec un ensemble de ressources vide si tout a été détruit. Une destruction partielle conserve les entrées nécessaires pour suivre les objets restants.

L'état associe chaque adresse Terraform à l'identifiant réel de l'objet. Lors d'un plan, Terraform rafraîchit ces informations auprès du provider et les compare à la configuration pour calculer les créations, changements et suppressions. Effacer seulement le fichier d'état ne détruit aucune infrastructure et fait perdre ces associations. Les sauvegardes de l'état peuvent encore contenir les anciens secrets.

### 2. Que signifie l'immuabilité de l'infrastructure ?

Une infrastructure immuable se met à jour en remplaçant ses composants par de nouvelles instances issues d'une définition versionnée. On évite de modifier manuellement une instance en cours d'exécution, car ces modifications ne seraient pas reproductibles depuis le dépôt.

Dans ce TP, les images décrivent le contenu des conteneurs. Modifier l'environnement d'un conteneur PostgreSQL provoque son remplacement plutôt qu'une modification manuelle de l'instance. Une nouvelle version de l'application se déploie avec une nouvelle image. Les données doivent être traitées séparément si elles doivent survivre au remplacement.

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
