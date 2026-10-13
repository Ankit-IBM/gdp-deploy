# Kubernetes, OpenShift, and Ansible — Operations Knowledge Base

## 1. Kubernetes Architecture

### Control Plane Components
- **kube-apiserver**: Front door for all REST operations. All components communicate via the API server. Runs on control-plane nodes, port 6443 (HTTPS). Stateless — can be horizontally scaled.
- **etcd**: Distributed key-value store. Holds all cluster state. Runs on port 2379 (client) and 2380 (peer). Should always be an odd number of members (3 or 5) for quorum. Back up with `etcdctl snapshot save`.
- **kube-scheduler**: Watches for unscheduled Pods; assigns them to nodes based on resource requests, affinity, taints/tolerations.
- **kube-controller-manager**: Runs controllers: Node, ReplicaSet, Endpoints, Namespace, ServiceAccount, etc.
- **cloud-controller-manager**: Integrates with cloud provider APIs (AWS, GCP, Azure, vSphere).

### Node Components
- **kubelet**: Agent on every node. Talks to API server. Manages Pod lifecycle via CRI (Container Runtime Interface).
- **kube-proxy**: Maintains iptables/ipvs rules for Service networking.
- **Container runtime**: containerd (default), CRI-O, or Docker (deprecated since 1.24).

### Networking Model
- Every Pod gets a unique IP. Pods communicate directly without NAT.
- CNI plugins: Calico, Cilium, Flannel, OVN-Kubernetes (OpenShift default), Multus.
- Services: ClusterIP (internal), NodePort (node-level), LoadBalancer (cloud LB), ExternalName.
- Ingress: routes external HTTP(S) to Services. Requires an Ingress controller (nginx-ingress, HAProxy, Traefik).

---

## 2. Kubernetes Deployment & Management

### Core Objects
```yaml
# Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:1.2.0
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
```

### Rolling Updates & Rollbacks
```bash
kubectl set image deployment/myapp myapp=myapp:1.3.0
kubectl rollout status deployment/myapp
kubectl rollout history deployment/myapp
kubectl rollout undo deployment/myapp            # roll back one version
kubectl rollout undo deployment/myapp --to-revision=2
```

### ConfigMap & Secret
```bash
kubectl create configmap app-config --from-literal=ENV=production --from-file=config.yaml
kubectl create secret generic db-creds --from-literal=username=admin --from-literal=password=s3cr3t
kubectl get secret db-creds -o jsonpath='{.data.password}' | base64 -d
```

### Horizontal Pod Autoscaler
```bash
kubectl autoscale deployment myapp --cpu-percent=70 --min=2 --max=10
kubectl get hpa
```

### Persistent Volumes
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard
```

---

## 3. Kubernetes Troubleshooting

### Pod Troubleshooting Workflow
1. `kubectl get pods -n <ns> -o wide` — check STATUS, RESTARTS, NODE
2. `kubectl describe pod <pod> -n <ns>` — check Events section at bottom
3. `kubectl logs <pod> -n <ns> --previous` — previous container logs on CrashLoopBackOff
4. `kubectl exec -it <pod> -n <ns> -- /bin/sh` — interactive shell
5. `kubectl top pod <pod> -n <ns>` — CPU/memory usage

### Common Pod States
| State | Cause | Fix |
|-------|-------|-----|
| `Pending` | No schedulable node (resources, taints, node selector) | `kubectl describe pod` → check Events for scheduling failure |
| `CrashLoopBackOff` | Container exits non-zero repeatedly | `kubectl logs --previous`; fix app or liveness probe |
| `OOMKilled` | Container exceeded memory limit | Increase `resources.limits.memory` |
| `ImagePullBackOff` | Image not found or registry auth missing | Check image name/tag; create `imagePullSecret` |
| `Terminating` (stuck) | Finalizer blocking deletion | `kubectl patch pod <pod> -p '{"metadata":{"finalizers":[]}}' --type=merge` |
| `CreateContainerError` | Volume mount failure, securityContext issue | `kubectl describe pod` → check volume events |

### Node Troubleshooting
```bash
kubectl get nodes                                # check Ready status
kubectl describe node <node>                    # check Conditions, Capacity, Allocatable
kubectl cordon <node>                           # stop scheduling new pods
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>                         # re-enable scheduling

# On the node itself:
systemctl status kubelet
journalctl -u kubelet -n 100 --no-pager
systemctl status containerd
df -h                                           # check disk (common cause of NotReady)
```

### Node NotReady — Diagnosis
1. SSH to node: `journalctl -u kubelet -f`
2. Check disk: `df -h /` — if `/var/lib/kubelet` or `/var/lib/containerd` is full → eviction
3. Check network: `ping <control-plane-IP>` from node
4. Check certificates: `openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -noout -dates`
5. Restart kubelet: `systemctl restart kubelet`

### etcd Troubleshooting
```bash
# Check etcd health
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  endpoint health

# Snapshot backup
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%F).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Restore
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-2024-01-01.db \
  --data-dir=/var/lib/etcd-restore
```

### Networking Troubleshooting
```bash
# DNS resolution inside pod
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup myservice.mynamespace

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check Service endpoints
kubectl get endpoints myservice -n mynamespace

# Network policy debug — check if policy blocks traffic
kubectl get networkpolicy -n mynamespace
```

### Certificate Renewal
```bash
kubeadm certs check-expiration
kubeadm certs renew all
systemctl restart kube-apiserver kube-controller-manager kube-scheduler
```

---

## 4. OpenShift (OCP) Architecture

### OpenShift vs Kubernetes Differences
- **Operators**: OCP is Operator-first. Everything is managed by Operators (CVO, MCO, DNS, Ingress, etc.)
- **Cluster Version Operator (CVO)**: Manages OCP upgrades; reads from `ClusterVersion` CR.
- **Machine Config Operator (MCO)**: Manages node OS config via `MachineConfig` CRs. Changes trigger node drain/reboot.
- **Routes vs Ingress**: OCP uses `Route` objects (HAProxy router). Ingress objects are also supported and auto-converted.
- **SCCs (SecurityContextConstraints)**: OCP's pod security model (stricter than upstream PSS). `restricted-v2` is default.
- **OpenShift SDN / OVN-Kubernetes**: Default CNI. OVN-Kubernetes is the default from OCP 4.12+.
- **Image Streams**: Internal registry abstraction. `oc import-image`, `oc tag`.
- **Build Configs**: Source-to-Image (S2I) builds integrated into the platform.
- **Projects**: Namespaces with additional metadata and quotas.

### OCP Control Plane
- **etcd** (3 members, on control-plane nodes): port 2379/2380
- **kube-apiserver** + **openshift-apiserver**: OCP adds extension API groups
- **oauth-server**: Handles OpenShift OAuth (HTPasswd, LDAP, GitHub, OIDC)

### OCP Storage
- **ODF (OpenShift Data Foundation)**: Ceph-based, provides RWX via CephFS, RBD block storage, object storage.
- **Local Storage Operator**: Uses local disks as PVs.
- **NFS Provisioner**: Deprecated; use ODF or CSI instead.

---

## 5. OpenShift Deployment

### oc CLI Essential Commands
```bash
oc login https://api.cluster.example.com:6443 -u admin -p password
oc project myproject
oc new-project myproject --description="My App" --display-name="My Application"

# Deploy from image
oc new-app --image=registry.example.com/myapp:1.0 --name=myapp

# Expose service as Route
oc expose svc/myapp --hostname=myapp.apps.cluster.example.com

# Scale
oc scale deployment/myapp --replicas=5

# Rollout
oc rollout status deployment/myapp
oc rollout undo deployment/myapp
```

### OpenShift Builds
```bash
# S2I build from Git
oc new-app python:3.11~https://github.com/example/myapp.git --name=myapp

# Trigger rebuild
oc start-build myapp

# Build logs
oc logs -f bc/myapp
```

### OpenShift Routes
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: myapp
  namespace: myproject
spec:
  host: myapp.apps.cluster.example.com
  to:
    kind: Service
    name: myapp
  port:
    targetPort: 8080
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

### SCC — Fix "Permission Denied" for Containers
```bash
# Check which SCC a pod is using
oc get pod <pod> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'

# Grant anyuid SCC to a service account (use sparingly)
oc adm policy add-scc-to-user anyuid -z myserviceaccount -n mynamespace

# Check what SCC a user/SA can use
oc adm policy who-can use scc restricted-v2
```

### MachineConfig — Node OS Customization
```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-custom-sysctl
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - path: /etc/sysctl.d/99-custom.conf
        contents:
          source: "data:,vm.max_map_count%3D262144%0A"
        mode: 0644
```

---

## 6. OpenShift Troubleshooting

### OCP Cluster Operator Health
```bash
oc get clusteroperators                          # all COs — check AVAILABLE/DEGRADED
oc get co | grep -v "True.*False.*False"        # show only degraded/unavailable
oc describe co <operator-name>                  # detailed status and message
```

### OCP Node Troubleshooting
```bash
oc get nodes
oc describe node <node>
oc adm node-logs <node> -u kubelet              # kubelet logs
oc adm node-logs <node> -u crio                 # CRI-O logs
oc debug node/<node>                            # privileged debug pod on node
# Inside debug pod:
chroot /host
systemctl status kubelet
journalctl -u kubelet -n 100
```

### OCP Upgrade Troubleshooting
```bash
oc get clusterversion
oc describe clusterversion version              # shows upgrade conditions/errors
oc adm upgrade                                  # show available upgrades
oc adm upgrade --to=4.14.5                     # upgrade to specific version

# Pause MCO during upgrade troubleshooting
oc patch mcp worker --type merge -p '{"spec":{"paused":true}}'
```

### Must-Gather Diagnostic Collection
```bash
oc adm must-gather                              # collect full cluster diagnostics
oc adm must-gather --image=registry.redhat.io/openshift4/ose-must-gather:latest
# Outputs to must-gather.local.<timestamp>/
```

### OCP ImagePullBackOff — Fix Registry Auth
```bash
# Create pull secret for Red Hat registry
oc create secret docker-registry redhat-pull \
  --docker-server=registry.redhat.io \
  --docker-username=<rhn-user> \
  --docker-password=<rhn-pass> \
  -n mynamespace

oc secrets link default redhat-pull --for=pull -n mynamespace
```

### OCP etcd Backup
```bash
# On any control-plane node:
/usr/local/bin/cluster-backup.sh /home/core/backup
# Saves etcd snapshot + static pod manifests to /home/core/backup/
```

---

## 7. Ansible Architecture & Concepts

### Core Concepts
- **Inventory**: List of managed hosts. Static (`/etc/ansible/hosts`) or dynamic (scripts, plugins).
- **Playbook**: YAML file containing one or more Plays. A Play maps hosts to Tasks.
- **Task**: A single unit of work using a module (e.g., `ansible.builtin.yum`, `ansible.builtin.copy`).
- **Module**: The "action" executed on a host. 3000+ built-in modules.
- **Role**: Reusable unit — `tasks/`, `handlers/`, `templates/`, `vars/`, `defaults/`, `files/`, `meta/`.
- **Handler**: Task triggered by `notify` — runs once at end of play if notified.
- **Variable**: Defined in inventory, playbook, role vars/defaults, group_vars/, host_vars/, or passed with `-e`.
- **Facts**: Host information gathered by `setup` module at start of play (`ansible_os_family`, `ansible_default_ipv4`, etc.).
- **Vault**: Encrypted variable files — `ansible-vault encrypt vars/secrets.yml`.
- **Collections**: Distributable bundles of roles, modules, plugins — `ansible-galaxy collection install`.

### Inventory Examples
```ini
# Static inventory
[webservers]
web1.example.com ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/id_rsa
web2.example.com

[dbservers]
db1.example.com ansible_port=2222

[prod:children]
webservers
dbservers

[prod:vars]
env=production
```

```yaml
# Dynamic inventory (YAML format)
all:
  children:
    k8s_nodes:
      hosts:
        node1: { ansible_host: 10.0.1.10 }
        node2: { ansible_host: 10.0.1.11 }
      vars:
        ansible_user: core
        ansible_become: true
```

---

## 8. Ansible Playbook Patterns

### Standard Playbook Structure
```yaml
---
- name: Configure web servers
  hosts: webservers
  become: true
  vars:
    app_port: 8080
  tasks:
    - name: Install nginx
      ansible.builtin.package:
        name: nginx
        state: present

    - name: Deploy config
      ansible.builtin.template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
        owner: root
        group: root
        mode: '0644'
      notify: Restart nginx

    - name: Ensure nginx is started
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true

  handlers:
    - name: Restart nginx
      ansible.builtin.service:
        name: nginx
        state: restarted
```

### Error Handling
```yaml
- name: Attempt risky task
  ansible.builtin.command: /opt/deploy.sh
  register: result
  ignore_errors: true

- name: Handle failure
  ansible.builtin.debug:
    msg: "Deploy failed: {{ result.stderr }}"
  when: result.rc != 0

# Block/rescue/always
- block:
    - name: Try this
      ansible.builtin.command: /opt/risky.sh
  rescue:
    - name: Run on failure
      ansible.builtin.debug:
        msg: "Caught: {{ ansible_failed_result }}"
  always:
    - name: Always cleanup
      ansible.builtin.file:
        path: /tmp/lockfile
        state: absent
```

### Loops and Conditions
```yaml
- name: Create users
  ansible.builtin.user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    state: present
  loop:
    - { name: alice, groups: wheel }
    - { name: bob,   groups: docker }

- name: Install packages on RHEL only
  ansible.builtin.yum:
    name: "{{ item }}"
    state: present
  loop: [httpd, mod_ssl]
  when: ansible_os_family == "RedHat"
```

### Ansible Vault
```bash
ansible-vault encrypt group_vars/all/secrets.yml
ansible-vault edit group_vars/all/secrets.yml
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file ~/.vault_pass
```

---

## 9. Ansible Troubleshooting

### Verbose & Debug
```bash
ansible-playbook site.yml -v           # task output
ansible-playbook site.yml -vvv         # connection details + module args
ansible-playbook site.yml -vvvv        # SSH debug

# Test connectivity
ansible all -m ping -i inventory/hosts
ansible webservers -m setup -i inventory/hosts   # gather facts

# Dry run
ansible-playbook site.yml --check --diff
```

### Common Errors and Fixes
| Error | Cause | Fix |
|-------|-------|-----|
| `UNREACHABLE! SSH Error` | SSH key missing, wrong user, host unreachable | Check `ansible_user`, `ansible_ssh_private_key_file`, test `ssh -i key user@host` |
| `MODULE FAILURE: Python not found` | No python on target | Set `ansible_python_interpreter=/usr/bin/python3` in inventory |
| `Permission denied` | `become` not set or sudo not configured | Add `become: true`; check `/etc/sudoers` on target |
| `Template not found` | Wrong relative path to `.j2` | Use `templates/` directory inside role; reference without path |
| `Variable undefined` | Typo or missing `vars` | Use `{{ var | default('fallback') }}`; check `group_vars/` |
| `Idempotency failure` | Task re-runs incorrectly | Use `changed_when: false` for read-only commands; use proper state= |
| `Timeout on long tasks` | Default 10min async | Use `async: 3600` + `poll: 30` |

### Ansible Collections for K8s/OCP
```bash
# Install required collections
ansible-galaxy collection install kubernetes.core
ansible-galaxy collection install redhat.openshift

# Use k8s module
- name: Deploy ConfigMap
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: myconfig
        namespace: default
      data:
        key: value

# Wait for Deployment
- name: Wait for rollout
  kubernetes.core.k8s_rollout_status:
    name: myapp
    namespace: default
    kind: Deployment
```

---

## 10. Ansible for Kubernetes & OpenShift Deployments

### kubeadm Cluster Bootstrap (Ansible)
```yaml
- name: Initialize kubeadm control plane
  ansible.builtin.command: >
    kubeadm init
    --control-plane-endpoint={{ lb_endpoint }}:6443
    --pod-network-cidr=10.244.0.0/16
    --upload-certs
  register: kubeadm_init
  when: inventory_hostname == groups['masters'][0]

- name: Copy kubeconfig to root
  ansible.builtin.copy:
    src: /etc/kubernetes/admin.conf
    dest: /root/.kube/config
    remote_src: true
    mode: '0600'
  when: inventory_hostname == groups['masters'][0]

- name: Join worker nodes
  ansible.builtin.command: "{{ hostvars[groups['masters'][0]].kubeadm_join_cmd }}"
  when: inventory_hostname in groups['workers']
```

### OpenShift IPI/UPI Ansible Helper
```yaml
# Wait for OCP bootstrap complete
- name: Wait for bootstrap API
  ansible.builtin.uri:
    url: "https://api.{{ cluster_name }}.{{ base_domain }}:6443/healthz"
    validate_certs: false
    status_code: 200
  register: api_health
  until: api_health.status == 200
  retries: 60
  delay: 30

# Approve pending CSRs
- name: Approve all pending CSRs
  ansible.builtin.shell: |
    oc get csr -o name | xargs oc adm certificate approve
  environment:
    KUBECONFIG: /root/auth/kubeconfig
  changed_when: true
```

### Ansible Operator SDK — OCP Operator Pattern
```bash
# Scaffold an Ansible-based operator
operator-sdk init --plugins=ansible --domain=example.com
operator-sdk create api --group=app --version=v1alpha1 --kind=MyApp --generate-role

# roles/myapp/tasks/main.yml gets rendered per CR instance
# Deploy with make deploy
```

---

## 11. Helm on Kubernetes

```bash
# Add repo and install
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install myrelease bitnami/postgresql \
  --namespace db --create-namespace \
  --set auth.postgresPassword=secret \
  --set primary.persistence.size=20Gi

# Upgrade
helm upgrade myrelease bitnami/postgresql --set image.tag=15.3.0

# Rollback
helm rollback myrelease 1

# Troubleshoot
helm history myrelease
helm get all myrelease
helm status myrelease
```

---

## 12. GitOps — Argo CD on Kubernetes/OpenShift

```bash
# Install Argo CD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Create Application CR
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/example/myapp-gitops.git
    targetRevision: main
    path: k8s/
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## 13. RBAC — Kubernetes & OpenShift

```yaml
# ClusterRole for read-only
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: mynamespace
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```bash
# Check permissions
kubectl auth can-i list pods --as=alice -n mynamespace
kubectl auth can-i '*' '*' --as=system:serviceaccount:default:mysa

# OCP
oc adm policy add-role-to-user edit alice -n mynamespace
oc adm policy add-cluster-role-to-user cluster-admin admin
```

---

## 14. Resource Management & Quotas

```yaml
# LimitRange — per-pod defaults
apiVersion: v1
kind: LimitRange
metadata:
  name: limits
  namespace: mynamespace
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "2"
      memory: "2Gi"

---
# ResourceQuota — namespace-level cap
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ns-quota
  namespace: mynamespace
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    count/pods: "20"
    count/services: "10"
```

---

## 15. Common Kubernetes Fix Recipes

### Fix: Pod stuck in Terminating
```bash
kubectl patch pod <pod> -n <ns> \
  -p '{"metadata":{"finalizers":[]}}' --type=merge
```

### Fix: Node disk pressure / eviction
```bash
# On node: clean up container images
crictl rmi --prune
# Or via docker
docker system prune -af

# Increase eviction thresholds (kubelet config)
# /var/lib/kubelet/config.yaml
evictionHard:
  nodefs.available: "5%"
  imagefs.available: "5%"
```

### Fix: Service not reachable
```bash
kubectl get svc myservice -n mynamespace
kubectl get endpoints myservice -n mynamespace  # if empty — no matching pods
kubectl get pods -l app=myapp -n mynamespace    # verify selector matches
```

### Fix: PVC stuck in Pending
```bash
kubectl describe pvc <pvc> -n <ns>   # check Events — usually no matching StorageClass
kubectl get storageclass             # list available classes
# Patch PVC to use correct storageClassName or mark default SC:
kubectl patch storageclass standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Fix: CertificateSigningRequest pending on new nodes
```bash
kubectl get csr
kubectl certificate approve <csr-name>
# Auto-approve via controller:
kubectl apply -f https://raw.githubusercontent.com/nicholasgasior/k8s-csr-approver/master/deploy.yaml
```

### Fix: OCP Operator Degraded
```bash
oc describe co <operator>            # read Degraded condition message
oc get pod -n openshift-<operator>   # check pods
oc logs -n openshift-<operator> <pod>
# Common fix: restart operator pod
oc delete pod -n openshift-<operator> <pod>
```

### Fix: kubeadm token expired for new node join
```bash
# Generate new join command on control-plane
kubeadm token create --print-join-command
```

---

## 16. Monitoring & Observability

```bash
# Prometheus / AlertManager (kube-prometheus-stack)
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

# Check Prometheus targets
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090

# Useful PromQL queries
# CPU throttling
sum(rate(container_cpu_cfs_throttled_seconds_total[5m])) by (pod, container)
# OOMKill events
kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}
# Node disk pressure
node_filesystem_avail_bytes / node_filesystem_size_bytes * 100 < 10

# OCP built-in monitoring
oc get prometheusrule -n openshift-monitoring
oc get alertmanagerconfig -n openshift-monitoring
```

---

## 17. Ansible AWX / Automation Controller

- **AWX**: Open-source Ansible automation web UI + API. Runs on Kubernetes/OpenShift.
- **Automation Controller** (formerly Ansible Tower): Red Hat supported version.
- Key objects: **Organizations**, **Inventories**, **Projects** (Git-backed), **Job Templates**, **Workflows**, **Credentials**, **Schedules**.

```bash
# Install AWX on Kubernetes via AWX Operator
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/main/deploy/awx-operator.yaml -n awx

# AWX CR
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: awx
spec:
  service_type: nodeport
  admin_user: admin
  admin_password_secret: awx-admin-password
```

---

## 18. Kubernetes Security Hardening

```bash
# Pod Security Admission (PSA) — enforce restricted profile
kubectl label namespace mynamespace \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted

# Network Policy — default deny all ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: mynamespace
spec:
  podSelector: {}
  policyTypes:
  - Ingress

# Falco runtime security
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set falco.grpc.enabled=true \
  --set falcoctl.artifact.follow.enabled=true
```

---

## 19. Multi-Cluster Management

- **ACM (Advanced Cluster Management for Kubernetes)** — Red Hat product for managing multiple OCP/K8s clusters from a central hub.
- **Submariner** — Cross-cluster networking (service discovery across clusters).
- **ArgoCD ApplicationSets** — Deploy apps to multiple clusters from one config.

```bash
# ACM hub cluster install
oc apply -f - <<EOF
apiVersion: operator.open-cluster-management.io/v1
kind: MultiClusterHub
metadata:
  name: multiclusterhub
  namespace: open-cluster-management
spec: {}
EOF

# Import managed cluster
oc apply -f managed-cluster.yaml
# Copy import command from ACM console and run on managed cluster
```

---

## 20. Key CLI Reference

```bash
# Kubernetes
kubectl get all -n mynamespace
kubectl get events -n mynamespace --sort-by=.lastTimestamp
kubectl api-resources                          # all resource types
kubectl explain deployment.spec.strategy       # inline docs
kubectl diff -f manifest.yaml                  # show diff before apply
kubectl apply --server-side -f manifest.yaml   # server-side apply (avoids conflicts)

# OpenShift
oc whoami
oc projects
oc status
oc get route -A                               # all routes all namespaces
oc adm top nodes
oc adm top pods -A --sort-by=memory

# Ansible
ansible-doc -l                                # list all modules
ansible-doc ansible.builtin.template          # module docs
ansible-inventory --list -i inventory/        # show parsed inventory as JSON
ansible all -m setup -a 'filter=ansible_distribution*' -i inventory/
```
