# Kubernetes Cluster Installation on AWS EC2

This project contains a step-by-step process to install a Kubernetes cluster manually on AWS EC2 using `kubeadm`.

## Architecture

```text
                    AWS VPC
                       |
        +--------------+--------------+
        |                             |
        |                             |
  Kubernetes Master              Kubernetes Worker
  EC2 Instance                   EC2 Instance
  Private IP: 172.31.20.108      Private IP: 172.31.31.246
        |                             |
        |        Kubernetes           |
        +------------ Network --------+
                       |
                    Calico CNI
```

### Components

- Kubernetes Master / Control Plane
- Kubernetes Worker Node
- containerd
- kubeadm
- kubelet
- kubectl
- Calico CNI
- AWS EC2
- AWS Security Groups

---

# 1. AWS EC2 Requirements

Create two Ubuntu EC2 instances.

### Master Node

```text
Private IP: 172.31.20.108
```

### Worker Node

```text
Private IP: 172.31.31.246
```

Both instances should:

- Be in the same VPC
- Preferably be in the same subnet
- Be able to communicate using their private IP addresses
- Use the same Kubernetes version
- Use the same container runtime

Recommended minimum for a learning environment:

```text
CPU:    2 vCPU
RAM:    4 GB
Disk:   20 GB+
OS:     Ubuntu
```

---

# 2. AWS Security Group Configuration

This is one of the most important steps.

The Master and Worker nodes must be able to communicate with each other.

For a lab environment, the easiest approach is to allow traffic between the Kubernetes node Security Group itself.

## Important Kubernetes Ports

### Master / Control Plane

| Port | Protocol | Purpose |
|---:|---|---|
| 6443 | TCP | Kubernetes API Server |
| 2379-2380 | TCP | etcd |
| 10250 | TCP | Kubelet API |
| 10257 | TCP | kube-controller-manager |
| 10259 | TCP | kube-scheduler |

### Worker Node

| Port | Protocol | Purpose |
|---:|---|---|
| 10250 | TCP | Kubelet API |
| 30000-32767 | TCP | NodePort Services |

### Calico

| Port | Protocol | Purpose |
|---:|---|---|
| 179 | TCP | BGP |
| 4789 | UDP | VXLAN, if VXLAN is used |
| 5473 | TCP | Calico Typha, if used |

For the Calico configuration used in this project, **TCP 179 between Kubernetes nodes is especially important**.

Do not expose Kubernetes internal ports publicly to `0.0.0.0/0` unless there is a specific reason.

Prefer:

```text
Source: Kubernetes node Security Group
```

instead of:

```text
0.0.0.0/0
```

---

# 3. Update Ubuntu

Run on both Master and Worker:

```bash
sudo apt update
sudo apt upgrade -y
```

Install basic packages:

```bash
sudo apt install -y curl wget apt-transport-https ca-certificates gpg
```

---

# 4. Disable Swap

Kubernetes requires swap to be disabled for the standard kubeadm setup.

Check:

```bash
free -h
```

Disable:

```bash
sudo swapoff -a
```

To permanently disable swap, comment the swap entry in:

```bash
sudo vi /etc/fstab
```

Then verify:

```bash
free -h
```

Swap should show:

```text
Swap: 0B 0B 0B
```

---

# 5. Install Container Runtime

This project uses:

```text
containerd
```

Install:

```bash
sudo apt install -y containerd
```

Create the configuration:

```bash
sudo mkdir -p /etc/containerd
```

Generate default configuration:

```bash
containerd config default | sudo tee /etc/containerd/config.toml
```

Enable SystemdCgroup:

```bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

Restart:

```bash
sudo systemctl restart containerd
```

Enable at boot:

```bash
sudo systemctl enable containerd
```

Check:

```bash
sudo systemctl status containerd
```

---

# 6. Install Kubernetes Components

Install:

```text
kubeadm
kubelet
kubectl
```

The same Kubernetes version should be installed on all nodes.

Check:

```bash
kubeadm version
kubectl version --client
kubelet --version
```

Enable kubelet:

```bash
sudo systemctl enable kubelet
```

The kubelet may show as inactive before `kubeadm init` or `kubeadm join`. This can be normal.

---

# 7. Initialize the Master Node

Run the master installation script:

```bash
chmod +x k8s-master.sh
./k8s-master.sh
```

The important command performed by the master setup is:

```bash
sudo kubeadm init
```

After successful initialization, configure kubectl:

```bash
mkdir -p $HOME/.kube

sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Test:

```bash
kubectl get nodes
```

Initially the master may show:

```text
NotReady
```

This is expected until a CNI network plugin is installed.

---

# 8. Install Calico CNI

Calico provides networking between Kubernetes pods and nodes.

Install Calico:

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.3/manifests/calico.yaml
```

Check:

```bash
kubectl get pods -n kube-system
```

Check specifically:

```bash
kubectl get pods -n kube-system -o wide | grep calico
```

The Calico node pods should eventually become:

```text
1/1 Running
```

---

# 9. Generate Worker Join Command

On the Master:

```bash
kubeadm token create --print-join-command
```

Example:

```bash
kubeadm join 172.31.20.108:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Copy this command.

---

# 10. Join Worker Node

SSH into the worker:

```bash
ssh ubuntu@172.31.31.246
```

Run the join command generated on the Master.

Example:

```bash
sudo kubeadm join 172.31.20.108:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Do not manually replace the token or hash.

---

# 11. Verify Worker from Master

Run on the Master:

```bash
kubectl get nodes
```

Expected:

```text
NAME               STATUS   ROLES           VERSION
ip-172-31-20-108   Ready    control-plane   v1.34.x
ip-172-31-31-246   Ready    <none>          v1.34.x
```

If the worker is `NotReady`, check:

```bash
kubectl describe node ip-172-31-31-246
```

---

# 12. Check Calico

Run:

```bash
kubectl get pods -n kube-system -o wide | grep calico
```

Expected:

```text
calico-kube-controllers-xxxxx   1/1   Running
calico-node-xxxxx               1/1   Running
calico-node-yyyyy               1/1   Running
```

## Important: Calico BGP Port

If Calico shows:

```text
0/1 Running
```

check TCP port 179.

From Master:

```bash
nc -vz 172.31.31.246 179
```

From Worker:

```bash
nc -vz 172.31.20.108 179
```

Expected:

```text
Connection to 172.31.31.246 179 port [tcp/bgp] succeeded!
```

If it says:

```text
Connection timed out
```

check the AWS Security Group.

---

# 13. Verify Kubernetes System Pods

Run:

```bash
kubectl get pods -n kube-system
```

You should eventually see the major components running:

```text
coredns
etcd
kube-apiserver
kube-controller-manager
kube-proxy
kube-scheduler
calico
```

---

# 14. Test Kubernetes with Nginx

Create a test deployment:

```bash
kubectl create deployment nginx --image=nginx
```

Check:

```bash
kubectl get deployments
```

Check pods:

```bash
kubectl get pods -o wide
```

---

# 15. Expose Nginx

Create a NodePort service:

```bash
kubectl expose deployment nginx \
  --type=NodePort \
  --port=80
```

Check:

```bash
kubectl get svc
```

Example:

```text
NAME    TYPE       CLUSTER-IP     PORT(S)
nginx   NodePort   10.96.x.x      80:30xxx/TCP
```

The `30xxx` port is the NodePort.

---

# 16. AWS Security Group for NodePort

If Kubernetes gives:

```text
80:30080/TCP
```

then AWS must allow:

```text
TCP 30080
```

in the EC2 Security Group.

For a lab, you can allow:

```text
Custom TCP
Port: 30000-32767
Source: Your IP
```

It is better to restrict the source to your own public IP rather than allowing:

```text
0.0.0.0/0
```

---

# 17. Access Nginx

Find the NodePort:

```bash
kubectl get svc nginx
```

Example:

```text
80:30080/TCP
```

Then access:

```text
http://<EC2-PUBLIC-IP>:30080
```

For example:

```text
http://YOUR-EC2-PUBLIC-IP:30080
```

The request reaches the Kubernetes NodePort and is forwarded to the Nginx pod.

---

# 18. Test Pod-to-Pod Networking

Create two test pods:

```bash
kubectl run test1 --image=busybox --command -- sleep 3600
```

```bash
kubectl run test2 --image=busybox --command -- sleep 3600
```

Check:

```bash
kubectl get pods -o wide
```

Get test2 IP:

```bash
kubectl get pod test2 -o wide
```

Then test connectivity:

```bash
kubectl exec -it test1 -- ping <TEST2-POD-IP>
```

This tests the Kubernetes pod network.

---

# 19. Useful Kubernetes Commands

Check nodes:

```bash
kubectl get nodes
```

Detailed node information:

```bash
kubectl get nodes -o wide
```

Check pods:

```bash
kubectl get pods
```

All namespaces:

```bash
kubectl get pods -A
```

Services:

```bash
kubectl get svc
```

Deployments:

```bash
kubectl get deployments
```

Describe a pod:

```bash
kubectl describe pod <pod-name>
```

View logs:

```bash
kubectl logs <pod-name>
```

Delete a pod:

```bash
kubectl delete pod <pod-name>
```

Delete deployment:

```bash
kubectl delete deployment nginx
```

Delete service:

```bash
kubectl delete service nginx
```

---

# 20. Check Kubernetes Ports

On the EC2 nodes:

```bash
sudo ss -lntp
```

Check Kubernetes API:

```bash
sudo ss -lntp | grep 6443
```

Check kubelet:

```bash
sudo ss -lntp | grep 10250
```

Check BGP:

```bash
sudo ss -lntp | grep 179
```

---

# 21. Check Services

Check kubelet:

```bash
sudo systemctl status kubelet
```

Check containerd:

```bash
sudo systemctl status containerd
```

Restart kubelet:

```bash
sudo systemctl restart kubelet
```

Restart containerd:

```bash
sudo systemctl restart containerd
```

---

# 22. Troubleshooting

## Worker NotReady

Run:

```bash
kubectl describe node <worker-node>
```

Check Calico:

```bash
kubectl get pods -n kube-system -o wide | grep calico
```

Check kubelet:

```bash
sudo systemctl status kubelet
```

Check containerd:

```bash
sudo systemctl status containerd
```

---

## Calico 0/1 Running

Check:

```bash
kubectl describe pod -n kube-system <calico-node-pod>
```

If you see:

```text
BIRD is not ready
BGP not established
```

check port 179:

```bash
nc -vz <OTHER-NODE-PRIVATE-IP> 179
```

Then check the AWS Security Group.

---

## Worker Cannot Join

Check Master API Server:

```bash
nc -vz 172.31.20.108 6443
```

Expected:

```text
Connection succeeded
```

Check AWS Security Group port:

```text
TCP 6443
```

---

# 23. Get a New Worker Join Command

If the old token expires, generate a new one:

```bash
kubeadm token create --print-join-command
```

Run the generated command on the worker.

---

# 24. Remove a Worker from the Cluster

From the Master:

```bash
kubectl drain <worker-node> --ignore-daemonsets --delete-emptydir-data
```

Then:

```bash
kubectl delete node <worker-node>
```

On the Worker:

```bash
sudo kubeadm reset -f
```

---

# 25. GitHub Workflow

This project can be maintained using Git.

Check status:

```bash
git status
```

Add files:

```bash
git add .
```

Commit:

```bash
git commit -m "Update Kubernetes installation process"
```

Pull latest GitHub changes:

```bash
git pull --rebase origin main
```

Push:

```bash
git push origin main
```

Repository:

```text
https://github.com/rkrath0206/docker-installation.git
```

---

# 26. Recommended Project Structure

A better structure for this project is:

```text
docker-installation/
│
├── README.md
│
├── k8s-master.sh
├── k8s-worker.sh
│
└── k8s/
    ├── deployment.yaml
    ├── service.yaml
    └── namespace.yaml
```

The scripts are responsible for installation.

The YAML files are responsible for Kubernetes applications.

The README explains the complete installation and operational process.

---

# 27. Complete Installation Flow

The complete process is:

```text
1. Create Master EC2
             |
2. Create Worker EC2
             |
3. Configure AWS Security Groups
             |
4. Disable Swap
             |
5. Install containerd
             |
6. Install kubeadm/kubelet/kubectl
             |
7. Run Master installation script
             |
8. kubeadm init
             |
9. Configure kubectl
             |
10. Install Calico
             |
11. Generate kubeadm join command
             |
12. Run join command on Worker
             |
13. Check kubectl get nodes
             |
14. Check Calico
             |
15. Configure NodePort if required
             |
16. Open NodePort in AWS Security Group
             |
17. Deploy application
             |
18. Create Service
             |
19. Test application
```

---

# 28. Final Verification

Run these commands on the Master:

```bash
kubectl get nodes -o wide
```

```bash
kubectl get pods -A
```

```bash
kubectl get svc -A
```

```bash
kubectl get deployments -A
```

The cluster is ready when:

```text
Master     → Ready
Worker     → Ready
Calico     → Running / Ready
CoreDNS    → Running
Kubelet    → Running
Containerd → Running
```

Then you can deploy applications such as:

```text
Java application
Spring Boot
Nginx
Python
MySQL
Dockerized applications
Jenkins CI/CD
```

---

## Important Security Notes

Never commit the following to GitHub:

```text
.kube/config
AWS access keys
AWS secret keys
GitHub tokens
SSH private keys
Passwords
Kubernetes certificates
```

Use `.gitignore` to prevent accidental commits:

```gitignore
.kube/
*.pem
*.key
.env
credentials
secrets/
```

For a production Kubernetes cluster, use a more restrictive network policy, private networking, proper TLS/certificate management, monitoring, logging, backups, and a production-grade CNI/security configuration.