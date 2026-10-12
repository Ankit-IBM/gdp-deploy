# IBM Guardium Deployment Automation

End-to-end lifecycle automation for IBM Guardium Data Protection 12.x:
VM provisioning (on-prem KVM, VMware vSphere/vCenter, GCP, AWS, Azure),
Collector → Aggregator registration, sample policy deployment, and S-TAP
agent installation via SSH, WinRM, or GIM (Guardium Installation Manager).

---

## Directory layout

```
guardium-deployment/
├── config/
│   ├── lab.yml                     # active lab config
│   ├── customer-template.yml       # template for customer deployments
│   └── guardium.yml                # default appliance sizing
├── scripts/
│   ├── guardium-deploy             # main CLI (all commands)
│   ├── guardium-everything.sh      # one-shot full automation helper
│   └── deploy-guardium.sh          # legacy alias → guardium-deploy
├── terraform/
│   ├── main.tf                     # KVM/libvirt modules (lab)
│   ├── cloud.tf                    # multi-cloud dispatch (vsphere/gcp/aws/azure)
│   ├── providers.tf                # all provider declarations
│   ├── variables.tf                # core variables
│   ├── cloud_variables.tf          # cloud-provider variables
│   └── modules/
│       ├── guardium-vm/            # KVM/libvirt module
│       ├── guardium-vsphere/       # VMware vSphere module
│       ├── guardium-gcp/           # Google Cloud module
│       ├── guardium-aws/           # AWS module
│       └── guardium-azure/         # Azure module
├── ansible/
│   ├── inventory/hosts.yml         # appliances + stap_linux + stap_windows
│   ├── group_vars/all.yml
│   ├── playbooks/
│   │   ├── wait-for-guardium.yml   # wait for SSH + converge
│   │   ├── register-collector.yml  # collector → aggregator registration
│   │   ├── deploy-policies.yml     # sample policy deployment
│   │   ├── install-stap-ssh.yml    # S-TAP via SSH (Linux)
│   │   ├── install-stap-winrm.yml  # S-TAP via WinRM (Windows)
│   │   └── install-stap-gim.yml    # S-TAP via GIM
│   └── roles/guardium/
├── guardapi/                       # Python REST API library
│   ├── client.py                   # HTTPS client
│   ├── registration.py             # collector→aggregator registration
│   ├── policies.py                 # sample policy deploy
│   └── stap.py                     # SSH / WinRM / GIM dispatcher
└── state/deployment.yml            # deployment state (no secrets)
```

---

## Quick start — full deployment

```bash
cd /root/guardium-deployment
python3 -m venv .venv && source .venv/bin/activate
pip install ansible PyYAML paramiko pywinrm requests

# Edit config/lab.yml with your IPs, bridge name, and ISO path.

# Interactive menu — walks you through every step:
./scripts/guardium-deploy menu

# Or run each phase individually:
./scripts/guardium-deploy collector              # provision Collector VM
./scripts/guardium-deploy aggregator             # provision Aggregator VM
./scripts/guardium-deploy converge collector     # wait + configure Collector
./scripts/guardium-deploy converge aggregator    # wait + configure Aggregator
./scripts/guardium-deploy register               # register Collector → Aggregator
./scripts/guardium-deploy policies               # deploy sample policies
./scripts/guardium-deploy stap                   # install S-TAP (prompts for method)
```

---

## Multi-cloud deployment

Set `cloud.provider` in your config (or pass `-var cloud_provider=<value>`):

| Provider | Value | Prerequisites |
|---|---|---|
| KVM/libvirt (lab) | `kvm` | virsh, OVS bridge, ISO on disk |
| VMware vCenter | `vsphere` | vSphere 7+, OVA in Content Library |
| Google Cloud | `gcp` | Custom image from Guardium ISO, VPC subnet |
| AWS | `aws` | AMI imported via VM Import/Export, VPC subnet |
| Azure | `azure` | Managed image from Guardium VHD, VNet subnet |

### vSphere
```bash
export VSPHERE_USER="administrator@vsphere.local"
export VSPHERE_PASSWORD="secret"
terraform -chdir=terraform apply \
  -var cloud_provider=vsphere \
  -var vsphere_server=vcenter.example.com \
  -var vsphere_datacenter=DC1 \
  -var vsphere_cluster=Cluster1 \
  -var vsphere_datastore=datastore1 \
  -var vsphere_network="VM Network" \
  -var vsphere_content_library=guardium-lib \
  -var vsphere_content_library_item=guardium-12.2 \
  -var collector_ip=10.50.20.31 \
  -var aggregator_ip=10.50.20.21
```

### AWS
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
terraform -chdir=terraform apply \
  -var cloud_provider=aws \
  -var aws_region=us-east-1 \
  -var aws_guardium_ami_id=ami-0123456789abcdef0 \
  -var aws_subnet_id=subnet-abc12345 \
  -var 'aws_security_group_ids=["sg-abc12345"]' \
  -var collector_ip=10.50.20.31 \
  -var aggregator_ip=10.50.20.21
```

### GCP
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
terraform -chdir=terraform apply \
  -var cloud_provider=gcp \
  -var gcp_project_id=my-project \
  -var gcp_region=us-central1 \
  -var gcp_zone=us-central1-a \
  -var gcp_subnetwork=projects/my-project/regions/us-central1/subnetworks/default \
  -var gcp_guardium_image=projects/my-project/global/images/guardium-12-2 \
  -var collector_ip=10.50.20.31 \
  -var aggregator_ip=10.50.20.21
```

### Azure
```bash
export ARM_CLIENT_ID="..." ARM_CLIENT_SECRET="..." ARM_TENANT_ID="..."
terraform -chdir=terraform apply \
  -var cloud_provider=azure \
  -var azure_subscription_id=<sub-id> \
  -var azure_resource_group=rg-guardium \
  -var azure_location=eastus \
  -var azure_guardium_image_id=/subscriptions/.../guardium-12-2 \
  -var azure_subnet_id=/subscriptions/.../subnets/guardium \
  -var azure_admin_ssh_public_key="ssh-rsa AAAA..." \
  -var collector_ip=10.50.20.31 \
  -var aggregator_ip=10.50.20.21
```

---

## Registration (Collector → Aggregator)

```bash
export GUARDIUM_COLLECTOR_PASSWORD="admin-pass"
export GUARDIUM_AGGREGATOR_PASSWORD="admin-pass"
./scripts/guardium-deploy register

# Or directly via Ansible:
ansible-playbook ansible/playbooks/register-collector.yml \
  -e collector_url=https://10.50.20.31:8443 \
  -e collector_username=admin \
  -e collector_password=secret \
  -e aggregator_ip=10.50.20.21 \
  -e aggregator_username=admin \
  -e aggregator_password=secret
```

---

## Sample policy deployment

Deploys four baseline policies: `BASELINE_AUDIT`, `PCI_DSS_AUDIT`, `HIPAA_AUDIT`, `EXTRUSION_DETECT`.

```bash
export GUARDIUM_COLLECTOR_PASSWORD="admin-pass"
./scripts/guardium-deploy policies

# Or directly:
python3 -m guardapi.policies \
  --url https://10.50.20.31:8443 \
  --username admin --password secret
```

---

## S-TAP / GIM installation

### Interactive (prompts for method + confirms automation)
```bash
./scripts/guardium-deploy stap
```
If you answer **`n`** at the confirmation prompt, the script prints exact
manual one-liner commands you can run yourself — nothing is installed.

### SSH (Linux/Unix DB server)
```bash
# Automated:
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/install-stap-ssh.yml \
  -e guardium_collector_ip=10.50.20.31

# Manual one-liner (printed when you say no, or run directly):
python3 -m guardapi.stap manual --method ssh \
  --host 10.1.2.10 --guardium-ip 10.50.20.31
```

### WinRM (Windows DB server)
```bash
# Automated:
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/install-stap-winrm.yml \
  -e guardium_collector_ip=10.50.20.31 \
  -e stap_msi_path=/path/to/guard-stap.msi

# Manual one-liner:
python3 -m guardapi.stap manual --method winrm \
  --host 10.1.2.20 --guardium-ip 10.50.20.31
```

### GIM (Guardium Installation Manager — IBM recommended for enterprise)
```bash
# Automated (push to multiple DB servers):
ansible-playbook ansible/playbooks/install-stap-gim.yml \
  -e gim_server_url=https://10.50.20.31:8082 \
  -e gim_username=admin -e gim_password=secret \
  -e guardium_collector_ip=10.50.20.31 \
  -e '{"db_hosts":[
        {"host":"10.1.2.10","os_type":"linux","db_type":"oracle"},
        {"host":"10.1.2.20","os_type":"windows","db_type":"mssql"}
      ]}'

# Manual one-liner (all three GIM methods printed):
python3 -m guardapi.stap manual --method gim \
  --host 10.1.2.10 --guardium-ip 10.50.20.31 \
  --gim-url https://10.50.20.31:8082
```

---

## Environment variables (credentials — never in config files)

| Variable | Purpose |
|---|---|
| `GUARDIUM_COLLECTOR_USERNAME` | Collector admin username |
| `GUARDIUM_COLLECTOR_PASSWORD` | Collector admin password |
| `GUARDIUM_AGGREGATOR_USERNAME` | Aggregator admin username |
| `GUARDIUM_AGGREGATOR_PASSWORD` | Aggregator admin password |
| `GIM_USERNAME` | GIM admin username |
| `GIM_PASSWORD` | GIM admin password |
| `GIM_SERVER_URL` | GIM server URL (https://ip:8082) |
| `VSPHERE_USER` / `VSPHERE_PASSWORD` / `VSPHERE_SERVER` | vCenter auth |
| `GOOGLE_APPLICATION_CREDENTIALS` | GCP service account key |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | AWS credentials |
| `ARM_CLIENT_ID` / `ARM_CLIENT_SECRET` / `ARM_TENANT_ID` | Azure credentials |

---

## Safety

- Destruction requires `GUARDIUM_ALLOW_DESTROY=yes` and typing `DESTROY` interactively.
- No credentials are stored in config files or state.
- S-TAP automation always prompts before touching any DB server.
# gdp-deploy
