output "collector_vm_name" {
  value = var.deploy_collector ? module.guardium_collector[0].name : null
}

output "aggregator_vm_name" {
  value = var.deploy_aggregator ? module.guardium_aggregator[0].name : null
}

output "collector_domain" {
  value = var.deploy_collector ? module.guardium_collector[0].fqdn : null
}

output "aggregator_domain" {
  value = var.deploy_aggregator ? module.guardium_aggregator[0].fqdn : null
}
