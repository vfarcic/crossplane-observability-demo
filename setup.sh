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
|AWS account with admin permissions|Yes|'https://aws.amazon.com'                           |
|AWS CLI         |Yes                  |'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html'|

If you are running this script from **Nix shell**, most of the requirements are already set with the exception of **Docker** and the **AWS account**.
" | gum format

gum confirm "
Do you have those tools installed?
" || exit 0

rm -f .env

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

kubectl apply --filename crossplane-packages/dot-kubernetes.yaml

kubectl apply --filename crossplane-packages/dot-sql.yaml

kubectl apply --filename crossplane-packages/helm-incluster.yaml

kubectl apply \
    --filename crossplane-packages/kubernetes-incluster.yaml

echo "## Waiting for Crossplane packages to be ready (<=30 min.)..." \
    | gum format

sleep 60

kubectl wait --for=condition=healthy provider.pkg.crossplane.io \
    --all --timeout=1800s

kubectl apply \
    --filename crossplane-packages/aws-config.yaml

##################
# Atlas Operator #
##################

echo "# Atlas Operator" | gum format

helm upgrade --install atlas-operator \
    oci://ghcr.io/ariga/charts/atlas-operator \
    --namespace atlas-operator --create-namespace --wait

####################
# External Secrets #
####################

echo "# External Secrets" | gum format

helm upgrade --install \
    external-secrets external-secrets/external-secrets \
    --namespace external-secrets --create-namespace --wait

echo '## We are about to create a Secret in AWS Secret Manager. The command that follows will display output and you should press `q` to continue.' \
    | gum format
gum input --placeholder "Press the enter key to continue."
set +e
aws secretsmanager create-secret \
    --name db-password --region us-east-1 \
    --secret-string "{\"password\": \"IWillNeverTell\" }"
set -e

kubectl apply --filename external-secrets/aws.yaml

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

set +e
aws secretsmanager delete-secret --secret-id dynatrace-tokens \
    --region us-east-1 --force-delete-without-recovery \
    --no-cli-page
set -e

aws secretsmanager create-secret \
    --name dynatrace-tokens --region us-east-1 \
    --secret-string "{\"apiToken\": \"$DYNATRACE_OPERATOR_TOKEN\", \"dataIngestToken\": \"$DYNATRACE_DATA_INGEST_TOKEN\"}"

helm upgrade --install \
    dynatrace-operator oci://docker.io/dynatrace/dynatrace-operator \
    --set installCRD=true --set csidriver.enabled=true \
    --atomic --create-namespace --namespace dynatrace --wait

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
