# ── Multi-cloud dispatch ─────────────────────────────────────────────────────
# Set var.cloud_provider: kvm | vsphere | gcp | aws | azure
# Only the selected provider's module is instantiated (count = 0 for others).

# ── vSphere / on-prem vCenter ─────────────────────────────────────────────────
# Boots from an ISO stored on a vSphere Datastore (no OVA/content-library needed).
# Upload the ISO to the datastore first, then set vsphere_iso_datastore_path.
module "guardium_collector_vsphere" {
  count  = (var.cloud_provider == "vsphere" && var.deploy_collector) ? 1 : 0
  source = "./modules/guardium-vsphere"

  name               = var.collector_name
  fqdn               = var.collector_hostname
  vm_ip              = var.collector_ip
  cpu                = var.collector_cpu
  memory_mb          = var.collector_memory_mb
  disk_gb            = var.collector_disk_gb
  datacenter         = var.vsphere_datacenter
  cluster            = var.vsphere_cluster
  datastore          = var.vsphere_datastore
  network_name       = var.vsphere_network
  iso_datastore_path = var.vsphere_iso_datastore_path
  vm_folder          = var.vsphere_vm_folder
}

module "guardium_aggregator_vsphere" {
  count  = (var.cloud_provider == "vsphere" && var.deploy_aggregator) ? 1 : 0
  source = "./modules/guardium-vsphere"

  name               = var.aggregator_name
  fqdn               = var.aggregator_hostname
  vm_ip              = var.aggregator_ip
  cpu                = var.aggregator_cpu
  memory_mb          = var.aggregator_memory_mb
  disk_gb            = var.aggregator_disk_gb
  datacenter         = var.vsphere_datacenter
  cluster            = var.vsphere_cluster
  datastore          = var.vsphere_datastore
  network_name       = var.vsphere_network
  iso_datastore_path = var.vsphere_iso_datastore_path
  vm_folder          = var.vsphere_vm_folder
}

# ── GCP ───────────────────────────────────────────────────────────────────────
module "guardium_collector_gcp" {
  count  = (var.cloud_provider == "gcp" && var.deploy_collector) ? 1 : 0
  source = "./modules/guardium-gcp"

  name           = var.collector_name
  fqdn           = var.collector_hostname
  vm_ip          = var.collector_ip
  disk_gb        = var.collector_disk_gb
  machine_type   = var.gcp_machine_type
  project_id     = var.gcp_project_id
  region         = var.gcp_region
  zone           = var.gcp_zone
  subnetwork     = var.gcp_subnetwork
  guardium_image = var.gcp_guardium_image
  network_tags   = var.gcp_network_tags
  labels         = var.gcp_labels
}

module "guardium_aggregator_gcp" {
  count  = (var.cloud_provider == "gcp" && var.deploy_aggregator) ? 1 : 0
  source = "./modules/guardium-gcp"

  name           = var.aggregator_name
  fqdn           = var.aggregator_hostname
  vm_ip          = var.aggregator_ip
  disk_gb        = var.aggregator_disk_gb
  machine_type   = var.gcp_machine_type
  project_id     = var.gcp_project_id
  region         = var.gcp_region
  zone           = var.gcp_zone
  subnetwork     = var.gcp_subnetwork
  guardium_image = var.gcp_guardium_image
  network_tags   = var.gcp_network_tags
  labels         = var.gcp_labels
}

# ── AWS ───────────────────────────────────────────────────────────────────────
module "guardium_collector_aws" {
  count  = (var.cloud_provider == "aws" && var.deploy_collector) ? 1 : 0
  source = "./modules/guardium-aws"

  name               = var.collector_name
  fqdn               = var.collector_hostname
  vm_ip              = var.collector_ip
  disk_gb            = var.collector_disk_gb
  guardium_ami_id    = var.aws_guardium_ami_id
  instance_type      = var.aws_instance_type
  subnet_id          = var.aws_subnet_id
  security_group_ids = var.aws_security_group_ids
  guardium_role      = "collector"
  tags               = var.aws_tags
}

module "guardium_aggregator_aws" {
  count  = (var.cloud_provider == "aws" && var.deploy_aggregator) ? 1 : 0
  source = "./modules/guardium-aws"

  name               = var.aggregator_name
  fqdn               = var.aggregator_hostname
  vm_ip              = var.aggregator_ip
  disk_gb            = var.aggregator_disk_gb
  guardium_ami_id    = var.aws_guardium_ami_id
  instance_type      = var.aws_instance_type
  subnet_id          = var.aws_subnet_id
  security_group_ids = var.aws_security_group_ids
  guardium_role      = "aggregator"
  tags               = var.aws_tags
}

# ── Azure ─────────────────────────────────────────────────────────────────────
module "guardium_collector_azure" {
  count  = (var.cloud_provider == "azure" && var.deploy_collector) ? 1 : 0
  source = "./modules/guardium-azure"

  name                 = var.collector_name
  fqdn                 = var.collector_hostname
  vm_ip                = var.collector_ip
  disk_gb              = var.collector_disk_gb
  resource_group_name  = var.azure_resource_group
  location             = var.azure_location
  vm_size              = var.azure_vm_size
  guardium_image_id    = var.azure_guardium_image_id
  subnet_id            = var.azure_subnet_id
  admin_ssh_public_key = var.azure_admin_ssh_public_key
  guardium_role        = "collector"
  tags                 = var.azure_tags
}

module "guardium_aggregator_azure" {
  count  = (var.cloud_provider == "azure" && var.deploy_aggregator) ? 1 : 0
  source = "./modules/guardium-azure"

  name                 = var.aggregator_name
  fqdn                 = var.aggregator_hostname
  vm_ip                = var.aggregator_ip
  disk_gb              = var.aggregator_disk_gb
  resource_group_name  = var.azure_resource_group
  location             = var.azure_location
  vm_size              = var.azure_vm_size
  guardium_image_id    = var.azure_guardium_image_id
  subnet_id            = var.azure_subnet_id
  admin_ssh_public_key = var.azure_admin_ssh_public_key
  guardium_role        = "aggregator"
  tags                 = var.azure_tags
}
