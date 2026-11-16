#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export TF_IN_AUTOMATION=true
mkdir -p evidence

cleanup() {
  local original_status=$?
  trap - EXIT
  set +e
  terraform destroy -auto-approve -input=false -no-color 2>&1 | tee evidence/06-destroy.log
  local destroy_status=${PIPESTATUS[0]}
  rm -f deployment.tfplan
  if (( original_status != 0 )); then
    exit "$original_status"
  fi
  exit "$destroy_status"
}

terraform fmt -check -recursive
terraform init -input=false -no-color 2>&1 | tee evidence/01-init.log
terraform validate -no-color 2>&1 | tee evidence/02-validate.log
terraform plan -input=false -no-color -out=deployment.tfplan 2>&1 | tee evidence/03-plan.log
trap cleanup EXIT
terraform apply -auto-approve -input=false -no-color deployment.tfplan 2>&1 | tee evidence/04-apply.log
bash scripts/verify.sh 2>&1 | tee evidence/05-validation.log
terraform plan -detailed-exitcode -input=false -no-color 2>&1 | tee evidence/05-idempotence.log
