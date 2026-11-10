#!/bin/bash
# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`
#----------------------------------------------------start--------------------------------------------------#

echo "${BG_MAGENTA}${BOLD}Starting Execution${RESET}"

gcloud services enable dataplex.googleapis.com

bq mk --location=US --dataset ecommerce

gcloud services enable bigqueryconnection.googleapis.com

bq mk --connection --location=US --project_id=$DEVSHELL_PROJECT_ID \
    --connection_type=CLOUD_RESOURCE customer_data_connection

CLOUD=$(bq show --connection $DEVSHELL_PROJECT_ID.US.customer_data_connection | grep "serviceAccountId" | awk '{gsub(/"/, "", $8); print $8}')

NEWs="${CLOUD%?}"

gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member="serviceAccount:$NEWs" \
    --role="roles/storage.objectViewer"

bq mkdef --autodetect=true --source_format=CSV \
    --connection_id=$DEVSHELL_PROJECT_ID.US.customer_data_connection \
    gs://$DEVSHELL_PROJECT_ID-bucket/customer-online-sessions.csv > table_def.json

bq mk --table --external_table_definition=table_def.json \
    ecommerce.customer_online_sessions

cat > aspect_template.json << EOF
{
  "name": "sensitive_data_aspect",
  "type": "record",
  "recordFields": [
    {
      "name": "has_sensitive_data",
      "type": "bool",
      "index": 1,
      "annotations": { "displayName": "Has Sensitive Data" }
    },
    {
      "name": "sensitive_data_type",
      "type": "enum",
      "index": 2,
      "annotations": { "displayName": "Sensitive Data Type" },
      "enumValues": [
        { "name": "Location Info", "index": 1 },
        { "name": "Contact Info", "index": 2 },
        { "name": "None", "index": 3 }
      ]
    }
  ]
}
EOF

ENTRY_NAME=""
for i in $(seq 1 30); do
  for LOC in us US; do
    ENTRY_NAME=$(gcloud dataplex entries lookup \
      "projects/$DEVSHELL_PROJECT_ID/locations/$LOC/entryGroups/@bigquery/entries/bigquery.googleapis.com/projects/$DEVSHELL_PROJECT_ID/datasets/ecommerce/tables/customer_online_sessions" \
      --format="value(name)" 2>/dev/null)
    if [ -n "$ENTRY_NAME" ]; then break; fi
  done
  if [ -n "$ENTRY_NAME" ]; then break; fi
  sleep 10
done

if [ -z "$ENTRY_NAME" ]; then
  ENTRY_NAME="projects/$DEVSHELL_PROJECT_ID/locations/us/entryGroups/@bigquery/entries/bigquery.googleapis.com/projects/$DEVSHELL_PROJECT_ID/datasets/ecommerce/tables/customer_online_sessions"
fi

ASPECT_LOC=$(echo "$ENTRY_NAME" | cut -d'/' -f4)
[ -z "$ASPECT_LOC" ] && ASPECT_LOC=us

if ! gcloud dataplex aspect-types create sensitive-data-aspect \
    --location=$ASPECT_LOC \
    --display-name="Sensitive Data Aspect" \
    --metadata-template-file-name=aspect_template.json; then
  ASPECT_LOC=global
  gcloud dataplex aspect-types create sensitive-data-aspect \
    --location=global \
    --display-name="Sensitive Data Aspect" \
    --metadata-template-file-name=aspect_template.json
fi

cat > aspect_file.json << EOF
{
  "$DEVSHELL_PROJECT_ID.$ASPECT_LOC.sensitive-data-aspect": {
    "data": {
      "has_sensitive_data": true,
      "sensitive_data_type": "Location Info"
    }
  }
}
EOF

gcloud dataplex entries update-aspects "$ENTRY_NAME" --aspects=aspect_file.json

echo "${BG_RED}${BOLD}Congratulations For Completing The Lab !!!${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#