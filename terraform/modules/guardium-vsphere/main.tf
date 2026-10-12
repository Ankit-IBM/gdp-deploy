# ── Guardium VM on VMware vSphere / vCenter ─────────────────────────────────
# Prerequisites:
#   - vSphere 7+ with a vCenter endpoint
#   - A VM template or content-library item holding the Guardium OVA/ISO
#   - Terraform vsphere provider ~> 2.6
#
# Required variables: see variables.tf
# The ISO is attached as a CDROM and removed after first boot by the installer.

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

data "vsphere_content_library" "lib" {
  name = var.content_library_name
}

data "vsphere_content_library_item" "ova" {
  name       = var.content_library_item
  library_id = data.vsphere_content_library.lib.id
  type       = "ovf"
}

resource "vsphere_virtual_machine" "guardium_vm" {
  name             = var.name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.ds.id
  folder           = var.vm_folder

  num_cpus = var.cpu
  memory   = var.memory_mb
  guest_id = "rhel9_64Guest"

  firmware = "bios"

  network_interface {
    network_id   = data.vsphere_network.net.id
    adapter_type = "vmxnet3"
  }

  disk {
    label            = "disk0"
    size             = var.disk_gb
    thin_provisioned = true
    eagerly_scrub    = false
  }

  clone {
    template_uuid = data.vsphere_content_library_item.ova.id
  }

  # Guardium appliance uses its own NM_setup; no cloud-init customization.
  lifecycle {
    ignore_changes = [clone[0].customize]
  }

  extra_config = {
    "guestinfo.hostname" = var.fqdn
    "guestinfo.ip"       = var.vm_ip
  }

  tags = var.tags
}
