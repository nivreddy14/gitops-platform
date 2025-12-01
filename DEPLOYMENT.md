# Deployment Guide

## Prerequisites

1. **Kubernetes Cluster Running**
   ```bash
   # If using kind
   kind create cluster --name platform
   
   # Verify cluster
   kubectl cluster-info
   ```

2. **ArgoCD Installed**
   ```bash
   # If not already installed
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   
   # Wait for ArgoCD to be ready
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
   
   # Get ArgoCD admin password
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   
   # Port forward to access UI
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   # Access at https://localhost:8080 (admin / <password>)
   ```

## Step 1: Update Repository URLs

Before deploying, update the repository URL in all ArgoCD Application files:

```bash
# Update platform-apps.yaml
sed -i 's|https://github.com/YOUR_ORG/gitops-platform.git|https://github.com/YOUR_USERNAME/gitops-platform.git|g' argocd/platform-apps.yaml

# Update user-template.yaml
sed -i 's|https://github.com/YOUR_ORG/gitops-platform.git|https://github.com/YOUR_USERNAME/gitops-platform.git|g' argocd/user-template.yaml
```

Or manually edit:
- `argocd/platform-apps.yaml` - Update `spec.source.repoURL`
- `argocd/user-template.yaml` - Update `spec.source.repoURL`

## Step 2: Deploy Platform Components

### Deploy Operators First

```bash
# Apply platform applications
kubectl apply -f argocd/platform-apps.yaml

# Check application status
kubectl get applications -n argocd

# Watch applications sync
watch kubectl get applications -n argocd
```

### Wait for Operators to be Ready

```bash
# Wait for Strimzi operator
kubectl wait --for=condition=ready pod -l name=strimzi-cluster-operator -n platform-operators --timeout=300s

# Wait for RabbitMQ operator
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=rabbitmq-cluster-operator -n platform-operators --timeout=300s

# Wait for Camel K operator
kubectl wait --for=condition=ready pod -l name=camel-k-operator -n platform-operators --timeout=300s
```

### Verify Operators

```bash
# Check Strimzi
kubectl get deployment strimzi-cluster-operator -n platform-operators

# Check RabbitMQ
kubectl get deployment rabbitmq-cluster-operator -n platform-operators

# Check Camel K
kubectl get deployment camel-k-operator -n platform-operators

# Check CRDs
kubectl get crd | grep -E "kafka|rabbitmq|camel"
```

## Step 3: Wait for Platform Services

### Kafka Cluster

```bash
# Watch Kafka cluster creation
kubectl get kafka -n platform-kafka -w

# Wait for Kafka to be ready (takes 3-5 minutes)
kubectl wait --for=condition=ready kafka/event-cluster -n platform-kafka --timeout=600s

# Verify Kafka pods
kubectl get pods -n platform-kafka

# Check Kafka topics
kubectl get kafkatopic -n platform-kafka
```

### RabbitMQ Cluster

```bash
# Watch RabbitMQ cluster creation
kubectl get rabbitmqcluster -n platform-rabbitmq -w

# Wait for RabbitMQ to be ready
kubectl wait --for=condition=ready rabbitmqcluster/rabbitmq-cluster -n platform-rabbitmq --timeout=600s

# Verify RabbitMQ pods
kubectl get pods -n platform-rabbitmq

# Get RabbitMQ management UI credentials
kubectl get secret rabbitmq-cluster-default-user -n platform-rabbitmq -o jsonpath="{.data.username}" | base64 -d
kubectl get secret rabbitmq-cluster-default-user -n platform-rabbitmq -o jsonpath="{.data.password}" | base64 -d
```

### Backstage

```bash
# Watch Backstage deployment
kubectl get pods -n platform-backstage -w

# Wait for Backstage to be ready
kubectl wait --for=condition=ready pod -l app=backstage -n platform-backstage --timeout=600s

# Check Backstage status
kubectl get all -n platform-backstage
```

## Step 4: Access Services

### Port Forwarding

```bash
# Backstage
kubectl port-forward svc/backstage -n platform-backstage 7007:7007 &
# Access at http://localhost:7007

# RabbitMQ Management UI
kubectl port-forward svc/rabbitmq-cluster -n platform-rabbitmq 15672:15672 &
# Access at http://localhost:15672 (use credentials from above)

# Kafka (for local testing)
kubectl port-forward svc/event-cluster-kafka-bootstrap -n platform-kafka 9092:9092 &
```

### Verify Connectivity

```bash
# Test Kafka connectivity
kubectl run kafka-test -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-topics.sh --list --bootstrap-server event-cluster-kafka-bootstrap:9092

# Test RabbitMQ connectivity
kubectl run rabbitmq-test -n platform-rabbitmq --rm -it --restart=Never \
  --image=rabbitmq:3.13-management -- \
  rabbitmqadmin -H rabbitmq-cluster -u admin -p admin list queues
```

## Step 5: Create User Namespaces

### Option 1: Using the Script

```bash
# Create user namespace for alice
./scripts/create-user.sh alice

# Create user namespace for bob
./scripts/create-user.sh bob

# Verify user namespaces
kubectl get namespaces -l user-namespace=true
```

### Option 2: Using ArgoCD Application

```bash
# Copy template and customize
cp argocd/user-template.yaml argocd/user-alice-app.yaml

# Edit the file and replace USERNAME with alice
# Then apply
kubectl apply -f argocd/user-alice-app.yaml
```

### Verify User Resources

```bash
# Check user namespace
kubectl get all -n user-alice

# Check user Kafka resources
kubectl get kafkatopic,kafkauser -n platform-kafka -l user=alice

# Check user Camel K platform
kubectl get integrationplatform -n user-alice
```

## Step 6: Test Integration

### Deploy a Test Camel K Integration

```bash
# Switch to user namespace
kubectl config set-context --current --namespace=user-alice

# Create a simple Camel K integration
cat <<EOF | kubectl apply -f -
apiVersion: camel.apache.org/v1
kind: Integration
metadata:
  name: kafka-to-log
  namespace: user-alice
spec:
  sources:
    - content: |
        from("kafka:alice-events?brokers=event-cluster-kafka-bootstrap.platform-kafka.svc.cluster.local:9092")
          .log("Received: \${body}")
      name: route.yaml
EOF

# Watch integration build and deploy
kubectl get integration -w

# Check integration logs
kubectl logs -l camel.apache.org/integration=kafka-to-log -f
```

### Send Test Message to Kafka

```bash
# Run Kafka producer
kubectl run kafka-producer -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-console-producer.sh --topic alice-events \
  --bootstrap-server event-cluster-kafka-bootstrap:9092

# Type messages and press Enter
# You should see them in the Camel K integration logs
```

## Troubleshooting

### Check ArgoCD Application Status

```bash
# List all applications
kubectl get applications -n argocd

# Describe specific application
kubectl describe application platform-operators -n argocd

# Get sync status
argocd app get platform-operators
```

### Check Operator Logs

```bash
# Strimzi operator logs
kubectl logs -n platform-operators -l name=strimzi-cluster-operator --tail=100

# RabbitMQ operator logs
kubectl logs -n platform-operators -l app.kubernetes.io/name=rabbitmq-cluster-operator --tail=100

# Camel K operator logs
kubectl logs -n platform-operators -l name=camel-k-operator --tail=100
```

### Common Issues

1. **Kafka cluster not starting**
   - Check storage class: `kubectl get storageclass`
   - Update `base/kafka/kafka-cluster.yaml` with correct storageClassName
   - Check PVC status: `kubectl get pvc -n platform-kafka`

2. **RabbitMQ cluster not starting**
   - Check storage class: `kubectl get pvc -n platform-rabbitmq`
   - Check operator logs for errors

3. **Camel K integrations not building**
   - Check integration platform: `kubectl get integrationplatform -n user-alice`
   - Check builder pod logs: `kubectl logs -n user-alice -l camel.apache.org/component=builder`

4. **Network connectivity issues**
   - Check NetworkPolicy: `kubectl get networkpolicy -n user-alice`
   - Verify DNS: `kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup event-cluster-kafka-bootstrap.platform-kafka.svc.cluster.local`

## Cleanup

```bash
# Delete user namespaces
kubectl delete namespace user-alice user-bob

# Delete platform applications
kubectl delete -f argocd/platform-apps.yaml

# Wait for resources to be cleaned up
kubectl delete namespace platform-kafka platform-rabbitmq platform-backstage platform-operators --wait=true

# If needed, delete ArgoCD
kubectl delete namespace argocd
```

## Next Steps

1. **Configure Git Integration in Backstage**
   - Add GitHub token to backstage-app-config
   - Register components in catalog

2. **Set up Monitoring**
   - Deploy Prometheus and Grafana
   - Configure ServiceMonitors for Kafka, RabbitMQ

3. **Add More Users**
   - Use `create-user.sh` script
   - Or create ArgoCD Applications

4. **Customize Resources**
   - Adjust resource limits in base configurations
   - Create overlays for different environments
   - Add custom Camel K integrations

5. **Implement CI/CD**
   - Connect ArgoCD to your Git repository
   - Enable auto-sync
   - Set up webhooks for faster deployments
