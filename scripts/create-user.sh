#!/bin/bash
set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <username>"
    echo "Example: $0 user1"
    exit 1
fi

USERNAME=$1
NAMESPACE="user-${USERNAME}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Creating user namespace: ${NAMESPACE}"

# Create user overlay directory
mkdir -p "${REPO_ROOT}/overlays/users/${USERNAME}"

# Create kustomization.yaml for the user
cat > "${REPO_ROOT}/overlays/users/${USERNAME}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NAMESPACE}

bases:
  - ../../../base/user-namespace

nameSuffix: ""

replacements:
  - source:
      kind: Namespace
      name: user-template
    targets:
      - select:
          kind: Namespace
        fieldPaths:
          - metadata.name
      - select:
          kind: ResourceQuota
        fieldPaths:
          - metadata.namespace
      - select:
          kind: LimitRange
        fieldPaths:
          - metadata.namespace
      - select:
          kind: ServiceAccount
        fieldPaths:
          - metadata.namespace
      - select:
          kind: Role
        fieldPaths:
          - metadata.namespace
      - select:
          kind: RoleBinding
        fieldPaths:
          - metadata.namespace
          - subjects.0.namespace
      - select:
          kind: NetworkPolicy
        fieldPaths:
          - metadata.namespace
      - select:
          kind: IntegrationPlatform
        fieldPaths:
          - metadata.namespace
      - select:
          kind: ConfigMap
        fieldPaths:
          - metadata.namespace

patches:
  - patch: |-
      - op: replace
        path: /metadata/name
        value: ${NAMESPACE}
    target:
      kind: Namespace
      name: user-template
EOF

# Create ArgoCD Application for the user
cat > "${REPO_ROOT}/argocd/applications/${USERNAME}.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${USERNAME}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-org>/<your-repo>.git  # CHANGE THIS
    targetRevision: main
    path: overlays/users/${USERNAME}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  syncWaves:
    - wave: 3
EOF

# Update argocd/kustomization.yaml to include the new user application
if ! grep -q "${USERNAME}.yaml" "${REPO_ROOT}/argocd/kustomization.yaml"; then
    echo "  - applications/${USERNAME}.yaml" >> "${REPO_ROOT}/argocd/kustomization.yaml"
fi

echo ""
echo "✅ User ${USERNAME} configuration created!"
echo ""
echo "Next steps:"
echo "1. Review the generated files in overlays/users/${USERNAME}/"
echo "2. Update the repoURL in argocd/applications/${USERNAME}.yaml"
echo "3. Commit and push changes:"
echo "   git add ."
echo "   git commit -m 'Add user ${USERNAME}'"
echo "   git push"
echo ""
echo "4. ArgoCD will automatically sync and create the namespace"
echo "   Or manually sync:"
echo "   kubectl apply -f argocd/applications/${USERNAME}.yaml"
echo ""
echo "5. Verify deployment:"
echo "   kubectl get namespace ${NAMESPACE}"
echo "   kubectl get all -n ${NAMESPACE}"
echo ""
echo "To deploy integrations as ${USERNAME}:"
echo "   kubectl apply -f your-integration.yaml -n ${NAMESPACE}"
