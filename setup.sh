#!/bin/sh
set -e

gum confirm '
Are you ready to start?
Select "Yes" only if you did NOT follow the story from the start (if you jumped straight into this chapter).
Feel free to say "No" and inspect the script if you prefer setting up resources manually.
' || exit 0

echo "
## You will need following tools installed:
|Name            |Required             |More info                                          |
|----------------|---------------------|---------------------------------------------------|
|Docker          |Yes                  |'https://docs.docker.com/engine/install'           |
|gitHub CLI      |Yes                  |'https://cli.github.com/'                          |
|git CLI         |Yes                  |'https://git-scm.com/downloads'                    |
|helm CLI        |If using Helm        |'https://helm.sh/docs/intro/install/'              |
|kubectl CLI     |Yes                  |'https://kubernetes.io/docs/tasks/tools/#kubectl'  |
|kind CLI        |Yes                  |'https://kind.sigs.k8s.io/docs/user/quick-start/#installation'|
|yq CLI          |Yes                  |'https://github.com/mikefarah/yq#install'          |
|Google Cloud account with admin permissions|If using Google Cloud|'https://cloud.google.com'|
|Google Cloud CLI|If using Google Cloud|'https://cloud.google.com/sdk/docs/install'        |
|gke-gcloud-auth-plugin|If using Google Cloud|'https://cloud.google.com/blog/products/containers-kubernetes/kubectl-auth-changes-in-gke'|
|AWS account with admin permissions|If using AWS|'https://aws.amazon.com'                  |
|AWS CLI         |If using AWS         |'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html'|
|Azure account with admin permissions|If using Azure|'https://azure.microsoft.com'         |
|az CLI          |If using Azure       |'https://learn.microsoft.com/cli/azure/install-azure-cli'|

If you are running this script from **Nix shell**, most of the requirements are already set with the exception of **Docker** and the **hyperscaler account**.
" | gum format

gum confirm "
Do you have those tools installed?
" || exit 0

rm -f .env

#############
# Variables #
#############

echo "# Variables" | gum format

echo "export HYPERSCALER=$HYPERSCALER" >> .env

###########
# Cluster #
###########

echo "# Cluster" | gum format

kind create cluster --name crossplane-observability-demo

kubectl create namespace a-team

##############
# Crossplane #
##############

echo "# Crossplane" | gum format

helm repo add crossplane-stable https://charts.crossplane.io/stable

helm repo update

helm upgrade --install crossplane crossplane-stable/crossplane \
    --namespace crossplane-system --create-namespace \
    --values ./crossplane-config/values.yaml \
    --wait

if [[ "$HYPERSCALER" == "google" ]]; then

    gcloud auth login

    # Project

    PROJECT_ID=dot-$(date +%Y%m%d%H%M%S)

    echo "export PROJECT_ID=$PROJECT_ID" >> .env

    gcloud projects create ${PROJECT_ID}

    # APIs

    echo "## Open https://console.cloud.google.com/marketplace/product/google/container.googleapis.com?project=$PROJECT_ID in a browser and *ENABLE* the API." \
        | gum format

    gum input --placeholder "
Press the enter key to continue."

echo "## Open https://console.cloud.google.com/apis/library/sqladmin.googleapis.com?project=$PROJECT_ID in a browser and *ENABLE* the API." \
        | gum format

    gum input --placeholder "
Press the enter key to continue."

    # Service Account (general)

    export SA_NAME=devops-toolkit

    export SA="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

    gcloud iam service-accounts create $SA_NAME \
        --project $PROJECT_ID

    export ROLE=roles/admin

    gcloud projects add-iam-policy-binding --role $ROLE \
        $PROJECT_ID --member serviceAccount:$SA

    gcloud iam service-accounts keys create gcp-creds.json \
        --project $PROJECT_ID --iam-account $SA

    # Crossplane

    yq --inplace ".spec.projectID = \"$PROJECT_ID\"" \
        crossplane-packages/google-config.yaml

    kubectl --namespace crossplane-system \
        create secret generic gcp-creds \
        --from-file creds=./gcp-creds.json

elif [[ "$HYPERSCALER" == "aws" ]]; then

    AWS_ACCESS_KEY_ID=$(gum input --placeholder "AWS Access Key ID" --value "$AWS_ACCESS_KEY_ID")
    echo "export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >> .env

    AWS_SECRET_ACCESS_KEY=$(gum input --placeholder "AWS Secret Access Key" --value "$AWS_SECRET_ACCESS_KEY" --password)
    echo "export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" >> .env

    AWS_ACCOUNT_ID=$(gum input --placeholder "AWS Account ID" --value "$AWS_ACCOUNT_ID")
    echo "export AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID" >> .env

    echo "[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
" >aws-creds.conf

    kubectl --namespace crossplane-system \
        create secret generic aws-creds \
        --from-file creds=./aws-creds.conf \
        --from-literal accessKeyID=$AWS_ACCESS_KEY_ID \
        --from-literal secretAccessKey=$AWS_SECRET_ACCESS_KEY
else

    AZURE_TENANT_ID=$(gum input --placeholder "Azure Tenant ID" --value "$AZURE_TENANT_ID")

    az login --tenant $AZURE_TENANT_ID

    export SUBSCRIPTION_ID=$(az account show --query id -o tsv)

    az ad sp create-for-rbac --sdk-auth --role Owner --scopes /subscriptions/$SUBSCRIPTION_ID | tee azure-creds.json

    kubectl --namespace crossplane-system create secret generic azure-creds --from-file creds=./azure-creds.json

    TIMESTAMP=$(date +%Y%m%d%H%M%S)

    yq --inplace ".spec.id = \"db$TIMESTAMP\"" \
        db/azure.yaml

    yq --inplace ".metadata.name = \"db$TIMESTAMP-password\"" \
        db/azure-password.yaml

fi

kubectl apply --filename crossplane-packages/dot-kubernetes.yaml

kubectl apply --filename crossplane-packages/dot-sql.yaml

kubectl apply --filename crossplane-packages/helm-incluster.yaml

kubectl apply \
    --filename crossplane-packages/kubernetes-incluster.yaml

echo "## Waiting for Crossplane packages to be ready..." \
    | gum format

sleep 60

kubectl wait --for=condition=healthy provider.pkg.crossplane.io \
    --all --timeout=600s

kubectl apply \
    --filename crossplane-packages/$HYPERSCALER-config.yaml

if [[ "$HYPERSCALER" == "azure" ]]; then

    kubectl --namespace a-team apply \
        --filename db/azure-password.yaml

else

    kubectl --namespace a-team apply --filename db/password.yaml

fi

##################
# Atlas Operator #
##################

echo "# Atlas Operator" | gum format

helm upgrade --install atlas-operator \
    oci://ghcr.io/ariga/charts/atlas-operator \
    --namespace atlas-operator --create-namespace --wait

#############
# Dynatrace #
#############

echo "# Dynatrace" | gum format

gum confirm '
To configure Dynatrace, you need to complete a few manual steps:

- Navigate to the Dynatrace Kubernetes app and click "Add cluster"
- Select "Other distributions"
- Enter "crossplane-observability-demo" as cluster name
- Generate the needed tokens

Ready?
' || exit 0

DYNATRACE_URL=$(gum input --placeholder "Dynatrace URL" --value "$DYNATRACE_URL")
echo "export DYNATRACE_URL=$DYNATRACE_URL" >> .env

DYNATRACE_OPERATOR_TOKEN=$(gum input --placeholder "Dynatrace Operator Token" --value "$DYNATRACE_OPERATOR_TOKEN" --password)
echo "export DYNATRACE_OPERATOR_TOKEN=$DYNATRACE_OPERATOR_TOKEN" >> .env

DYNATRACE_DATA_INGEST_TOKEN=$(gum input --placeholder "Dynatrace Data Ingest Token" --value "$DYNATRACE_DATA_INGEST_TOKEN" --password)
echo "export DYNATRACE_DATA_INGEST_TOKEN=$DYNATRACE_DATA_INGEST_TOKEN" >> .env

helm upgrade dynatrace-operator oci://docker.io/dynatrace/dynatrace-operator \
    --set "installCRD=true" \
    --set "csidriver.enabled=true" \
    --atomic \
    --create-namespace --namespace dynatrace \
    --install

kubectl --namespace dynatrace \
    create secret generic crossplane-observability-demo \
    --from-literal=apiToken=$DYNATRACE_OPERATOR_TOKEN \
    --from-literal=dataIngestToken=$DYNATRACE_DATA_INGEST_TOKEN

yq --inplace ".spec.apiUrl = \"$DYNATRACE_URL/api\"" ./observability/dynatrace/dynakube.yaml
kubectl --namespace dynatrace apply -f ./observability/dynatrace/dynakube.yaml

########
# Misc #
########

chmod +x destroy.sh

echo "## Setup is complete" | gum format
