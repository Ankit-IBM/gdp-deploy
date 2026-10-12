output "instance_id"   { value = aws_instance.guardium_vm.id }
output "private_ip"    { value = aws_network_interface.guardium_nic.private_ip }
output "hostname"      { value = var.fqdn }
