# Dynatrace Operator

FIXME: Remove this directory

This directory contains all information on how I installed the Dynatrace operator in my test cluster. I think everything
should work with the recent composition changes but still I'll leave them here until we have it verified. 

Here are all commands:

```sh
kind create cluster --name crossplane-dynatrace-test
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
helm upgrade --install crossplane crossplane-stable/crossplane \
   --namespace crossplane-system --create-namespace \
   --values ./crossplane-config/values.yaml \
   --wait

kubectl apply --filename crossplane-packages/helm-incluster.yaml
kubectl apply --filename crossplane-packages/kubernetes-incluster.yaml
kubectl apply -f observability/dynatrace/operator/configs.yaml
 
kubectl create ns dynatrace
kubectl --namespace dynatrace \
    create secret generic crossplane-dynatrace-test \
    --from-literal=apiToken=xxx \
    --from-literal=dataIngestToken=xxx
kubectl apply -n dynatrace -f observability/dynatrace/operator/operator-crossplane.yaml
```