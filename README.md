# 🚀 SolidaryTech GitOps Infrastructure

Complete GitOps solution for deploying SolidaryTech microservices to Kubernetes using ArgoCD and Helm.

## 📋 Overview

This repository contains the GitOps configuration for deploying the SolidaryTech platform microservices to AWS EKS. It implements a production-ready GitOps workflow with:

- **ArgoCD** for continuous deployment
- **Helm** for package management and configuration
- **AWS ECR** for container registry
- **AWS Secrets Manager** for secrets management
- **External Secrets Operator** for Kubernetes secrets synchronization
- **Prometheus ServiceMonitors** for observability
- **Horizontal Pod Autoscaling** for automatic scaling

## 🏗️ Architecture

```
┌─────────────────┐
│   GitHub Repo   │
│  (stage5 code)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ GitHub Actions  │
│  (CI Pipeline)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   AWS ECR       │
│  (Docker Images)│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ GitOps Repo     │
│  (this repo)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   ArgoCD        │
│  (CD Pipeline)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   AWS EKS       │
│  (Kubernetes)   │
└─────────────────┘
```

## 📁 Repository Structure

```
hackathon-gitops/
├── argocd/
│   ├── namespace.yaml              # ArgoCD namespace
│   └── install.yaml                # ArgoCD installation
├── base/
│   ├── namespace.yaml              # Application namespace
│   └── external-secret-operator/   # External Secrets Operator
│       ├── namespace.yaml
│       ├── deployment.yaml
│       ├── secretstore.yaml
│       └── irsa.yaml
├── charts/
│   ├── ngo-service/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── serviceaccount.yaml
│   │       ├── hpa.yaml
│   │       ├── externalsecret.yaml
│   │       ├── servicemonitor.yaml
│   │       └── _helpers.tpl
│   ├── donation-service/
│   │   └── (same structure as ngo-service)
│   └── volunteer-service/
│       └── (same structure as ngo-service)
├── environments/
│   └── production/
│       ├── ngo-service-values.yaml
│       ├── donation-service-values.yaml
│       └── volunteer-service-values.yaml
├── apps/
│   ├── ngo-service/
│   │   └── argo-application.yaml
│   ├── donation-service/
│   │   └── argo-application.yaml
│   └── volunteer-service/
│       └── argo-application.yaml
├── .github/workflows/
│   ├── deploy-ngo-service.yml
│   ├── deploy-donation-service.yml
│   └── deploy-volunteer-service.yml
├── bootstrap.sh
└── README.md
```

## 🔧 Prerequisites

### Required Tools

- **kubectl** - Kubernetes command-line tool
- **aws CLI** - AWS command-line interface
- **helm** - Kubernetes package manager
- **docker** - Container runtime (for local testing)

### AWS Resources

Ensure the following resources are provisioned via the `hackathon-iac` repository:

- EKS cluster
- ECR repositories (ngo-service, donation-service, volunteer-service)
- RDS instances (ngo_db, donation_db)
- SQS queue (solidary-donations)
- DynamoDB table (SolidaryTechVolunteers)
- SSM Parameters with infrastructure outputs

### Required Secrets

Configure these secrets in your GitHub repository settings:

- `AWS_ROLE_ARN` - IAM role for GitHub Actions (created by hackathon-iac Terraform)
  - After running `terraform apply` in hackathon-iac, the role ARN will be available as an output
  - Expected value: `arn:aws:iam::621996700064:role/github-actions-hackathon-gitops`
  - Retrieve with: `terraform output -raw github_actions_role_arn` from hackathon-iac directory
  
- `GITOPS_REPO_TOKEN` - Personal access token for GitOps repo access

### AWS Secrets Manager

Create the following secrets in AWS Secrets Manager:

```
solidarytech/production/ngo-service/database-url
solidarytech/production/donation-service/database-url
solidarytech/production/aws/access-key-id
solidarytech/production/aws/secret-access-key
```

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/hackathon-gitops.git
cd hackathon-gitops
```

### 2. Configure AWS Credentials

```bash
aws configure
```

### 3. Run Bootstrap Script

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap script will:
- Configure kubectl for your EKS cluster
- Create necessary namespaces
- Install External Secrets Operator
- Install ArgoCD
- Create ArgoCD applications
- Sync applications to the cluster

### 4. Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080 in your browser.

**Default credentials:**
- Username: `admin`
- Password: Retrieved by bootstrap script or via:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  ```

## 🔄 CI/CD Pipeline

### Workflow

1. **Code Push** - Developer pushes code to `stage5` repository
2. **GitHub Actions** - CI pipeline triggers on push to main branch
3. **Build & Push** - Docker image is built and pushed to ECR with git SHA tag
4. **Update GitOps** - Helm values file is automatically updated with new image tag
5. **ArgoCD Sync** - ArgoCD detects the change and syncs Helm release
6. **Rolling Update** - Kubernetes performs rolling update of pods

### Manual Deployment

To manually trigger a deployment:

```bash
# Via GitHub Actions UI
# Navigate to Actions tab → Select workflow → Run workflow

# Via ArgoCD UI
# Navigate to application → Sync button

# Via Helm (direct)
helm upgrade ngo-service ./charts/ngo-service \
  --namespace solidarytech \
  -f environments/production/ngo-service-values.yaml
```

## 📊 Monitoring

### ArgoCD Dashboard

Monitor deployment status and application health via the ArgoCD UI.

### Kubernetes Resources

```bash
# Check application status
kubectl get applications -n argocd

# Check pods
kubectl get pods -n solidarytech

# Check services
kubectl get svc -n solidarytech

# Check HPA status
kubectl get hpa -n solidarytech

# Check External Secrets
kubectl get externalsecrets -n solidarytech
```

### Prometheus Metrics

ServiceMonitors are configured for each service. Ensure Prometheus is installed in your cluster to collect metrics.

```bash
# Check ServiceMonitors
kubectl get servicemonitors -n solidarytech
```

## 🔐 Secrets Management

### External Secrets Operator

The External Secrets Operator synchronizes secrets from AWS Secrets Manager to Kubernetes secrets.

**Secret Mapping:**

| Kubernetes Secret | AWS Secrets Manager Secret |
|-------------------|---------------------------|
| ngo-service-secrets | solidarytech/production/ngo-service/database-url |
| donation-service-secrets | solidarytech/production/donation-service/database-url, sqs-url, aws credentials |
| volunteer-service-secrets | solidarytech/production/aws/access-key-id, aws-secret-access-key |

### Manual Secret Refresh

To manually refresh secrets:

```bash
kubectl annotate externalsecret ngo-service-secrets -n solidarytech force-sync=$(date +%s)
```

## 🛠️ Troubleshooting

### ArgoCD Application Not Syncing

```bash
# Check application status
kubectl get application ngo-service -n argocd -o yaml

# Force sync
kubectl patch application ngo-service -n argocd --type merge -p '{"spec":{"sync":{"manual":true}}}'

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller
```

### External Secrets Not Syncing

```bash
# Check ExternalSecret status
kubectl get externalsecret ngo-service-secrets -n solidarytech -o yaml

# Check External Secrets Operator logs
kubectl logs -n external-secrets deployment/external-secrets

# Verify SecretStore configuration
kubectl get secretstore aws-secrets-manager -n solidarytech -o yaml
```

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n solidarytech

# Check pod logs
kubectl logs <pod-name> -n solidarytech

# Check events
kubectl get events -n solidarytech --sort-by='.lastTimestamp'
```

### Image Pull Errors

```bash
# Verify ECR credentials are configured
kubectl get secret -n solidarytech

# Check if image exists in ECR
aws ecr describe-images --repository-name ngo-service
```

## 🔧 Configuration

### Scaling Configuration

Edit HPA configuration in Helm values files:

```yaml
# environments/production/ngo-service-values.yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

### Resource Limits

Edit resource limits in Helm values files:

```yaml
# charts/ngo-service/values.yaml
resources:
  requests:
    cpu: 500m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi
```

### Health Checks

Modify health check probes in Helm values files:

```yaml
# charts/ngo-service/values.yaml
healthCheck:
  path: /health
  port: 8081
  livenessProbe:
    initialDelaySeconds: 30
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3
  readinessProbe:
    initialDelaySeconds: 10
    periodSeconds: 5
    timeoutSeconds: 3
    failureThreshold: 3
```

### Environment-Specific Values

Create new environment values files in `environments/` directory:

```bash
# Example for staging
cp environments/production/ngo-service-values.yaml environments/staging/ngo-service-values.yaml
# Edit the values for staging environment
```

## 📝 Best Practices

1. **Always test changes in a non-production environment first**
2. **Use semantic versioning for image tags when possible**
3. **Monitor ArgoCD sync status after deployments**
4. **Keep secrets out of the GitOps repository**
5. **Regularly review and update resource limits**
6. **Use ArgoCD's sync waves for ordered deployments**
7. **Implement proper rollback procedures**
8. **Monitor HPA scaling events**

## 🔗 Related Repositories

- **hackathon-iac** - Infrastructure provisioning with Terraform
- **stage5** - Application source code

## 📚 Additional Resources

- [ArgoCD Documentation](https://argoproj.github.io/argo-cd/)
- [Helm Documentation](https://helm.sh/docs/)
- [External Secrets Operator](https://external-secrets.io/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📄 License

This project is part of the SolidaryTech Hackathon.

## 🆘 Support

For issues and questions, please open an issue in the repository.
