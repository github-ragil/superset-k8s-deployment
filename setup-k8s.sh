#!/bin/bash
set -e

# Default values
K8S_VERSION="1.29"  # Default major.minor version only
FULL_K8S_VERSION="" # Variable to store full package version
NODE_TYPE="master"  # Default is master node
JOIN_TOKEN=""
JOIN_ADDRESS=""
DISCOVERY_TOKEN_HASH=""
INSTALL_CALICO=true
INSTALL_LOCAL_PATH=true
INSTALL_HELM=true

# Help message
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --node-type    Node type (master, worker, or only-setup)"
    echo "  --pod-network-cidr   Pod network CIDR (e.g., 192.168.0.0/16)"
    echo "  --apiserver-advertise-address   API server advertise address"
    echo "  --control-plane-endpoint   Control plane endpoint"
    echo "  --service-cidr    Service CIDR (e.g., 10.96.0.0/12)"
    echo "  --kubernetes-version   Kubernetes version (e.g., 1.29, 1.28)"
    echo "  --join-token    Join token for worker nodes"
    echo "  --join-address  Master node address for worker nodes"
    echo "  --discovery-token-hash  Discovery token hash for worker nodes"
    echo "  --install-calico   Install Calico network plugin (true/false)"
    echo "  --install-local-path  Install local-path storage provisioner (true/false)"
    echo "  --install-helm    Install Helm package manager (true/false)"
    echo "  --help            Display this help message"
    exit 0
}

# Parse command line arguments
KUBEADM_ARGS=""
while [[ $# -gt 0 ]]; do 
    case $1 in
        --help)
            show_help
            ;;
        --node-type)
            NODE_TYPE=$2
            shift 2
            ;;
        --kubernetes-version)
            K8S_VERSION=$2
            shift 2
            ;;
        --join-token)
            JOIN_TOKEN=$2
            shift 2
            ;;
        --join-address)
            JOIN_ADDRESS=$2
            shift 2
            ;;
        --discovery-token-hash)
            DISCOVERY_TOKEN_HASH=$2
            shift 2
            ;;
        --install-calico)
            INSTALL_CALICO=$2
            shift 2
            ;;
        --install-local-path)
            INSTALL_LOCAL_PATH=$2
            shift 2
            ;;
        --install-helm)
            INSTALL_HELM=$2
            shift 2
            ;;
        --pod-network-cidr|--apiserver-advertise-address|--control-plane-endpoint|--service-cidr)
            KUBEADM_ARGS="$KUBEADM_ARGS $1 $2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate node type
if [[ "$NODE_TYPE" != "master" && "$NODE_TYPE" != "worker" && "$NODE_TYPE" != "only-setup" ]]; then
    echo "Error: Node type must be either 'master', 'worker', or 'only-setup'"
    exit 1
fi

# Check required arguments for worker nodes
if [[ "$NODE_TYPE" == "worker" ]]; then
    if [[ -z "$JOIN_TOKEN" || -z "$JOIN_ADDRESS" || -z "$DISCOVERY_TOKEN_HASH" ]]; then
        echo "Error: Worker nodes require --join-token, --join-address, and --discovery-token-hash"
        exit 1
    fi
fi

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with root privileges"
   exit 1
fi

echo "Starting Kubernetes initialization script..."
echo "Node type: ${NODE_TYPE}"
echo "Kubernetes Version: ${K8S_VERSION}"

# Disable swap (idempotent)
echo "Disabling swap..."
swapoff -a
if grep -q "^/swap" /etc/fstab; then
    sed -i '/^\/swap/d' /etc/fstab
fi
if grep -q "swap" /etc/fstab; then
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
fi

# Enable kernel modules (idempotent)
echo "Enabling required kernel modules..."
KERNEL_MODULES_FILE="/etc/modules-load.d/k8s.conf"
KERNEL_MODULES=("overlay" "br_netfilter")

# Create or update modules file
if [ ! -f "$KERNEL_MODULES_FILE" ]; then
    printf "%s\n" "${KERNEL_MODULES[@]}" > "$KERNEL_MODULES_FILE"
else
    for module in "${KERNEL_MODULES[@]}"; do
        if ! grep -q "^$module\$" "$KERNEL_MODULES_FILE"; then
            echo "$module" >> "$KERNEL_MODULES_FILE"
        fi
    done
fi

# Load modules if not already loaded
for module in "${KERNEL_MODULES[@]}"; do
    if ! lsmod | grep -q "^$module"; then
        modprobe "$module"
    fi
done

# Network settings (idempotent)
echo "Adjusting network settings..."
SYSCTL_FILE="/etc/sysctl.d/k8s.conf"
SYSCTL_SETTINGS=(
    "net.bridge.bridge-nf-call-iptables=1"
    "net.bridge.bridge-nf-call-ip6tables=1"
    "net.ipv4.ip_forward=1"
)

# Create or update sysctl file
touch "$SYSCTL_FILE"
for setting in "${SYSCTL_SETTINGS[@]}"; do
    key=$(echo "$setting" | cut -d= -f1)
    value=$(echo "$setting" | cut -d= -f2)
    
    if grep -q "^$key" "$SYSCTL_FILE"; then
        # Update existing setting
        sed -i "s/^$key.*/$key = $value/" "$SYSCTL_FILE"
    else
        # Add new setting
        echo "$key = $value" >> "$SYSCTL_FILE"
    fi
done

# Apply sysctl settings
sysctl --system

# Install containerd (idempotent)
echo "Installing containerd..."
if ! command -v containerd &> /dev/null; then
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common

    # Add Docker repository (For containerd)
    DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"
    if [ ! -f "$DOCKER_KEYRING" ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o "$DOCKER_KEYRING"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_KEYRING] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    apt-get update
    apt-get install -y containerd.io
fi

# Configure containerd (idempotent)
echo "Configuring containerd..."
CONTAINERD_CONFIG="/etc/containerd/config.toml"
if [ ! -f "$CONTAINERD_CONFIG" ] || ! grep -q "SystemdCgroup = true" "$CONTAINERD_CONFIG" 2>/dev/null; then
    mkdir -p /etc/containerd
    containerd config default | tee "$CONTAINERD_CONFIG" > /dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' "$CONTAINERD_CONFIG"
    systemctl restart containerd
fi

# Install kubeadm, kubelet, kubectl (idempotent)
echo "Installing kubeadm, kubelet, kubectl..."
if ! command -v kubeadm &> /dev/null; then
    REPO_VERSION=$(echo "$K8S_VERSION" | cut -d. -f1-2)
    echo "Adding Kubernetes repository (version: ${REPO_VERSION})..."
    
    K8S_KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
    if [ ! -f "$K8S_KEYRING" ]; then
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v${REPO_VERSION}/deb/Release.key | gpg --dearmor -o "$K8S_KEYRING"
        echo "deb [signed-by=$K8S_KEYRING] https://pkgs.k8s.io/core:/stable:/v${REPO_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    fi

    apt-get update
    
    # Package version retrieval and validation
    FULL_K8S_VERSION=$(apt-cache madison kubeadm | grep "${K8S_VERSION}" | head -1 | awk '{print $3}')
    if [ -z "$FULL_K8S_VERSION" ]; then
        echo "Error: No package found for Kubernetes version ${K8S_VERSION}"
        echo "Available versions:"
        apt-cache madison kubeadm | grep -oP '1\.\d+\.\d+-\d+' | sort -u
        exit 1
    fi

    echo "Installing Kubernetes ${FULL_K8S_VERSION}..."
    apt-get install -y --allow-change-held-packages "kubelet=${FULL_K8S_VERSION}" "kubeadm=${FULL_K8S_VERSION}" "kubectl=${FULL_K8S_VERSION}"
    apt-mark hold kubelet kubeadm kubectl
fi

# If only-setup is specified, exit here
if [[ "$NODE_TYPE" == "only-setup" ]]; then
    echo "Setup completed successfully!"
    echo "Kubernetes components have been installed, but no cluster has been initialized or joined."
    echo ""
    echo "To initialize a master node later, run:"
    echo "  $0 --node-type master [other options]"
    echo "To join as a worker node later, run:"
    echo "  $0 --node-type worker --join-token TOKEN --join-address ADDRESS --discovery-token-hash HASH"
    
    echo "Installed versions:"
    kubectl version --client 2>/dev/null || echo "kubectl not configured"
    kubeadm version
    exit 0
fi

# Reset existing cluster configuration (if any)
echo "Cleaning up existing cluster configuration..."
if command -v kubeadm &> /dev/null; then
    kubeadm reset -f > /dev/null 2>&1 || true
fi
rm -rf /etc/cni/net.d/* > /dev/null 2>&1 || true
rm -rf /var/lib/cni/ > /dev/null 2>&1 || true

# Clean up .kube directory
if [ -n "$SUDO_USER" ]; then
    USER_HOME="/home/$SUDO_USER"
    echo "Cleanup: Removing .kube directory for user $SUDO_USER"
    rm -rf "$USER_HOME/.kube" > /dev/null 2>&1 || true
else
    echo "Cleanup: Removing .kube directory for root user"
    rm -rf "$HOME/.kube/" > /dev/null 2>&1 || true
fi

# Reset iptables rules
echo "Resetting iptables rules..."
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X > /dev/null 2>&1 || true

if [[ "$NODE_TYPE" == "master" ]]; then
    # Initialize master node
    echo "Initializing master node..."
    echo "Using kubeadm init arguments: $KUBEADM_ARGS"
    kubeadm init $KUBEADM_ARGS --ignore-preflight-errors=all
    
    # Configure kubectl
    echo "Configuring kubectl..."
    if [ -n "$SUDO_USER" ]; then
        USER_HOME="/home/$SUDO_USER"
        mkdir -p "$USER_HOME/.kube"
        cp -i /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
        chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$USER_HOME/.kube"
        echo "Created kubectl configuration for user $SUDO_USER"
    else
        mkdir -p "$HOME/.kube"
        cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
        echo "Created kubectl configuration for root user"
    fi
    
    # Display join command
    echo "Displaying join command for worker nodes..."
    kubeadm token create --print-join-command
    
    # Remove control-plane taint to allow scheduling pods on master nodes
    echo "Removing control-plane taint from all nodes..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- > /dev/null 2>&1 || \
        echo "Warning: Failed to remove control-plane taint (might not have any nodes yet)"
    
    # Install Calico if requested
    if [[ "$INSTALL_CALICO" == "true" ]]; then
        echo "Installing Calico networking..."
        kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml > /dev/null 2>&1 || \
            echo "Error: Failed to install Calico"
    fi
    
    # Install local-path provisioner if requested
    if [[ "$INSTALL_LOCAL_PATH" == "true" ]]; then
        echo "Installing local-path storage provisioner..."
        kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml > /dev/null 2>&1 || \
            echo "Error: Failed to install local-path provisioner"
        
        echo "Configuring local-path as default storage class..."
        kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' > /dev/null 2>&1 || \
            echo "Error: Failed to set local-path as default storage class"
    fi
    
    # Install Helm if requested
    if [[ "$INSTALL_HELM" == "true" ]]; then
        echo "Installing Helm 3..."
        curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash > /dev/null 2>&1 || \
            echo "Error: Failed to install Helm 3"
        echo "Helm version: $(helm version --short 2>/dev/null || echo 'Helm not installed')"
    fi
    
    echo "Master node initialization complete!"
else
    # Join worker node
    echo "Joining worker node to cluster..."
    kubeadm join "${JOIN_ADDRESS}" --token "${JOIN_TOKEN}" --discovery-token-ca-cert-hash "${DISCOVERY_TOKEN_HASH}"
    
    echo "Worker node has joined the cluster!"
fi

echo "Installed versions:"
kubectl version --client 2>/dev/null || echo "kubectl not configured"
kubeadm version

echo "Kubernetes setup completed successfully!"
