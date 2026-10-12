variable "name"                  { type = string }
variable "resource_group_name"   { type = string }
variable "location"              { type = string }
variable "vm_size"               { type = string; default = "Standard_D8s_v5" }
variable "guardium_image_id"     { type = string; description = "Resource ID of the managed image or SIG version" }
variable "subnet_id"             { type = string }
variable "vm_ip"                 { type = string }
variable "disk_gb"               { type = number; default = 300 }
variable "fqdn"                  { type = string }
variable "guardium_role"         { type = string; default = "collector" }
variable "admin_ssh_public_key"  { type = string; description = "SSH public key for Azure provisioning acceptance (not used by Guardium)" }
variable "tags"                  { type = map(string); default = {} }
