locals {
  network_bridge     = var.network_bridge
  deploy_collection  = var.deploy_collector
  deploy_aggregation = var.deploy_aggregator

  collector_vm = {
    name  = var.collector_name
    cpu   = var.collector_cpu
    ram   = var.collector_memory_mb
    disk  = var.collector_disk_gb
    ip    = var.collector_ip
    fqdn  = var.collector_hostname
    image = var.iso_path
  }

  aggregator_vm = {
    name  = var.aggregator_name
    cpu   = var.aggregator_cpu
    ram   = var.aggregator_memory_mb
    disk  = var.aggregator_disk_gb
    ip    = var.aggregator_ip
    fqdn  = var.aggregator_hostname
    image = var.iso_path
  }
}

module "guardium_collector" {
  count  = var.deploy_collector ? 1 : 0
  source = "./modules/guardium-vm"

  name           = local.collector_vm.name
  cpu            = local.collector_vm.cpu
  memory_mb      = local.collector_vm.ram
  disk_gb        = local.collector_vm.disk
  network_type   = var.network_type
  network_bridge = local.network_bridge
  storage_pool   = var.storage_pool
  iso_path       = local.collector_vm.image
  vm_ip          = local.collector_vm.ip
  fqdn           = local.collector_vm.fqdn
}

module "guardium_aggregator" {
  count  = var.deploy_aggregator ? 1 : 0
  source = "./modules/guardium-vm"

  name           = local.aggregator_vm.name
  cpu            = local.aggregator_vm.cpu
  memory_mb      = local.aggregator_vm.ram
  disk_gb        = local.aggregator_vm.disk
  network_type   = var.network_type
  network_bridge = local.network_bridge
  storage_pool   = var.storage_pool
  iso_path       = local.aggregator_vm.image
  vm_ip          = local.aggregator_vm.ip
  fqdn           = local.aggregator_vm.fqdn
}
