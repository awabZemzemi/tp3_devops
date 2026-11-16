#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p evidence

# Le pipeline a déjà déployé les ressources : on conserve le même état pour
# prouver un vrai remplacement, avant la destruction finale du job.
db=$(terraform output -raw db_container_name)
old_id=$(docker inspect --format '{{.Id}}' "$db")
base_name=$(docker exec "$db" sh -ec 'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT current_database()"')
updated_name="${base_name}_ci"

terraform plan -input=false -lock-timeout=60s -no-color -var="db_name=${updated_name}" -out=update.tfplan 2>&1 | tee evidence/ci-update-plan.log
terraform apply -auto-approve -input=false -lock-timeout=60s -no-color update.tfplan 2>&1 | tee evidence/ci-update-apply.log
new_id=$(docker inspect --format '{{.Id}}' "$db")
[[ "$old_id" != "$new_id" ]]
bash scripts/verify.sh | tee evidence/ci-update-validation.log

actual_name=$(docker exec "$db" sh -ec 'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT current_database()"')
[[ "$actual_name" == "$updated_name" ]]
printf 'Identifiant PostgreSQL modifié : %s → %s\nBase vérifiée par SQL : %s\n' "$old_id" "$new_id" "$actual_name" | tee -a evidence/ci-update-validation.log
terraform plan -input=false -detailed-exitcode -no-color -var="db_name=${updated_name}" 2>&1 | tee evidence/ci-update-idempotence.log
