variable "name"                  { type = string }
variable "guardium_ami_id"       { type = string; description = "AMI ID imported from the Guardium VMDK/OVA" }
variable "instance_type"         { type = string; default = "m5.2xlarge" }
variable "subnet_id"             { type = string }
variable "security_group_ids"    { type = list(string); default = [] }
variable "vm_ip"                 { type = string }
variable "disk_gb"               { type = number; default = 300 }
variable "fqdn"                  { type = string }
variable "guardium_role"         { type = string; default = "collector" }
variable "iam_instance_profile"  { type = string; default = "" }
variable "tags"                  { type = map(string); default = {} }
