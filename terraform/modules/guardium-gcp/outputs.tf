output "instance_id"      { value = google_compute_instance.guardium_vm.instance_id }
output "internal_ip"      { value = google_compute_address.internal_ip.address }
output "hostname"         { value = var.fqdn }
