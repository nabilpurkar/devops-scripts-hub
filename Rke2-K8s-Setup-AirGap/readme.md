# RKE2 Airgap Installation and Upgrade Guide (v1.24.x to v1.28.x)

---

## 📋 Pre-Requisites (Common for All Nodes)

```bash
# Disable cloud network service
systemctl disable nm-cloud-setup.service
systemctl is-enabled nm-cloud-setup.service  # Ensure it shows "disabled"

# Required kernel modules
modprobe overlay
modprobe br_netfilter

# Sysctl network settings
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
echo 1 > /proc/sys/net/ipv4/ip_forward

# Disable SELinux (for now, until SELinux policies are managed properly)
setenforce 0
```

---

## 🧱 Step 1: Prepare Airgap Artifacts

### ✅ Download the following for your target version (on an internet machine):

| Version        | Binary                                                                                                | Images                                                                                                       | CNI Images                                                                                                          | SHA                                                                                            |
| -------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| 1.24.17+rke2r1 | [Binary](https://github.com/rancher/rke2/releases/download/v1.24.17%2Brke2r1/rke2.linux-amd64.tar.gz) | [Images](https://github.com/rancher/rke2/releases/download/v1.24.17%2Brke2r1/rke2-images.linux-amd64.tar.gz) | [Calico](https://github.com/rancher/rke2/releases/download/v1.24.17%2Brke2r1/rke2-images-calico.linux-amd64.tar.gz) | [SHA](https://github.com/rancher/rke2/releases/download/v1.24.17%2Brke2r1/sha256sum-amd64.txt) |
| 1.25.16+rke2r1 | [Binary](https://github.com/rancher/rke2/releases/download/v1.25.16%2Brke2r1/rke2.linux-amd64.tar.gz) | [Images](https://github.com/rancher/rke2/releases/download/v1.25.16%2Brke2r1/rke2-images.linux-amd64.tar.gz) | [Calico](https://github.com/rancher/rke2/releases/download/v1.25.16%2Brke2r1/rke2-images-calico.linux-amd64.tar.gz) | [SHA](https://github.com/rancher/rke2/releases/download/v1.25.16%2Brke2r1/sha256sum-amd64.txt) |
| 1.26.12+rke2r1 | [Binary](https://github.com/rancher/rke2/releases/download/v1.26.12%2Brke2r1/rke2.linux-amd64.tar.gz) | [Images](https://github.com/rancher/rke2/releases/download/v1.26.12%2Brke2r1/rke2-images.linux-amd64.tar.gz) | [Calico](https://github.com/rancher/rke2/releases/download/v1.26.12%2Brke2r1/rke2-images-calico.linux-amd64.tar.gz) | [SHA](https://github.com/rancher/rke2/releases/download/v1.26.12%2Brke2r1/sha256sum-amd64.txt) |
| 1.27.8+rke2r1  | [Binary](https://github.com/rancher/rke2/releases/download/v1.27.8%2Brke2r1/rke2.linux-amd64.tar.gz)  | [Images](https://github.com/rancher/rke2/releases/download/v1.27.8%2Brke2r1/rke2-images.linux-amd64.tar.gz)  | [Calico](https://github.com/rancher/rke2/releases/download/v1.27.8%2Brke2r1/rke2-images-calico.linux-amd64.tar.gz)  | [SHA](https://github.com/rancher/rke2/releases/download/v1.27.8%2Brke2r1/sha256sum-amd64.txt)  |
| 1.28.4+rke2r1  | [Binary](https://github.com/rancher/rke2/releases/download/v1.28.4%2Brke2r1/rke2.linux-amd64.tar.gz)  | [Images](https://github.com/rancher/rke2/releases/download/v1.28.4%2Brke2r1/rke2-images.linux-amd64.tar.gz)  | [Calico](https://github.com/rancher/rke2/releases/download/v1.28.4%2Brke2r1/rke2-images-calico.linux-amd64.tar.gz)  | [SHA](https://github.com/rancher/rke2/releases/download/v1.28.4%2Brke2r1/sha256sum-amd64.txt)  |

### ✅ SCP artifacts to airgap node:

```bash
scp -i <key.pem> -r <artifact_folder> ec2-user@<AIRGAP_NODE_IP>:/home/ec2-user
```

---

## 🚀 Step 2: RKE2 Server Installation (First Control Plane Node)

```bash
mkdir -p /rke2-artifacts
sudo cp /home/ec2-user/<artifact_folder>/* /rke2-artifacts/
cd /rke2-artifacts

tar xvf rke2.linux-amd64.tar.gz

# Download install script (on internet, then copy)
curl -sfL https://get.rke2.io -o install.sh

INSTALL_RKE2_ARTIFACT_PATH=/rke2-artifacts sh install.sh

systemctl daemon-reload
systemctl enable rke2-server
systemctl start rke2-server

journalctl -u rke2-server -f
```

Configure kubeconfig:

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/usr/local/bin/kubectl get nodes
```

---

## 🚀 Step 3: Agent (Worker Node) Installation

### ✅ On each agent:

```bash
mkdir -p /rke2-artifacts
sudo cp /home/ec2-user/<artifact_folder>/* /rke2-artifacts/
cd /rke2-artifacts

tar xvf rke2.linux-amd64.tar.gz
INSTALL_RKE2_ARTIFACT_PATH=/rke2-artifacts sh install.sh
```

### ✅ Create config file for agent:

```bash
mkdir -p /etc/rancher/rke2

cat <<EOF > /etc/rancher/rke2/config.yaml
token: <your-cluster-token>
server: https://<control-plane-node-ip>:9345
cni: calico
node-name: <unique-agent-name>
EOF

systemctl enable rke2-agent
systemctl start rke2-agent
```

---

## 🛡️ Step 4: Taking ETCD Snapshots (Before Upgrade)

```bash
/usr/local/bin/rke2 etcd-snapshot save
ls /var/lib/rancher/rke2/server/db/snapshots/
```

---

## 🔁 Step 5: Manual RKE2 Upgrade (v1.24.x → v1.28.x)

For **each server and agent node**:

### ✅ (A) Remove Old Images

```bash
rm -f /var/lib/rancher/rke2/agent/images/*.tar.gz
```

### ✅ (B) Place New Images

```bash
cp /rke2-artifacts/rke2-images*.tar.gz /var/lib/rancher/rke2/agent/images/
```

### ✅ (C) Run Installer

```bash
cd /rke2-artifacts
INSTALL_RKE2_ARTIFACT_PATH=/rke2-artifacts sh install.sh
```

### ✅ (D) Restart Services

```bash
systemctl restart rke2-server  # For control plane nodes
systemctl restart rke2-agent   # For worker nodes
```

### ✅ (E) Verify Upgrade

```bash
/usr/local/bin/rke2 --version
kubectl get nodes
```

---

## 🤖 Step 6: Automated Upgrade Using System Upgrade Controller (Optional for Airgap)

### ✅ Requirements to pre-pull to your private registry:

* `rancher/system-upgrade-controller:<version>`
* `rancher/kubectl:<version>`
* `rancher/rke2-upgrade:<target-rke2-version>`

> Example (for upgrading to 1.28.x):

* `rancher/system-upgrade-controller:v0.14.0`
* `rancher/kubectl:v1.28.0`
* `rancher/rke2-upgrade:v1.28.4-rke2r1`

### ✅ Steps:

1. Mirror required images to your private registry.
2. Update `system-upgrade-controller.yaml` with your registry path.
3. Apply it:

```bash
kubectl apply -f system-upgrade-controller.yaml
```

4. Create a `Plan` CRD for control-plane upgrade, then agents.

Official docs: [https://docs.rke2.io/upgrade/automated/](https://docs.rke2.io/upgrade/automated/)

---

### ✅ Final Verification (Post Upgrade)
```
kubectl get nodes
/usr/local/bin/rke2 --version
kubectl get pods -A
```

### ✅ RKE2 Node Type Differences (Control Plane vs Worker) + Useful Commands
### 🆚 Key Difference Between Control Plane Node vs Agent (Worker) Node (By Command)
Node Type	Which Service You Start	Which Binary	Purpose
Control Plane Node (Master)	systemctl start rke2-server	/usr/local/bin/rke2 server	Runs Kubernetes API server, controller, scheduler, embedded etcd
Agent Node (Worker)	systemctl start rke2-agent	/usr/local/bin/rke2 agent	Runs only kubelet and container runtime. No etcd, no API server

### ✅ Must-Know Commands for Both (Control plane & Worker)
🔹 Systemd Service Commands (Start / Stop / Enable / Status)
Action	Control Plane	Worker Node
Reload systemd	systemctl daemon-reload	systemctl daemon-reload
Enable Service	systemctl enable rke2-server	systemctl enable rke2-agent
Start Service	systemctl start rke2-server	systemctl start rke2-agent
Check Service Status	systemctl status rke2-server	systemctl status rke2-agent
Follow Logs	journalctl -u rke2-server -f	journalctl -u rke2-agent -f

### ✅ Cluster Interaction Commands (Control Plane Node Only)
Action	Command
Export kubeconfig file	export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
Check node status	kubectl get nodes
Check pods	kubectl get pods -A
Check version	/usr/local/bin/rke2 --version
Take etcd snapshot	/usr/local/bin/rke2 etcd-snapshot save

### ✅ Folder Paths to Know
Purpose	Path
RKE2 binaries	/usr/local/bin/
RKE2 config	/etc/rancher/rke2/config.yaml
Images (airgap tar files)	/var/lib/rancher/rke2/agent/images/
Kubeconfig	/etc/rancher/rke2/rke2.yaml
Logs (systemd)	journalctl -u rke2-server -f or journalctl -u rke2-agent -f

### ✅ How to Get <token> for Workers and Extra Masters:
On your first master node (control plane):
cat /var/lib/rancher/rke2/server/node-token


### ✅ How to Add Extra Control Plane Node (HA Master)
On new master node:

# Create config file
mkdir -p /etc/rancher/rke2/

cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://<any-existing-master-ip>:9345
token: <same-cluster-token-from-first-master>
cni: calico
node-name: master-2
EOF

# Run installer
INSTALL_RKE2_ARTIFACT_PATH=/rke2-artifacts sh install.sh

# Enable and start server service
systemctl daemon-reload
systemctl enable rke2-server
systemctl start rke2-server

---

### ✅ How to Add Extra Worker Node
On worker node:
# Create config file
mkdir -p /etc/rancher/rke2/

cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://<any-master-ip>:9345
token: <same-cluster-token-from-first-master>
cni: calico
node-name: worker-1
EOF

# Run installer
INSTALL_RKE2_ARTIFACT_PATH=/rke2-artifacts sh install.sh

# Enable and start agent service
systemctl daemon-reload
systemctl enable rke2-agent
systemctl start rke2-agent

--- 

✅ How to Verify After Adding Nodes:
Run on any Control Plane Node:

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes

You should now see:
Multiple masters (Ready, ControlPlane role)
Multiple workers (Ready, worker role)

---

### ✅ Troubleshooting Common Issues:
Problem	Fix
Node not joining	Double check server IP, token, firewall/ports
Service failing	journalctl -u rke2-server -f or journalctl -u rke2-agent -f
Kubeconfig file missing	Only exists on master nodes
Version check	/usr/local/bin/rke2 --version
Want etcd backup	/usr/local/bin/rke2 etcd-snapshot save (master only)

---
## ✅ Summary:
This guide covers:

✅ Air-gapped RKE2 Installation

Single Master (Control Plane)

Multi-master (HA Control Plane)

Worker (Agent) nodes

✅ etcd Snapshot Backup

How to take manual etcd backup from control plane nodes

✅ Manual RKE2 Upgrade (Airgap)

Example upgrade from v1.24 → v1.28

Both for server and agent nodes

Proper steps for placing new artifacts and restarting services

✅ Automated Upgrade Method (Optional - Production Grade)

Using system-upgrade-controller

Pre-requisite: Airgap Private Registry mirroring

Required images:

rancher/rke2-upgrade

rancher/system-upgrade-controller

rancher/kubectl

✅ Adding Extra Nodes

Extra control plane nodes (HA setup)

Extra worker nodes

Fetching node-token for joining

✅ Troubleshooting & Health Check Commands

Service status

Logs

Version check

Cluster node health (kubectl get nodes)

📚 Further References:
📖 Official Docs:
Rancher RKE2 Documentation

🐛 Issue Troubleshooting / Bug Reporting:
RKE2 GitHub Issues

