## Intro

FIXME: Tested only on AWS

## Setup

```sh
git clone https://github.com/vfarcic/crossplane-observability-demo

cd crossplane-observability-demo
```

FIXME: Install `nix` by following the instructions at https://nix.dev/install-nix. Watch https://youtu.be/0ulldVwZiKA if you are not familiar with Nix. Alternatively, you can skip executing `nix-shell` but, in that case, you need the tools used in this demo installed on your host machine.

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

export INGRESS_HOSTNAME=$(kubectl --namespace traefik \
    get service traefik \
    --output jsonpath="{.status.loadBalancer.ingress[0].hostname}")

export INGRESS_IP=$(dig +short $INGRESS_HOSTNAME \
    | awk '{print $1;}' | head -n 1)

echo $INGRESS_IP

# Repeat the `export` commands if the output is empty

unset KUBECONFIG

cat app.yaml

yq --inplace \
    ".spec.parameters.host = \"silly-demo.$INGRESS_IP.nip.io\"" \
    app.yaml

kubectl --namespace a-team apply --filename app.yaml

crossplane beta trace appclaim silly-demo --namespace a-team

export KUBECONFIG=$PWD/kubeconfig.yaml

kubectl --namespace production get all

curl "http://silly-demo.$INGRESS_IP.nip.io"

curl -X POST \
    "http://silly-demo.$INGRESS_IP.nip.io/video?id=1&title=An%20Amazing%20Video"

curl "http://silly-demo.$INGRESS_IP.nip.io/videos" | jq .
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

```sh
./destroy.sh
```
