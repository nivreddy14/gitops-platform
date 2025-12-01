# Platform Architecture

## Overview

This platform provides a complete event-driven architecture deployed on Kubernetes using GitOps principles with ArgoCD. It supports multi-tenancy with isolated user namespaces.

## Components

### Core Infrastructure

#### ArgoCD
- **Purpose**: GitOps continuous delivery
- **Deployment**: App-of-Apps pattern
- **Auto-sync**: Enabled for all applications
- **Self-heal**: Automatic drift correction

#### Operators Namespace
All operators run in the `operators` namespace with cluster-wide permissions:

1. **Strimzi Kafka Operator** (v0.43.0)
   - Manages Kafka clusters
   - CRDs: Kafka, KafkaTopic, KafkaUser, KafkaConnect
   - Watches `kafka` namespace

2. **RabbitMQ Cluster Operator** (v2.10.0)
   - Manages RabbitMQ clusters
   - CRD: RabbitmqCluster
   - Watches `rabbitmq` namespace

3. **Camel K Operator** (v2.5.0)
   - Manages Camel K integrations
   - CRDs: Integration, IntegrationPlatform
   - Watches all namespaces

### Event Streaming Layer

#### Kafka (namespace: kafka)
- **Cluster**: event-cluster (3 brokers)
- **Zookeeper**: 3 replicas
- **Storage**: 10Gi per broker (PVC)
- **Listeners**:
  - Plain: 9092 (no TLS)
  - TLS: 9093 (TLS enabled)
- **Default Topics**:
  - `events` - 6 partitions, 2 replicas
  - `commands` - 3 partitions, 2 replicas
  - `notifications` - 3 partitions, 2 replicas
- **Metrics**: JMX Prometheus Exporter enabled

#### RabbitMQ (namespace: rabbitmq)
- **Cluster**: rabbitmq-cluster (3 replicas)
- **Storage**: 10Gi per replica (PVC)
- **Plugins**: Federation, Shovel, Streams
- **Management UI**: Port 15672
- **AMQP**: Port 5672
- **Clustering**: Kubernetes native discovery
- **High Availability**: All queues replicated

### Integration Layer

#### Camel K (namespace: camelk)
- **IntegrationPlatform**: Configured with Maven settings
- **Build Strategy**: Kubernetes native
- **Runtime**: Quarkus
- **Supported Languages**: Java, Groovy, YAML, XML
- **Registry**: Local/configurable

### Developer Portal

#### Backstage (namespace: backstage)
- **Database**: PostgreSQL 15 (5Gi PVC)
- **Features**:
  - Service catalog
  - Kubernetes plugin
  - API documentation
  - Resource monitoring
- **Access**: Port 7007
- **Authentication**: Basic (configurable)

## Multi-Tenancy Architecture

### User Namespaces

Each user gets a dedicated namespace (`user-<username>`) with:

#### Resource Quotas
```yaml
CPU Requests: 4 cores
Memory Requests: 8Gi
CPU Limits: 8 cores
Memory Limits: 16Gi
PVCs: 10
Services: 10
Pods: 20
```

#### Network Policies
- **Ingress**: From same namespace and other platform namespaces
- **Egress**:
  - Kafka (kafka:9092, kafka:9093)
  - RabbitMQ (rabbitmq:5672, rabbitmq:15672)
  - DNS (kube-system:53)
  - HTTPS (443) for external APIs

#### RBAC
- **ServiceAccount**: user-sa
- **Role**: CRUD on pods, services, configmaps, secrets, integrations
- **Scope**: Limited to user namespace only

#### Camel K Integration
- Dedicated IntegrationPlatform per namespace
- Shared Maven settings
- Resource limits per integration:
  - CPU: 200m request, 500m limit
  - Memory: 256Mi request, 512Mi limit

## Data Flow Patterns

### Pattern 1: Event Sourcing
```
Producer → Kafka Topic → Camel K Consumer → Processing → Kafka Topic
```

### Pattern 2: Message Bridge
```
Kafka → Camel K Integration → RabbitMQ
RabbitMQ → Camel K Integration → Kafka
```

### Pattern 3: HTTP Webhook
```
External System → HTTP → Camel K → Kafka/RabbitMQ
```

### Pattern 4: Data Transformation
```
Kafka (events) → Transformer → Kafka (commands)
```

## Deployment Model

### GitOps Flow
```
Git Repository
    ↓
ArgoCD Sync
    ↓
Kubernetes Manifests (Kustomize)
    ↓
Kubernetes Resources
```

### Sync Waves
1. **Wave 0**: Operators (default)
2. **Wave 1**: Infrastructure (Kafka, RabbitMQ, Camel K)
3. **Wave 2**: Applications (Backstage)
4. **Wave 3**: User Namespaces

## Security

### Authentication & Authorization
- **ArgoCD**: RBAC configured
- **Kafka**: SASL/PLAIN (optional)
- **RabbitMQ**: Username/password (guest/guest - change in prod)
- **Backstage**: ServiceAccount with read-only cluster access

### Network Security
- NetworkPolicies enforce namespace isolation
- Users can only communicate with Kafka and RabbitMQ
- No cross-user namespace traffic allowed

### Resource Security
- ResourceQuotas prevent resource exhaustion
- LimitRanges enforce container resource boundaries
- PodSecurityStandards can be enforced (not configured yet)

## Monitoring & Observability

### Metrics (Available)
- **Kafka**: JMX metrics exposed via Prometheus exporter
- **RabbitMQ**: Prometheus plugin on port 15692
- **Camel K**: Integration metrics via Micrometer

### Logs
- All components log to stdout/stderr
- Can be collected via:
  - `kubectl logs`
  - Fluent Bit/Fluentd (not deployed)
  - Loki/Promtail (not deployed)

### Tracing
- Can be enabled via Camel K traits
- OpenTelemetry support available

## Scaling

### Horizontal Scaling
- **Kafka**: Scale brokers by updating replicas
- **RabbitMQ**: Scale nodes by updating replicas
- **Camel K Integrations**: Scale via replicas in Integration spec
- **Backstage**: Can run multiple replicas (need session sharing)

### Vertical Scaling
- Adjust resource requests/limits in base configs
- Operators handle rolling updates automatically

## Disaster Recovery

### Data Persistence
- **Kafka**: PersistentVolumes for broker data
- **RabbitMQ**: PersistentVolumes for queue data
- **PostgreSQL**: PersistentVolume for Backstage DB

### Backup Strategy
- PVC snapshots via CSI drivers
- Topic configs backed up in Git (KafkaTopic CRDs)
- RabbitMQ definitions exported regularly

### Recovery
- ArgoCD sync restores entire platform
- Data recovery from PVC snapshots
- Stateless components (Camel K) auto-recover

## Performance Tuning

### Kafka
- Adjust `log.segment.bytes` for throughput
- Tune `num.network.threads` and `num.io.threads`
- Configure compression: `compression.type=producer`

### RabbitMQ
- Enable lazy queues for large backlogs
- Tune `vm_memory_high_watermark`
- Use quorum queues for better replication

### Camel K
- Adjust JVM heap via traits
- Use native compilation for faster startup
- Configure Maven mirror for faster builds

## Local Development

### Kind Cluster Configuration
Recommended Kind config:
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 9092  # Kafka
  - containerPort: 30001
    hostPort: 15672 # RabbitMQ UI
  - containerPort: 30002
    hostPort: 7007  # Backstage
- role: worker
- role: worker
- role: worker
```

### Resource Requirements
- Minimum: 8 CPU, 16GB RAM
- Recommended: 12 CPU, 24GB RAM
- Disk: 50GB+ for PVCs

## Production Considerations

### Not Production Ready (Yet)
- Default credentials (change these!)
- No TLS for Kafka plain listener
- Single PostgreSQL instance (no HA)
- No monitoring stack deployed
- No backup automation
- Storage class set to `standard` (change for your cloud)

### Production Checklist
- [ ] Enable TLS for all components
- [ ] Configure proper authentication
- [ ] Deploy monitoring (Prometheus/Grafana)
- [ ] Set up log aggregation
- [ ] Configure backup automation
- [ ] Implement GitOps secret management (SealedSecrets/Vault)
- [ ] Enable Pod Security Standards
- [ ] Set up ingress controllers
- [ ] Configure DNS
- [ ] Implement disaster recovery plan
- [ ] Load testing
- [ ] Security scanning
