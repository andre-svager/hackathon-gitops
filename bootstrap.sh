#!/bin/bash
set -e

echo "🚀 Bootstrapping SolidaryTech GitOps Infrastructure"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ aws CLI not found. Please install AWS CLI first.${NC}"
    exit 1
fi

if ! command -v kustomize &> /dev/null; then
    echo -e "${YELLOW}⚠️  kustomize not found. Installing...${NC}"
    go install sigs.k8s.io/kustomize/kustomize/v5@latest
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"

# Configure kubectl for EKS cluster
echo "🔧 Configuring kubectl for EKS cluster..."
CLUSTER_NAME=$(aws ssm get-parameter --name /solidarytech/production/eks/cluster-name --query Parameter.Value --output text)
aws eks update-kubeconfig --name $CLUSTER_NAME --region us-east-1
echo -e "${GREEN}✅ kubectl configured${NC}"

# Create namespaces
echo "🏗️  Creating namespaces..."
kubectl apply -f argocd/namespace.yaml
kubectl apply -f base/namespace.yaml
kubectl apply -f base/external-secret-operator/namespace.yaml
echo -e "${GREEN}✅ Namespaces created${NC}"

# Install External Secrets Operator
echo "🔐 Installing External Secrets Operator..."
kubectl apply -f base/external-secret-operator/deployment.yaml
kubectl apply -f base/external-secret-operator/secretstore.yaml
kubectl apply -f base/external-secret-operator/irsa.yaml
echo -e "${GREEN}✅ External Secrets Operator installed${NC}"

# Wait for External Secrets Operator to be ready
echo "⏳ Waiting for External Secrets Operator to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/external-secrets -n external-secrets
echo -e "${GREEN}✅ External Secrets Operator ready${NC}"

# Install ArgoCD
echo "🎯 Installing ArgoCD..."
kubectl apply -f argocd/install.yaml
echo -e "${GREEN}✅ ArgoCD installation started${NC}"

# Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-application-controller -n argocd
echo -e "${GREEN}✅ ArgoCD ready${NC}"

# Create ArgoCD applications
echo "📦 Creating ArgoCD applications..."
kubectl apply -f apps/ngo-service/argo-application.yaml
kubectl apply -f apps/donation-service/argo-application.yaml
kubectl apply -f apps/volunteer-service/argo-application.yaml
echo -e "${GREEN}✅ ArgoCD applications created${NC}"

# Wait for applications to sync
echo "⏳ Waiting for applications to sync..."
kubectl wait --for=condition=healthy --timeout=600s application/ngo-service -n argocd || true
kubectl wait --for=condition=healthy --timeout=600s application/donation-service -n argocd || true
kubectl wait --for=condition=healthy --timeout=600s application/volunteer-service -n argocd || true
echo -e "${GREEN}✅ Applications synced${NC}"

# Get ArgoCD credentials
echo "🔑 Getting ArgoCD credentials..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
ARGOCD_SERVER=$(kubectl -n argocd get service argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo ""
echo -e "${GREEN}🎉 Bootstrap completed successfully!${NC}"
echo ""
echo "ArgoCD URL: https://$ARGOCD_SERVER"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
echo ""
echo "To access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then open https://localhost:8080"
echo ""
echo "To check application status:"
echo "  kubectl get applications -n argocd"
echo ""
echo "To check pods:"
echo "  kubectl get pods -n solidarytech"
