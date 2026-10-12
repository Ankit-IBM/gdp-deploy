output "vm_id"       { value = azurerm_linux_virtual_machine.guardium_vm.id }
output "private_ip"  { value = azurerm_network_interface.guardium_nic.private_ip_address }
output "hostname"    { value = var.fqdn }
