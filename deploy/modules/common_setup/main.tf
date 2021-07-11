# Create a resource group.

resource "azurerm_resource_group" "hana-resource-group" {
  name       = var.az_resource_group
  location   = var.az_region

  tags = {
    environment = "Terraform SAP HANA deployment"
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.sap_sid}-vnet"
  location            =  azurerm_resource_group.hana-resource-group.location
  resource_group_name =  azurerm_resource_group.hana-resource-group.name
  address_space       = ["10.0.0.0/21"]
}

resource "azurerm_subnet" "subnet" {
  name                      = "hdb-subnet"
  resource_group_name       = azurerm_resource_group.hana-resource-group.name
  virtual_network_name      = azurerm_virtual_network.vnet.name
  address_prefixes          = ["10.0.0.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "subnet-nsg-association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.sap_nsg.id
}