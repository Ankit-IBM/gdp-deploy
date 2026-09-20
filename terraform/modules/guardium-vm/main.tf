resource "libvirt_volume" "os_disk" {
  name             = "${var.name}-disk"
  pool             = var.storage_pool
  size             = var.disk_gb * 1024 * 1024 * 1024
  format           = "qcow2"
}

resource "libvirt_volume" "installer_iso" {
  name   = "${var.name}-installer.iso"
  pool   = var.storage_pool
  source = var.iso_path
  format = "iso"
}

resource "libvirt_domain" "guardium_vm" {
  name      = var.name
  memory    = var.memory_mb
  vcpu      = var.cpu
  running   = true

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.os_disk.id
  }

  disk {
    file = libvirt_volume.installer_iso.id
  }

  network_interface {
    bridge       = var.network_bridge
    hostname     = var.fqdn
    mac          = "52:54:00:${substr(md5(var.name),0,2)}:${substr(md5(var.name),2,2)}:${substr(md5(var.name),4,2)}"
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_port = "0"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }

  boot_device {
    dev = ["hd", "cdrom"]
  }

  xml {
    xslt = file("${path.module}/installer-cdrom.xsl")
  }
}
