# IBM Guardium Deployment Automation

This repository is a conservative foundation for deploying Guardium VMs on an existing Rocky Linux KVM/libvirt host. It does not install or reconfigure Rocky Linux, KVM, libvirt, Open vSwitch, or unrelated workloads.

## Verified host

The inspected host is Rocky Linux 9.8 with libvirt/QEMU available. The discovered installation image is `/home/dev/Security_Guardium_Product_Image_V12_2_ISO_with_12.2.2.iso`. The existing OVS bridge is `ovs-br0` (configured in `config/lab.yml`).

Both the Collector and Aggregator VMs have been provisioned and successfully completed the Guardium 12.2 OS installation (RHEL 9.6 base, `guardium-base*` packages). Key fixes required to get a working install, documented in [repo memory](../../.), include CPU `host-passthrough`, separating the OS disk (SATA) from the installer ISO (IDE), and booting `hd` before `cdrom`.

**All `virsh` and Terraform/OpenTofu invocations require passwordless `sudo`** on this host; without it, the libvirt provider intermittently fails with a polkit authorization timeout. Configure this once with:

```bash
sudo tee /etc/sudoers.d/guardium-deploy >/dev/null <<'EOF'
dev ALL=(root) NOPASSWD: ALL
EOF
sudo chmod 440 /etc/sudoers.d/guardium-deploy
sudo visudo -cf /etc/sudoers.d/guardium-deploy
```

## Known limitation: first-boot networking

The Guardium Kickstart does not configure a static IP or hostname. After installation, both appliances boot to `localhost login:` with no network reachable. IBM's own **NM_setup** wizard (interactive console, vendor/customer root credentials) must be completed manually before `./scripts/guardium-deploy converge <role>` can reach the host over SSH. This automation does not attempt to guess or bypass that credential.

## Configuration

Edit [config/lab.yml](config/lab.yml). The ISO path and OVS bridge are intentionally explicit:

```yaml
guardium:
  iso_path: /home/dev/Security_Guardium_Product_Image_V12_2_ISO_with_12.2.2.iso
network:
  ovs_bridge: ovs-br0
```

The host must also allow passwordless sudo for libvirt automation; otherwise validation fails with a `qemu:///system` authorization error:

```bash
sudo tee /etc/sudoers.d/guardium-deploy >/dev/null <<'EOF'
dev ALL=(root) NOPASSWD: ALL
EOF
sudo chmod 440 /etc/sudoers.d/guardium-deploy
sudo visudo -cf /etc/sudoers.d/guardium-deploy
```

Use [config/customer-template.yml](config/customer-template.yml) for customer-specific values. It contains no credentials. Credentials are expected through a secret store, Ansible Vault, or environment variables.

## Commands

### Deploy

```bash
cd /home/dev/guard
source .venv/bin/activate

./scripts/guardium-deploy status
./scripts/guardium-deploy validate
./scripts/guardium-deploy collector
./scripts/guardium-deploy aggregator
./scripts/guardium-deploy full
./scripts/guardium-deploy converge collector   # waits for SSH, then configures/validates
./scripts/guardium-deploy converge aggregator
./scripts/guardium-deploy resume
```

### One-shot deployment helper

```bash
cd /home/dev/guard
./scripts/guardium-everything.sh full
./scripts/guardium-everything.sh collector
./scripts/guardium-everything.sh aggregator
```

### Destroy / tear down the environment

To destroy the full lab environment, use the explicit approval guard and type `DESTROY` when prompted:

```bash
cd /home/dev/guard
GUARDIUM_ALLOW_DESTROY=yes ./scripts/guardium-deploy destroy
```

This is the full-environment teardown command. It removes the Terraform-managed VM infrastructure and requires the interactive `DESTROY` confirmation.

If you want to destroy only the currently managed state without the prompt, this is not allowed by design; the script intentionally blocks it unless `GUARDIUM_ALLOW_DESTROY=yes` is set.

### Destroy a specific role

The repo does not have a separate per-role destroy command; the supported destruction path is the full Terraform destroy guarded by `GUARDIUM_ALLOW_DESTROY=yes`.

`collector`/`aggregator`/`full` create the VM (if not already created) and automatically select the correct Guardium installer menu entry: entry 1 (`std`) for Collector, entry 3 (`agg`) for Aggregator. Boot selection only runs once per VM (tracked in `state/deployment.yml`).

`converge <role>` waits for the appliance to answer SSH at its configured IP, then runs [ansible/playbooks/wait-for-guardium.yml](ansible/playbooks/wait-for-guardium.yml) to complete host configuration and validation. This requires the Guardium NM_setup first-boot wizard to already be completed on the console (see limitation below).

The legacy `scripts/deploy-guardium.sh` name delegates to the same CLI.

The CLI validates the host, ISO, bridge, and Terraform configuration before provisioning. It does not claim that a Guardium appliance is installed merely because a VM exists. Installation, registration, GIM, S-TAP, database, and Central Manager commands remain explicit release-specific adapter boundaries until their supported IBM mechanisms are verified for the configured Guardium release.

## Safety and state

The automation never creates a bridge, deletes an existing network, wipes a disk, or destroys a VM automatically. Destruction requires `GUARDIUM_ALLOW_DESTROY=yes` and an interactive `DESTROY` confirmation. Verified infrastructure stages are recorded in [state/deployment.yml](state/deployment.yml); the file contains no secrets.

Terraform manages only VM infrastructure: CPU, memory, disks, ISO media, boot order, and the configured existing bridge. Guardium application behavior belongs in Ansible and the version-specific Python adapters under [guardapi](guardapi).

## Prerequisites and limitations

Install Terraform or OpenTofu, the libvirt provider, Ansible, Python 3, PyYAML, and the appropriate host permissions before provisioning. Terraform/OpenTofu is not installed in the current environment, so a real VM plan/apply has not been run. The Guardium ISO's exact role-selection and post-install API behavior must be validated against IBM documentation or a controlled installation before enabling those adapters; no undocumented commands or endpoints are guessed here.
# guardium-deployment
# guardium-deployment
# guardium-deployment
# guardium-deployment
