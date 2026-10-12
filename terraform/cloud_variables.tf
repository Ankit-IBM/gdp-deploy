# ── Cloud-provider selector ───────────────────────────────────────────────────
variable "cloud_provider" {
  description = "Target platform: kvm | vsphere | gcp | aws | azure"
  type        = string
  default     = "kvm"
  validation {
    condition     = contains(["kvm","vsphere","gcp","aws","azure"], var.cloud_provider)
    error_message = "cloud_provider must be one of: kvm, vsphere, gcp, aws, azure"
  }
}

# ── vSphere ───────────────────────────────────────────────────────────────────
variable "vsphere_datacenter"        { type = string; default = "" }
variable "vsphere_cluster"           { type = string; default = "" }
variable "vsphere_datastore"         { type = string; default = "" }
variable "vsphere_network"           { type = string; default = "" }
variable "vsphere_vm_folder"         { type = string; default = "guardium" }
# ISO must be uploaded to the datastore before applying.
# Value is the path inside the datastore, e.g.:
#   "guardium/Security_Guardium_Product_Image_V12_2.iso"
variable "vsphere_iso_datastore_path" {
  type        = string
  default     = ""
  description = "Path to Guardium ISO inside the vSphere datastore (e.g. 'guardium/guardium-12.2.iso')"
}
# Auth via env: VSPHERE_USER, VSPHERE_PASSWORD, VSPHERE_SERVER
variable "vsphere_user"                 { type = string;  default = "" }
variable "vsphere_password"             { type = string;  sensitive = true; default = "" }
variable "vsphere_server"               { type = string;  default = "" }
variable "vsphere_allow_unverified_ssl" { type = bool;    default = false }

# ── GCP ───────────────────────────────────────────────────────────────────────
variable "gcp_project_id"      { type = string;       default = "" }
variable "gcp_region"          { type = string;       default = "" }
variable "gcp_zone"            { type = string;       default = "" }
variable "gcp_machine_type"    { type = string;       default = "n2-standard-8" }
variable "gcp_subnetwork"      { type = string;       default = "" }
variable "gcp_guardium_image"  {
  type        = string
  default     = ""
  description = "Self-link of custom GCP image built from the Guardium ISO (selected interactively by scripts/list-images.py)"
}
variable "gcp_network_tags"    { type = list(string); default = ["guardium"] }
variable "gcp_labels"          { type = map(string);  default = {} }
# Auth via GOOGLE_APPLICATION_CREDENTIALS or gcloud ADC

# ── AWS ───────────────────────────────────────────────────────────────────────
variable "aws_region"            { type = string;       default = "us-east-1" }
variable "aws_guardium_ami_id"   {
  type        = string
  default     = ""
  description = "AMI ID imported from Guardium VMDK/OVA (selected interactively by scripts/list-images.py)"
}
variable "aws_instance_type"     { type = string;       default = "m5.2xlarge" }
variable "aws_subnet_id"         { type = string;       default = "" }
variable "aws_security_group_ids"{ type = list(string); default = [] }
variable "aws_tags"              { type = map(string);  default = {} }
# Auth via AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY or instance profile

# ── Azure ─────────────────────────────────────────────────────────────────────
variable "azure_subscription_id"     { type = string; default = "" }
variable "azure_resource_group"      { type = string; default = "" }
variable "azure_location"            { type = string; default = "" }
variable "azure_vm_size"             { type = string; default = "Standard_D8s_v5" }
variable "azure_guardium_image_id"   {
  type        = string
  default     = ""
  description = "Resource ID of Azure managed image or SIG version (selected interactively by scripts/list-images.py)"
}
variable "azure_subnet_id"           { type = string; default = "" }
variable "azure_admin_ssh_public_key"{ type = string; default = "" }
variable "azure_tags"                { type = map(string); default = {} }
# Auth via ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID
