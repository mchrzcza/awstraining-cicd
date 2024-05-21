#!/usr/bin/env bash

set -e

TF_STATE_BUCKET="tf-state-${PROFILE}-${REGION}-${UNIQUE_BUCKET_STRING}"

empty_tfstate_bucket() {
  aws s3api delete-objects \
      --bucket $TF_STATE_BUCKET \
      --delete "$(aws s3api list-object-versions --bucket ${TF_STATE_BUCKET} --output=json --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
      --profile $PROFILE \
      --region $REGION || true
}

delete_secrets_manager() {
  aws secretsmanager delete-secret \
      --secret-id backend-secretsmanager-test-eu-central-1 \
      --force-delete-without-recovery \
    	--profile $PROFILE \
    	--region $REGION || true
}

empty_ecr() {
  ECR_REPOSITORY="backend"
  aws ecr batch-delete-image \
      --repository-name $ECR_REPOSITORY \
      --profile $PROFILE \
      --region $REGION \
      --image-ids "$(aws ecr list-images --region $REGION --profile $PROFILE --repository-name $ECR_REPOSITORY --query 'imageIds[*]' --output json)" || true
}

delete_log_groups() {
  aws logs describe-log-groups --query 'logGroups[*].logGroupName' --output table --region $REGION --profile $PROFILE | \
  awk '{print $2}' | grep -v ^$ | while read x; do  echo "deleting $x" ; aws logs delete-log-group --log-group-name $x --region $REGION --profile $PROFILE; done || true
}

if [ "$#" -lt 4 ]; then
  echo "Not enough arguments provided."
  echo
  echo "Script should be used in following form:"
  echo
  echo "$0 SCRIPT PROFILE REGION ACTION"
  echo
  echo "example usage: "
  echo
  echo "$0 setup_new_region.sh backend-test eu-central-1 plan"
  echo
  echo "or: "
  echo
  echo "$0 setup_new_region.sh backend-test eu-central-1 apply"
  echo "$0 setup_new_region.sh backend-test eu-central-1 apply -auto-approve"
  echo
  echo "Apply will ask for your confirmation after each module."
  exit 1
fi

# remove any state from previous runs (possibly on different environments)
rm common/*/*/.terraform/terraform.tfstate || true

# Declare an associative array
declare -A REGION_TO_HUB=(
  ["eu-central-1"]="emea"
  ["us-east-1"]="us"
  ["cn-north-1"]="cn"
)

# Load properties file
source 'wrapper.properties'

SCRIPT=$1
PROFILE=$2
REGION=$3
# Get the corresponding hub from the associative array
HUB="${REGION_TO_HUB[$REGION]}"
ACTION=${@:4}

if [ "$ACTION" = "destroy -auto-approve" ]; then
  if aws s3api head-bucket --bucket $TF_STATE_BUCKET --profile $PROFILE --region $REGION 2>/dev/null; then
    ./$SCRIPT $PROFILE $REGION common/services/measurements-dynamodb $ACTION
    delete_secrets_manager
    empty_ecr
    ./$SCRIPT $PROFILE $REGION common/services/ecs-backend-service $ACTION
    ./$SCRIPT $PROFILE $REGION common/services/ecs-backend-cluster $ACTION
    ./$SCRIPT $PROFILE $REGION common/services/ecr $ACTION
    ./$SCRIPT $PROFILE $REGION common/monitoring/sns $ACTION
    ./$SCRIPT $PROFILE $REGION common/networking/securitygroups $ACTION
    ./$SCRIPT $PROFILE $REGION common/networking/vpc $ACTION
    ./$SCRIPT $PROFILE $REGION environments/$PROFILE/$HUB/$REGION/globals $ACTION
    ./$SCRIPT $PROFILE $REGION common/general/dynamo-lock $ACTION
    empty_tfstate_bucket
    ./$SCRIPT $PROFILE $REGION common/general/create-remote-state-bucket $ACTION
    delete_log_groups
  elif
    echo "Skipping destroy - everything was already destroyed!"
  fi
else
  ./$SCRIPT $PROFILE $REGION common/general/create-remote-state-bucket $ACTION
  ./$SCRIPT $PROFILE $REGION common/general/dynamo-lock $ACTION
  ./$SCRIPT $PROFILE $REGION environments/$PROFILE/$HUB/$REGION/globals $ACTION
  ./$SCRIPT $PROFILE $REGION common/networking/vpc $ACTION
  ./$SCRIPT $PROFILE $REGION common/networking/securitygroups $ACTION
  ./$SCRIPT $PROFILE $REGION common/monitoring/sns $ACTION
  ./$SCRIPT $PROFILE $REGION common/services/ecr $ACTION
  ./$SCRIPT $PROFILE $REGION common/services/ecs-backend-cluster $ACTION
  ./$SCRIPT $PROFILE $REGION common/services/ecs-backend-service $ACTION
  ./$SCRIPT $PROFILE $REGION common/services/measurements-dynamodb $ACTION
fi
