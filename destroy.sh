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
|AWS account with admin permissions|Yes|'https://aws.amazon.com'                           |
|AWS CLI         |Yes                  |'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html'|

If you are running this script from **Nix shell**, most of the requirements are already set with the exception of **Docker** and the **hyperscaler account**.
" | gum format

gum confirm "
Do you have those tools installed?
" || exit 0

###########
# Cluster #
###########

echo "# Cluster" | gum format

unset KUBECONFIG

echo "## Deleting resoureces..." | gum format

kubectl --namespace a-team delete --filename cluster/aws.yaml

kubectl --namespace a-team delete --filename db/aws.yaml

COUNTER=$(kubectl get managed --no-headers | grep -v object \
    | grep -v release | grep -v database | wc -l)

while [ $COUNTER -ne 0 ]; do
    echo "$COUNTER resources left to be deleted..."
    sleep 10
    COUNTER=$(kubectl get managed --no-headers | grep -v object \
        | grep -v release | grep -v database| wc -l)
done

kind delete cluster --name crossplane-observability-demo
