variable "name"                   { type = string }
variable "project_id"             { type = string }
variable "region"                 { type = string }
variable "zone"                   { type = string }
variable "machine_type"           { type = string; default = "n2-standard-8" }
variable "guardium_image"         { type = string; description = "Self-link or family of the Guardium custom image" }
variable "disk_gb"                { type = number; default = 300 }
variable "subnetwork"             { type = string }
variable "vm_ip"                  { type = string }
variable "fqdn"                   { type = string }
variable "network_tags"           { type = list(string); default = ["guardium"] }
variable "service_account_email"  { type = string; default = "" }
variable "labels"                 { type = map(string); default = {} }
