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

## ✅ Final Cluster Health Check (After Upgrade)

```bash
kubectl get nodes
/usr/local/bin/rke2 --version
kubectl get pods -A
```

---

## ✅ RKE2 Node Types: Control Plane vs Worker Node

| Node Type               | Service Command                  | Binary Path             | Runs                      |
|-------------------------|----------------------------------|-------------------------|---------------------------|
| Control Plane (Master)  | `systemctl start rke2-server`    | `/usr/local/bin/rke2 server` | API server, Scheduler, Controller, Embedded etcd |
| Worker (Agent)          | `systemctl start rke2-agent`     | `/usr/local/bin/rke2 agent`  | Kubelet, Container Runtime (No etcd, No API server) |

---

## ✅ Must-Know Service Commands (Control Plane & Worker)

| Action                | Control Plane Node             | Worker Node            |
|-----------------------|--------------------------------|------------------------|
| Reload systemd        | `systemctl daemon-reload`      | `systemctl daemon-reload` |
| Enable service        | `systemctl enable rke2-server` | `systemctl enable rke2-agent` |
| Start service         | `systemctl start rke2-server`  | `systemctl start rke2-agent` |
| Check status          | `systemctl status rke2-server` | `systemctl status rke2-agent` |
| View logs             | `journalctl -u rke2-server -f` | `journalctl -u rke2-agent -f` |

---

## ✅ Cluster Interaction (Run on Control Plane Node Only)

| Task                  | Command                          |
|-----------------------|----------------------------------|
| Export kubeconfig     | `export KUBECONFIG=/etc/rancher/rke2/rke2.yaml` |
| Check nodes           | `kubectl get nodes`             |
| Check pods            | `kubectl get pods -A`           |
| Check RKE2 version    | `/usr/local/bin/rke2 --version` |
| Take etcd snapshot    | `/usr/local/bin/rke2 etcd-snapshot save` |

---

## ✅ Important Folder Paths

| Purpose                   | Path                                     |
|---------------------------|-----------------------------------------|
| RKE2 binaries             | `/usr/local/bin/`                      |
| RKE2 config               | `/etc/rancher/rke2/config.yaml`        |
| Airgap images             | `/var/lib/rancher/rke2/agent/images/`  |
| Kubeconfig (master only)  | `/etc/rancher/rke2/rke2.yaml`          |
| Logs (systemd journal)    | `journalctl -u rke2-server -f` or `journalctl -u rke2-agent -f` |

---

## ✅ Joining New Nodes

### 📌 Get Cluster Token (Run on First Master Node)

```bash
cat /var/lib/rancher/rke2/server/node-token
```

---

### ✅ Add Extra Control Plane Node (HA Master)

On the **new master node**:

1. **Create config file:**

```bash
mkdir -p /etc/rancher/rke2/

cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://<EXISTING-MASTER-IP>:9345
token: <CLUSTER-TOKEN>
cni: calico
node-name: master-2
EOF
```

2. **Install RKE2 (airgap way):**

```bash
INSTALL_RKE2_ARTIFACT_PATH=/rke2-artifacts sh install.sh
```

3. **Enable and start service:**

```bash
systemctl daemon-reload
systemctl enable rke2-server
systemctl start rke2-server
```

---

### ✅ Add Extra Worker Node

On the **worker node**:

1. **Create config file:**

```bash
mkdir -p /etc/rancher/rke2/

cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://<MASTER-IP>:9345
token: <CLUSTER-TOKEN>
cni: calico
node-name: worker-1
EOF
```

2. **Install RKE2 (airgap way):**

```bash
INSTALL_RKE2_ARTIFACT_PATH=/rke2-artifacts sh install.sh
```

3. **Enable and start service:**

```bash
systemctl daemon-reload
systemctl enable rke2-agent
systemctl start rke2-agent
```

---

### ✅ Verify Node Join Status (Run on Control Plane)

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes
```

✅ You should see multiple **ControlPlane** and **Worker** nodes in **Ready** state.

---

## ✅ Manual Airgap RKE2 Upgrade (Example: v1.24 → v1.28)

For **both master and worker nodes**:

1. Place new airgap artifacts (`rke2`, `rke2-images.tar`) at `/rke2-artifacts/`.
2. Run the installer:

```bash
INSTALL_RKE2_ARTIFACT_PATH=/rke2-artifacts sh install.sh
```

3. Restart the RKE2 service:

```bash
# For master:
systemctl restart rke2-server

# For worker:
systemctl restart rke2-agent
```

4. Validate cluster:

```bash
kubectl get nodes
```

---

## ✅ Optional: Automated Upgrade (Production Grade)

**Pre-requisite:** Private airgap registry with following images:

- `rancher/rke2-upgrade`
- `rancher/system-upgrade-controller`
- `rancher/kubectl`

Use `system-upgrade-controller` for automated upgrades.

> 📌 Refer Rancher official docs for full setup.

---

## ✅ etcd Backup (Control Plane Only)

```bash
/usr/local/bin/rke2 etcd-snapshot save
```

---

## ✅ Troubleshooting Quick Reference

| Problem                          | Solution                                   |
|----------------------------------|-------------------------------------------|
| Node not joining                 | Verify server IP, token, network/firewall |
| Service won’t start              | Check logs: `journalctl -u rke2-* -f`     |
| Kubeconfig file missing (worker) | Exists only on master nodes              |
| Cluster version check            | `/usr/local/bin/rke2 --version`          |
| etcd backup                      | Run `rke2 etcd-snapshot save` on master |

---

## ✅ Summary

This guide covers:

✅ Airgap RKE2 installation (Single and Multi-node)  
✅ etcd snapshot backup  
✅ Manual upgrade (v1.24 → v1.28 example)  
✅ Optional automated upgrade using system-upgrade-controller  
✅ Adding new control plane and worker nodes  
✅ Must-know service and cluster commands  
✅ Folder paths  
✅ Troubleshooting common RKE2 issues  

---

📚 **Official Docs:**  
[Rancher RKE2 Documentation](https://docs.rke2.io/)

🐛 **For Bugs / Issues:**  
[RKE2 GitHub Issues](https://github.com/rancher/rke2/issues)


