# ── Guardium VM on Google Cloud Platform ─────────────────────────────────────
# Prerequisites:
#   - A custom GCP image built from the Guardium ISO (use `gcloud compute images import`)
#   - A VPC network and subnet reachable by the Collector/Aggregator
#   - Terraform google provider ~> 5.x
#
# The Guardium appliance needs an internal static IP; external access for S-TAP
# registration uses an internal LB or VPN back to the corporate network.

resource "google_compute_address" "internal_ip" {
  name         = "${var.name}-ip"
  subnetwork   = var.subnetwork
  address_type = "INTERNAL"
  address      = var.vm_ip
  region       = var.region
}

resource "google_compute_instance" "guardium_vm" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  tags = var.network_tags

  boot_disk {
    initialize_params {
      image = var.guardium_image
      size  = var.disk_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = var.subnetwork
    network_ip = google_compute_address.internal_ip.address
    # No access_config block = no external IP (appliances should stay private)
  }

  metadata = {
    "hostname"    = var.fqdn
    "guardium-ip" = var.vm_ip
  }

  # Guardium runs as a hardened appliance; OS login is not used.
  metadata_startup_script = null

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  labels = var.labels

  lifecycle {
    ignore_changes = [metadata_startup_script]
  }
}
