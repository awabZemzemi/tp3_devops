#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

url=$(terraform output -raw app_access_url)
db=$(terraform output -raw db_container_name)
app=$(terraform output -raw app_container_name)

body=$(curl --fail --silent --show-error --retry 20 --retry-delay 2 --retry-connrefused --max-time 10 "$url")
if [[ "$body" != *"Application Deployed via Terraform IaC!"* ]]; then
  printf 'La réponse HTTP ne contient pas le message attendu.\n' >&2
  exit 1
fi
printf 'HTTP OK : %s\n%s\n' "$url" "$body"

for container in "$db" "$app"; do
  status=$(docker inspect --format '{{.State.Health.Status}}' "$container")
  [[ "$status" == healthy ]]
  printf '%s : %s\n' "$container" "$status"
done

# Connexion TCP authentifiée : vérifie aussi le mot de passe, sans l'afficher.
result=$(docker exec "$db" sh -ec 'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT 1"')
[[ "$result" == 1 ]]
printf 'PostgreSQL : connexion authentifiée et SELECT 1 réussis.\n'
