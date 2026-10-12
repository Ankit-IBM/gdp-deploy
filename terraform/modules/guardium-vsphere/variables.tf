variable "name"              { type = string;  description = "VM display name in vCenter" }
variable "datacenter"        { type = string;  description = "vSphere datacenter name" }
variable "cluster"           { type = string;  description = "vSphere compute cluster name" }
variable "datastore"         { type = string;  description = "vSphere datastore name (hosts both VM disks and the ISO)" }
variable "network_name"      { type = string;  description = "vSphere port group / distributed port group name" }
variable "iso_datastore_path"{ type = string;  description = "Path to Guardium ISO inside the datastore, e.g. 'guardium/guardium-12.2.iso'" }
variable "vm_folder"         { type = string;  default = "guardium"; description = "vCenter VM folder path" }
variable "cpu"               { type = number;  default = 4 }
variable "memory_mb"         { type = number;  default = 16384 }
variable "disk_gb"           { type = number;  default = 300 }
variable "vm_ip"             { type = string;  description = "Static IP for Guardium appliance (set via NM_setup after boot)" }
variable "fqdn"              { type = string;  description = "Hostname or FQDN" }
variable "tags"              { type = map(string); default = {} }
