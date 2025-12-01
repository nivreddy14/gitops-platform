#!/bin/bash
set -e

echo "================================================"
echo "GitOps Platform - Setup Script"
echo "================================================"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "❌ git not found. Please install git."
    exit 1
fi

echo "✅ Prerequisites checked"
echo ""

# Check if ArgoCD is installed
echo "Checking for ArgoCD installation..."
if ! kubectl get namespace argocd &> /dev/null; then
    echo "❌ ArgoCD namespace not found."
    echo ""
    echo "Please install ArgoCD first:"
    echo "  kubectl create namespace argocd"
    echo "  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
    echo ""
    echo "Wait for ArgoCD to be ready:"
    echo "  kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd"
    echo ""
    echo "Get initial admin password:"
    echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    exit 1
fi

echo "✅ ArgoCD namespace found"
echo ""

# Check if ArgoCD is ready
echo "Checking if ArgoCD is ready..."
if ! kubectl get deployment argocd-server -n argocd &> /dev/null; then
    echo "❌ ArgoCD server deployment not found."
    exit 1
fi

echo "✅ ArgoCD is installed"
echo ""

# Git repository setup
echo "================================================"
echo "Git Repository Setup"
echo "================================================"
echo ""
echo "Before proceeding, you need to:"
echo "1. Push this repository to your Git server (GitHub, GitLab, etc.)"
echo "2. Update the repoURL in all ArgoCD application manifests"
echo ""
echo "Files to update:"
echo "  - argocd/applications/app-of-apps.yaml"
echo "  - argocd/applications/operators.yaml"
echo "  - argocd/applications/kafka.yaml"
echo "  - argocd/applications/rabbitmq.yaml"
echo "  - argocd/applications/camelk.yaml"
echo "  - argocd/applications/backstage.yaml"
echo ""
echo "Replace: https://github.com/<your-org>/<your-repo>.git"
echo "With your actual Git repository URL"
echo ""

read -p "Have you updated all repoURL fields? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please update the repository URLs first, then run this script again."
    exit 1
fi

echo ""
echo "================================================"
echo "Deploying Platform"
echo "================================================"
echo ""

# Apply App-of-Apps
echo "Applying App-of-Apps to ArgoCD..."
kubectl apply -f argocd/applications/app-of-apps.yaml

echo ""
echo "✅ App-of-Apps applied!"
echo ""
echo "ArgoCD will now sync all applications."
echo ""

echo "================================================"
echo "Monitoring Deployment"
echo "================================================"
echo ""

echo "Waiting for operators to deploy (this may take 2-3 minutes)..."
sleep 10

# Wait for operators namespace
kubectl wait --for=condition=available --timeout=300s deployment/strimzi-cluster-operator -n operators 2>/dev/null || echo "Strimzi operator still deploying..."
kubectl wait --for=condition=available --timeout=300s deployment/rabbitmq-cluster-operator -n operators 2>/dev/null || echo "RabbitMQ operator still deploying..."
kubectl wait --for=condition=available --timeout=300s deployment/camel-k-operator -n operators 2>/dev/null || echo "Camel K operator still deploying..."

echo ""
echo "Check deployment status:"
echo ""
echo "  # ArgoCD Applications"
echo "  kubectl get applications -n argocd"
echo ""
echo "  # Operators"
echo "  kubectl get pods -n operators"
echo ""
echo "  # Kafka"
echo "  kubectl get kafka -n kafka"
echo "  kubectl get pods -n kafka"
echo ""
echo "  # RabbitMQ"
echo "  kubectl get rabbitmqclusters -n rabbitmq"
echo "  kubectl get pods -n rabbitmq"
echo ""
echo "  # Camel K"
echo "  kubectl get integrationplatforms -n camelk"
echo ""
echo "  # Backstage"
echo "  kubectl get pods -n backstage"
echo ""

echo "================================================"
echo "Next Steps"
echo "================================================"
echo ""
echo "1. Create user namespaces:"
echo "   ./scripts/create-user.sh user1"
echo ""
echo "2. Port-forward services to access them:"
echo ""
echo "   # Kafka"
echo "   kubectl port-forward -n kafka svc/event-cluster-kafka-bootstrap 9092:9092"
echo ""
echo "   # RabbitMQ Management"
echo "   kubectl port-forward -n rabbitmq svc/rabbitmq-cluster 15672:15672"
echo "   # Access at: http://localhost:15672 (guest/guest)"
echo ""
echo "   # Backstage"
echo "   kubectl port-forward -n backstage svc/backstage 7007:7007"
echo "   # Access at: http://localhost:7007"
echo ""
echo "   # ArgoCD UI"
echo "   kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "   # Access at: https://localhost:8080"
echo ""
echo "3. Deploy example integrations:"
echo "   kubectl apply -f examples/camelk-integrations.yaml -n user1"
echo ""
echo "================================================"
echo "Setup Complete!"
echo "================================================"
