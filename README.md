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
├── external-secrets/               # External Secrets Operator
│   ├── namespace.yaml
│   ├── deployment.yaml
│   └── secretstore.yaml            # ClusterSecretStore for AWS
├── charts/
│   └── microservice/               # Generic microservice chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── serviceaccount.yaml
│           ├── hpa.yaml
│           ├── externalsecret.yaml
│           ├── servicemonitor.yaml
│           └── _helpers.tpl
├── environments/
│   └── production/
│       ├── ngo-service.yaml         # NGO service values
│       ├── donation-service.yaml    # Donation service values
│       └── volunteer-service.yaml   # Volunteer service values
├── apps/
│   ├── ngo-service/
│   │   └── argo-application.yaml
│   ├── donation-service/
│   │   └── argo-application.yaml
│   └── volunteer-service/
│       └── argo-application.yaml
├── .github/workflows/
│   ├── validate-gitops-pr.yml
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

The application repository (`hackathon-services`) owns testing, image building, scanning, and ECR publishing. This GitOps repository owns deployment configuration and ArgoCD reconciliation.

1. **Source CI** - A change to a service on `main` starts its services workflow.
2. **Build & Push** - The workflow builds and scans the image, then pushes an immutable full commit SHA tag to ECR.
3. **Create GitOps PR** - The services workflow updates only `environments/production/<service>.yaml` and opens a pull request in this repository.
4. **Show PR Link** - The services workflow finishes after creating the PR and exposes a clickable GitOps PR link in its job summary. It does not wait for or invoke GitOps validation.
5. **Validate GitOps PR** - `validate-gitops-pr.yml` independently validates concrete ECR values and renders every Helm release.
6. **Review and Merge** - GitHub branch protection requires the `validate-gitops` check to pass before `main` can receive the change.
7. **ArgoCD Sync** - After merge, ArgoCD detects the GitOps change and syncs the exact image SHA to EKS.

### Example: NGO service deployment

For a source commit `abc123...` changing `ngo-service`:

```text
hackathon-services/ngo-service change
  -> ci-ngo.yml
  -> ci-python-reusable.yml
  -> build and scan ngo-service:abc123...
  -> push 621996700064.dkr.ecr.us-east-1.amazonaws.com/ngo-service:abc123...
  -> open GitOps PR
```

The PR changes only the image tag in `environments/production/ngo-service.yaml`:

```yaml
image:
  repository: 621996700064.dkr.ecr.us-east-1.amazonaws.com/ngo-service
  tag: abc123...
```

The GitOps PR workflow then runs `validate-gitops`, which checks the full SHA tag and runs `helm lint` and `helm template`. If branch protection is configured correctly, the PR cannot merge until that check passes. Once merged, ArgoCD deploys the image. The services pipeline has already finished; the repositories communicate through the PR and its link, not through a synchronous workflow dependency.

### GitOps branch protection

Configure branch protection for the `main` branch in GitHub repository settings:

- Require a pull request before merging.
- Require status checks to pass before merging.
- Select the exact check: `validate-gitops`.
- Require branches to be up to date before merging.
- Restrict direct pushes to `main` to trusted administrators or automation only.
- Dismiss stale approvals when new commits are pushed, if reviews are required.

The branch protection rule is a GitHub repository setting, not a Kubernetes or ArgoCD setting. The services pipeline creates the PR but does not decide whether it is mergeable. The GitOps repository's own workflow and branch protection make that decision independently.

### Manual Deployment

To manually trigger a deployment:

```bash
# Via GitHub Actions UI
# Navigate to Actions tab → Select workflow → Run workflow

# Via ArgoCD UI
# Navigate to application → Sync button

# Via Helm (direct)
helm upgrade ngo-service ./charts/microservice \
  --namespace solidarytech \
  -f environments/production/ngo-service.yaml
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

Edit HPA configuration in service-specific values files:

```yaml
# environments/production/ngo-service.yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

### Resource Limits

Edit resource limits in service-specific values files:

```yaml
# environments/production/ngo-service.yaml
resources:
  requests:
    cpu: 500m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi
```

### Health Checks

Modify health check probes in service-specific values files:

```yaml
# environments/production/ngo-service.yaml
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

### Adding a New Service

To add a new microservice using the generic chart:

1. Create a new values file in `environments/production/`:
   ```bash
   cp environments/production/ngo-service.yaml environments/production/new-service.yaml
   ```

2. Edit the values file with service-specific configuration:
   ```yaml
   fullnameOverride: "new-service"
   service:
     targetPort: 8084
   image:
     repository: <ecr-url>
   externalSecret:
     secretName: new-service-secrets
     data:
       - secretKey: my-secret
         remoteRef:
           key: solidarytech/production/new-service/my-secret
   ```

3. Create an ArgoCD Application in `apps/new-service/argo-application.yaml`:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: new-service
     namespace: argocd
   spec:
     source:
       path: charts/microservice
       helm:
         valueFiles:
         - ../../environments/production/new-service.yaml
   ```

### Environment-Specific Values

Create new environment values files in `environments/` directory:

```bash
# Example for staging
mkdir environments/staging
cp environments/production/ngo-service.yaml environments/staging/ngo-service.yaml
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
