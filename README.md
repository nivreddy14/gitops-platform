# GitOps Platform - Multi-User Event-Driven Architecture

A complete GitOps-managed platform for event-driven architecture on Kubernetes using ArgoCD, featuring Kafka, RabbitMQ, Camel K, and Backstage.

## 🏗️ Architecture

- **ArgoCD**: GitOps continuous delivery
- **Strimzi Kafka**: Event streaming platform  
- **RabbitMQ**: Message broker with clustering
- **Camel K**: Lightweight integration framework
- **Backstage**: Developer portal and service catalog
- **Multi-tenancy**: Isolated namespaces per user

## 📋 Prerequisites

- Kind cluster running locally
- ArgoCD already deployed and accessible
- kubectl configured for your Kind cluster
- Git repository (for ArgoCD to sync from)

## 🚀 Quick Start

### 1. Clone and Push to Your Git Repository

```bash
# Initialize git if not already done
git init
git add .
git commit -m "Initial platform setup"
git remote add origin <your-git-repo-url>
git push -u origin main
```

### 2. Bootstrap the Platform

```bash
# Apply the App-of-Apps pattern to ArgoCD
kubectl apply -f argocd/applications/app-of-apps.yaml

# Wait for operators to be ready (3-5 minutes)
kubectl get pods -n operators -w

# Check all applications are synced
kubectl get applications -n argocd
```

### 3. Verify Deployments

```bash
# Check operators
kubectl get pods -n operators

# Check Kafka
kubectl get kafka -n kafka
kubectl get pods -n kafka

# Check RabbitMQ
kubectl get rabbitmqclusters -n rabbitmq
kubectl get pods -n rabbitmq

# Check Camel K
kubectl get integrationplatforms -n camelk

# Check Backstage
kubectl get pods -n backstage
```

### 4. Create User Namespaces

```bash
# Make script executable
chmod +x scripts/create-user.sh

# Create user namespaces
./scripts/create-user.sh user1
./scripts/create-user.sh user2
./scripts/create-user.sh user3
```

### 5. Access Services

```bash
# Kafka Bootstrap
kubectl port-forward -n kafka svc/event-cluster-kafka-bootstrap 9092:9092

# RabbitMQ Management UI
kubectl port-forward -n rabbitmq svc/rabbitmq-cluster 15672:15672
# Access: http://localhost:15672 (guest/guest)

# Backstage
kubectl port-forward -n backstage svc/backstage 7007:7007
# Access: http://localhost:7007
```

## 📁 Repository Structure

```
gitops-platform/
├── argocd/
│   ├── applications/       # ArgoCD Applications
│   │   ├── app-of-apps.yaml
│   │   ├── operators.yaml
│   │   ├── kafka.yaml
│   │   ├── rabbitmq.yaml
│   │   ├── camelk.yaml
│   │   └── backstage.yaml
│   └── kustomization.yaml
├── base/
│   ├── operators/          # All operators
│   ├── kafka/              # Kafka cluster
│   ├── rabbitmq/           # RabbitMQ cluster
│   ├── camelk/             # Camel K platform
│   ├── backstage/          # Backstage + PostgreSQL
│   └── user-namespace/     # User template
├── overlays/
│   ├── local/              # Local Kind optimizations
│   └── users/              # Per-user namespaces
├── scripts/                # Automation scripts
└── examples/               # Sample integrations
```

## 👥 Multi-User Setup

Each user gets:
- Dedicated namespace (`user-<n>`)
- ResourceQuota (CPU/Memory limits)
- NetworkPolicy (isolated traffic)
- ServiceAccount with RBAC
- Access to shared Kafka & RabbitMQ

## 📝 Example: Deploy Camel K Integration

```bash
# Apply example integration as user1
kubectl apply -f examples/camelk-integrations.yaml -n user1

# Check status
kubectl get integrations -n user1
kubectl logs -n user1 -l camel.apache.org/integration=kafka-consumer -f
```

## 🔍 Monitoring

```bash
# ArgoCD applications
kubectl get applications -n argocd

# All integrations across users
kubectl get integrations --all-namespaces

# Kafka topics
kubectl get kafkatopics -n kafka
```

## 🛠️ Customization

Edit base configurations and commit changes. ArgoCD will automatically sync:

- `base/kafka/kafka-cluster.yaml` - Kafka cluster size, storage
- `base/rabbitmq/rabbitmq-cluster.yaml` - RabbitMQ replicas, plugins
- `base/camelk/integration-platform.yaml` - Camel K settings
- `base/user-namespace/user-template.yaml` - User resource quotas

## 🔐 Security

- NetworkPolicies for namespace isolation
- RBAC for user permissions
- ResourceQuotas prevent resource exhaustion
- PodSecurityStandards enforced

## 📚 Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Detailed architecture
- [Strimzi Docs](https://strimzi.io/docs/)
- [RabbitMQ Operator](https://www.rabbitmq.com/kubernetes/operator/operator-overview.html)
- [Camel K Docs](https://camel.apache.org/camel-k/latest/)

## 🤝 Contributing

To add users or modify configs:
1. Create overlay in `overlays/users/<username>/`
2. Add ArgoCD application
3. Commit and push - ArgoCD syncs automatically
