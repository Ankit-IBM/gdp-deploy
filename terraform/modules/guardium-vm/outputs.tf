output "name" {
  value = libvirt_domain.guardium_vm.name
}

output "fqdn" {
  value = var.fqdn
}
