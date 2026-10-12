# ── Guardium VM on Microsoft Azure ───────────────────────────────────────────
# Prerequisites:
#   - A managed image (or Shared Image Gallery entry) created from the Guardium VHD
#     (az image create --source ...)
#   - An existing VNet/Subnet reachable by the Collector/Aggregator
#   - Terraform azurerm provider ~> 3.x
#
# NSG rules must allow TCP 8075 (S-TAP), 16022 (Guardium SSH), 443/8443 (UI/API)
# from the appropriate source address prefixes.

resource "azurerm_network_interface" "guardium_nic" {
  name                = "${var.name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.vm_ip
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "guardium_vm" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = "guardium"

  # Guardium uses its own credential system; disable password auth and supply a
  # placeholder SSH key so Azure accepts the create call. The key is not used.
  disable_password_authentication = true

  admin_ssh_key {
    username   = "guardium"
    public_key = var.admin_ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.guardium_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.disk_gb
  }

  source_image_id = var.guardium_image_id

  # No custom_data / cloud-init: Guardium uses NM_setup on first console login
  custom_data = null

  tags = merge(var.tags, {
    "guardium:role" = var.guardium_role
    "guardium:fqdn" = var.fqdn
  })

  lifecycle {
    ignore_changes = [custom_data, admin_ssh_key]
  }
}
