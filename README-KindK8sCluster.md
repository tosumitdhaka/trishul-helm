# Setup Custom Kind Cluster in WSL 2

This guide outlines the steps to set up a Kubernetes cluster using **Kind** inside **WSL 2 (Ubuntu)**. It includes a specific configuration for mapping ports for UI, SNMP Traps, Prometheus, and Grafana.

## Prerequisites
*/   Windows 10 or 11.
*   PowerShell (Administrator).

---

## 1. Update WSL
Open **PowerShell as Administrator** and run the following command to ensure the WSL kernel is up to date.

```powershell
wsl --update
```

## 2. Install Ubuntu
If you do not have Ubuntu installed, run the following in **PowerShell**:

```powershell
wsl --install -d Ubuntu
```
*Note: You will be prompted to create a UNIX username and password once the installation finishes.*

## 3. Update Ubuntu
Open your Ubuntu terminal (type `wsl` in PowerShell or open "Ubuntu" from the Start menu) and update the package lists.

```bash
sudo apt update && sudo apt upgrade -y
```

---

## 4. Install Docker Engine
Docker is required to run Kind nodes. Run the following commands inside your **Ubuntu terminal**:

1.  **Install Docker dependencies:**
    ```bash
    sudo apt install -y docker.io
    ```

2.  **Add your user to the Docker group** (allows running docker without `sudo`):
    ```bash
    sudo usermod -aG docker $USER
    newgrp docker
    ```

3.  **Enable Systemd (Important for WQL):**
    Edit the WSL configuration file:
    ```bash
    sudo nano /etc/wsl.conf
    ```
    Add these lines:
    ```ini
    [boot]
    systemd=true
    ```
    Save (`Ctrl+O`, `Enter`) and Exit (`Ctrl+X`).

4.  **Restart WSL:**
    Close the Ubuntu terminal. In **PowerShell**, run:
    ```powershell
    wsl --shutdown
    ```
    Open Ubuntu again and verify Docker is running:
    ```bash
    docker ps
    ```

---

## 5. Install Kind with Custom Config

1.  **Download and Install Kind:**
    ```bash
    # For AMD64 / x86_64
    [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    ```

2.  **Create the Configuration File:**
    Create a file named `kind-config.yaml`:
    ```bash
    nano kind-config.yaml
    ```

3.  **Paste the following content:**
    ```yaml
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
      - containerPort: 30093    # Prometheus Alertmanager
        hostPort: 30093
        protocol: TCP
      - containerPort: 30300    # Prometheus Grafana
        hostPort: 30300
        protocol: TCP
    ```
    Save and Exit.

4.  **Create the Cluster:**
    ```bash
    kind create cluster --config kind-config.yaml --name trishul-cluster
    ```

---

## 6. Install Kubectl & Set Namespace

1.  **Install Kubectl:**
    ```bash
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
    ```

2.  **Create Namespace `trishul`:**
    ```bash
    kubectl create namespace trishul
    ```

3.  **Set Context to Namespace:**
    This ensures all future `kubectl` commands apply to the `trishul` namespace by default.
    ```bash
    kubectl config set-context --current --namespace=trishul
    ```

---

## 7. Install Helm
Helm is the package manager for Kubernetes.

```bash
curl https:/7raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

## Verification
Run the following to ensure everything is set up correctly:

```bash
# Check Cluster Nodes
kubectl get nodes

# Check Current Namespace (Should be trishul)
kubectl config view --minify | grep namespace

# Check Helm Version
helm version
```
