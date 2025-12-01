# Testing Guide

This guide provides comprehensive testing procedures for the platform components.

## Prerequisites

Ensure all platform components are deployed and running:

```bash
# Check all applications
kubectl get applications -n argocd

# Verify operators
kubectl get pods -n platform-operators

# Verify services
kubectl get pods -n platform-kafka
kubectl get pods -n platform-rabbitmq
kubectl get pods -n platform-backstage
```

## 1. Testing Kafka

### Test Kafka Cluster

```bash
# Check Kafka cluster status
kubectl get kafka -n platform-kafka

# List Kafka topics
kubectl run kafka-topics -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-topics.sh --list --bootstrap-server event-cluster-kafka-bootstrap:9092

# Describe a topic
kubectl run kafka-describe -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-topics.sh --describe --topic platform-events \
  --bootstrap-server event-cluster-kafka-bootstrap:9092
```

### Produce and Consume Messages

```bash
# Terminal 1: Start a consumer
kubectl run kafka-consumer -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-console-consumer.sh --topic platform-events \
  --bootstrap-server event-cluster-kafka-bootstrap:9092 --from-beginning

# Terminal 2: Start a producer
kubectl run kafka-producer -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-console-producer.sh --topic platform-events \
  --bootstrap-server event-cluster-kafka-bootstrap:9092

# Type messages in Terminal 2, see them appear in Terminal 1
```

### Test CloudEvents Format

```bash
# Produce CloudEvents to Kafka
kubectl run kafka-producer -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bash -c 'echo "{ \"specversion\": \"1.0\", \"type\": \"com.example.test\", \"source\": \"test-producer\", \"id\": \"1234\", \"datacontenttype\": \"application/json\", \"data\": { \"message\": \"Hello CloudEvents\" } }" | bin/kafka-console-producer.sh --topic platform-events --bootstrap-server event-cluster-kafka-bootstrap:9092'

# Consume and verify
kubectl run kafka-consumer -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-console-consumer.sh --topic platform-events \
  --bootstrap-server event-cluster-kafka-bootstrap:9092 --max-messages 1
```

### Performance Test

```bash
# Producer performance test
kubectl run kafka-perf-producer -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-producer-perf-test.sh \
  --topic platform-events \
  --num-records 10000 \
  --record-size 1024 \
  --throughput -1 \
  --producer-props bootstrap.servers=event-cluster-kafka-bootstrap:9092

# Consumer performance test
kubectl run kafka-perf-consumer -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-consumer-perf-test.sh \
  --topic platform-events \
  --bootstrap-server event-cluster-kafka-bootstrap:9092 \
  --messages 10000 \
  --threads 1
```

## 2. Testing RabbitMQ

### Access RabbitMQ Management UI

```bash
# Port forward management UI
kubectl port-forward svc/rabbitmq-cluster -n platform-rabbitmq 15672:15672

# Get credentials
kubectl get secret rabbitmq-cluster-default-user -n platform-rabbitmq \
  -o jsonpath="{.data.username}" | base64 -d && echo
kubectl get secret rabbitmq-cluster-default-user -n platform-rabbitmq \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Access at http://localhost:15672
```

### Test RabbitMQ Messaging

```bash
# Start a consumer
kubectl run rabbitmq-consumer -n platform-rabbitmq --rm -it --restart=Never \
  --image=rabbitmq:3.13-management -- \
  rabbitmqadmin -H rabbitmq-cluster -u admin -p admin \
  get queue=platform.events count=100

# Publish a message
kubectl run rabbitmq-publisher -n platform-rabbitmq --rm -it --restart=Never \
  --image=rabbitmq:3.13-management -- \
  rabbitmqadmin -H rabbitmq-cluster -u admin -p admin \
  publish exchange=platform.events routing_key=test.message payload='{"test": "message"}'

# List queues
kubectl run rabbitmq-list -n platform-rabbitmq --rm -it --restart=Never \
  --image=rabbitmq:3.13-management -- \
  rabbitmqadmin -H rabbitmq-cluster -u admin -p admin list queues

# Check queue details
kubectl run rabbitmq-show -n platform-rabbitmq --rm -it --restart=Never \
  --image=rabbitmq:3.13-management -- \
  rabbitmqadmin -H rabbitmq-cluster -u admin -p admin show queue name=platform.events
```

## 3. Testing Camel K Integrations

### Deploy Test Integration

```bash
# Deploy the event generator
kubectl apply -f examples/camelk-integrations.yaml

# Or deploy individually
kubectl apply -f - <<EOF
apiVersion: camel.apache.org/v1
kind: Integration
metadata:
  name: simple-log
  namespace: user-alice
spec:
  sources:
    - content: |
        from("timer:tick?period=5000")
          .log("Hello from Camel K at \${date:now:HH:mm:ss}");
      name: route.yaml
EOF

# Watch integration status
kubectl get integration -n user-alice -w

# Check logs
kubectl logs -n user-alice -l camel.apache.org/integration=simple-log -f
```

### Test Kafka to RabbitMQ Bridge

```bash
# Deploy the bridge integration
kubectl apply -f - <<EOF
apiVersion: camel.apache.org/v1
kind: Integration
metadata:
  name: kafka-rabbitmq-bridge
  namespace: user-alice
spec:
  sources:
    - content: |
        from("kafka:alice-events?brokers=event-cluster-kafka-bootstrap.platform-kafka.svc.cluster.local:9092")
          .log("From Kafka: \${body}")
          .to("rabbitmq:amq.direct?hostname=rabbitmq-cluster.platform-rabbitmq.svc.cluster.local&username=admin&password=admin&queue=alice-events")
          .log("Sent to RabbitMQ");
      name: bridge.yaml
EOF

# Wait for integration to start
kubectl wait --for=condition=ready integration/kafka-rabbitmq-bridge -n user-alice --timeout=300s

# Send test message to Kafka
kubectl run kafka-test -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bash -c 'echo "Test message from Kafka" | bin/kafka-console-producer.sh --topic alice-events --bootstrap-server event-cluster-kafka-bootstrap:9092'

# Verify in RabbitMQ
kubectl run rabbitmq-check -n platform-rabbitmq --rm -it --restart=Never \
  --image=rabbitmq:3.13-management -- \
  rabbitmqadmin -H rabbitmq-cluster -u admin -p admin get queue=alice-events count=1
```

### Test HTTP to Kafka

```bash
# Deploy HTTP to Kafka integration
kubectl apply -f examples/camelk-integrations.yaml

# Wait for it to be ready
kubectl wait --for=condition=ready integration/http-to-kafka -n user-alice --timeout=300s

# Get the service
kubectl get svc -n user-alice -l camel.apache.org/integration=http-to-kafka

# Port forward
kubectl port-forward -n user-alice svc/http-to-kafka 8080:80

# Send test request
curl -X POST http://localhost:8080/events \
  -H "Content-Type: application/json" \
  -H "userId: user123" \
  -d '{"event": "test", "timestamp": "2024-01-01T00:00:00Z"}'

# Verify in Kafka
kubectl run kafka-verify -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-console-consumer.sh --topic alice-events \
  --bootstrap-server event-cluster-kafka-bootstrap:9092 --from-beginning --max-messages 1
```

## 4. Testing Backstage

### Access Backstage UI

```bash
# Port forward
kubectl port-forward svc/backstage -n platform-backstage 7007:7007

# Access at http://localhost:7007
```

### Verify Backstage Plugins

1. Navigate to http://localhost:7007
2. Check Catalog (should show default entities)
3. Verify Kubernetes plugin shows cluster resources
4. Check TechDocs (if configured)

### Test Backstage API

```bash
# Get catalog entities
curl http://localhost:7007/api/catalog/entities

# Get specific entity
curl http://localhost:7007/api/catalog/entities/by-name/component/default/example-component
```

## 5. Integration Testing

### End-to-End Event Flow Test

```bash
# 1. Deploy all example integrations
kubectl apply -f examples/camelk-integrations.yaml

# 2. Wait for all to be ready
kubectl wait --for=condition=ready integration --all -n user-alice --timeout=600s

# 3. Monitor logs in separate terminals
kubectl logs -n user-alice -l camel.apache.org/integration=event-generator -f
kubectl logs -n user-alice -l camel.apache.org/integration=kafka-to-rabbitmq -f
kubectl logs -n user-alice -l camel.apache.org/integration=cloudevents-consumer -f

# 4. Observe events flowing through the system
```

### Multi-User Test

```bash
# Create two users
./scripts/create-user.sh alice
./scripts/create-user.sh bob

# Verify isolation
kubectl run test-alice -n user-alice --rm -it --restart=Never --image=busybox -- sh
# Try to access bob's resources (should fail)
# nslookup service.user-bob.svc.cluster.local

# Test Kafka user permissions
kubectl get secret alice -n platform-kafka -o jsonpath='{.data.user\.crt}' | base64 -d > /tmp/alice.crt
kubectl get secret alice -n platform-kafka -o jsonpath='{.data.user\.key}' | base64 -d > /tmp/alice.key

# Alice should be able to write to alice-events but not bob-events
```

## 6. Performance and Load Testing

### Kafka Load Test

```bash
# Deploy multiple producers
for i in {1..5}; do
kubectl apply -f - <<EOF
apiVersion: camel.apache.org/v1
kind: Integration
metadata:
  name: load-producer-$i
  namespace: user-alice
spec:
  sources:
    - content: |
        from("timer:tick?period=100")
          .setBody(simple("Load test message \${exchangeProperty.CamelTimerCounter}"))
          .to("kafka:alice-events?brokers=event-cluster-kafka-bootstrap.platform-kafka.svc.cluster.local:9092");
      name: load.yaml
EOF
done

# Monitor metrics
kubectl top pods -n platform-kafka
kubectl top pods -n user-alice

# Check Kafka lag
kubectl run kafka-lag -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-consumer-groups.sh --bootstrap-server event-cluster-kafka-bootstrap:9092 \
  --describe --all-groups
```

### Resource Monitoring

```bash
# Watch resource usage
watch kubectl top pods -n platform-kafka
watch kubectl top pods -n platform-rabbitmq
watch kubectl top pods -n user-alice

# Check resource quotas
kubectl describe resourcequota -n user-alice

# Check persistent volume usage
kubectl get pvc -A
kubectl describe pvc -n platform-kafka
```

## 7. Failure Testing

### Test Kafka Resilience

```bash
# Delete a Kafka pod
kubectl delete pod event-cluster-kafka-0 -n platform-kafka

# Watch recovery
kubectl get pods -n platform-kafka -w

# Verify Kafka still works
kubectl run kafka-test -n platform-kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-3.8.0 -- \
  bin/kafka-topics.sh --list --bootstrap-server event-cluster-kafka-bootstrap:9092
```

### Test RabbitMQ Resilience

```bash
# Delete a RabbitMQ pod
kubectl delete pod rabbitmq-cluster-server-0 -n platform-rabbitmq

# Watch recovery
kubectl get pods -n platform-rabbitmq -w

# Verify RabbitMQ still works
kubectl run rabbitmq-test -n platform-rabbitmq --rm -it --restart=Never \
  --image=rabbitmq:3.13-management -- \
  rabbitmqadmin -H rabbitmq-cluster -u admin -p admin list queues
```

### Test Integration Restart

```bash
# Scale integration to 0
kubectl scale integration/event-generator -n user-alice --replicas=0

# Wait and scale back
sleep 10
kubectl scale integration/event-generator -n user-alice --replicas=1

# Verify it recovers
kubectl logs -n user-alice -l camel.apache.org/integration=event-generator -f
```

## 8. Cleanup After Testing

```bash
# Delete test integrations
kubectl delete integration --all -n user-alice

# Delete test users
kubectl delete namespace user-alice user-bob

# Clean up test pods
kubectl delete pod -n platform-kafka --field-selector=status.phase==Succeeded
kubectl delete pod -n platform-rabbitmq --field-selector=status.phase==Succeeded
```

## Common Issues and Solutions

### Integration fails to build
- Check integration platform: `kubectl get integrationplatform -n user-alice`
- Check builder logs: `kubectl logs -n user-alice -l camel.apache.org/component=builder`
- Solution: Ensure container registry is accessible

### Kafka connection refused
- Check Kafka service: `kubectl get svc -n platform-kafka`
- Verify NetworkPolicy allows traffic
- Solution: Update NetworkPolicy or use correct service name

### RabbitMQ authentication failed
- Check secret: `kubectl get secret rabbitmq-cluster-default-user -n platform-rabbitmq`
- Solution: Use correct credentials from secret

### Integration stuck in "Building" state
- Check builder pod: `kubectl get pods -n user-alice -l camel.apache.org/component=builder`
- Check events: `kubectl get events -n user-alice --sort-by='.lastTimestamp'`
- Solution: May need to increase timeout or resources
