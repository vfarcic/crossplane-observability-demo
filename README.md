## Intro

FIXME: Add Ingress to the cluster

FIXME: Tested only on AWS

## Setup

```sh
git clone https://github.com/vfarcic/crossplane-observability-demo

cd crossplane-observability-demo
```

FIXME: Nix reference

```sh
nix-shell --run $SHELL

chmod +x setup.sh

./setup.sh

source .env
```

## Cluster

```sh
cat cluster/aws.yaml

kubectl --namespace a-team apply --filename cluster/aws.yaml

crossplane beta trace clusterclaim cluster --namespace a-team
```

## Database

FIXME: DB reference

```sh
cat db/aws.yaml

kubectl --namespace a-team apply --filename db/aws.yaml

crossplane beta trace sqlclaim my-db --namespace a-team
```

## App

```sh
export KUBECONFIG=$PWD/kubeconfig.yaml

aws eks update-kubeconfig --region us-east-1 \
    --name a-team-cluster --kubeconfig $KUBECONFIG

cat app/*.yaml

export INGRESS_HOSTNAME=$(kubectl --namespace traefik \
    get service traefik \
    --output jsonpath="{.status.loadBalancer.ingress[0].hostname}")

export INGRESS_IP=$(dig +short $INGRESS_HOSTNAME \
    | awk '{print $1;}' | head -n 1)

yq --inplace \
    ".spec.rules[0].host = \"sillydemo.$INGRESS_IP.nip.io\"" \
    app/ingress.yaml

kubectl --namespace production apply --filename app/

curl "http://sillydemo.$INGRESS_IP.nip.io"

curl -X POST \
    "http://sillydemo.$INGRESS_IP.nip.io/video?id=1&title=An%20Amazing%20Video"

curl "http://sillydemo.$INGRESS_IP.nip.io/videos" | jq .
```

* Generate load on https://app.ddosify.com
* Stop the DB instance from the AWS console

## Dynatrace

All Dynatrace components are installed and configured via the setup script. The following components will be enabled
during setup:

- [Dynatrace Kubernetes Operator](https://github.com/Dynatrace/dynatrace-operator) to monitor the local Kubernetes
  cluster
- [Dynatrace Active Gate on AWS]() to monitor the given AWS account
- A Crossplane for Platform Engineers dashboard will be created

```sh
curl "http://sillydemo.$INGRESS_IP.nip.io/videos"
```

## Destroy

FIXME: Delete traefik

```sh
./destroy.sh
```
