variable "name"                 { type = string }
variable "datacenter"           { type = string }
variable "cluster"              { type = string }
variable "datastore"            { type = string }
variable "network_name"         { type = string }
variable "content_library_name" { type = string }
variable "content_library_item" { type = string }
variable "vm_folder"            { type = string; default = "" }
variable "cpu"                  { type = number; default = 4 }
variable "memory_mb"            { type = number; default = 16384 }
variable "disk_gb"              { type = number; default = 300 }
variable "vm_ip"                { type = string }
variable "fqdn"                 { type = string }
variable "tags"                 { type = map(string); default = {} }
