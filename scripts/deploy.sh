#!/usr/bin/env bash
# Creates a kind cluster (if needed), builds the image, loads it, and applies the manifests.
set -euo pipefail
cd "$(dirname "$0")/.."
CLUSTER=${CLUSTER:-module6}

kind get clusters | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --image kindest/node:v1.35.0
docker build -t inventory-app:1.0 app/
kind load docker-image inventory-app:1.0 --name "$CLUSTER"
kubectl apply -f k8s/inventory-deployment.yaml -f k8s/inventory-service.yaml
kubectl rollout status deployment/inventory --timeout=120s
# Start the client only once the Service has ready endpoints.
kubectl apply -f k8s/client-deployment.yaml
kubectl rollout status deployment/inventory-client --timeout=120s
kubectl get pods,svc -o wide
