variable "deploy_collector" {
  description = "Whether to deploy the Collector VM."
  type        = bool
  default     = true
}

variable "deploy_aggregator" {
  description = "Whether to deploy the Aggregator VM."
  type        = bool
  default     = true
}

variable "iso_path" {
  description = "Path to the Guardium ISO to attach to the VM for installation."
  type        = string
  default     = "/home/dev/Security_Guardium_Product_Image_V12_2_ISO_with_12.2.2.iso"
}

variable "storage_pool" {
  description = "Existing libvirt storage pool used for VM volumes."
  type        = string
  default     = "default"
}

variable "network_type" {
  description = "Network implementation. Use 'ovs' for Open vSwitch or 'bridge' for Linux bridge."
  type        = string
  default     = "ovs"
}

variable "network_bridge" {
  description = "Host bridge or OVS bridge name to attach the VM NIC to."
  type        = string
  default     = ""
}

variable "collector_name" {
  description = "Collector VM name."
  type        = string
  default     = "guardium-collector"
}

variable "aggregator_name" {
  description = "Aggregator VM name."
  type        = string
  default     = "guardium-aggregator"
}

variable "collector_cpu" {
  description = "Collector CPU count."
  type        = number
  default     = 4
}

variable "collector_memory_mb" {
  description = "Collector memory in MB."
  type        = number
  default     = 16384
}

variable "collector_disk_gb" {
  description = "Collector root disk in GB."
  type        = number
  default     = 300
}

variable "aggregator_cpu" {
  description = "Aggregator CPU count."
  type        = number
  default     = 4
}

variable "aggregator_memory_mb" {
  description = "Aggregator memory in MB."
  type        = number
  default     = 16384
}

variable "aggregator_disk_gb" {
  description = "Aggregator root disk in GB."
  type        = number
  default     = 300
}

variable "collector_ip" {
  description = "Collector IP address."
  type        = string
  default     = "10.50.20.31"
}

variable "aggregator_ip" {
  description = "Aggregator IP address."
  type        = string
  default     = "10.50.20.21"
}

variable "collector_hostname" {
  description = "Collector FQDN."
  type        = string
  default     = "gdp-col01"
}

variable "aggregator_hostname" {
  description = "Aggregator FQDN."
  type        = string
  default     = "gdp-agg01"
}
