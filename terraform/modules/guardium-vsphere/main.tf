# ── Guardium VM on VMware vSphere / vCenter ──────────────────────────────────
# Boots from an ISO stored on a vSphere Datastore (no OVA/content-library needed).
# The ISO must already be uploaded to the datastore before running Terraform.
#
# Upload the ISO first:
#   govc datastore.upload -ds=<datastore> /local/path/to/guardium-12.2.iso guardium/guardium-12.2.iso
#   # or via the vSphere Client: Storage → <datastore> → Upload Files
#
# Terraform selects the datastore ISO path via var.iso_datastore_path.
# A blank OS disk is created alongside it — the installer writes to that disk.
# After first boot the ISO is detached automatically (eject_cd_rom = true after install).

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "ds" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "net" {
  name          = var.network_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "guardium_vm" {
  name             = var.name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.ds.id
  folder           = var.vm_folder

  num_cpus               = var.cpu
  memory                 = var.memory_mb
  guest_id               = "rhel9_64Guest"
  firmware               = "bios"
  hardware_version       = 19   # vSphere 7+ hardware version
  efi_secure_boot_enabled = false

  # ── OS disk (blank — installer writes here) ─────────────────────────────────
  disk {
    label            = "disk0"
    size             = var.disk_gb
    unit_number      = 0
    thin_provisioned = true
    eagerly_scrub    = false
  }

  # ── Guardium ISO from vSphere Datastore ─────────────────────────────────────
  # Format: "[<datastore-name>] <path-on-datastore>"
  # e.g.    "[datastore1] guardium/Security_Guardium_Product_Image_V12_2.iso"
  cdrom {
    datastore_id = data.vsphere_datastore.ds.id
    path         = var.iso_datastore_path   # path inside the datastore
  }

  # ── Network ──────────────────────────────────────────────────────────────────
  network_interface {
    network_id   = data.vsphere_network.net.id
    adapter_type = "vmxnet3"
  }

  # ── Boot order: disk first so re-boots don't reinstall; CDROM for first boot ─
  boot_delay           = 5000   # ms — gives isolinux time to appear
  boot_retry_enabled   = true
  boot_retry_delay     = 10000

  # extra_config is injected into VMware guestinfo; Guardium NM_setup reads it
  extra_config = {
    "guestinfo.hostname" = var.fqdn
    "guestinfo.ip"       = var.vm_ip
  }

  tags = var.tags

  # Guardium appliance uses NM_setup on console; never use cloud-init customization.
  lifecycle {
    ignore_changes = [
      cdrom,        # don't re-attach ISO on subsequent applies after install
      extra_config,
      tags,
    ]
  }
}
