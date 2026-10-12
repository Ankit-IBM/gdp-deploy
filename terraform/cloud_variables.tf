# ── Cloud-provider selector ───────────────────────────────────────────────────
variable "cloud_provider" {
  description = "Target cloud/hypervisor: kvm | vsphere | gcp | aws | azure"
  type        = string
  default     = "kvm"
  validation {
    condition     = contains(["kvm", "vsphere", "gcp", "aws", "azure"], var.cloud_provider)
    error_message = "cloud_provider must be one of: kvm, vsphere, gcp, aws, azure"
  }
}

# ── vSphere ──────────────────────────────────────────────────────────────────
variable "vsphere_datacenter"           { type = string; default = "" }
variable "vsphere_cluster"              { type = string; default = "" }
variable "vsphere_datastore"            { type = string; default = "" }
variable "vsphere_network"              { type = string; default = "" }
variable "vsphere_content_library"      { type = string; default = "" }
variable "vsphere_content_library_item" { type = string; default = "" }
variable "vsphere_vm_folder"            { type = string; default = "guardium" }

# ── GCP ───────────────────────────────────────────────────────────────────────
variable "gcp_project_id"       { type = string; default = "" }
variable "gcp_region"           { type = string; default = "" }
variable "gcp_zone"             { type = string; default = "" }
variable "gcp_machine_type"     { type = string; default = "n2-standard-8" }
variable "gcp_subnetwork"       { type = string; default = "" }
variable "gcp_guardium_image"   { type = string; default = "" }
variable "gcp_network_tags"     { type = list(string); default = ["guardium"] }
variable "gcp_labels"           { type = map(string); default = {} }

# ── AWS ───────────────────────────────────────────────────────────────────────
variable "aws_guardium_ami_id"    { type = string; default = "" }
variable "aws_instance_type"      { type = string; default = "m5.2xlarge" }
variable "aws_subnet_id"          { type = string; default = "" }
variable "aws_security_group_ids" { type = list(string); default = [] }
variable "aws_tags"               { type = map(string); default = {} }

# ── Azure ─────────────────────────────────────────────────────────────────────
variable "azure_resource_group"        { type = string; default = "" }
variable "azure_location"              { type = string; default = "" }
variable "azure_vm_size"               { type = string; default = "Standard_D8s_v5" }
variable "azure_guardium_image_id"     { type = string; default = "" }
variable "azure_subnet_id"             { type = string; default = "" }
variable "azure_admin_ssh_public_key"  { type = string; default = "" }
variable "azure_tags"                  { type = map(string); default = {} }

# ── vSphere provider auth (populated from env vars or tfvars) ─────────────────
variable "vsphere_user"                 { type = string; default = "" }
variable "vsphere_password"             { type = string; sensitive = true; default = "" }
variable "vsphere_server"               { type = string; default = "" }
variable "vsphere_allow_unverified_ssl" { type = bool; default = false }

# ── AWS provider region ───────────────────────────────────────────────────────
variable "aws_region" { type = string; default = "us-east-1" }

# ── Azure provider subscription ───────────────────────────────────────────────
variable "azure_subscription_id" { type = string; default = "" }
