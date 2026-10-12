# ── Guardium VM on Amazon Web Services ───────────────────────────────────────
# Prerequisites:
#   - A custom AMI imported from the Guardium VMDK/OVA via VM Import/Export
#     (aws ec2 import-image --disk-containers ...)
#   - A VPC subnet reachable by the Collector/Aggregator endpoints
#   - Terraform aws provider ~> 5.x
#
# Security groups must allow TCP 8075 (S-TAP) and 16022 (Guardium SSH) from
# the database subnets, and TCP 443/8443 from administrators.

resource "aws_network_interface" "guardium_nic" {
  subnet_id         = var.subnet_id
  private_ips       = [var.vm_ip]
  security_groups   = var.security_group_ids
  source_dest_check = false

  tags = merge(var.tags, { Name = "${var.name}-nic" })
}

resource "aws_instance" "guardium_vm" {
  ami           = var.guardium_ami_id
  instance_type = var.instance_type

  network_interface {
    network_interface_id = aws_network_interface.guardium_nic.id
    device_index         = 0
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.disk_gb
    delete_on_termination = true
    encrypted             = true
  }

  iam_instance_profile = var.iam_instance_profile

  user_data = null   # Guardium uses its own NM_setup wizard; no cloud-init

  tags = merge(var.tags, {
    Name            = var.name
    "guardium:role" = var.guardium_role
    "guardium:fqdn" = var.fqdn
  })

  lifecycle {
    ignore_changes = [user_data, ami]
  }
}
