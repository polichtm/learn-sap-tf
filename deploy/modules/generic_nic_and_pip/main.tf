# Create public IPs

resource "random_string" "pipname" {
  length  = 10
  upper   = false
  number  = true
  lower   = true
  special = false
}

resource "azurerm_public_ip" "pip" {
  name                         = "${var.name}-pip"
  location                     = var.az_region
  resource_group_name          = var.az_resource_group
  allocation_method            = var.public_ip_allocation_type
  domain_name_label            = "hdb0${random_string.pipname.result}"

  idle_timeout_in_minutes = 30

  tags = {
    environment = "Terraform SAP HANA deployment"
  }
}

# Create network interface
resource "azurerm_network_interface" "nic" {
  depends_on                = [azurerm_public_ip.pip]
  name                      = "${var.name}-nic"
  location                  = var.az_region
  resource_group_name       = var.az_resource_group

  ip_configuration {
    name      = "${var.name}-nic-configuration"
    subnet_id = var.subnet_id

    private_ip_address_allocation           = var.private_ip_address != local.empty_string ? local.static : local.dynamic
    private_ip_address                      = var.private_ip_address
    public_ip_address_id                    = azurerm_public_ip.pip.id
  }

  tags = {
    environment = "Terraform SAP HANA deployment"
  }
}

