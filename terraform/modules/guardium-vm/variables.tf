variable "name" {
  description = "VM name."
  type        = string
}

variable "cpu" {
  description = "VM CPU count."
  type        = number
}

variable "memory_mb" {
  description = "Memory in MB."
  type        = number
}

variable "disk_gb" {
  description = "Disk size in GB."
  type        = number
}

variable "storage_pool" {
  description = "Existing libvirt storage pool for VM volumes."
  type        = string
}

variable "network_type" {
  description = "Network type (ovs or bridge)."
  type        = string
  default     = "ovs"
}

variable "network_bridge" {
  description = "Bridge name to attach the VM to."
  type        = string
  default     = "br0"
}

variable "iso_path" {
  description = "ISO path to attach as installation media."
  type        = string
}

variable "vm_ip" {
  description = "IP address to assign to the VM."
  type        = string
}

variable "fqdn" {
  description = "VM hostname or FQDN."
  type        = string
}
