output "vm_id"    { value = vsphere_virtual_machine.guardium_vm.id }
output "vm_ip"    { value = var.vm_ip }
output "hostname" { value = var.fqdn }
output "datastore"{ value = var.datastore }
