#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export TF_IN_AUTOMATION=true
mkdir -p evidence

cleanup() {
  local original_status=$?
  trap - EXIT
  set +e
  terraform destroy -auto-approve -input=false -no-color 2>&1 | tee evidence/10-update-destroy.log
  local destroy_status=${PIPESTATUS[0]}
  rm -f baseline.tfplan update.tfplan
  if (( original_status != 0 )); then exit "$original_status"; fi
  exit "$destroy_status"
}

terraform init -input=false -no-color
terraform plan -input=false -no-color -var='db_name=devops_db' -out=baseline.tfplan
trap cleanup EXIT
terraform apply -auto-approve -input=false -no-color baseline.tfplan 2>&1 | tee evidence/08-update-baseline-apply.log
old_db_id=$(docker inspect --format '{{.Id}}' tp-db-postgres)

terraform plan -input=false -no-color -var='db_name=devops_db_v2' -out=update.tfplan 2>&1 | tee evidence/09-update-plan.log
terraform apply -auto-approve -input=false -no-color update.tfplan 2>&1 | tee evidence/09-update-apply.log
new_db_id=$(docker inspect --format '{{.Id}}' tp-db-postgres)
[[ "$old_db_id" != "$new_db_id" ]]
bash scripts/verify.sh | tee evidence/09-update-validation.log

new_db_name=$(docker exec tp-db-postgres sh -ec 'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT current_database()"')
[[ "$new_db_name" == devops_db_v2 ]]
printf 'Identifiant PostgreSQL modifié : %s → %s\nBase vérifiée par SQL : %s\n' "$old_db_id" "$new_db_id" "$new_db_name" | tee -a evidence/09-update-validation.log
