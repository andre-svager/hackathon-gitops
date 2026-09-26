#!/bin/bash
set -e

echo "🚀 Bootstrapping SolidaryTech GitOps Infrastructure"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
AWS_REGION="${AWS_REGION:-us-east-1}"
GITOPS_REPO_URL="${GITOPS_REPO_URL:-https://github.com/andre-svager/hackathon-gitops.git}"
DRY_RUN="${DRY_RUN:-false}"

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

# Validate GitOps repository URL
echo "🔍 Validating GitOps repository URL..."
if ! curl -s -o /dev/null -w "%{http_code}" --head "$GITOPS_REPO_URL" | grep -q "200\|301\|302"; then
    echo -e "${RED}❌ GitOps repository URL is not accessible: ${GITOPS_REPO_URL}${NC}"
    echo "Please verify the repository URL and try again."
    exit 1
fi
echo -e "${GREEN}✅ GitOps repository URL is accessible${NC}"

# Configure kubectl for EKS cluster
echo "🔧 Configuring kubectl for EKS cluster..."
CLUSTER_NAME=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name /solidarytech/production/eks/cluster-name \
    --query Parameter.Value \
    --output text)
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
echo -e "${GREEN}✅ kubectl configured${NC}"

# Fail before changing the cluster if required AWS-managed values are missing.
echo "🔎 Checking required AWS secrets and parameters..."
REQUIRED_SECRETS=(
    solidarytech/production/ngo-service/database-url
    solidarytech/production/donation-service/database-url
    solidarytech/production/aws/access-key-id
    solidarytech/production/aws/secret-access-key
)
for secret_id in "${REQUIRED_SECRETS[@]}"; do
    if ! aws secretsmanager describe-secret \
        --region "$AWS_REGION" \
        --secret-id "$secret_id" >/dev/null 2>&1; then
        echo -e "${RED}❌ Missing Secrets Manager secret in ${AWS_REGION}: ${secret_id}${NC}"
        exit 1
    fi
done
if ! aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name /solidarytech/production/sqs/queue-url \
    --query Parameter.Value \
    --output text >/dev/null; then
    echo -e "${RED}❌ Missing SSM parameter in ${AWS_REGION}: /solidarytech/production/sqs/queue-url${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Required AWS secrets and parameters found${NC}"

# Create namespaces
echo "🏗️  Creating namespaces..."
kubectl apply -f argocd/namespace.yaml
kubectl create namespace solidarytech --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Namespaces created${NC}"

# Create Kubernetes Secrets from AWS-managed values
echo "🔐 Creating Kubernetes Secrets..."
NGO_DATABASE_URL=$(aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id solidarytech/production/ngo-service/database-url \
    --query SecretString \
    --output text)
DONATION_DATABASE_URL=$(aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id solidarytech/production/donation-service/database-url \
    --query SecretString \
    --output text)
AWS_ACCESS_KEY_ID=$(aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id solidarytech/production/aws/access-key-id \
    --query SecretString \
    --output text)
AWS_SECRET_ACCESS_KEY=$(aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id solidarytech/production/aws/secret-access-key \
    --query SecretString \
    --output text)
SQS_URL=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name /solidarytech/production/sqs/queue-url \
    --query Parameter.Value \
    --output text)

kubectl create secret generic ngo-service-secrets \
    --namespace solidarytech \
    --from-literal=database-url="$NGO_DATABASE_URL" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic donation-service-secrets \
    --namespace solidarytech \
    --from-literal=database-url="$DONATION_DATABASE_URL" \
    --from-literal=sqs-url="$SQS_URL" \
    --from-literal=aws-access-key-id="$AWS_ACCESS_KEY_ID" \
    --from-literal=aws-secret-access-key="$AWS_SECRET_ACCESS_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic volunteer-service-secrets \
    --namespace solidarytech \
    --from-literal=aws-access-key-id="$AWS_ACCESS_KEY_ID" \
    --from-literal=aws-secret-access-key="$AWS_SECRET_ACCESS_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Kubernetes Secrets created${NC}"

# Install ArgoCD
echo "🎯 Installing ArgoCD..."
MAX_RETRIES=3
for i in $(seq 1 $MAX_RETRIES); do
    if kubectl apply --server-side --force-conflicts -n argocd \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml; then
        break
    fi
    echo -e "${YELLOW}⚠️  Attempt $i/$MAX_RETRIES failed, retrying in 5s...${NC}"
    sleep 5
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo -e "${RED}❌ Failed to install ArgoCD after ${MAX_RETRIES} attempts${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✅ ArgoCD installation started${NC}"

# Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
kubectl rollout status --timeout=600s statefulset/argocd-application-controller -n argocd
echo -e "${GREEN}✅ ArgoCD ready${NC}"

# Create ArgoCD applications
echo "📦 Creating ArgoCD applications..."
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}⚠️  DRY RUN MODE: Skipping ArgoCD application creation${NC}"
    echo "Would apply:"
    echo "  - apps/ngo-service/argo-application.yaml"
    echo "  - apps/donation-service/argo-application.yaml"
    echo "  - apps/volunteer-service/argo-application.yaml"
else
    # Update repoURL in Application manifests
    sed -i "s|repoURL:.*|repoURL: ${GITOPS_REPO_URL}|g" apps/ngo-service/argo-application.yaml
    sed -i "s|repoURL:.*|repoURL: ${GITOPS_REPO_URL}|g" apps/donation-service/argo-application.yaml
    sed -i "s|repoURL:.*|repoURL: ${GITOPS_REPO_URL}|g" apps/volunteer-service/argo-application.yaml
    sed -i "s|repoURL:.*|repoURL: ${GITOPS_REPO_URL}|g" apps/ngo-service/argo-application.yaml
    sed -i 's|repoURL: https://github.com/andre-svager/hackathon-gitops.git|repoURL: https://prometheus-community.github.io/helm-charts|' apps/observability/prometheus-application.yaml
    sed -i 's|repoURL: https://github.com/andre-svager/hackathon-gitops.git|repoURL: https://grafana.github.io/helm-charts|' apps/observability/loki-application.yaml
    sed -i 's|repoURL: https://github.com/andre-svager/hackathon-gitops.git|repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts|' apps/observability/otel-collector-application.yaml
    
    if kubectl apply -f apps/ngo-service/argo-application.yaml; then
        echo -e "${GREEN}✅ ngo-service application created${NC}"
    else
        echo -e "${RED}❌ Failed to create ngo-service application${NC}"
        exit 1
    fi
    
    if kubectl apply -f apps/donation-service/argo-application.yaml; then
        echo -e "${GREEN}✅ donation-service application created${NC}"
    else
        echo -e "${RED}❌ Failed to create donation-service application${NC}"
        exit 1
    fi
    
    if kubectl apply -f apps/volunteer-service/argo-application.yaml; then
        echo -e "${GREEN}✅ volunteer-service application created${NC}"
    else
        echo -e "${RED}❌ Failed to create volunteer-service application${NC}"
        exit 1
    fi
    
    # --- Observability stack (Prometheus, Grafana, Loki, OTel Collector) ---
    echo "📊 Checking pod headroom before installing observability stack..."
    ALLOCATABLE=$(kubectl get nodes -o=jsonpath='{.items[*].status.allocatable.pods}' | tr ' ' '\n' | awk '{s+=$1} END {print s}')
    RUNNING=$(kubectl get pods -A --no-headers | wc -l)
    HEADROOM=$((ALLOCATABLE - RUNNING))
    if [ "$HEADROOM" -lt 12 ]; then
        echo -e "${YELLOW}⚠️  Only ${HEADROOM} pod slots free (${RUNNING}/${ALLOCATABLE} used) - observability stack needs ~12${NC}"
    else
        echo -e "${GREEN}✅ ${HEADROOM} pod slots free${NC}"
    fi

    if kubectl apply -f apps/observability/prometheus-application.yaml && \
       kubectl apply -f apps/observability/loki-application.yaml && \
       kubectl apply -f apps/observability/otel-collector-application.yaml; then
        echo -e "${GREEN}✅ Observability applications created${NC}"
    else
        echo -e "${RED}❌ Failed to create one or more observability applications${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✅ ArgoCD applications created${NC}"

# Wait for applications to sync
if [ "$DRY_RUN" = "false" ]; then
    echo "⏳ Waiting for applications to sync..."
    kubectl wait --for=condition=healthy --timeout=600s application/ngo-service -n argocd || true
    kubectl wait --for=condition=healthy --timeout=600s application/donation-service -n argocd || true
    kubectl wait --for=condition=healthy --timeout=600s application/volunteer-service -n argocd || true
    echo -e "${GREEN}✅ Applications synced${NC}"
    
    # Verify applications were created successfully
    echo "🔍 Verifying applications..."
    APP_COUNT=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
    if [ "$APP_COUNT" -ge 3 ]; then
        echo -e "${GREEN}✅ All applications created successfully${NC}"
        kubectl get applications -n argocd
    else
        echo -e "${YELLOW}⚠️  Only ${APP_COUNT} applications created (expected 3)${NC}"
    fi
fi

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
