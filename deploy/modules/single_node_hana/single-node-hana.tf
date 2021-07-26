# Configure the Microsoft Azure Provider
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~> 2.0"
    }
  }
}
provider "azurerm" {
  features {}
}

module "common_setup" {
  source            = "../common_setup"
  allow_ips         = var.allow_ips
  az_region         = var.az_region
  az_resource_group = var.az_resource_group
  install_xsa       = var.install_xsa
  sap_instancenum   = var.sap_instancenum
  sap_sid           = var.sap_sid
}

module "create_hdb" {
  source = "../create_hdb_node"

  az_resource_group         = module.common_setup.resource_group_name
  az_region                 = var.az_region
  az_domain_name            = var.az_domain_name
  hdb_num                   = 0
  hana_subnet_id            = module.common_setup.vnet_subnets
  nsg_id                    = module.common_setup.nsg_id
  private_ip_address        = var.private_ip_address_hdb
  public_ip_allocation_type = var.public_ip_allocation_type
  sap_sid                   = var.sap_sid
  sshkey_path_public        = var.sshkey_path_public
  storage_disk_sizes_gb     = var.storage_disk_sizes_gb
  vm_user                   = var.vm_user
  vm_size                   = var.vm_size
}