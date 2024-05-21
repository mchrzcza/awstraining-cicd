#!/usr/bin/bash

set -e
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

SCRIPT=$1
PROFILE=$2
REGION=$3
# Get the corresponding hub from the associative array
HUB="${REGION_TO_HUB[$REGION]}"
ACTION=${@:4}

if [ "$ACTION" = "destroy -auto-approve" ]; then
  ./$SCRIPT $PROFILE $REGION common/services/measurements-dynamodb $ACTION
  ./$SCRIPT $PROFILE $REGION common/services/ecs-backend-service $ACTION
  ./$SCRIPT $PROFILE $REGION common/services/ecs-backend-cluster $ACTION
  ./$SCRIPT $PROFILE $REGION common/services/ecr $ACTION
  ./$SCRIPT $PROFILE $REGION common/monitoring/sns $ACTION
  ./$SCRIPT $PROFILE $REGION common/networking/securitygroups $ACTION
  ./$SCRIPT $PROFILE $REGION common/networking/vpc $ACTION
  ./$SCRIPT $PROFILE $REGION environments/$PROFILE/$HUB/$REGION/globals $ACTION
  ./$SCRIPT $PROFILE $REGION common/general/dynamo-lock $ACTION
  ./$SCRIPT $PROFILE $REGION common/general/create-remote-state-bucket $ACTION
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
