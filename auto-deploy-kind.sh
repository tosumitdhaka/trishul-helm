#!/bin/bash

# ============================================
# Auto Deploy Script for Trishul Kind Cluster
# ============================================
# This script automates the deployment of Trishul
# to a Kind cluster with options for manual or auto mode

set -e

# ============================================
# Configuration
# ============================================
KIND_CLUSTER_NAME="trishul-cluster"
NAMESPACE="trishul"
HELM_RELEASE_NAME="trishul"
GHCR_REGISTRY="ghcr.io/tosumitdhaka/trishul:2.1.7"
HELM_CHART_DIR="trishul-helm"
GHCR_TOKEN="${GHCR_TOKEN:-}"

# Embedded Kind Cluster Configuration
read -r -d '' KIND_CONFIG << 'EOF' || true
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080    # UI
    hostPort: 30080
    protocol: TCP
  - containerPort: 30162    # Trap Receiver
    hostPort: 30162
    protocol: UDP
  - containerPort: 30090    # Prometheus
    hostPort: 30090
    protocol: TCP
  - containerPort: 30091    # Prometheus Alertmanager
    hostPort: 30091
    protocol: TCP
  - containerPort: 30092    # Prometheus Grafana
    hostPort: 30092
    protocol: TCP
  - containerPort: 30081    # UI 2
    hostPort: 30081
    protocol: TCP
  - containerPort: 30082    # UI 3
    hostPort: 30082
    protocol: TCP
EOF

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# Functions
# ============================================

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if a command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed"
        return 1
    fi
    print_success "$1 is installed"
}

# ============================================
# Step 1: Create Kind Cluster
# ============================================
create_kind_cluster() {
    print_header "Step 1: Creating Kind Cluster"
    
    if kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
        print_success "Kind cluster '$KIND_CLUSTER_NAME' already exists"
    else
        print_info "Creating Kind cluster '$KIND_CLUSTER_NAME'..."
        
        # Create temporary config file with embedded configuration
        local kind_config_temp=$(mktemp)
        echo "$KIND_CONFIG" > $kind_config_temp
        
        print_info "Using embedded kind configuration with port mappings"
        kind create cluster --name $KIND_CLUSTER_NAME --config $kind_config_temp
        
        # Clean up temp config
        rm -f $kind_config_temp
        
        print_success "Kind cluster '$KIND_CLUSTER_NAME' created"
    fi
    
    # Set context to the cluster
    print_info "Setting kubectl context to '$KIND_CLUSTER_NAME'..."
    kubectl cluster-info --context kind-$KIND_CLUSTER_NAME
    print_success "Context set to kind-$KIND_CLUSTER_NAME"
}

# ============================================
# Step 2: Create Namespace
# ============================================
create_namespace() {
    print_header "Step 2: Creating Namespace"
    
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        print_success "Namespace '$NAMESPACE' already exists"
    else
        print_info "Creating namespace '$NAMESPACE'..."
        kubectl create namespace $NAMESPACE
        print_success "Namespace '$NAMESPACE' created"
    fi
}

# ============================================
# Step 3: Set Context to Namespace
# ============================================
set_namespace_context() {
    print_header "Step 3: Setting Kubernetes Context"
    
    print_info "Setting default namespace to '$NAMESPACE'..."
    kubectl config set-context --current --namespace=$NAMESPACE
    print_success "Default namespace set to '$NAMESPACE'"
    
    # Verify context
    CURRENT_CONTEXT=$(kubectl config current-context)
    CURRENT_NAMESPACE=$(kubectl config view --minify --output 'jsonpath={.contexts[0].context.namespace}')
    print_info "Current context: $CURRENT_CONTEXT"
    print_info "Current namespace: $CURRENT_NAMESPACE"
}

# ====================================================
# Step 4: Login to GHCR and Create Image Pull Secret    
# ====================================================
login_ghcr() {
    print_header "Step 4: Login to GitHub Container Registry"
    
    if [ -z "$GHCR_TOKEN" ]; then
        print_warning "GHCR_TOKEN environment variable not set"
        read -sp "Enter GitHub PAT token (will not be displayed): " GHCR_TOKEN
        echo ""
    fi
    
    if [ -z "$GHCR_TOKEN" ]; then
        print_error "GitHub PAT token is required"
        return 1
    fi
    
    print_info "Logging in to ghcr.io..."
    echo $GHCR_TOKEN | docker login ghcr.io -u tosumitdhaka --password-stdin
    print_success "Successfully logged in to ghcr.io"
    
    # Create image pull secret in the namespace
    print_info "Creating image pull secret in namespace '$NAMESPACE'..."
    
    # Delete existing secret if it exists
    kubectl delete secret ghcr-secret -n $NAMESPACE --ignore-not-found=true
    
    # Create new secret
    kubectl create secret docker-registry ghcr-secret \
        --docker-server=ghcr.io \
        --docker-username=tosumitdhaka \
        --docker-password=$GHCR_TOKEN \
        -n $NAMESPACE
    
    print_success "Image pull secret created/updated"
}

# ============================================
# Step 5 & 6: Manual Mode
# ============================================
manual_mode() {
    print_header "Step 5 & 6: Manual Installation Mode"
    
    print_info "Pulling Helm chart from $GHCR_REGISTRY..."
    
    # Create temporary directory for pulling chart
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    print_info "Temporary directory: $TEMP_DIR"
    
    # Pull the OCI chart
    print_info "Pulling OCI chart..."
    helm pull oci://${GHCR_REGISTRY%:*} --version ${GHCR_REGISTRY##*:} --destination $TEMP_DIR
    
    if [ $? -ne 0 ]; then
        print_error "Failed to pull Helm chart from $GHCR_REGISTRY"
        return 1
    fi
    
    # Find the extracted chart directory
    CHART_TAR=$(ls $TEMP_DIR/*.tgz 2>/dev/null | head -1)
    if [ -z "$CHART_TAR" ]; then
        print_error "No chart tarball found"
        return 1
    fi
    
    print_info "Extracting chart from $CHART_TAR..."
    tar -xzf $CHART_TAR -C $TEMP_DIR
    
    # Find the chart directory
    EXTRACTED_CHART=$(find $TEMP_DIR -maxdepth 1 -type d ! -name "*" -prune | head -1)
    if [ -z "$EXTRACTED_CHART" ]; then
        EXTRACTED_CHART=$(ls -d $TEMP_DIR/trishul 2>/dev/null || ls -d $TEMP_DIR/*/ 2>/dev/null | head -1)
    fi
    
    if [ -z "$EXTRACTED_CHART" ] || [ ! -d "$EXTRACTED_CHART" ]; then
        print_error "Failed to extract Helm chart"
        return 1
    fi
    
    print_success "Chart extracted to $EXTRACTED_CHART"
    
    # Copy chart to helm directory
    print_info "Copying chart to $HELM_CHART_DIR directory..."
    if [ -d "$HELM_CHART_DIR" ]; then
        rm -rf $HELM_CHART_DIR
    fi
    cp -r $EXTRACTED_CHART $HELM_CHART_DIR
    
    # Extract values file
    VALUES_FILE="$HELM_CHART_DIR/values.yaml"
    if [ -f "$VALUES_FILE" ]; then
        print_success "Values file extracted to $VALUES_FILE"
        print_info "You can now edit the values file and run the auto mode"
        echo ""
        print_info "To deploy, run:"
        echo "  ./auto-deploy-kind.sh --mode auto"
    else
        print_warning "Values file not found in extracted chart"
    fi
    
    print_header "Manual Mode Complete"
    print_info "Exiting script. You can now manually configure values.yaml if needed."
    exit 0
}

# ============================================
# Step 5 & 7: Auto Mode
# ============================================
auto_mode() {
    print_header "Step 5 & 7: Auto Installation/Upgrade Mode"
    
    print_info "Installing/Upgrading Helm chart from $GHCR_REGISTRY..."
    
    # Check if values file exists in current directory
    local values_param=""
    if [ -f "values.yaml" ]; then
        values_param="--values values.yaml"
        print_info "Using values.yaml from current directory"
    else
        print_warning "values.yaml not found in current directory"
        print_info "Using default values from the chart"
    fi
    
    # Check if release already exists
    if helm list -n $NAMESPACE 2>/dev/null | grep -q "^${HELM_RELEASE_NAME}"; then
        print_info "Release '$HELM_RELEASE_NAME' already exists. Performing upgrade..."
        
        helm upgrade $HELM_RELEASE_NAME oci://${GHCR_REGISTRY%:*} \
            --version ${GHCR_REGISTRY##*:} \
            --namespace $NAMESPACE \
            --cleanup-on-fail \
            --wait=false \
            $values_param 2>/dev/null || {
            print_warning "Upgrade failed, attempting to uninstall and reinstall..."
            helm uninstall $HELM_RELEASE_NAME -n $NAMESPACE --wait=false
            sleep 3
            helm install $HELM_RELEASE_NAME oci://${GHCR_REGISTRY%:*} \
                --version ${GHCR_REGISTRY##*:} \
                --namespace $NAMESPACE \
                $values_param
        }
        
        print_success "Helm release upgraded successfully"
    else
        print_info "Installing new Helm release '$HELM_RELEASE_NAME'..."
        
        helm install $HELM_RELEASE_NAME oci://${GHCR_REGISTRY%:*} \
            --version ${GHCR_REGISTRY##*:} \
            --namespace $NAMESPACE \
            $values_param
        
        print_success "Helm release installed successfully"
    fi
    
    # Wait for 10 seconds
    print_info "Waiting 10 seconds for pods to initialize..."
    sleep 10
    
    # Print pod status
    print_header "Pod Status After Deployment"
    kubectl get pods -n $NAMESPACE -o wide
    
    # Additional status information
    echo ""
    print_header "Services"
    kubectl get svc -n $NAMESPACE
    
    echo ""
    print_header "Deployment Status"
    helm list -n $NAMESPACE | grep $HELM_RELEASE_NAME || print_warning "Release not found"
    
    print_success "Auto deployment completed!"
}

# ============================================
# Display usage
# ============================================
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --mode MODE            Deployment mode: 'manual' or 'auto' (default: interactive)
    --cluster NAME         Kind cluster name (default: trishul-cluster)
    --namespace NS         Kubernetes namespace (default: trishul)
    --token TOKEN          GitHub PAT token (can also use GHCR_TOKEN env variable)
    --force                Force clean installation (uninstall existing release first)
    -h, --help             Display this help message

Modes:
    interactive            Prompts user to choose between manual and auto mode
    manual                 Pull charts to local directory and extract values.yaml
    auto                   Directly install/upgrade charts from registry

Examples:
    $0                                    # Interactive mode
    $0 --mode manual                      # Manual mode
    $0 --mode auto --token <PAT>          # Auto mode with token
    $0 --mode auto --force                # Auto mode with clean installation
    $0 --cluster my-cluster --namespace my-ns --mode auto

EOF
}

# ============================================
# Main Script
# ============================================
main() {
    local mode="interactive"
    local force_install=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                mode="$2"
                shift 2
                ;;
            --cluster)
                KIND_CLUSTER_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --token)
                GHCR_TOKEN="$2"
                shift 2
                ;;
            --force)
                force_install=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    print_header "Trishul Auto-Deploy Kind Script"
    print_info "Cluster: $KIND_CLUSTER_NAME"
    print_info "Namespace: $NAMESPACE"
    print_info "Mode: $mode"
    if [ "$force_install" = true ]; then
        print_warning "Force installation enabled - existing release will be removed"
    fi
    
    # Check prerequisites
    print_header "Checking Prerequisites"
    check_command kubectl || exit 1
    check_command helm || exit 1
    check_command kind || exit 1
    check_command docker || exit 1
    
    # Execute steps
    create_kind_cluster
    create_namespace
    set_namespace_context
    login_ghcr || exit 1
    
    # Handle force installation
    if [ "$force_install" = true ]; then
        print_warning "Force flag enabled - uninstalling existing release if present..."
        helm uninstall $HELM_RELEASE_NAME -n $NAMESPACE --wait=false 2>/dev/null || print_info "No existing release to remove"
        sleep 3
    fi
    
    # Interactive mode: ask user for mode
    if [ "$mode" = "interactive" ]; then
        echo ""
        echo -e "${BLUE}Choose deployment mode:${NC}"
        echo "1) Manual - Pull charts and extract values (default)"
        echo "2) Auto - Install/upgrade directly from registry"
        read -p "Enter choice (1 or 2): " user_choice
        
        case $user_choice in
            1|"")
                mode="manual"
                ;;
            2)
                mode="auto"
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    # Execute mode
    case $mode in
        manual)
            manual_mode
            ;;
        auto)
            auto_mode
            ;;
        *)
            print_error "Unknown mode: $mode"
            usage
            exit 1
            ;;
    esac
    
    print_success "Script execution completed!"
}

# Run main function
main "$@"
