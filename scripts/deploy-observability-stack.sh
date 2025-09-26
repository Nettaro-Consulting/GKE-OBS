#!/bin/bash
[cite_start]# [cite: 634-698]
set -e
echo "--- Desplegando Stack de Observabilidad en GKE Autopilot ---"

# --- Variables ---
# Utiliza variables de entorno existentes o valores por defecto
PROJECT_ID=${PROJECT_ID:-"tu-proyecto-gcp"}
CLUSTER_NAME=${CLUSTER_NAME:-"observability-cluster"}
REGION=${REGION:-"us-central1"}
REPO_URL=${REPO_URL:-"https://github.com/tu-usuario/observability-stack.git"}

# --- 1. Crear clúster GKE Autopilot (si no existe) ---
echo "Verificando clúster GKE Autopilot..."
if ! gcloud container clusters describe $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID &> /dev/null; then
  echo "Creando clúster GKE Autopilot '$CLUSTER_NAME'..."
  gcloud container clusters create-auto $CLUSTER_NAME \
      --region=$REGION \
      --project=$PROJECT_ID \
      --enable-autorepair \
      --enable-autoupgrade \
      --enable-ip-alias
else
  echo "El clúster '$CLUSTER_NAME' ya existe."
fi

# --- 2. Obtener credenciales ---
echo "Obteniendo credenciales del clúster..."
gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID

# --- 3. Instalar ArgoCD (si no existe) ---
echo "Verificando instalación de ArgoCD..."
if ! kubectl get namespace argocd &> /dev/null; then
  echo "Instalando ArgoCD..."
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
else
  echo "ArgoCD ya está instalado."
fi

# --- 4. Esperar a que ArgoCD esté listo ---
echo "Esperando a que ArgoCD esté listo..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# --- 5. Aplicar Application of Apps ---
echo "Desplegando Application of Apps..."
# Usamos un here-document para sustituir la variable REPO_URL
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: observability-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: apps
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

# --- 6. Obtener password de ArgoCD ---
echo "--- ¡Despliegue iniciado! ---"
echo "La contraseña de ArgoCD Admin es:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# --- 7. Instrucciones finales ---
echo "Para acceder a los servicios (espera a que se desplieguen):"
echo "  ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Grafana:   kubectl port-forward svc/grafana -n monitoring 3000:80"
echo "Monitorea el progreso en la UI de ArgoCD o con: kubectl get applications -n argocd -w"