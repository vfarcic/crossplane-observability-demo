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
|kind CLI        |Yes                  |'https://kind.sigs.k8s.io/docs/user/quick-start/#installation'|
|Google Cloud account with admin permissions|If using Google Cloud|'https://cloud.google.com'|
|Google Cloud CLI|If using Google Cloud|'https://cloud.google.com/sdk/docs/install'        |
|gke-gcloud-auth-plugin|If using Google Cloud|'https://cloud.google.com/blog/products/containers-kubernetes/kubectl-auth-changes-in-gke'|
|AWS account with admin permissions|If using AWS|'https://aws.amazon.com'                  |
|AWS CLI         |If using AWS         |'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html'|

If you are running this script from **Nix shell**, most of the requirements are already set with the exception of **Docker** and the **hyperscaler account**.
" | gum format

gum confirm "
Do you have those tools installed?
" || exit 0

###########
# Cluster #
###########

echo "# Cluster" | gum format

if [[ "$HYPERSCALER" == "google" ]]; then

    gcloud projects delete $PROJECT_ID --quiet

else

    echo "## Deleting resoureces..." | gum format
    kubectl --namespace a-team delete \
        --filename cluster/$HYPERSCALER.yaml

    kubectl --namespace a-team delete \
        --filename db/$HYPERSCALER.yaml

    COUNTER=$(kubectl get managed --no-headers | grep -v object \
        | grep -v release | grep -v database | wc -l)

    while [ $COUNTER -ne 0 ]; do
        echo "$COUNTER resources left to be deleted..."
        sleep 10
        COUNTER=$(kubectl get managed --no-headers | grep -v object \
            | grep -v release | grep -v database| wc -l)
    done

fi

kind delete cluster
