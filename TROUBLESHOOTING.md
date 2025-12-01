# Troubleshooting Guide

## Common Issues and Solutions

### ArgoCD Issues

#### Applications Not Syncing

**Problem**: ArgoCD applications show "OutOfSync" status

**Solutions**:
```bash
# Check application status
kubectl get applications -n argocd

# Describe specific application
kubectl describe application operators -n argocd

# Force refresh
kubectl patch application operators -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}'

# Force sync
kubectl patch application operators -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'
```

#### Repository Not Accessible

**Problem**: "Unable to load data: failed to get git client"

**Solutions**:
1. Check repoURL in application manifests
2. Verify git repository is accessible
3. Check ArgoCD has proper credentials

```bash
# Test repository access
kubectl exec -n argocd deployment/argocd-repo-server -- \
  git ls-remote https://github.com/your-org/your-repo.git
```

### Operator Issues

#### Strimzi Operator Not Running

**Problem**: Kafka cluster not being created

**Check**:
```bash
# Check operator pod
kubectl get pods -n operators -l name=strimzi-cluster-operator

# Check operator logs
kubectl logs -n operators -l name=strimzi-cluster-operator --tail=50

# Check RBAC
kubectl auth can-i create kafka --as=system:serviceaccount:operators:strimzi-cluster-operator
```

**Common Causes**:
- Insufficient RBAC permissions
- Wrong WATCHED_NAMESPACE environment variable
- CRDs not installed

**Fix**:
```bash
# Verify CRDs exist
kubectl get crd kafkas.kafka.strimzi.io

# Restart operator
kubectl rollout restart deployment/strimzi-cluster-operator -n operators
```

#### RabbitMQ Operator Issues

**Problem**: RabbitmqCluster not being created

**Check**:
```bash
# Check operator
kubectl get pods -n operators -l app.kubernetes.io/name=rabbitmq-cluster-operator

# Check logs
kubectl logs -n operators -l app.kubernetes.io/name=rabbitmq-cluster-operator

# Check CRD
kubectl get crd rabbitmqclusters.rabbitmq.com
```

#### Camel K Operator Issues

**Problem**: Integrations not deploying

**Check**:
```bash
# Check operator
kubectl get pods -n operators -l app=camel-k-operator

# Check logs
kubectl logs -n operators -l app=camel-k-operator --tail=100

# Check integration platform
kubectl get integrationplatforms -n camelk
kubectl describe integrationplatform camel-k -n camelk
```

### Kafka Issues

#### Kafka Cluster Not Ready

**Problem**: Kafka pods not starting or cluster not ready

**Check**:
```bash
# Check Kafka resource
kubectl get kafka event-cluster -n kafka
kubectl describe kafka event-cluster -n kafka

# Check pods
kubectl get pods -n kafka
kubectl describe pod event-cluster-kafka-0 -n kafka

# Check Zookeeper
kubectl get pods -n kafka -l strimzi.io/name=event-cluster-zookeeper
kubectl logs event-cluster-zookeeper-0 -n kafka
```

**Common Issues**:

1. **Storage Issues**:
```bash
# Check PVCs
kubectl get pvc -n kafka

# Check storage class
kubectl get storageclass

# If PVCs pending, check events
kubectl describe pvc data-event-cluster-kafka-0 -n kafka
```

2. **Resource Constraints**:
```bash
# Check if pods are being scheduled
kubectl get events -n kafka --sort-by='.lastTimestamp'

# Check node resources
kubectl top nodes
```

3. **Zookeeper Connection Issues**:
```bash
# Test Zookeeper connectivity from Kafka pod
kubectl exec -n kafka event-cluster-kafka-0 -- \
  bash -c 'echo ruok | nc event-cluster-zookeeper-client 2181'
```

#### Kafka Topics Not Created

**Problem**: KafkaTopic resources not creating actual topics

**Check**:
```bash
# Check KafkaTopic resources
kubectl get kafkatopics -n kafka

# Describe specific topic
kubectl describe kafkatopic events -n kafka

# Check Topic Operator logs
kubectl logs -n kafka -l strimzi.io/name=event-cluster-entity-operator -c topic-operator

# List topics directly in Kafka
kubectl exec -n kafka event-cluster-kafka-0 -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

#### Cannot Connect to Kafka from Camel K

**Problem**: Camel K integration can't connect to Kafka

**Check**:
```bash
# Check NetworkPolicy
kubectl get networkpolicy -n user1

# Test connectivity from user namespace
kubectl run -n user1 -it --rm debug --image=busybox --restart=Never -- \
  nc -zv event-cluster-kafka-bootstrap.kafka.svc.cluster.local 9092

# Check Kafka listeners
kubectl get kafka event-cluster -n kafka -o jsonpath='{.status.listeners}'
```

**Fix**:
```bash
# Verify Kafka bootstrap address
kubectl get svc -n kafka event-cluster-kafka-bootstrap

# Check if service is reachable
kubectl exec -n user1 <integration-pod> -- \
  curl -v telnet://event-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092
```

### RabbitMQ Issues

#### RabbitMQ Cluster Not Forming

**Problem**: RabbitMQ pods running but cluster not forming

**Check**:
```bash
# Check cluster status
kubectl exec -n rabbitmq rabbitmq-cluster-server-0 -- \
  rabbitmqctl cluster_status

# Check pod logs
kubectl logs -n rabbitmq rabbitmq-cluster-server-0

# Check service
kubectl get svc -n rabbitmq
```

**Common Fixes**:
```bash
# Reset cluster (WARNING: loses data)
kubectl delete pod -n rabbitmq rabbitmq-cluster-server-0

# Force cluster join
kubectl exec -n rabbitmq rabbitmq-cluster-server-1 -- \
  rabbitmqctl stop_app && \
  rabbitmqctl join_cluster rabbit@rabbitmq-cluster-server-0.rabbitmq-cluster-nodes && \
  rabbitmqctl start_app
```

#### Cannot Access Management UI

**Problem**: RabbitMQ management UI not accessible

**Check**:
```bash
# Check if management plugin enabled
kubectl exec -n rabbitmq rabbitmq-cluster-server-0 -- \
  rabbitmq-plugins list

# Enable if needed
kubectl exec -n rabbitmq rabbitmq-cluster-server-0 -- \
  rabbitmq-plugins enable rabbitmq_management

# Verify service
kubectl get svc -n rabbitmq rabbitmq-cluster

# Port-forward
kubectl port-forward -n rabbitmq svc/rabbitmq-cluster 15672:15672
```

### Camel K Integration Issues

#### Integration Stuck in "Building"

**Problem**: Integration stays in Building phase

**Check**:
```bash
# Check integration status
kubectl get integration -n user1 kafka-consumer
kubectl describe integration -n user1 kafka-consumer

# Check builder pod
kubectl get pods -n user1 -l camel.apache.org/integration=kafka-consumer

# Check builder logs
kubectl logs -n user1 -l camel.apache.org/integration=kafka-consumer -c builder
```

**Common Causes**:
- Maven repository unreachable
- Insufficient resources
- Network issues

**Fix**:
```bash
# Check IntegrationPlatform
kubectl get integrationplatform -n user1

# Check Maven settings
kubectl get configmap maven-settings -n user1 -o yaml

# Delete and recreate integration
kubectl delete integration kafka-consumer -n user1
kubectl apply -f your-integration.yaml -n user1
```

#### Integration Error State

**Problem**: Integration shows Error status

**Check**:
```bash
# Check integration status
kubectl get integration -n user1 -o yaml

# Check pod logs
kubectl logs -n user1 -l camel.apache.org/integration=kafka-consumer

# Check events
kubectl get events -n user1 --field-selector involvedObject.kind=Integration
```

#### Integration Cannot Connect to Kafka/RabbitMQ

**Problem**: Integration logs show connection errors

**Check NetworkPolicy**:
```bash
# Check NetworkPolicy
kubectl get networkpolicy -n user1 -o yaml

# Test connectivity
kubectl run -n user1 test-pod --image=busybox --rm -it -- \
  nc -zv event-cluster-kafka-bootstrap.kafka.svc.cluster.local 9092
```

**Fix NetworkPolicy**:
Ensure egress rules allow traffic to kafka and rabbitmq namespaces on the correct ports.

### Backstage Issues

#### Backstage Pod Not Starting

**Problem**: Backstage deployment fails

**Check**:
```bash
# Check pods
kubectl get pods -n backstage

# Check logs
kubectl logs -n backstage deployment/backstage

# Check PostgreSQL
kubectl get pods -n backstage -l app=postgres
kubectl logs -n backstage -l app=postgres
```

**Common Issues**:
- PostgreSQL not ready
- Database connection issues
- Config map errors

**Fix**:
```bash
# Restart PostgreSQL
kubectl rollout restart statefulset/postgres -n backstage

# Check database connectivity
kubectl exec -n backstage deployment/backstage -- \
  nc -zv postgres 5432

# Recreate Backstage
kubectl rollout restart deployment/backstage -n backstage
```

### Resource Issues

#### Pods Pending Due to Insufficient Resources

**Problem**: Pods stuck in Pending state

**Check**:
```bash
# Check pod status
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# Check node resources
kubectl top nodes
kubectl describe nodes
```

**Solutions**:
- Reduce resource requests in base configs
- Add more nodes to cluster
- Scale down non-critical components

#### PVC Pending

**Problem**: PersistentVolumeClaims stuck in Pending

**Check**:
```bash
# Check PVCs
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage class
kubectl get storageclass
kubectl describe storageclass standard
```

**Fix for Kind**:
```bash
# Kind uses local-path provisioner
# If it's not working, reinstall Kind cluster with proper storage
```

### Network Issues

#### Cross-Namespace Communication Blocked

**Problem**: User pods can't reach Kafka/RabbitMQ

**Check**:
```bash
# Check NetworkPolicy in user namespace
kubectl get networkpolicy -n user1 -o yaml

# Test connectivity
kubectl run test -n user1 --image=busybox --rm -it -- \
  wget -O- http://rabbitmq-cluster.rabbitmq:15672
```

**Fix**:
Verify NetworkPolicy allows egress to kafka and rabbitmq namespaces.

### Kind Cluster Issues

#### Cluster Resources Exhausted

**Problem**: Kind cluster running out of resources

**Check**:
```bash
# Check Docker resources
docker stats

# Check Kind cluster
kubectl top nodes
kubectl get pods --all-namespaces
```

**Solutions**:
- Increase Docker Desktop resources
- Recreate cluster with more resources
- Reduce replica counts

#### Kind Cluster Won't Start

**Problem**: kind create cluster fails

**Solutions**:
```bash
# Delete old cluster
kind delete cluster

# Recreate with proper config
kind create cluster --config kind-config.yaml

# Check Docker
docker ps
docker system df
```

## Debug Commands Cheat Sheet

```bash
# Quick health check
kubectl get all --all-namespaces
kubectl get applications -n argocd
kubectl get kafka,kafkatopics -n kafka
kubectl get rabbitmqclusters -n rabbitmq
kubectl get integrations --all-namespaces

# Logs
kubectl logs -n <namespace> <pod-name> --tail=100 -f
kubectl logs -n <namespace> -l app=<label> --all-containers=true

# Events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top nodes
kubectl top pods -n <namespace>

# Describe resources
kubectl describe pod <pod-name> -n <namespace>
kubectl describe svc <service-name> -n <namespace>

# Execute commands in pods
kubectl exec -it <pod-name> -n <namespace> -- bash
kubectl exec <pod-name> -n <namespace> -- <command>

# Port forwarding
kubectl port-forward -n <namespace> svc/<service-name> <local-port>:<remote-port>
kubectl port-forward -n <namespace> <pod-name> <local-port>:<remote-port>

# Restart deployments
kubectl rollout restart deployment/<name> -n <namespace>
kubectl rollout status deployment/<name> -n <namespace>
```

## Getting Help

If you're still stuck:

1. Check ArgoCD UI for sync status
2. Review operator logs
3. Check Kubernetes events
4. Verify network connectivity
5. Review resource quotas and limits
6. Check RBAC permissions

For more help, file an issue with:
- `kubectl version`
- `kubectl get all -n <namespace>`
- Relevant logs
- Error messages
