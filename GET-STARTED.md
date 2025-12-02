# 🚀 Getting Started with GitOps Platform

Welcome! This repository provides a complete event-driven platform with multi-user support, managed by ArgoCD.

## What You Get

✅ **Apache Kafka** (3-node cluster with Strimzi)  
✅ **RabbitMQ** (3-node HA cluster)  
✅ **Camel K** (Cloud-native integrations)  
✅ **Backstage** (Developer portal)  
✅ **Multi-tenancy** (Isolated user namespaces)  
✅ **GitOps** (ArgoCD automated deployment)

## 5-Minute Quick Start

### Option 1: Automated Installation

```bash
# Clone this repository
git clone <your-repo-url>
cd gitops-platform

# Run quick start (creates kind cluster + deploys everything)
./quick-start.sh

# Wait 10-15 minutes for everything to deploy
```

### Option 2: Existing Cluster

```bash
# Prerequisites: ArgoCD already installed on your cluster

# 1. Update repository URL
export REPO_URL="https://github.com/your-username/gitops-platform.git"
sed -i "s|https://github.com/YOUR_ORG/gitops-platform.git|$REPO_URL|g" argocd/*.yaml

# 2. Deploy platform
kubectl apply -f argocd/platform-apps.yaml

# 3. Create a user
./scripts/create-user.sh alice

# 4. Check status
kubectl get applications -n argocd
kubectl get pods -n platform-kafka
kubectl get pods -n user-alice
```

## What Gets Deployed

### Platform Components
- **platform-operators**: Strimzi, RabbitMQ, Camel K operators
- **platform-kafka**: 3-broker Kafka cluster + ZooKeeper
- **platform-rabbitmq**: 3-node RabbitMQ cluster
- **platform-backstage**: Developer portal with PostgreSQL

### Per-User Resources
- Isolated Kubernetes namespace
- Dedicated Kafka topics with ACLs
- RabbitMQ virtual host (optional)
- Camel K integration platform
- Resource quotas and network policies

## Next Steps

### 1. Access Services

```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: https://localhost:8080
# User: admin / Password: (get with kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Backstage
kubectl port-forward svc/backstage -n platform-backstage 7007:7007
# Visit: http://localhost:7007

# RabbitMQ Management
kubectl port-forward svc/rabbitmq-cluster -n platform-rabbitmq 15672:15672
# Visit: http://localhost:15672
```

### 2. Deploy Your First Integration

```bash
# Deploy a sample Camel K integration
kubectl apply -f examples/camelk-integrations.yaml

# Watch it build and deploy
kubectl get integration -n user-alice -w

# View logs
kubectl logs -n user-alice -l camel.apache.org/integration=event-generator -f
```

### 3. Test Event Flow

```bash
# Send a message to Kafka
kubectl run kafka-producer -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bash -c 'echo "Hello from Kafka!" | bin/kafka-console-producer.sh \
  --topic alice-events --bootstrap-server event-cluster-kafka-bootstrap:9092'

# Check integration logs to see it processed
kubectl logs -n user-alice -l camel.apache.org/integration=kafka-to-log -f
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    ArgoCD (GitOps)                       │
│              Watches Git → Deploys to K8s                │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
    Operators    Platform    User Namespaces
    (Strimzi,    Services    (alice, bob, ...)
     RabbitMQ,   (Kafka,     
     Camel K)    RabbitMQ,   Each user gets:
                 Backstage)  • Isolated namespace
                             • Kafka topics + ACLs
                             • Camel K platform
                             • Resource quotas
```

## Common Tasks

### Create a New User
```bash
./scripts/create-user.sh bob
```

### Deploy an Integration
```bash
kubectl apply -f - <<EOF
apiVersion: camel.apache.org/v1
kind: Integration
metadata:
  name: hello-world
  namespace: user-alice
spec:
  sources:
    - content: |
        from("timer:tick?period=5000")
          .log("Hello World at \${date:now:HH:mm:ss}");
      name: route.yaml
