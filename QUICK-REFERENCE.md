# Quick Reference Guide

## Quick Commands

### Initial Setup
```bash
# 1. Update repository URLs in all ArgoCD applications
find argocd/applications -name "*.yaml" -exec sed -i 's|https://github.com/<your-org>/<your-repo>.git|YOUR_REPO_URL|g' {} \;

# 2. Bootstrap platform
./scripts/bootstrap-argocd.sh

# 3. Watch deployment
watch kubectl get applications -n argocd
```

### User Management
```bash
# Create user
./scripts/create-user.sh user1

# List all user namespaces
kubectl get namespaces -l type=user-namespace

# Check user resources
kubectl get all -n user-user1
```

### Access Services
```bash
# Kafka
kubectl port-forward -n kafka svc/event-cluster-kafka-bootstrap 9092:9092

# RabbitMQ Management UI
kubectl port-forward -n rabbitmq svc/rabbitmq-cluster 15672:15672
# URL: http://localhost:15672 (guest/guest)

# Backstage
kubectl port-forward -n backstage svc/backstage 7007:7007
# URL: http://localhost:7007

# ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# URL: https://localhost:8080
# Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

### Kafka Operations
```bash
# List topics
kubectl exec -n kafka event-cluster-kafka-0 -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# Create topic
kubectl exec -n kafka event-cluster-kafka-0 -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic my-topic --partitions 3 --replication-factor 2

# Describe topic
kubectl exec -n kafka event-cluster-kafka-0 -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --describe --topic events

# Produce message
kubectl exec -n kafka event-cluster-kafka-0 -- \
  bin/kafka-console-producer.sh --bootstrap-server localhost:9092 \
  --topic events

# Consume messages
kubectl exec -n kafka event-cluster-kafka-0 -- \
  bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic events --from-beginning

# Check consumer groups
kubectl exec -n kafka event-cluster-kafka-0 -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
```

### RabbitMQ Operations
```bash
# List queues
kubectl exec -n rabbitmq rabbitmq-cluster-server-0 -- \
  rabbitmqctl list_queues

# List exchanges
kubectl exec -n rabbitmq rabbitmq-cluster-server-0 -- \
  rabbitmqctl list_exchanges

# List bindings
kubectl exec -n rabbitmq rabbitmq-cluster-server-0 -- \
  rabbitmqctl list_bindings

# Check cluster status
kubectl exec -n rabbitmq rabbitmq-cluster-server-0 -- \
  rabbitmqctl cluster_status

# List users
kubectl exec -n rabbitmq rabbitmq-cluster-server-0 -- \
  rabbitmqctl list_users
```

### Camel K Operations
```bash
# List integrations (all namespaces)
kubectl get integrations --all-namespaces

# Deploy integration
kubectl apply -f my-integration.yaml -n user1

# Get integration details
kubectl describe integration kafka-consumer -n user1

# Check integration logs
kubectl logs -n user1 -l camel.apache.org/integration=kafka-consumer -f

# Delete integration
kubectl delete integration kafka-consumer -n user1

# Check IntegrationPlatform
kubectl get integrationplatform -n user1
kubectl describe integrationplatform camel-k -n user1

# Scale integration
kubectl scale integration kafka-consumer -n user1 --replicas=3
```

### Monitoring & Debugging
```bash
# Check all pods
kubectl get pods --all-namespaces

# Check specific namespace
kubectl get all -n kafka

# Watch pods
watch kubectl get pods -n kafka

# Get pod logs
kubectl logs -n kafka event-cluster-kafka-0 -f

# Get events
kubectl get events -n kafka --sort-by='.lastTimestamp'

# Check resource usage
kubectl top nodes
kubectl top pods -n kafka

# Describe resource
kubectl describe pod event-cluster-kafka-0 -n kafka

# Execute command in pod
kubectl exec -it event-cluster-kafka-0 -n kafka -- bash

# Check PVCs
kubectl get pvc -n kafka
```

### ArgoCD Operations
```bash
# List applications
kubectl get applications -n argocd

# Get application details
kubectl describe application kafka -n argocd

# Sync application manually
kubectl patch application kafka -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'

# Refresh application
kubectl patch application kafka -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}'

# Delete application
kubectl delete application kafka -n argocd
```

### Troubleshooting Quick Checks
```bash
# Overall health
kubectl get all --all-namespaces | grep -v Running | grep -v Completed

# Operator health
kubectl get pods -n operators

# Storage issues
kubectl get pvc --all-namespaces | grep Pending

# Recent events (last 10)
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -10

# Failed pods
kubectl get pods --all-namespaces --field-selector status.phase=Failed

# Restart deployment
kubectl rollout restart deployment/<name> -n <namespace>

# Check NetworkPolicy
kubectl get networkpolicy -n user1 -o yaml
```

## Configuration Files

### ArgoCD Application Structure
```
argocd/
├── applications/
│   ├── app-of-apps.yaml      # Main application (apply this first)
│   ├── operators.yaml         # All operators
│   ├── kafka.yaml            # Kafka cluster
│   ├── rabbitmq.yaml         # RabbitMQ cluster
│   ├── camelk.yaml           # Camel K platform
│   └── backstage.yaml        # Backstage portal
└── kustomization.yaml
```

### Base Resources
```
base/
├── operators/         # Strimzi, RabbitMQ, Camel K operators
├── kafka/            # Kafka cluster + topics
├── rabbitmq/         # RabbitMQ cluster
├── camelk/           # Camel K IntegrationPlatform
├── backstage/        # Backstage + PostgreSQL
└── user-namespace/   # User namespace template
```

### Example Integration
```yaml
apiVersion: camel.apache.org/v1
kind: Integration
metadata:
  name: kafka-consumer
  namespace: user1
spec:
  sources:
    - content: |
        from("kafka:events?brokers=event-cluster-kafka-bootstrap.kafka:9092&groupId=my-group")
          .log("Message: ${body}")
      name: kafka-consumer.groovy
```

## Common Kafka Bootstrap Addresses

From different namespaces:

- **Same namespace (kafka)**: `event-cluster-kafka-bootstrap:9092`
- **Different namespace**: `event-cluster-kafka-bootstrap.kafka:9092`
- **Full FQDN**: `event-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092`

## Common RabbitMQ Addresses

- **AMQP**: `rabbitmq-cluster.rabbitmq:5672`
- **Management**: `rabbitmq-cluster.rabbitmq:15672`
- **Full FQDN**: `rabbitmq-cluster.rabbitmq.svc.cluster.local:5672`

## Resource Limits (Per User Namespace)

```yaml
CPU Requests: 4 cores
Memory Requests: 8Gi
CPU Limits: 8 cores
Memory Limits: 16Gi
Pods: 20
PVCs: 10
Services: 10
```

## Default Credentials

**⚠️ Change these in production!**

- **RabbitMQ**: guest/guest
- **PostgreSQL (Backstage)**: backstage/backstage123
- **ArgoCD**: admin/(get from secret)

```bash
# Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

## Integration Examples Path
```bash
# Example integrations are in:
examples/camelk-integrations.yaml

# Deploy to user namespace:
kubectl apply -f examples/camelk-integrations.yaml -n user1
```

## Useful Aliases
```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods --all-namespaces'
alias kga='kubectl get applications -n argocd'
alias kl='kubectl logs'
alias kd='kubectl describe'
alias ke='kubectl exec -it'
```

## Port Forwarding for Local Development
```bash
# Create a script for all port-forwards
cat > port-forward-all.sh << 'EOF'
#!/bin/bash
kubectl port-forward -n kafka svc/event-cluster-kafka-bootstrap 9092:9092 &
kubectl port-forward -n rabbitmq svc/rabbitmq-cluster 15672:15672 &
kubectl port-forward -n rabbitmq svc/rabbitmq-cluster 5672:5672 &
kubectl port-forward -n backstage svc/backstage 7007:7007 &
kubectl port-forward -n argocd svc/argocd-server 8080:443 &
echo "All services port-forwarded. Press Ctrl+C to stop."
wait
EOF
chmod +x port-forward-all.sh
```

## Clean Up Everything
```bash
# Delete all applications (keeps ArgoCD)
kubectl delete application --all -n argocd

# Or delete everything including namespaces
kubectl delete namespace operators kafka rabbitmq camelk backstage
kubectl delete namespace -l type=user-namespace
```
