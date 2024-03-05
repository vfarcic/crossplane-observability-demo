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

#################
# Control Plane #
#################

echo "# Control Plane" | gum format

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

helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install \
    external-secrets external-secrets/external-secrets \
    --namespace external-secrets --create-namespace --wait

# FIXME: This is using the AWS credentials that are saved on the device, not the ones you pass to the script
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

# Kubernetes Operator
gum confirm "
We are going to install the Dynatrace Kubernetes operator first. Please generate the needed tokens first:

- Navigate to the Dynatrace $(gum style --foreground 212 'Kubernetes') app (Ctrl + K and type Kubernetes)
- Select $(gum style --foreground 212 'Add cluster') in the top right
- Scroll down to $(gum style --foreground 212 'generate the suggested tokens')

Ready?
" || exit 0

DYNATRACE_URL=$(gum input --placeholder "Dynatrace URL (e.g., https://ENVIRONMENTID.sprint.dynatracelabs.com)" --value "$DYNATRACE_URL")
echo "export DYNATRACE_URL=$DYNATRACE_URL" >> .env

DYNATRACE_OPERATOR_TOKEN=$(gum input --placeholder "Dynatrace Operator Token" --value "$DYNATRACE_OPERATOR_TOKEN" --password)
echo "export DYNATRACE_OPERATOR_TOKEN=$DYNATRACE_OPERATOR_TOKEN" >> .env

DYNATRACE_DATA_INGEST_TOKEN=$(gum input --placeholder "Dynatrace Data Ingest Token" --value "$DYNATRACE_DATA_INGEST_TOKEN" --password)
echo "export DYNATRACE_DATA_INGEST_TOKEN=$DYNATRACE_DATA_INGEST_TOKEN" >> .env

helm repo add dynatrace-operator-stable https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
helm upgrade --install dynatrace-operator dynatrace-operator-stable/dynatrace-operator \
    --version 0.15.0 \
    --namespace dynatrace --create-namespace \
    --set installCRD=true --set csidriver.enabled=true \
    --atomic --wait

# FIXME: Switch to `external-secrets`
kubectl --namespace dynatrace \
    create secret generic crossplane-observability-demo \
    --from-literal=apiToken=$DYNATRACE_OPERATOR_TOKEN \
    --from-literal=dataIngestToken=$DYNATRACE_DATA_INGEST_TOKEN

yq --inplace ".spec.apiUrl = \"$DYNATRACE_URL/api\"" \
    ./observability/dynatrace/dynakube.yaml

kubectl --namespace dynatrace apply \
    --filename observability/dynatrace/dynakube.yaml

yq --inplace \
    ".spec.parameters.apps.dynatrace.apiUrl = \"$DYNATRACE_URL/api\"" \
    cluster/aws.yaml

# AWS Monitoring
# FIXME: This can be automated via the config api
gum confirm "
Next, we are going to configure AWS monitoring. This means, we are going to deploy two IAM roles, an IAM policy and an EC2 instance.
Please generate a token first:

- Navigate to the Dynatrace $(gum style --foreground 212 'AWS Classic') app (Ctrl + K and type AWS)
- Select $(gum style --foreground 212 'Enable AWS monitoring')
- Select $(gum style --foreground 212 'Connect new instance')
- Enter the following data:
  - Connection Name: Whatever you prefer, this is the display name of the AWS connection (e.g. name of the AWS account)
  - Authentication method: $(gum style --foreground 212 'Role-based authentication')
  - IAM role that Dynatrace should use to get monitoring data: $(gum style --foreground 212 'dynatrace-monitoring')
  - Your Amazon account ID: $(gum style --foreground 212 "$AWS_ACCOUNT_ID")
  - Resources to be monitored: $(gum style --foreground 212 'Monitor all resources')
- Copy the token (don't click 'Connect' yet - this will be the next step)

Ready?
" || exit 0

DYNATRACE_AWS_TOKEN=$(gum input --placeholder "Token" --value "$DYNATRACE_AWS_TOKEN" --password)
echo "export DYNATRACE_AWS_TOKEN=$DYNATRACE_AWS_TOKEN" >> .env

cp ./observability/dynatrace/aws/userData.txt ./observability/dynatrace/aws/userData.local.txt
sed -i -e "s/{{ TOKEN }}/$DYNATRACE_AWS_TOKEN/g" ./observability/dynatrace/aws/userData.local.txt

AWS_USER_DATA=$(cat ./observability/dynatrace/aws/userData.local.txt | base64)

cp observability/dynatrace/aws/ec2.yaml observability/dynatrace/aws/ec2.local.yaml
yq -i e "(.spec.forProvider | select(has(\"userData\")).userData) = \"$AWS_USER_DATA\"" observability/dynatrace/aws/ec2.local.yaml

kubectl apply -f ./observability/dynatrace/aws/policy.yaml
kubectl apply -f ./observability/dynatrace/aws/roles.yaml
kubectl apply -f ./observability/dynatrace/aws/ec2.local.yaml

rm ./observability/dynatrace/aws/userData.local.txt
rm ./observability/dynatrace/aws/ec2.local.yaml

gum confirm "
Now click $(gum style --foreground 212 'Connect') in the Dynatrace UI.

Done?
" || exit 0

# Crossplane Dashboard
# FIXME: is there an API for creating oauth clients?
gum confirm "
Last, we need to configure an OAuth client to automatically create Dynatrace Dashboards:

- Click on your use icon in the bottom left and select $(gum style --foreground 212 'Account Management')
- Select the account of your tenant
- Click on $(gum style --foreground 212 'Identity & access management') -> $(gum style --foreground 212 'OAuth clients')
- Create a new OAuth client and select all $(gum style --foreground 212 'Document Service scopes')
- Copy the generated credentials

Ready?
" || exit 0

DYNATRACE_OAUTH_CLIENT_ID=$(gum input --placeholder "Client ID" --value "$DYNATRACE_OAUTH_CLIENT_ID" --password)
echo "export DYNATRACE_OAUTH_CLIENT_ID=$DYNATRACE_OAUTH_CLIENT_ID" >> .env
DYNATRACE_OAUTH_CLIENT_SECRET=$(gum input --placeholder "Client Secret" --value "$DYNATRACE_OAUTH_CLIENT_SECRET" --password)
echo "export DYNATRACE_OAUTH_CLIENT_SECRET=$DYNATRACE_OAUTH_CLIENT_SECRET" >> .env

# FIXME: Use external secrets
kubectl --namespace dynatrace \
    create secret generic oauth-credentials \
    --from-literal=clientId=$DYNATRACE_OAUTH_CLIENT_ID \
    --from-literal=clientSecret=$DYNATRACE_OAUTH_CLIENT_SECRET

kubectl apply -f ./observability/dynatrace/crossplane-dashboard

set +e
aws secretsmanager delete-secret --secret-id dynatrace-tokens \
    --region us-east-1 --force-delete-without-recovery \
    --no-cli-page
sleep 10
set -e

aws secretsmanager create-secret \
    --name dynatrace-tokens --region us-east-1 \
    --secret-string "{\"apiToken\": \"$DYNATRACE_OPERATOR_TOKEN\", \"dataIngestToken\": \"$DYNATRACE_DATA_INGEST_TOKEN\", \"oauthClientId\": \"$DYNATRACE_OAUTH_CLIENT_ID\", \"oauthClientSecret\": \"$DYNATRACE_OAUTH_CLIENT_SECRET\"}"

########
# Misc #
########

chmod +x destroy.sh

echo "## Setup is complete" | gum format
