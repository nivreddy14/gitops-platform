#!/bin/bash
set -e

# Quick Start Script for GitOps Platform
# This script sets up the entire platform on a local kind cluster

CLUSTER_NAME="${CLUSTER_NAME:-gitops-platform}"
REPO_URL="${REPO_URL:-https://github.com/YOUR_ORG/gitops-platform.git}"

echo "╔════════════════════════════════════════════════════╗"
echo "║   GitOps Platform - Quick Start Installation      ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "❌ $1 is not installed. Please install it first."
        exit 1
    fi
    echo "✅ $1 is installed"
}

echo "Checking prerequisites..."
check_command kubectl
check_command kind
echo ""

# Create kind cluster if it doesn't exist
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "📦 Kind cluster '${CLUSTER_NAME}' already exists"
else
    echo "📦 Creating kind cluster '${CLUSTER_NAME}'..."
    cat <<EOF | kind create cluster --name ${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
EOF
    echo "✅ Kind cluster created"
fi

echo ""
echo "🔧 Configuring kubectl context..."
kubectl cluster-info --context kind-${CLUSTER_NAME}

# Install ArgoCD if not present
echo ""
if kubectl get namespace argocd &> /dev/null; then
    echo "🎯 ArgoCD namespace already exists"
else
    echo "🎯 Installing ArgoCD..."
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    echo "⏳ Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    echo "✅ ArgoCD is ready"
fi

# Get ArgoCD password
echo ""
echo "🔑 ArgoCD Credentials:"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
if [ -n "$ARGOCD_PASSWORD" ]; then
    echo "   Username: admin"
    echo "   Password: $ARGOCD_PASSWORD"
    echo ""
    echo "   Access ArgoCD UI:"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "   Then visit: https://localhost:8080"
else
    echo "   ⚠️  Could not retrieve password. It may have been deleted."
fi

# Update repository URL if provided
echo ""
if [ "$REPO_URL" != "https://github.com/YOUR_ORG/gitops-platform.git" ]; then
    echo "📝 Updating repository URL to: $REPO_URL"
    sed -i.bak "s|https://github.com/YOUR_ORG/gitops-platform.git|$REPO_URL|g" argocd/platform-apps.yaml
    sed -i.bak "s|https://github.com/YOUR_ORG/gitops-platform.git|$REPO_URL|g" argocd/user-template.yaml
    rm -f argocd/*.bak
    echo "✅ Repository URL updated"
else
    echo "⚠️  Using default repository URL. Update it with:"
    echo "   export REPO_URL=https://github.com/your-username/gitops-platform.git"
    echo "   Then re-run this script"
fi

# Deploy platform applications
echo ""
echo "🚀 Deploying platform applications..."
kubectl apply -f argocd/platform-apps.yaml

echo ""
echo "⏳ Waiting for operators to be ready (this may take 3-5 minutes)..."
echo "   Waiting for Strimzi operator..."
kubectl wait --for=condition=available deployment/strimzi-cluster-operator -n platform-operators --timeout=300s 2>/dev/null || true

echo "   Waiting for RabbitMQ operator..."
kubectl wait --for=condition=available deployment/rabbitmq-cluster-operator -n platform-operators --timeout=300s 2>/dev/null || true

echo "   Waiting for Camel K operator..."
kubectl wait --for=condition=available deployment/camel-k-operator -n platform-operators --timeout=300s 2>/dev/null || true

echo ""
echo "⏳ Waiting for Kafka cluster (this may take 5-10 minutes)..."
kubectl wait --for=condition=ready kafka/event-cluster -n platform-kafka --timeout=900s 2>/dev/null || echo "   ⚠️  Kafka may still be initializing. Check with: kubectl get kafka -n platform-kafka"

echo ""
echo "⏳ Waiting for RabbitMQ cluster..."
kubectl wait --for=condition=ready rabbitmqcluster/rabbitmq-cluster -n platform-rabbitmq --timeout=600s 2>/dev/null || echo "   ⚠️  RabbitMQ may still be initializing. Check with: kubectl get rabbitmqcluster -n platform-rabbitmq"

echo ""
echo "⏳ Waiting for Backstage..."
kubectl wait --for=condition=available deployment/backstage -n platform-backstage --timeout=600s 2>/dev/null || echo "   ⚠️  Backstage may still be initializing. Check with: kubectl get pods -n platform-backstage"

# Create example user
echo ""
echo "👤 Creating example user 'demo'..."
./scripts/create-user.sh demo 2>/dev/null || echo "   ⚠️  User creation script not found or failed"

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║            ✅ Installation Complete! ✅             ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "📊 Check deployment status:"
echo "   kubectl get applications -n argocd"
echo "   kubectl get pods -n platform-kafka"
echo "   kubectl get pods -n platform-rabbitmq"
echo "   kubectl get pods -n platform-backstage"
echo ""
echo "🔗 Access services:"
echo ""
echo "   ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   https://localhost:8080 (admin / $ARGOCD_PASSWORD)"
echo ""
echo "   Backstage:"
echo "   kubectl port-forward svc/backstage -n platform-backstage 7007:7007"
echo "   http://localhost:7007"
echo ""
echo "   RabbitMQ Management:"
echo "   kubectl port-forward svc/rabbitmq-cluster -n platform-rabbitmq 15672:15672"
echo "   http://localhost:15672 (admin / check secret)"
echo ""
echo "📚 Next steps:"
echo "   1. Review DEPLOYMENT.md for detailed configuration"
echo "   2. Check TESTING.md for testing procedures"
echo "   3. Explore examples/ directory for Camel K integrations"
echo "   4. Create more users: ./scripts/create-user.sh <username>"
echo ""
echo "🎉 Happy building!"
