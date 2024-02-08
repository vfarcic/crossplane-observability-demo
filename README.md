## Intro

FIXME: Test Google Cloud

## Setup

```sh
git clone https://github.com/vfarcic/crossplane-observability-demo

cd crossplane-observability-demo

export HYPERSCALER=[...] # Replace `[...]` with `azure`, `aws`, or `google`
```

FIXME: Nix reference

```sh
nix-shell --run $SHELL shell/$HYPERSCALER.nix

chmod +x setup.sh

./setup.sh

source .env
```

## Crossplane

```sh
cat cluster/$HYPERSCALER.yaml

kubectl --namespace a-team apply \
    --filename cluster/$HYPERSCALER.yaml

crossplane beta trace clusterclaim cluster --namespace a-team

cat db/$HYPERSCALER.yaml

kubectl --namespace a-team apply --filename db/$HYPERSCALER.yaml

crossplane beta trace sqlclaim my-db --namespace a-team
```

## Dynatrace

The Dynatrace operator is installed and configured via the setup script.

FIXME @Kathi: Add (eventually automate) instructions on how to add dashboards

## Destroy

```sh
./destroy.sh
```
