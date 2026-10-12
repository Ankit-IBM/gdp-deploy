terraform {
  required_version = ">= 1.6.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.3"
    }
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.6"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# KVM/libvirt (on-prem lab)
provider "libvirt" {
  uri = "qemu:///system"
}

# vSphere — credentials via env vars:
#   VSPHERE_USER, VSPHERE_PASSWORD, VSPHERE_SERVER
provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = var.vsphere_allow_unverified_ssl
}

# GCP — credentials via GOOGLE_APPLICATION_CREDENTIALS or gcloud ADC
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# AWS — credentials via AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY or instance role
provider "aws" {
  region = var.aws_region
}

# Azure — credentials via ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID
provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}
