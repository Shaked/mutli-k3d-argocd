#!/bin/bash
source ./.env
if [ -z "$GITHUB_REPO_URL" ]; then
    echo "GITHUB_REPO_URL is not set"
    exit 1
fi

BASE64_GITHUB_REPO_URL=$(echo -n $GITHUB_REPO_URL | base64)

if [ -z "$GITHUB_USERNAME" ]; then
    echo "GITHUB_USERNAME is not set"
    exit 1
fi

BASE64_GITHUB_USERNAME=$(echo -n $GITHUB_USERNAME | base64)

if [ -z "$GITHUB_PAT" ]; then
    echo "GITHUB_PAT is not set"
    exit 1
fi
BASE64_GITHUB_PAT=$(echo -n $GITHUB_PAT | base64)

echo "Installing k3d"
brew install k3d
echo "Creating k3d cluster"
ARGOCD_CLUSTER_CONTEXT_NAME=argocd
K3D_ARGOCD_CLUSTER_CONTEXT_NAME=k3d-$ARGOCD_CLUSTER_CONTEXT_NAME
k3d cluster create $ARGOCD_CLUSTER_CONTEXT_NAME

echo "Installing ArgoCD"
kubectl --context $K3D_ARGOCD_CLUSTER_CONTEXT_NAME create namespace argocd
kubectl --context $K3D_ARGOCD_CLUSTER_CONTEXT_NAME apply \
    -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml

REMOTE_CLUSTER_CONTEXT_NAME=$(./create-cluster.sh $ARGOCD_CLUSTER_CONTEXT_NAME)
./add-to-argo.sh $ARGOCD_CLUSTER_CONTEXT_NAME $REMOTE_CLUSTER_CONTEXT_NAME
kubectl --context $K3D_ARGOCD_CLUSTER_CONTEXT_NAME apply -n argocd -f -<<EOF
apiVersion: v1
data:
  password: $BASE64_GITHUB_PAT
  url: $BASE64_GITHUB_REPO_URL
  username: $BASE64_GITHUB_USERNAME
kind: Secret
metadata:
  annotations:
    managed-by: argocd.argoproj.io
  labels:
    argocd.argoproj.io/secret-type: repo-creds
  name: creds-3663023373
  namespace: argocd
type: Opaque
EOF
kubectl --context $K3D_ARGOCD_CLUSTER_CONTEXT_NAME apply -n argocd -f -<<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
  sources:
    - repoURL: $GITHUB_REPO_URL
      path: "argocd/projects"
      targetRevision: main
    - repoURL: $GITHUB_REPO_URL
      path: "argocd/appsets/infra"
      targetRevision: main
    - repoURL: $GITHUB_REPO_URL
      path: "argocd/appsets/apps"
      targetRevision: main
  destination:
    namespace: argocd
    name: in-cluster
EOF
