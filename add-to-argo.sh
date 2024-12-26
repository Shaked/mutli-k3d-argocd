#!/bin/bash
ARGOCD_CLUSTER_CONTEXT_NAME=$1
REMOTE_CLUSTER_CONTEXT_NAME=$2
K3D_ARGOCD_CLUSTER_CONTEXT_NAME=k3d-$ARGOCD_CLUSTER_CONTEXT_NAME
K3D_REMOTE_CLUSTER_CONTEXT_NAME=k3d-$REMOTE_CLUSTER_CONTEXT_NAME
REMOTE_SA_NAME=argocd-manager-token
docker network connect $K3D_ARGOCD_CLUSTER_CONTEXT_NAME $K3D_REMOTE_CLUSTER_CONTEXT_NAME-server-0
echo "Merge kubeconfigs"
k3d kubeconfig merge "$ARGOCD_CLUSTER_CONTEXT_NAME" -d -s=false
k3d kubeconfig merge "$REMOTE_CLUSTER_CONTEXT_NAME" -d -s=false
kubectl --context $K3D_REMOTE_CLUSTER_CONTEXT_NAME create serviceaccount $REMOTE_SA_NAME
kubectl --context $K3D_REMOTE_CLUSTER_CONTEXT_NAME create clusterrolebinding $REMOTE_SA_NAME-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=default:$REMOTE_SA_NAME
kubectl --context $K3D_REMOTE_CLUSTER_CONTEXT_NAME apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $REMOTE_SA_NAME
  annotations:
    kubernetes.io/service-account.name: $REMOTE_SA_NAME
type: kubernetes.io/service-account-token
EOF
SA_TOKEN=$(kubectl --context $K3D_REMOTE_CLUSTER_CONTEXT_NAME get secret $REMOTE_SA_NAME -o jsonpath='{.data.token}' | base64 --decode)
echo "Fetch token from remote cluster SA: $REMOTE_SA_NAME"
# REMOTE_CLUSTER_ARGOCD_MANAGER_TOKEN=$(kubectl --context $K3D_REMOTE_CLUSTER_CONTEXT_NAME get secrets -n kube-system |\
#     grep argocd-manager |\
#     awk '{ print $1 }' |\
#     xargs kubectl get secrets -n kube-system -o jsonpath='{ .data.token }'\
# )
echo "Create cluster secret in argocd context: $K3D_ARGOCD_CLUSTER_CONTEXT_NAME"
kubectl --context $K3D_ARGOCD_CLUSTER_CONTEXT_NAME apply -n argocd -f -<<EOF
apiVersion: v1
kind: Secret
metadata:
  namespace: argocd
  name: $K3D_REMOTE_CLUSTER_CONTEXT_NAME
  labels:
    argocd.argoproj.io/secret-type: cluster
    cloud-provider: aws
    cluster-purpose: applicative
    environment: dev
    environment-dev: "true"
    environment-stage: "true"
    product-app1: "true"
type: Opaque
stringData:
  name: $K3D_REMOTE_CLUSTER_CONTEXT_NAME
  server: "https://$K3D_REMOTE_CLUSTER_CONTEXT_NAME-server-0:6443"
  config: |
    {
        "bearerToken": "$SA_TOKEN",
        "tlsClientConfig": {
            "insecure": true
        }
    }
EOF
