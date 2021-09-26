# Introductory guide to deploying SAP HANA on Azure by using Terraform and Ansible

## Abstract and learning objectives 

In the first part of this guide, you will learn about the basic principles of deploying Azure resources by leveraging capabilities of Terraform. In the second part, you will apply that knowledge to automate implementation of an Azure VM running SUSE Linux Enterprise Server for SAP. The third part will introduce the core concepts of Ansible and describe the process of leveraging it for configuration management in the context of Terraform-based deployments. The fourth part will illustrate an integration between Terraform and Ansible which results in deployment of an Azure VM running SUSE Linux Enterprise Server for SAP with its local storage configured in the manner that represents the recommended volume layout for SAP HANA. 

The information presented here is meant to provide the foundational knowledge of Terraform-based Azure resource provisioning and Ansible-based Linux configuration management. After stepping through this guide, you should be able to prepare for and perform an automated deployment and storage configuration of an Azure VM running Linux by using Terraform and Ansible. This should facilitate exploring more complex implementations suitable for full-fledged SAP deployments in Azure, such as those which form the [SAP Deployment Automation Framework])https://github.com/Azure/sap-hana).

> **Note**: This guide uses the open source version of Terraform [Terraform OSS](https://www.terraform.io/), rather than its Enterprise counterpart [Terraform Enterprise](https://www.hashicorp.com/products/terraform).

> **Note**: For more in-depth coverage of Terraform OSS and Terraform Enterprise, refer to [Terraform Documentation](https://www.terraform.io/docs/index.html).

> **Note**: For more in-depth coverage of Ansible, refer to [Ansible Documentation](https://www.ansible.com/).

## Part 1

### Overview

Your tasks in this lab will include the preparation for the Terraform and Ansible-based deployment of resources required to provision an Azure VM running SLES for SAP, invoking the deployment, validating the outcome of the deployment, and removal of all of the deployed resources.

### Requirements

-   A Microsoft Azure subscription
-   A user account with, at minimum, the Contributor rights in the Azure subscription
-   A lab computer running a modern web browser (Microsoft Edge, Google Chrome, or Mozilla Firefox) with access to Azure

> **Note**: The lab does not require locally installed software. The lab leverages the default configuration of Azure Cloud Shell.

### Introduction to Terraform

Terraform OSS is an open-source software utility created by HashiCorp. Its purpose is to facilitate consistent declarative provisioning model of resources on practically any environment that can be managed via software. Terraform relies on custom configuration files (by convention, files with the extension .tf and tf.json) written in the HashiCorp Configuration Language to describe types and properties of individual resources that form the target provisioning environment. Terraform provides an abstraction layer over managed resources, which is particularly helpful in hybrid and multi-cloud scenarios. One or more configuration files comprise a Terraform configuration, which represents the managed environment.

> **Note**: Terraform Open Source is available as a single binary for multiple operating system platforms, including Windows, macOS, Solaris, and Linux. Yu can download the latest version of the binary (1.0.7 as of September 2021) from https://www.terraform.io/downloads.html] (https://www.terraform.io/downloads.html).
 
The declarative nature of Terraform allows you to describe the intended end state without having to deal with the implementation details. In addition, Terraform maintains a state information, which represents the current status of the target environment, as long as you manage it exclusively by using Terraform.

#### Basic structure of HashiCorp Configuration Language

The syntax of the Terraform language is relatively straightforward. Its basic structure is based on labeled blocks of entries, where a block can correspond to an entity (such as a variable or a managed resource) and arguments representing its properties. Blocks can be nested. Each argument consists of a name (identifying a property of a variable or resource) and a literal or expression representing its value. For example, the following notation describes an Azure resource group containing a virtual network (with both located in the same Azure region):

   ```
   resource "azurerm_resource_group" "hana-resource-group" {
     name       = "hana-lab-resource-group"
     location   = "eastus"
     }
   }

   resource "azurerm_virtual_network" "hana-virtual-network" {
     name                = "vnet1"
     resource_group_name = azurerm_resource_group.hana-resource-group.name
     location            = azurerm_resource_group.hana-resource-group.location
     address_space       = ["10.0.0.0/16"]
   }
   ```   

#### Terraform providers

Terraform providers are plugins that provide logical abstraction of API providers capable of managing target resources. For example, the Azure provider serves as the interface to Azure Resource Manager, which exposes API used to interact with Azure resources. The following notation is used to incorporate the Azure provider into the configuration of the target environment:

   ```
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
   ```

> **Note**: To identify the latest version of the Azure resource provider, refer to [Terraform Registry](https://registry.terraform.io/providers/hashicorp/azurerm/latest).

#### Terraform variables

Terraform extensively utilizes variables. A variable declaration resides in its own block and is typically stored in a file with the name variables.tf (althoug that's not a requirement). For example, the following blocks declare the `az_region` and `az_resource_group` variables.

   ```
   variable "az_region" {
     description = "The name of an Azure region that will host deployed resources"
     default = "eastus"
   }

   variable "az_resource_group" {
     description = "The name of an Azure resource group that contain host deployed resources"
     default = "hana-lab-resource-group"
   }
   ```
By using these variables, you modify the block that creates the target Azure resource group:

   ```
   resource "azurerm_resource_group" "hana-resource-group" {
     name       = var.az_resource_group
     location   = var.az_region
   }
   ```

This facilitates future updates, especially if the references to the Azure region and the resource group appear multiple times throughout multiple Terraform configuration files. In addition, it becomes more straightforward to use the same set of configuration files to provision the same set of resources across multiple target environments.

Assigning non-default values to variables is typically done by using files with extension .tfvars. If the file name is set to terraform.tfvars (or its extension changed to .auto.tfvars), its content will be automatically loaded into Terraform configuration. Assigning the default value to a variable in a .tf file makes the explicit assignment optional (the default value is overridden in case of an explicit assignment).

#### Terraform expressions

Expressions are used to reference or calculate values within a configuration. In the simplest case, an expression is a literal value, such as a string or number. More complex ones include arithmetic and conditional operations, references to data exported by resources, and built-in functions. For example, the following argument assignment illustrates the use of conditional expression to determine whether a private IP address allocation is static or dynamic:

   ```
   private_ip_address_allocation = var.private_ip_address != local.empty_string ? local.static : local.dynamic
   ```

#### Terraform file processing

To derive its configuration, Terraform automatically loads all of the .tf and .tf.json files within the directory structure you use for deployment. To avoid conflicts, each file should define a distinct set of entities. While there is an option to implement overrides, this is typically not recommended due to increased complexity. 

#### Terraform modules

In more involved scenarios, it might be beneficial to use multiple Terraform modules. A module constitutes a container hosting multiple resources that are typically deployed and managed together. This approach facilitates reusability and simplifies testing, however it might lead to increased complexity. 

Every Terraform configuration consists of at least one module, known as its root module, which contains the resources defined in the .tf files in the same directory from which you initiate the provisioning process. With the multi-module approach, the root module calls other modules, referred to as child modules. 

For example, for deployment of SAP HANA to Azure VMs, you might consider creating the following modules:

- **common_setup** - provisioning a target resource group with a virtual network containing a subnet and a network security group associated with the subnets
- **generic_nic_and_pip** - provisioning a network interface and public IP address
- **generic_vm_and_disk_creation** - provisioning the operating system and data disks, as well as the corresponding Azure VMs
- **create_hdb_node** - combining the provisioning of an Azure VM with its storage and network resources by calling the **generic_nic_and_pip** and **generic_vm_and_disk_creation** child modules
- **single_node_hana** - provisioning the target environment by calling the **common_setup** and **create_hdb_node** child modules (this facilitates deployment of multiple Azure VMs into the same virtual network).

##### Interaction between modules

Child modules are defined by using the same configuration language as the root modules. However, resources defined in a module are dedicated to that module, so the calling module cannot directly access their attributes. To allow for an interaction between the calling and called modules, modules support:

- Input variables to accept values from the calling module. 
- Output values to return results to the calling module. The calling module can assign these values to its own arguments or propagate them as arguments when calling other modules.

When working with modules, it is also important to keep in mind the difference between automatically-loaded .tfvars files and variable defaults. In case of the former, the variable assignments apply only to the calling module, while, with the latter, child modules are in scope, so effectively variables with defaults are optional as well.

To define a child module, simply create a new directory and add to it .tf files defining the intended functionality. Terraform can load modules from a local file system path or from a remote repository. To call a child module, add a module block referencing it within the parent module and, if applicable, set values for its arguments. The module block includes a source argument, which is a meta-argument required by Terraform. Its value points to the location hosting configuration files of the called module. For example, the following listing illustrates the file system structure hosting the modules that implement deployment of SAP HANA to Azure VMs:

   ```
   └──common_setup
        └──main.tf
        └──nsg.tf
        └──outputs.tf
        └──variables.tf
        └──versions.tf
   └──create_hdb_node
        └──main.tf
        └──outputs.tf
        └──variables.tf
        └──versions.tf
   └──generic_nic_and_pip
        └──main.tf
        └──outputs.tf
        └──variables.tf
        └──versions.tf
   └──generic_vm_and_disk_creation
        └──main.tf
        └──outputs.tf
        └──variables.tf
        └──versions.tf
   └──single_node_hana
        └──outputs.tf
        └──single-node-hana.tf
        └──terraform.tfvars
        └──variables.tf
        └──versions.tf
   ```

With this folder and file hierarchy in place, you could call the **nic_and_pip_setup** module by using the following block in the **create_hdb_node** module:

   ```
   module "nic_and_pip_setup" {
     source = "../generic_nic_and_pip"

     az_resource_group         = var.az_resource_group
     az_region                 = var.az_region
     name                      = local.machine_name
     nsg_id                    = var.nsg_id
     subnet_id                 = var.hana_subnet_id
     private_ip_address        = var.private_ip_address
     public_ip_allocation_type = var.public_ip_allocation_type
     backend_ip_pool_ids       = var.backend_ip_pool_ids
   }
   ```

#### Terraform state

The declarative approach implemented by Terraform allows you to identify the actual state of managed resources. Terraform automatically keeps track of that state. By default, Terraform stores it locally in a file named terraform.tfstate. This might be sufficient if you are the sole person administering the target environment, but it will likely lead to conflicts in a distributed environment with multiple stakeholders responsible for resource administration. To address such scenarios, Terraform supports remote data stores, such as Azure Storage. In addition, depending on the data store choice, Terraform provides the ability to lock the state for all write operations. As long as Terraform is the sole resource provisioning methodology, this effectively prevents conflicts that could result in corrupting the state database.

#### Implementing Terraform configuration

Implementing Terraform configuration is typically performed by using a sequence of three commands:

- `terraform init` initializes the working directory. Terraform locates and parses module blocks, identifies direct and indirect references to providers and saves the corresponding plugins in a subdirectory of the .terraform directory in the file system location from which this command is being run.
- `terraform plan -out=tfplan` creates a provisioning plan and saves it to a local file named tfplan. 
- `terraform apply -input=false tfplan -auto-approve` applies the plan created in the previous step, effectively starting the resource provisioning process without a prompt for confirmation.

You can use additional attributes when running these commands, for example, in order to explicitly set values of specific variables rather than relying on the content of the tfvar files. It is also possible, although not recommended to run `terraform apply` without preceding `terraform plan` and providing the name of the local file containing the provisioning plan.

#### Additional common Terraform commands

The terraform `show command` generates a readable output of a state or plan file. This allows you to inspect either one to either examine the current state of the environment or to ensure that the planned operations match your expectations

## Part 2

### Lab instructions

1. Navigate to the Azure portal and sign in to the Azure subscription that you will be using in this lab with an account that has at least the Contributor role within the scope of that subscription.
1. In the Azure portal, start a Bash session in Cloud Shell.
1. From the Bash session, run the following command to remove any pre-existing directory containing a clone of the repo you'll be using in this lab:

   ```
   rm ./learn-sap-tf -rf
   ```   

1. From the Bash session, run the following command to clone the repo you'll be using in this lab:

   ```
   git clone https://github.com/polichtm/learn-sap-tf.git
   ```   

1. From the Bash session, run the following command to change the current directory to `./learn-sap-tf/deploy/modules/single_node_hana/`:

   ```
   cd ./learn-sap-tf/deploy/modules/single_node_hana/
   ```

1. From the Bash session, use your preferred text editor to open `\deploy\moduls\single_node_hana\single-node-hana.tf` file and comment out the block of the **create_hdb** module by adding leading `/*` and trailing `*/`, so it looks like the following listing:

   ```
   /*
   module "create_hdb" {
     source                    = "../create_hdb_node"
     az_resource_group         = module.common_setup.resource_group_name
     az_region                 = var.az_region
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
   */
   ```

1. Since this child module is referenced in the outputs.tf within the root module, you will need to temporarily exclude it from the scope of Terraform processing. To accomplish this, simply rename its extension from .tf to .tf_ by running the following command from the Bash session:

   ```
   mv outputs.tf outputs.tf_
   ```   

   > **Note**: In general, before you start a Terraform-based deployment, you need to sign in to Azure AD to gain access to the target Azure subscription. In this case, sign-in is not necessary since Azure Cloud Shell automatically provides authenticated access. 

1. From the Bash session, run the following commands to download and extract the Terraform binary to the current directory:

   ```
   curl -o https://releases.hashicorp.com/terraform/1.0.7/terraform_1.0.7_linux_amd64.zip
   unzip terraform.zip
   ```

1. From the Bash session, run the following command to initialize the working directory:

   ```
   terraform init
   ```   

1. From the Bash session, run the following command to create a provisioning plan and save it to a local file named tfplan_common_setup:

   ```
   terraform plan -out tfplan_common_setup
   ```   

1. From the Bash session, review the generated output, which should have the following format:

   ```
   Terraform used the selected providers to generate the following execution
   plan. Resource actions are indicated with the following symbols:
     + create
    <= read (data resources)

   Terraform will perform the following actions:

     # module.common_setup.data.azurerm_network_security_group.nsg_info will be read during apply
     # (config refers to values not yet known)
    <= data "azurerm_network_security_group" "nsg_info"  {
         + id                  = (known after apply)
         + location            = (known after apply)
         + name                = "I20-nsg"
         + resource_group_name = "hana-sn-RG"
         + security_rule       = (known after apply)
         + tags                = (known after apply)

         + timeouts {
             + read = (known after apply)
         }
     }

     # module.common_setup.azurerm_network_security_group.sap_nsg will be created
     + resource "azurerm_network_security_group" "sap_nsg" {
         + id                  = (known after apply)
         + location            = "westus2"
         + name                = "I20-nsg"
         + resource_group_name = "hana-sn-RG"
         + security_rule       = [
             + {
                 + access                                     = "Allow"
                 + description                                = ""
                 + destination_address_prefix                 = "*"
                 + destination_address_prefixes               = []
                 + destination_application_security_group_ids = []
                 + destination_port_range                     = "22"
                 + destination_port_ranges                    = []
                 + direction                                  = "Inbound"
                 + name                                       = "SSH"
                 + priority                                   = 101
                 + protocol                                   = "Tcp"
                 + source_address_prefix                      = ""
                 + source_address_prefixes                    = [
                     + "0.0.0.0/0",
                   ]
                 + source_application_security_group_ids      = []
                 + source_port_range                          = "*"
                 + source_port_ranges                         = []
               },
             + {
                 + access                                     = "Allow"
                 + description                                = ""
                 + destination_address_prefix                 = "*"
                 + destination_address_prefixes               = []
                 + destination_application_security_group_ids = []
                 + destination_port_range                     = "30100-30199"
                 + destination_port_ranges                    = []
                 + direction                                  = "Inbound"
                 + name                                       = "open-hana-db-ports"
                 + priority                                   = 102
                 + protocol                                   = "Tcp"
                 + source_address_prefix                      = ""
                 + source_address_prefixes                    = [
                     + "0.0.0.0/0",
                   ]
                 + source_application_security_group_ids      = []
                 + source_port_range                          = "*"
                 + source_port_ranges                         = []
               },
           ]
       }

     # module.common_setup.azurerm_network_security_rule.hana-xsc-rules[0] will be created
     + resource "azurerm_network_security_rule" "hana-xsc-rules" {
         + access                      = "Allow"
         + destination_address_prefix  = "*"
         + destination_port_range      = "8001"
         + direction                   = "Inbound"
         + id                          = (known after apply)
         + name                        = "XSC-HTTP"
         + network_security_group_name = "I20-nsg"
         + priority                    = 105
         + protocol                    = "Tcp"
         + resource_group_name         = "hana-sn-RG"
         + source_address_prefixes     = [
             + "0.0.0.0/0",
           ]
         + source_port_range           = "*"
       }

     # module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1] will be created
     + resource "azurerm_network_security_rule" "hana-xsc-rules" {
         + access                      = "Allow"
         + destination_address_prefix  = "*"
         + destination_port_range      = "4301"
         + direction                   = "Inbound"
         + id                          = (known after apply)
         + name                        = "XSC-HTTPS"
         + network_security_group_name = "I20-nsg"
         + priority                    = 106
         + protocol                    = "Tcp"
         + resource_group_name         = "hana-sn-RG"
         + source_address_prefixes     = [
             + "0.0.0.0/0",
           ]
         + source_port_range           = "*"
       }

     # module.common_setup.azurerm_resource_group.hana-resource-group will be created
     + resource "azurerm_resource_group" "hana-resource-group" {
         + id       = (known after apply)
         + location = "westus2"
         + name     = "hana-sn-RG"
         + tags     = {
             + "environment" = "Terraform SAP HANA deployment"
           }
       }

     # module.common_setup.azurerm_subnet.subnet will be created
     + resource "azurerm_subnet" "subnet" {
         + address_prefix                                 = (known after apply)
         + address_prefixes                               = [
             + "10.0.0.0/24",
           ]
         + enforce_private_link_endpoint_network_policies = false
         + enforce_private_link_service_network_policies  = false
         + id                                             = (known after apply)
         + name                                           = "hdb-subnet"
         + resource_group_name                            = "hana-sn-RG"
         + virtual_network_name                           = "I20-vnet"
       }

     # module.common_setup.azurerm_subnet_network_security_group_association.subnet-nsg-association will be created
     + resource "azurerm_subnet_network_security_group_association" "subnet-nsg-association" {
         + id                        = (known after apply)
         + network_security_group_id = (known after apply)
         + subnet_id                 = (known after apply)
       }

     # module.common_setup.azurerm_virtual_network.vnet will be created
     + resource "azurerm_virtual_network" "vnet" {
         + address_space         = [
             + "10.0.0.0/21",
           ]
         + dns_servers           = (known after apply)
         + guid                  = (known after apply)
         + id                    = (known after apply)
         + location              = "westus2"
         + name                  = "I20-vnet"
         + resource_group_name   = "hana-sn-RG"
         + subnet                = (known after apply)
         + vm_protection_enabled = false
       }

   Plan: 7 to add, 0 to change, 0 to destroy.

   ─────────────────────────────────────────────────────────────────────────────

   Saved the plan to: tfplan_common_setup

   To perform exactly these actions, run the following command to apply:
       terraform apply "tfplan_common_setup"
   ```

1. From the Bash session, run the following command to deploy the 7 resources included in the plan generated by Terraform:

   ```
   terraform apply -auto-approve tfplan_common_setup
   ```   

1. From the Bash session, examine the output generated during the deployment and verify that it includes that entry `Apply complete! Resources: 7 added, 0 changed, 0 destroyed`.

   ```
   module.common_setup.azurerm_resource_group.hana-resource-group: Creating...
   module.common_setup.azurerm_resource_group.hana-resource-group: Creation complete after 1s [id=/subscriptions/2739aaee-92c7-423f-b14a-a9e56e278973/resourceGroups/hana-sn-RG]
   module.common_setup.azurerm_virtual_network.vnet: Creating...
   module.common_setup.azurerm_network_security_group.sap_nsg: Creating...
   module.common_setup.azurerm_virtual_network.vnet: Creation complete after 8s [id=/subscriptions/2739aaee-92c7-423f-b14a-a9e56e278973/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet]
   module.common_setup.azurerm_subnet.subnet: Creating...
   module.common_setup.azurerm_network_security_group.sap_nsg: Creation complete after 8s [id=/subscriptions/2739aaee-92c7-423f-b14a-a9e56e278973/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg]
   module.common_setup.data.azurerm_network_security_group.nsg_info: Reading...
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1]: Creating...
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[0]: Creating...
   module.common_setup.data.azurerm_network_security_group.nsg_info: Read complete after 0s [id=/subscriptions/2739aaee-92c7-423f-b14a-a9e56e278973/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg]
   module.common_setup.azurerm_subnet.subnet: Creation complete after 4s [id=/subscriptions/2739aaee-92c7-423f-b14a-a9e56e278973/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet/subnets/hdb-subnet]
   module.common_setup.azurerm_subnet_network_security_group_association.subnet-nsg-association: Creating...
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[0]: Still creating... [10s elapsed]
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1]: Still creating... [10s elapsed]
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[0]: Creation complete after 12s [id=/subscriptions/2739aaee-92c7-423f-b14a-a9e56e278973/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg/securityRules/XSC-HTTP]
   module.common_setup.azurerm_subnet_network_security_group_association.subnet-nsg-association: Still creating... [10s elapsed]
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1]: Still creating... [20s elapsed]
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1]: Creation complete after 23s [id=/subscriptions/2739aaee-92c7-423f-b14a-a9e56e278973/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg/securityRules/XSC-HTTPS]
   module.common_setup.azurerm_subnet_network_security_group_association.subnet-nsg-association: Still creating... [20s elapsed]
   module.common_setup.azurerm_subnet_network_security_group_association.subnet-nsg-association: Creation complete after 23s [id=/subscriptions/2739aaee-92c7-423f-b14a-a9e56e278973/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet/subnets/hdb-subnet]

   Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
   ```

1. From the Bash session, run the following command to examine the resources provisioned by Terraform: 

   ```
   terraform state list
   ```   

1. From the Bash session, examine the output generated by the command you ran in the previous step and verify that it lists the following entries:

   ```   
   module.common_setup.data.azurerm_network_security_group.nsg_info
   module.common_setup.azurerm_network_security_group.sap_nsg
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[0]
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1]
   module.common_setup.azurerm_resource_group.hana-resource-group
   module.common_setup.azurerm_subnet.subnet
   module.common_setup.azurerm_subnet_network_security_group_association.subnet-nsg-association
   module.common_setup.azurerm_virtual_network.vnet
   ```   

1. From the Bash session, run the following command to examine details of the virtual network.

   ```
   terraform state show module.common_setup.azurerm_virtual_network.vnet
   ```   

> **Note**: You can use the same command to examine details of any other resource provisioned by Terraform (as long as it's part of its state) by providing the Terraform identifier of that resource as the parameter of the `terraform state show` command.

1. From the Bash session, examine the output generated by the command you ran in the previous step and verify that it resembles the following content:

   ```
   $ terraform state show module.common_setup.azurerm_virtual_network.vnet
   # module.common_setup.azurerm_virtual_network.vnet:
   resource "azurerm_virtual_network" "vnet" {
       address_space         = [
           "10.0.0.0/21",
       ]
       dns_servers           = []
       guid                  = "81667441-ff29-42be-90d4-67d7c8c61649"
       id                    = "/subscriptions/f2a433cb-fe79-4736-99da-352777fa4171/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet"
       location              = "westus2"
       name                  = "I20-vnet"
       resource_group_name   = "hana-sn-RG"
       subnet                = []
       vm_protection_enabled = false
   }
   ```

1. From the Bash session, revert the changes you applied to the **single-node.hana.tf** and **outputs.tf** file and 
1. From the Bash session, run the following command to create a provisioning plan and save it to a local file named tfplan_full_setup:

   ```
   terraform plan -out tfplan_full_setup
   ```   

1. From the Bash session, review the generated output, which should have the following format:

   ```
   $ terraform plan -out tfplan_full_setup
   module.common_setup.azurerm_resource_group.hana-resource-group: Refreshing state... [id=/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG]
   module.common_setup.azurerm_network_security_group.sap_nsg: Refreshing state... [id=/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg]
   module.common_setup.azurerm_virtual_network.vnet: Refreshing state... [id=/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet]
   module.common_setup.azurerm_subnet.subnet: Refreshing state... [id=/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet/subnets/hdb-subnet]
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[0]: Refreshing state... [id=/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg/securityRules/XSC-HTTP]
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1]: Refreshing state... [id=/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg/securityRules/XSC-HTTPS]
   module.common_setup.azurerm_subnet_network_security_group_association.subnet-nsg-association: Refreshing state... [id=/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet/subnets/hdb-subnet]

   Note: Objects have changed outside of Terraform

   Terraform detected the following changes made outside of Terraform since the
   last "terraform apply":

     # module.common_setup.azurerm_virtual_network.vnet has been changed
        ~ resource "azurerm_virtual_network" "vnet" {
           id                    = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet"
           name                  = "I20-vnet"
         ~ subnet                = [
             + {
                 + address_prefix = "10.0.0.0/24"
                 + id             = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet/subnets/hdb-subnet"
                 + name           = "hdb-subnet"
                 + security_group = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg"
               },
           ]
         + tags                  = {}
           # (6 unchanged attributes hidden)
         }
     # module.common_setup.azurerm_network_security_group.sap_nsg has been changed
        ~ resource "azurerm_network_security_group" "sap_nsg" {
           id                  = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg"
           name                = "I20-nsg"
         ~ security_rule       = [
             + {
                 + access                                     = "Allow"
                 + description                                = ""
                 + destination_address_prefix                 = "*"
                 + destination_address_prefixes               = []
                 + destination_application_security_group_ids = []
                 + destination_port_range                     = "4301"
                 + destination_port_ranges                    = []
                 + direction                                  = "Inbound"
                 + name                                       = "XSC-HTTPS"
                 + priority                                   = 106
                 + protocol                                   = "Tcp"
                 + source_address_prefix                      = ""
                 + source_address_prefixes                    = [
                     + "0.0.0.0/0",
                   ]
                 + source_application_security_group_ids      = []
                 + source_port_range                          = "*"
                 + source_port_ranges                         = []
               },
             + {
                 + access                                     = "Allow"
                 + description                                = ""
                 + destination_address_prefix                 = "*"
                 + destination_address_prefixes               = []
                 + destination_application_security_group_ids = []
                 + destination_port_range                     = "8001"
                 + destination_port_ranges                    = []
                 + direction                                  = "Inbound"
                 + name                                       = "XSC-HTTP"
                 + priority                                   = 105
                 + protocol                                   = "Tcp"
                 + source_address_prefix                      = ""
                 + source_address_prefixes                    = [
                     + "0.0.0.0/0",
                   ]
                 + source_application_security_group_ids      = []
                 + source_port_range                          = "*"
                 + source_port_ranges                         = []
               },
               # (2 unchanged elements hidden)
           ]
         + tags                = {}
           # (2 unchanged attributes hidden)
       }
     # module.common_setup.azurerm_network_security_rule.hana-xsc-rules[0] has been changed
     ~ resource "azurerm_network_security_rule" "hana-xsc-rules" {
         + destination_address_prefixes               = []
         + destination_application_security_group_ids = []
         + destination_port_ranges                    = []
           id                                         = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg/securityRules/XSC-HTTP"
           name                                       = "XSC-HTTP"
         + source_application_security_group_ids      = []
         + source_port_ranges                         = []
           # (10 unchanged attributes hidden)
       }
     # module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1] has been changed
     ~ resource "azurerm_network_security_rule" "hana-xsc-rules" {
         + destination_address_prefixes               = []
         + destination_application_security_group_ids = []
         + destination_port_ranges                    = []
           id                                         = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg/securityRules/XSC-HTTPS"
           name                                       = "XSC-HTTPS"
         + source_application_security_group_ids      = []
         + source_port_ranges                         = []
           # (10 unchanged attributes hidden)
       }
     # module.common_setup.azurerm_subnet.subnet has been changed
     ~ resource "azurerm_subnet" "subnet" {
           id                                             = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet/subnets/hdb-subnet"
           name                                           = "hdb-subnet"
         + service_endpoint_policy_ids                    = []
         + service_endpoints                              = []
           # (6 unchanged attributes hidden)
       }

   Unless you have made equivalent changes to your configuration, or ignored the
   relevant attributes using ignore_changes, the following plan may include
   actions to undo or respond to these changes.

   ─────────────────────────────────────────────────────────────────────────────

   Terraform used the selected providers to generate the following execution
   plan. Resource actions are indicated with the following symbols:
     + create
     ~ update in-place
    <= read (data resources)

   Terraform will perform the following actions:

     # module.common_setup.data.azurerm_network_security_group.nsg_info will be read during apply
     # (config refers to values not yet known)
    <= data "azurerm_network_security_group" "nsg_info"  {
         ~ id                  = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg" -> (known after apply)
         ~ location            = "westus2" -> (known after apply)
           name                = "I20-nsg"
         ~ security_rule       = [
             - {
                 - access                                     = "Allow"
                 - description                                = ""
                 - destination_address_prefix                 = "*"
                 - destination_address_prefixes               = []
                 - destination_application_security_group_ids = []
                 - destination_port_range                     = "30100-30199"
                 - destination_port_ranges                    = []
                 - direction                                  = "Inbound"
                 - name                                       = "open-hana-db-ports"
                 - priority                                   = 102
                 - protocol                                   = "Tcp"
                 - source_address_prefix                      = ""
                 - source_address_prefixes                    = [
                     - "0.0.0.0/0",
                   ]
                 - source_application_security_group_ids      = []
                 - source_port_range                          = "*"
                 - source_port_ranges                         = []
               },
             - {
                 - access                                     = "Allow"
                 - description                                = ""
                 - destination_address_prefix                 = "*"
                 - destination_address_prefixes               = []
                 - destination_application_security_group_ids = []
                 - destination_port_range                     = "22"
                 - destination_port_ranges                    = []
                 - direction                                  = "Inbound"
                 - name                                       = "SSH"
                 - priority                                   = 101
                 - protocol                                   = "Tcp"
                 - source_address_prefix                      = ""
                 - source_address_prefixes                    = [
                     - "0.0.0.0/0",
                   ]
                 - source_application_security_group_ids      = []
                 - source_port_range                          = "*"
                 - source_port_ranges                         = []
               },
           ] -> (known after apply)
         ~ tags                = {} -> (known after apply)
           # (1 unchanged attribute hidden)

         + timeouts {
             + read = (known after apply)
           }
       }

     # module.common_setup.azurerm_network_security_group.sap_nsg will be updated in-place
     ~ resource "azurerm_network_security_group" "sap_nsg" {
           id                  = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/networkSecurityGroups/I20-nsg"
           name                = "I20-nsg"
         ~ security_rule       = [
             - {
                 - access                                     = "Allow"
                 - description                                = ""
                 - destination_address_prefix                 = "*"
                 - destination_address_prefixes               = []
                 - destination_application_security_group_ids = []
                 - destination_port_range                     = "22"
                 - destination_port_ranges                    = []
                 - direction                                  = "Inbound"
                 - name                                       = "SSH"
                 - priority                                   = 101
                 - protocol                                   = "Tcp"
                 - source_address_prefix                      = ""
                 - source_address_prefixes                    = [
                     - "0.0.0.0/0",
                   ]
                 - source_application_security_group_ids      = []
                 - source_port_range                          = "*"
                 - source_port_ranges                         = []
               },
             - {
                 - access                                     = "Allow"
                 - description                                = ""
                 - destination_address_prefix                 = "*"
                 - destination_address_prefixes               = []
                 - destination_application_security_group_ids = []
                 - destination_port_range                     = "30100-30199"
                 - destination_port_ranges                    = []
                 - direction                                  = "Inbound"
                 - name                                       = "open-hana-db-ports"
                 - priority                                   = 102
                 - protocol                                   = "Tcp"
                 - source_address_prefix                      = ""
                 - source_address_prefixes                    = [
                     - "0.0.0.0/0",
                   ]
                 - source_application_security_group_ids      = []
                 - source_port_range                          = "*"
                 - source_port_ranges                         = []
               },
             - {
                 - access                                     = "Allow"
                 - description                                = ""
                 - destination_address_prefix                 = "*"
                 - destination_address_prefixes               = []
                 - destination_application_security_group_ids = []
                 - destination_port_range                     = "4301"
                 - destination_port_ranges                    = []
                 - direction                                  = "Inbound"
                 - name                                       = "XSC-HTTPS"
                 - priority                                   = 106
                 - protocol                                   = "Tcp"
                 - source_address_prefix                      = ""
                 - source_address_prefixes                    = [
                     - "0.0.0.0/0",
                   ]
                 - source_application_security_group_ids      = []
                 - source_port_range                          = "*"
                 - source_port_ranges                         = []
               },
             - {
                 - access                                     = "Allow"
                 - description                                = ""
                 - destination_address_prefix                 = "*"
                 - destination_address_prefixes               = []
                 - destination_application_security_group_ids = []
                 - destination_port_range                     = "8001"
                 - destination_port_ranges                    = []
                 - direction                                  = "Inbound"
                 - name                                       = "XSC-HTTP"
                 - priority                                   = 105
                 - protocol                                   = "Tcp"
                 - source_address_prefix                      = ""
                 - source_address_prefixes                    = [
                     - "0.0.0.0/0",
                   ]
                 - source_application_security_group_ids      = []
                 - source_port_range                          = "*"
                 - source_port_ranges                         = []
               },
             + {
                 + access                                     = "Allow"
                 + description                                = null
                 + destination_address_prefix                 = "*"
                 + destination_address_prefixes               = []
                 + destination_application_security_group_ids = []
                 + destination_port_range                     = "22"
                 + destination_port_ranges                    = []
                 + direction                                  = "Inbound"
                 + name                                       = "SSH"
                 + priority                                   = 101
                 + protocol                                   = "Tcp"
                 + source_address_prefix                      = null
                 + source_address_prefixes                    = [
                     + "0.0.0.0/0",
                   ]
                 + source_application_security_group_ids      = []
                 + source_port_range                          = "*"
                 + source_port_ranges                         = []
               },
             + {
                 + access                                     = "Allow"
                 + description                                = null
                 + destination_address_prefix                 = "*"
                 + destination_address_prefixes               = []
                 + destination_application_security_group_ids = []
                 + destination_port_range                     = "30100-30199"
                 + destination_port_ranges                    = []
                 + direction                                  = "Inbound"
                 + name                                       = "open-hana-db-ports"
                 + priority                                   = 102
                 + protocol                                   = "Tcp"
                 + source_address_prefix                      = null
                 + source_address_prefixes                    = [
                  + "0.0.0.0/0",
                   ]
                 + source_application_security_group_ids      = []
                 + source_port_range                          = "*"
                 + source_port_ranges                         = []
               },
           ]
           tags                = {}
           # (2 unchanged attributes hidden)
       }

     # module.create_hdb.module.nic_and_pip_setup.azurerm_network_interface.nic will be created
     + resource "azurerm_network_interface" "nic" {
         + applied_dns_servers           = (known after apply)
         + dns_servers                   = (known after apply)
         + enable_accelerated_networking = false
         + enable_ip_forwarding          = false
         + id                            = (known after apply)
         + internal_dns_name_label       = (known after apply)
         + internal_domain_name_suffix   = (known after apply)
         + location                      = "westus2"
         + mac_address                   = (known after apply)
         + name                          = "hdb0-nic"
         + private_ip_address            = (known after apply)
         + private_ip_addresses          = (known after apply)
         + resource_group_name           = "hana-sn-RG"
         + tags                          = {
             + "environment" = "Terraform SAP HANA deployment"
           }
         + virtual_machine_id            = (known after apply)

         + ip_configuration {
             + name                          = "hdb0-nic-configuration"
             + primary                       = (known after apply)
             + private_ip_address            = "10.0.0.6"
             + private_ip_address_allocation = "static"
             + private_ip_address_version    = "IPv4"
             + public_ip_address_id          = (known after apply)
             + subnet_id                     = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet/subnets/hdb-subnet"
           }
       }

     # module.create_hdb.module.nic_and_pip_setup.azurerm_public_ip.pip will be created
     + resource "azurerm_public_ip" "pip" {
         + allocation_method       = "Dynamic"
         + availability_zone       = (known after apply)
         + domain_name_label       = (known after apply)
         + fqdn                    = (known after apply)
         + id                      = (known after apply)
         + idle_timeout_in_minutes = 30
         + ip_address              = (known after apply)
         + ip_version              = "IPv4"
         + location                = "westus2"
         + name                    = "hdb0-pip"
         + resource_group_name     = "hana-sn-RG"
         + sku                     = "Basic"
         + sku_tier                = "Regional"
         + tags                    = {
             + "environment" = "Terraform SAP HANA deployment"
           }
         + zones                   = (known after apply)
       }

     # module.create_hdb.module.nic_and_pip_setup.random_string.pipname will be created
     + resource "random_string" "pipname" {
         + id          = (known after apply)
         + length      = 10
         + lower       = true
         + min_lower   = 0
         + min_numeric = 0
         + min_special = 0
         + min_upper   = 0
         + number      = true
         + result      = (known after apply)
         + special     = false
         + upper       = false
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_managed_disk.disk[0] will be created
     + resource "azurerm_managed_disk" "disk" {
         + create_option        = "Empty"
         + disk_iops_read_write = (known after apply)
         + disk_mbps_read_write = (known after apply)
         + disk_size_gb         = 512
         + id                   = (known after apply)
         + location             = "westus2"
         + name                 = "hdb0-disk0"
         + resource_group_name  = "hana-sn-RG"
         + source_uri           = (known after apply)
         + storage_account_type = "Premium_LRS"
         + tier                 = (known after apply)
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_managed_disk.disk[1] will be created
     + resource "azurerm_managed_disk" "disk" {
         + create_option        = "Empty"
         + disk_iops_read_write = (known after apply)
         + disk_mbps_read_write = (known after apply)
         + disk_size_gb         = 512
         + id                   = (known after apply)
         + location             = "westus2"
         + name                 = "hdb0-disk1"
         + resource_group_name  = "hana-sn-RG"
         + source_uri           = (known after apply)
         + storage_account_type = "Premium_LRS"
         + tier                 = (known after apply)
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_managed_disk.disk[2] will be created
     + resource "azurerm_managed_disk" "disk" {
         + create_option        = "Empty"
         + disk_iops_read_write = (known after apply)
         + disk_mbps_read_write = (known after apply)
         + disk_size_gb         = 512
         + id                   = (known after apply)
         + location             = "westus2"
         + name                 = "hdb0-disk2"
         + resource_group_name  = "hana-sn-RG"
         + source_uri           = (known after apply)
         + storage_account_type = "Premium_LRS"
         + tier                 = (known after apply)
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_storage_account.bootdiagstorageaccount will be created
     + resource "azurerm_storage_account" "bootdiagstorageaccount" {
         + access_tier                      = (known after apply)
         + account_kind                     = "StorageV2"
         + account_replication_type         = "LRS"
         + account_tier                     = "Standard"
         + allow_blob_public_access         = false
         + enable_https_traffic_only        = true
         + id                               = (known after apply)
         + is_hns_enabled                   = false
         + large_file_share_enabled         = (known after apply)
         + location                         = "westus2"
         + min_tls_version                  = "TLS1_0"
         + name                             = (known after apply)
         + nfsv3_enabled                    = false
         + primary_access_key               = (sensitive value)
         + primary_blob_connection_string   = (sensitive value)
         + primary_blob_endpoint            = (known after apply)
         + primary_blob_host                = (known after apply)
         + primary_connection_string        = (sensitive value)
         + primary_dfs_endpoint             = (known after apply)
         + primary_dfs_host                 = (known after apply)
         + primary_file_endpoint            = (known after apply)
         + primary_file_host                = (known after apply)
         + primary_location                 = (known after apply)
         + primary_queue_endpoint           = (known after apply)
         + primary_queue_host               = (known after apply)
         + primary_table_endpoint           = (known after apply)
         + primary_table_host               = (known after apply)
         + primary_web_endpoint             = (known after apply)
         + primary_web_host                 = (known after apply)
         + resource_group_name              = "hana-sn-RG"
         + secondary_access_key             = (sensitive value)
         + secondary_blob_connection_string = (sensitive value)
         + secondary_blob_endpoint          = (known after apply)
         + secondary_blob_host              = (known after apply)
         + secondary_connection_string      = (sensitive value)
         + secondary_dfs_endpoint           = (known after apply)
         + secondary_dfs_host               = (known after apply)
         + secondary_file_endpoint          = (known after apply)
         + secondary_file_host              = (known after apply)
         + secondary_location               = (known after apply)
         + secondary_queue_endpoint         = (known after apply)
         + secondary_queue_host             = (known after apply)
         + secondary_table_endpoint         = (known after apply)
         + secondary_table_host             = (known after apply)
         + secondary_web_endpoint           = (known after apply)
         + secondary_web_host               = (known after apply)
         + shared_access_key_enabled        = true
         + tags                             = {
             + "environment" = "Terraform SAP HANA deployment"
           }

         + blob_properties {
             + change_feed_enabled      = (known after apply)
             + default_service_version  = (known after apply)
             + last_access_time_enabled = (known after apply)
             + versioning_enabled       = (known after apply)

             + container_delete_retention_policy {
                 + days = (known after apply)
               }

             + cors_rule {
                 + allowed_headers    = (known after apply)
                 + allowed_methods    = (known after apply)
                 + allowed_origins    = (known after apply)
                 + exposed_headers    = (known after apply)
                 + max_age_in_seconds = (known after apply)
               }

             + delete_retention_policy {
                 + days = (known after apply)
               }
           }

         + identity {
             + identity_ids = (known after apply)
             + principal_id = (known after apply)
             + tenant_id    = (known after apply)
             + type         = (known after apply)
           }

         + network_rules {
             + bypass                     = (known after apply)
             + default_action             = (known after apply)
             + ip_rules                   = (known after apply)
             + virtual_network_subnet_ids = (known after apply)

             + private_link_access {
                 + endpoint_resource_id = (known after apply)
                 + endpoint_tenant_id   = (known after apply)
               }
           }

         + queue_properties {
             + cors_rule {
                 + allowed_headers    = (known after apply)
                 + allowed_methods    = (known after apply)
                 + allowed_origins    = (known after apply)
                 + exposed_headers    = (known after apply)
                 + max_age_in_seconds = (known after apply)
               }

             + hour_metrics {
                 + enabled               = (known after apply)
                 + include_apis          = (known after apply)
                 + retention_policy_days = (known after apply)
                 + version               = (known after apply)
               }

             + logging {
                 + delete                = (known after apply)
                 + read                  = (known after apply)
                 + retention_policy_days = (known after apply)
                 + version               = (known after apply)
                 + write                 = (known after apply)
               }

             + minute_metrics {
                 + enabled               = (known after apply)
                 + include_apis          = (known after apply)
                 + retention_policy_days = (known after apply)
                 + version               = (known after apply)
               }
           }

         + routing {
             + choice                      = (known after apply)
             + publish_internet_endpoints  = (known after apply)
             + publish_microsoft_endpoints = (known after apply)
        }

         + share_properties {
             + cors_rule {
                 + allowed_headers    = (known after apply)
                 + allowed_methods    = (known after apply)
                 + allowed_origins    = (known after apply)
                 + exposed_headers    = (known after apply)
                 + max_age_in_seconds = (known after apply)
               }

             + retention_policy {
                 + days = (known after apply)
               }

             + smb {
                 + authentication_types            = (known after apply)
                 + channel_encryption_type         = (known after apply)
                 + kerberos_ticket_encryption_type = (known after apply)
                 + versions                        = (known after apply)
               }
           }
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine.vm will be created
     + resource "azurerm_virtual_machine" "vm" {
         + availability_set_id              = (known after apply)
         + delete_data_disks_on_termination = false
         + delete_os_disk_on_termination    = true
         + id                               = (known after apply)
         + license_type                     = (known after apply)
         + location                         = "westus2"
         + name                             = "hdb0"
         + network_interface_ids            = (known after apply)
         + resource_group_name              = "hana-sn-RG"
         + tags                             = {
             + "database-hana-sn-RG" = ""
             + "hdb0"                = ""
           }
         + vm_size                          = "Standard_D2s_v3"

         + boot_diagnostics {
             + enabled     = true
             + storage_uri = (known after apply)
           }

         + identity {
             + identity_ids = (known after apply)
             + principal_id = (known after apply)
             + type         = (known after apply)
           }

         + os_profile {
             + admin_username = "labuser"
             + computer_name  = "hdb0"
             + custom_data    = (known after apply)
           }

         + os_profile_linux_config {
             + disable_password_authentication = true

             + ssh_keys {
                 + key_data = <<-EOT
                       ---- BEGIN SSH2 PUBLIC KEY ----
                       Comment: "rsa-key-20210911"
                       AAAAB3NzaC1yc2EAAAADAQABAAABAQCyi9UBbwfLv93GwhS4xzz2xmaOQBkhrKwK
                       Yu9YQ9/9pDOhMC0IdJ5DJe3XtkTovZA9TpYhm5MezUsNdnJCvRSVn2rGWf/hZTPy
                       Gw1e3rEhHjwWGO/5sXThmqaYs976+moGb03VGoOIgrE1vc4lpn4piOaaDetSVDZz
                       A2d8RMzDE3s3GpEp+0niRZ19kKeOA5bR0s7lJL4AyshMrmPPV3IoChzZLptEdKPU
                       NvtF9hwWiLEAtoo0SnsUsadis67li3c5rnolBhLP/+9pqSCwAyLZ5gGkodPcsJdD
                       kiL42OJTf4V9gh04UoJ3Jk18oo97itQIYSAsEKbCJRFMiUuU9Und
                       ---- END SSH2 PUBLIC KEY ----
                   EOT
                 + path     = "/home/labuser/.ssh/authorized_keys"
               }
           }

         + storage_data_disk {
             + caching                   = (known after apply)
             + create_option             = (known after apply)
             + disk_size_gb              = (known after apply)
             + lun                       = (known after apply)
             + managed_disk_id           = (known after apply)
             + managed_disk_type         = (known after apply)
             + name                      = (known after apply)
             + vhd_uri                   = (known after apply)
             + write_accelerator_enabled = (known after apply)
           }

         + storage_image_reference {
             + offer     = "sles-sap-12-sp5"
             + publisher = "SUSE"
             + sku       = "gen1"
             + version   = "latest"
           }

         + storage_os_disk {
             + caching                   = "ReadWrite"
             + create_option             = "FromImage"
             + disk_size_gb              = (known after apply)
             + managed_disk_id           = (known after apply)
             + managed_disk_type         = "Standard_LRS"
             + name                      = "hdb0-OsDisk"
             + os_type                   = (known after apply)
             + write_accelerator_enabled = false
           }
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine_data_disk_attachment.disk[0] will be created
     + resource "azurerm_virtual_machine_data_disk_attachment" "disk" {
         + caching                   = "ReadWrite"
         + create_option             = "Attach"
         + id                        = (known after apply)
         + lun                       = 0
         + managed_disk_id           = (known after apply)
         + virtual_machine_id        = (known after apply)
         + write_accelerator_enabled = false
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine_data_disk_attachment.disk[1] will be created
     + resource "azurerm_virtual_machine_data_disk_attachment" "disk" {
         + caching                   = "ReadWrite"
         + create_option             = "Attach"
         + id                        = (known after apply)
         + lun                       = 1
         + managed_disk_id           = (known after apply)
         + virtual_machine_id        = (known after apply)
         + write_accelerator_enabled = false
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine_data_disk_attachment.disk[2] will be created
     + resource "azurerm_virtual_machine_data_disk_attachment" "disk" {
         + caching                   = "ReadWrite"
         + create_option             = "Attach"
         + id                        = (known after apply)
         + lun                       = 2
         + managed_disk_id           = (known after apply)
         + virtual_machine_id        = (known after apply)
         + write_accelerator_enabled = false
       }

     # module.create_hdb.module.vm_and_disk_creation.random_id.randomId will be created
     + resource "random_id" "randomId" {
         + b64_std     = (known after apply)
         + b64_url     = (known after apply)
         + byte_length = 8
         + dec         = (known after apply)
         + hex         = (known after apply)
         + id          = (known after apply)
         + keepers     = {
             + "resource_group" = "hana-sn-RG"
           }
       }

   Plan: 12 to add, 1 to change, 0 to destroy.

   Changes to Outputs:
     + hdb_ip      = (known after apply)
     + hdb_vm_user = "labuser"

   ─────────────────────────────────────────────────────────────────────────────

   Saved the plan to: tfplan_full_setup

   To perform exactly these actions, run the following command to apply:
       terraform apply "tfplan_full_setup"
   ```
1. From the Bash session, run the following command to deploy the additional 12 resources included in the plan generated by Terraform:

   ```
   terraform apply -auto-approve tfplan_full_setup
   ```   

1. From the Bash session, examine the output generated during the deployment and verify that it includes that entry `Apply complete! Resources: 12 added, 1 changed, 0 destroyed`.
1. From the Bash session, run the following command to examine the resources provisioned by Terraform: 

   ```
   terraform state list
   ```   

1. From the Bash session, examine the output generated by the command you ran in the previous step and verify that it lists the following entries:

   ```   
   module.common_setup.data.azurerm_network_security_group.nsg_info
   module.common_setup.azurerm_network_security_group.sap_nsg
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[0]
   module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1]
   module.common_setup.azurerm_resource_group.hana-resource-group
   module.common_setup.azurerm_subnet.subnet
   module.common_setup.azurerm_subnet_network_security_group_association.subnet-nsg-association
   module.common_setup.azurerm_virtual_network.vnet
   module.create_hdb.module.nic_and_pip_setup.azurerm_network_interface.nic
   module.create_hdb.module.nic_and_pip_setup.azurerm_public_ip.pip
   module.create_hdb.module.nic_and_pip_setup.random_string.pipname
   module.create_hdb.module.vm_and_disk_creation.azurerm_managed_disk.disk[0]
   module.create_hdb.module.vm_and_disk_creation.azurerm_managed_disk.disk[1]
   module.create_hdb.module.vm_and_disk_creation.azurerm_managed_disk.disk[2]
   module.create_hdb.module.vm_and_disk_creation.azurerm_storage_account.bootdiagstorageaccount
   module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine.vm
   module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine_data_disk_attachment.disk[0]
   module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine_data_disk_attachment.disk[1]
   module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine_data_disk_attachment.disk[2]
   module.create_hdb.module.vm_and_disk_creation.random_id.randomId
   ```   

1. In the web browser window displaying the Cloud Shell pane in the Azure portal, open another tab, navigate to the Azure portal, locate the **hana-sn-RG** resource group, review its resources, and verify that their list and settings match the Terraform-defined configuration.
1. Switch back to the web browser tab displaying the Bash session and run the following command to delete the provisioned Azure resources

   ```
   terraform destroy -auto-approve
   ```   

   > **Note**: Wait for the deprovisioning to complete before you proceed to the next part of the lab.

1. Close the Cloud Shell pane.

## Part 3

### Introduction to Ansible 

Ansible is an open-source platform that traditionally used for configuration management and application deployments targeting Linux and Windows operating systems, although by virtue of its extensibility, it also offers the ability to provision and manage cloud resources. It is possible, for example, to perform tasks described in this lab exclusively by using Ansible. However, our objective is to illustrate integration between Terraform and Ansible, with Ansible dedicated exclusively to configuration management and application deployment.

### Ansible components

The core components of Ansible include:

- Control Machine. This is a system with locally installed Ansible components, from which the configurations are run. We will use for this purpose Azure Cloud Shell.

   > **Note**: If you intend to use your own computer to run this lab, use the [Installing Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) documentation to set up Ansible.

- Managed Nodes. These are the target systems that are being managed by Ansible. Note that Ansible does not require any components to be preinstalled on managed nodes. Instead, you need to be able to connect to them in the context of their local root/administrative account.
- Roles. Roles are groupings of configuration and management tasks (which can be combined into reusable modules) that collectively deliver specific functionality. For example, in our lab, there are the following roles:

   - host-name-resolution - adds entries to the local hosts file on a managed node.
   - hotfix - installs on a managed node hotfixes recommended by the SLES vendor
   - imds-reg - registers the current deployment state with Azure's Metadata Service (IMDS)
   - install-python-sdk - install Python packages on a managed node
   - disk-setup - sets up the local volume configuration on a managed node
   - ssh-key-distribute - distributes SSH keys across managed nodes (in case of a clustered deployment)

- Playbooks. Playbooks assign roles to managed nodes, which effectively deliver the desired configuration, deployment, and orchestration functionality. In our case, the playbook has the following format:

   ```
   ---
   - hosts: hdb0
     roles:
       - { role: imds-reg, scenario: "hana-singlenode", deploy_status: "started"}

   - hosts: "hdb0"
     become: true
     roles:
       - disk-setup
       - hotfix

   - hosts: hdb0
     roles:
       - { role: imds-reg, scenario: "hana-singlenode", deploy_status: "finished"}
   ```

- Inventory. An inventory is a list of managed nodes. You can create the inventory manually or dynamically. When operating in Azure, Ansible facilitates implementing a dynamic inventory by relying on the azure_rm.py Python script.

### Combining Terraform and Ansible 

You can combine Terraform and Ansible by leveraging their respective strenghts, with Terraform handling resource provisioning and Ansible performing configuration management. In our scenario, this translates into Terraform provisioning the Azure VM which will host SAP HANA and Ansible configuring its local disk volumes. To invoke Ansible scripts from a Terraform configuration, you can take advantage of provisioners.

### Terraform provisioners

Terraform provisioners facilitate running arbitrary scripts on a local or remote computer in coordination with creation or deletion of the corresponding resource. This makes them suitable for performing configuration management tasks, such as those delivered by Ansible. 

Once the resource provisioning completes, the local-exec provisioner invokes a configuration task on the same computer where Terraform is running. The remote-exec provisioner invokes that task directly on a remote resource. When using remote-exec provisioners, you need to specify settings necessary to connect to the remote resource being targeted. 

When using Ansible, you can use local-exec provisioner to invoke remote configuration by relying on SSH (for Linux) or WinRM (for Windows). Ansible supports the corresponding authentication methods (such as an SSH key pair and passwords). As you invoke execution of an Ansible playbook, you point to the target resource by relying on the Ansible inventory.

Provisioners can be added directly to a resource. For example, in our scenario, we rely on the local-exec provisioner resource referenced in the Terraform child module **playbook-execution**, which is invoked from the **single_node_hana** root module. The latter includes the following content in its main.tf file:

   ```
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

   module "configure_vm" {
     source                   = "../playbook-execution"
     ansible_playbook_path        = var.ansible_playbook_path
     az_resource_group        = module.common_setup.resource_group_name
     sshkey_path_private      = var.sshkey_path_private
     sap_instancenum          = var.sap_instancenum
     sap_sid                  = var.sap_sid
     vm_user                  = var.vm_user
     url_sap_hdbserver        = var.url_sap_hdbserver
     pw_os_sapadm             = var.pw_os_sapadm
     pw_os_sidadm             = var.pw_os_sidadm
     pw_db_system             = var.pw_db_system
     useHana2                 = var.useHana2
     vms_configured           = "${module.create_hdb.machine_hostname}"
     hana1_db_mode            = var.hana1_db_mode
     url_xsa_runtime          = var.url_xsa_runtime
     url_di_core              = var.url_di_core
     url_sapui5               = var.url_sapui5
     url_portal_services      = var.url_portal_services
     url_xs_services          = var.url_xs_services
     url_shine_xsa            = var.url_shine_xsa
     url_xsa_hrtt             = var.url_xsa_hrtt
     url_xsa_webide           = var.url_xsa_webide
     url_xsa_mta              = var.url_xsa_mta
     pwd_db_xsaadmin          = var.pwd_db_xsaadmin
     pwd_db_tenant            = var.pwd_db_tenant
     pwd_db_shine             = var.pwd_db_shine
     email_shine              = var.email_shine
     install_xsa              = var.install_xsa
     install_shine            = var.install_shine
     install_cockpit          = var.install_cockpit
     install_webide           = var.install_webide
     url_cockpit              = var.url_cockpit
   }
   ```

The **playbook-execution** module implements the **local-exec** provisioner which relies on the dynamically generated inventory to invoke the script referenced by the **ansible_playbook_path** variable:

   ```
   resource null_resource "mount-disks-and-configure-hana" {
     provisioner "local-exec" {
       command = <<EOT
       OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
       AZURE_RESOURCE_GROUPS="${var.az_resource_group}" \
       ANSIBLE_HOST_KEY_CHECKING="False" \
       ansible-playbook -u ${var.vm_user} \
       --private-key '${var.sshkey_path_private}' \
       --extra-vars="{ \
        \"url_hdbserver\": \"${var.url_sap_hdbserver}\", \
        \"sap_sid\": \"${var.sap_sid}\", \
        \"sap_instancenum\": \"${var.sap_instancenum}\", \
        \"pwd_os_sapadm\": \"${var.pw_os_sapadm}\", \
        \"pwd_os_sidadm\": \"${var.pw_os_sidadm}\", \
        \"pwd_db_system\": \"${var.pw_db_system}\", \
        \"pwd_hacluster\": \"${var.pw_hacluster}\", \
        \"hdb0_ip\": \"${var.private_ip_address_hdb0}\", \
        \"hdb1_ip\": \"${var.private_ip_address_hdb1}\", \
        \"use_hana2\": ${var.useHana2}, \
        \"hana1_db_mode\": \"${var.hana1_db_mode}\", \
        \"lb_frontend_ip\": \"${var.private_ip_address_lb_frontend}\", \
        \"resource_group\": \"${var.az_resource_group}\", \
        \"url_xsa_runtime\": \"${var.url_xsa_runtime}\", \
        \"url_di_core\": \"${var.url_di_core}\", \
        \"url_sapui5\": \"${var.url_sapui5}\", \
        \"url_portal_services\": \"${var.url_portal_services}\", \
        \"url_xs_services\": \"${var.url_xs_services}\", \
        \"url_shine_xsa\": \"${var.url_shine_xsa}\", \
        \"url_xsa_hrtt\": \"${var.url_xsa_hrtt}\", \
        \"url_xsa_webide\": \"${var.url_xsa_webide}\", \
        \"url_xsa_mta\": \"${var.url_xsa_mta}\", \
        \"url_timeout\": \"${var.url_timeout}\", \
        \"url_retries_cnt\": \"${var.url_retries_cnt}\", \
        \"url_retries_delay\": \"${var.url_retries_delay}\",\
        \"package_retries_cnt\": \"${var.package_retries_cnt}\", \
        \"package_retries_delay\": \"${var.package_retries_delay}\", \
        \"pwd_db_xsaadmin\": \"${var.pwd_db_xsaadmin}\", \
        \"pwd_db_tenant\": \"${var.pwd_db_tenant}\", \
        \"pwd_db_shine\": \"${var.pwd_db_shine}\", \
        \"email_shine\": \"${var.email_shine}\", \
        \"install_xsa\": ${var.install_xsa}, \
        \"install_shine\": ${var.install_shine}, \
        \"install_cockpit\": ${var.install_cockpit}, \
        \"install_webide\": ${var.install_webide}, \
        \"url_cockpit\": \"${var.url_cockpit}\" }" \
        -i '../../../ansible/azure_rm.py' ${var.ansible_playbook_path}
        EOT

       environment = {
         HOSTS = "${var.vms_configured}"
       }
     }
   }
   ```

That value of that variable is assigned in the **variables.tf** file in the **playbook-execution** module.

   ```
   variable "ansible_playbook_path" {
     description = "Path from this module to the playbook"
     default     = "../../../ansible/single_node_playbook.yml"
   }
   ```

The corresponding playbook resides in the dedicated **ansible** directory structure, which is part of the following file system hierarchy:

   ```
   └──deploy
        └──modules
             └──common_setup
                   └──main.tf
                   └──nsg.tf
                   └──outputs.tf
                   └──variables.tf
                   └──versions.tf
        └──create_hdb_node
                   └──main.tf
                   └──outputs.tf
                   └──variables.tf
                   └──versions.tf
        └──generic_nic_and_pip
                   └──main.tf
                   └──outputs.tf
                   └──variables.tf
                   └──versions.tf
        └──generic_vm_and_disk_creation
                   └──main.tf
                   └──outputs.tf
                   └──variables.tf
                   └──versions.tf
        └──single_node_hana
                   └──outputs.tf
                   └──single-node-hana.tf
                   └──terraform.tfvars
                   └──variables.tf
                   └──versions.tf
        └──playbook-execution
                   └──main.tf
                   └──variables.tf
   └──ansible
        └──roles
             └──roles
                   └──disk-setup
                         └──defaults
                              └──main.yml
                         └──tasks
                              └──main.yml
                   └──host-name-resolution
                         └──tasks
                              └──main.yml
                   └──hotfix
                         └──tasks
                              └──main.yml
                   └──imds-reg
                         └──defaults
                              └──main.yml
                         └──tasks
                              └──main.yml
                   └──install-python-sdk
                         └──tasks
                              └──main.yml
                              └──requirements.txt
                   └──ssh-key-distribute
                         └──tasks
                              └──main.yml
        └──azure_rm.py
        └──configcheck.yml
        └──requirements.yml
        └──single_node_playbook.yml

   ```

## Part 4

### Lab instructions

1. Navigate to the Azure portal and sign in to the Azure subscription that you will be using in this lab with an account that has at least the Contributor role within the scope of that subscription.
1. In the Azure portal, start a Bash session in Cloud Shell.
1. From the Bash session, run the following command to remove any pre-existing directory containing a clone of the repo you'll be using in this lab:

   ```
   rm ./learn-sap-tfwa -rf
   ```   

1. From the Bash session, run the following command to clone the repo you'll be using in this lab:

   ```
   git clone https://github.com/polichtm/learn-sap-tfwa.git
   ```   

1. From the Bash session, run the following command to change the current directory to `./learn-sap-tfwa/deploy/modules/single_node_hana/`:

   ```
   cd ./learn-sap-tfwa/deploy/modules/single_node_hana/
   ```   

1. From the Bash session, run the following command to allow execution of the Ansible inventory script azure_rm.py:

   ```
   chmod +x ../../../ansible/azure_rm.py
   ```   

1. From the Bash session, run the following commands to download and extract the Terraform binary to the current directory:

   ```
   curl -o https://releases.hashicorp.com/terraform/1.0.7/terraform_1.0.7_linux_amd64.zip
   unzip terraform.zip
   ```

1. From the Bash session, run the following command to initialize the working directory:

   ```
   terraform init
   ```   

1. From the Bash session, run the following command to create a provisioning plan and save it to a local file named tfplan_full_setup:

   ```
   terraform plan -out tfplan_tf_with_ansible
   ```   

1. From the Bash session, review the generated output, which should have the following format:

   ```
   Terraform used the selected providers to generate the following execution
   plan. Resource actions are indicated with the following symbols:
     + create
    <= read (data resources)

   Terraform will perform the following actions:

     # module.common_setup.data.azurerm_network_security_group.nsg_info will be read during apply
     # (config refers to values not yet known)
    <= data "azurerm_network_security_group" "nsg_info"  {
         + id                  = (known after apply)
         + location            = (known after apply)
         + name                = "I20-nsg"
         + resource_group_name = "hana-sn-RG"
         + security_rule       = (known after apply)
         + tags                = (known after apply)

         + timeouts {
             + read = (known after apply)
         }
     }

     # module.common_setup.azurerm_network_security_group.sap_nsg will be created
     + resource "azurerm_network_security_group" "sap_nsg" {
         + id                  = (known after apply)
         + location            = "westus2"
         + name                = "I20-nsg"
         + resource_group_name = "hana-sn-RG"
         + security_rule       = [
             + {
                 + access                                     = "Allow"
                 + description                                = ""
                 + destination_address_prefix                 = "*"
                 + destination_address_prefixes               = []
                 + destination_application_security_group_ids = []
                 + destination_port_range                     = "22"
                 + destination_port_ranges                    = []
                 + direction                                  = "Inbound"
                 + name                                       = "SSH"
                 + priority                                   = 101
                 + protocol                                   = "Tcp"
                 + source_address_prefix                      = ""
                 + source_address_prefixes                    = [
                     + "0.0.0.0/0",
                   ]
                 + source_application_security_group_ids      = []
                 + source_port_range                          = "*"
                 + source_port_ranges                         = []
               },
             + {
                 + access                                     = "Allow"
                 + description                                = ""
                 + destination_address_prefix                 = "*"
                 + destination_address_prefixes               = []
                 + destination_application_security_group_ids = []
                 + destination_port_range                     = "30100-30199"
                 + destination_port_ranges                    = []
                 + direction                                  = "Inbound"
                 + name                                       = "open-hana-db-ports"
                 + priority                                   = 102
                 + protocol                                   = "Tcp"
                 + source_address_prefix                      = ""
                 + source_address_prefixes                    = [
                     + "0.0.0.0/0",
                   ]
                 + source_application_security_group_ids      = []
                 + source_port_range                          = "*"
                 + source_port_ranges                         = []
               },
           ]
       }

     # module.common_setup.azurerm_network_security_rule.hana-xsc-rules[0] will be created
     + resource "azurerm_network_security_rule" "hana-xsc-rules" {
         + access                      = "Allow"
         + destination_address_prefix  = "*"
         + destination_port_range      = "8001"
         + direction                   = "Inbound"
         + id                          = (known after apply)
         + name                        = "XSC-HTTP"
         + network_security_group_name = "I20-nsg"
         + priority                    = 105
         + protocol                    = "Tcp"
         + resource_group_name         = "hana-sn-RG"
         + source_address_prefixes     = [
             + "0.0.0.0/0",
           ]
         + source_port_range           = "*"
       }

     # module.common_setup.azurerm_network_security_rule.hana-xsc-rules[1] will be created
     + resource "azurerm_network_security_rule" "hana-xsc-rules" {
         + access                      = "Allow"
         + destination_address_prefix  = "*"
         + destination_port_range      = "4301"
         + direction                   = "Inbound"
         + id                          = (known after apply)
         + name                        = "XSC-HTTPS"
         + network_security_group_name = "I20-nsg"
         + priority                    = 106
         + protocol                    = "Tcp"
         + resource_group_name         = "hana-sn-RG"
         + source_address_prefixes     = [
             + "0.0.0.0/0",
           ]
         + source_port_range           = "*"
       }

     # module.common_setup.azurerm_resource_group.hana-resource-group will be created
     + resource "azurerm_resource_group" "hana-resource-group" {
         + id       = (known after apply)
         + location = "westus2"
         + name     = "hana-sn-RG"
         + tags     = {
             + "environment" = "Terraform SAP HANA deployment"
           }
       }

     # module.common_setup.azurerm_subnet.subnet will be created
     + resource "azurerm_subnet" "subnet" {
         + address_prefix                                 = (known after apply)
         + address_prefixes                               = [
             + "10.0.0.0/24",
           ]
         + enforce_private_link_endpoint_network_policies = false
         + enforce_private_link_service_network_policies  = false
         + id                                             = (known after apply)
         + name                                           = "hdb-subnet"
         + resource_group_name                            = "hana-sn-RG"
         + virtual_network_name                           = "I20-vnet"
       }

     # module.common_setup.azurerm_subnet_network_security_group_association.subnet-nsg-association will be created
     + resource "azurerm_subnet_network_security_group_association" "subnet-nsg-association" {
         + id                        = (known after apply)
         + network_security_group_id = (known after apply)
         + subnet_id                 = (known after apply)
       }

     # module.common_setup.azurerm_virtual_network.vnet will be created
     + resource "azurerm_virtual_network" "vnet" {
         + address_space         = [
             + "10.0.0.0/21",
           ]
         + dns_servers           = (known after apply)
         + guid                  = (known after apply)
         + id                    = (known after apply)
         + location              = "westus2"
         + name                  = "I20-vnet"
         + resource_group_name   = "hana-sn-RG"
         + subnet                = (known after apply)
         + vm_protection_enabled = false
       }

     # module.configure_vm.null_resource.mount-disks-and-configure-hana will be created
     + resource "null_resource" "mount-disks-and-configure-hana" {
         + id = (known after apply)
       }

     # module.create_hdb.module.nic_and_pip_setup.azurerm_network_interface.nic will be created
     + resource "azurerm_network_interface" "nic" {
         + applied_dns_servers           = (known after apply)
         + dns_servers                   = (known after apply)
         + enable_accelerated_networking = false
         + enable_ip_forwarding          = false
         + id                            = (known after apply)
         + internal_dns_name_label       = (known after apply)
         + internal_domain_name_suffix   = (known after apply)
         + location                      = "westus2"
         + mac_address                   = (known after apply)
         + name                          = "hdb0-nic"
         + private_ip_address            = (known after apply)
         + private_ip_addresses          = (known after apply)
         + resource_group_name           = "hana-sn-RG"
         + tags                          = {
             + "environment" = "Terraform SAP HANA deployment"
           }
         + virtual_machine_id            = (known after apply)

         + ip_configuration {
             + name                          = "hdb0-nic-configuration"
             + primary                       = (known after apply)
             + private_ip_address            = "10.0.0.6"
             + private_ip_address_allocation = "static"
             + private_ip_address_version    = "IPv4"
             + public_ip_address_id          = (known after apply)
             + subnet_id                     = "/subscriptions/f2a433ab-fe79-4736-99da-352777fa417d/resourceGroups/hana-sn-RG/providers/Microsoft.Network/virtualNetworks/I20-vnet/subnets/hdb-subnet"
           }
       }

     # module.create_hdb.module.nic_and_pip_setup.azurerm_public_ip.pip will be created
     + resource "azurerm_public_ip" "pip" {
         + allocation_method       = "Dynamic"
         + availability_zone       = (known after apply)
         + domain_name_label       = (known after apply)
         + fqdn                    = (known after apply)
         + id                      = (known after apply)
         + idle_timeout_in_minutes = 30
         + ip_address              = (known after apply)
         + ip_version              = "IPv4"
         + location                = "westus2"
         + name                    = "hdb0-pip"
         + resource_group_name     = "hana-sn-RG"
         + sku                     = "Basic"
         + sku_tier                = "Regional"
         + tags                    = {
             + "environment" = "Terraform SAP HANA deployment"
           }
         + zones                   = (known after apply)
       }

     # module.create_hdb.module.nic_and_pip_setup.random_string.pipname will be created
     + resource "random_string" "pipname" {
         + id          = (known after apply)
         + length      = 10
         + lower       = true
         + min_lower   = 0
         + min_numeric = 0
         + min_special = 0
         + min_upper   = 0
         + number      = true
         + result      = (known after apply)
         + special     = false
         + upper       = false
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_managed_disk.disk[0] will be created
     + resource "azurerm_managed_disk" "disk" {
         + create_option        = "Empty"
         + disk_iops_read_write = (known after apply)
         + disk_mbps_read_write = (known after apply)
         + disk_size_gb         = 512
         + id                   = (known after apply)
         + location             = "westus2"
         + name                 = "hdb0-disk0"
         + resource_group_name  = "hana-sn-RG"
         + source_uri           = (known after apply)
         + storage_account_type = "Premium_LRS"
         + tier                 = (known after apply)
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_managed_disk.disk[1] will be created
     + resource "azurerm_managed_disk" "disk" {
         + create_option        = "Empty"
         + disk_iops_read_write = (known after apply)
         + disk_mbps_read_write = (known after apply)
         + disk_size_gb         = 512
         + id                   = (known after apply)
         + location             = "westus2"
         + name                 = "hdb0-disk1"
         + resource_group_name  = "hana-sn-RG"
         + source_uri           = (known after apply)
         + storage_account_type = "Premium_LRS"
         + tier                 = (known after apply)
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_managed_disk.disk[2] will be created
     + resource "azurerm_managed_disk" "disk" {
         + create_option        = "Empty"
         + disk_iops_read_write = (known after apply)
         + disk_mbps_read_write = (known after apply)
         + disk_size_gb         = 512
         + id                   = (known after apply)
         + location             = "westus2"
         + name                 = "hdb0-disk2"
         + resource_group_name  = "hana-sn-RG"
         + source_uri           = (known after apply)
         + storage_account_type = "Premium_LRS"
         + tier                 = (known after apply)
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_storage_account.bootdiagstorageaccount will be created
     + resource "azurerm_storage_account" "bootdiagstorageaccount" {
         + access_tier                      = (known after apply)
         + account_kind                     = "StorageV2"
         + account_replication_type         = "LRS"
         + account_tier                     = "Standard"
         + allow_blob_public_access         = false
         + enable_https_traffic_only        = true
         + id                               = (known after apply)
         + is_hns_enabled                   = false
         + large_file_share_enabled         = (known after apply)
         + location                         = "westus2"
         + min_tls_version                  = "TLS1_0"
         + name                             = (known after apply)
         + nfsv3_enabled                    = false
         + primary_access_key               = (sensitive value)
         + primary_blob_connection_string   = (sensitive value)
         + primary_blob_endpoint            = (known after apply)
         + primary_blob_host                = (known after apply)
         + primary_connection_string        = (sensitive value)
         + primary_dfs_endpoint             = (known after apply)
         + primary_dfs_host                 = (known after apply)
         + primary_file_endpoint            = (known after apply)
         + primary_file_host                = (known after apply)
         + primary_location                 = (known after apply)
         + primary_queue_endpoint           = (known after apply)
         + primary_queue_host               = (known after apply)
         + primary_table_endpoint           = (known after apply)
         + primary_table_host               = (known after apply)
         + primary_web_endpoint             = (known after apply)
         + primary_web_host                 = (known after apply)
         + resource_group_name              = "hana-sn-RG"
         + secondary_access_key             = (sensitive value)
         + secondary_blob_connection_string = (sensitive value)
         + secondary_blob_endpoint          = (known after apply)
         + secondary_blob_host              = (known after apply)
         + secondary_connection_string      = (sensitive value)
         + secondary_dfs_endpoint           = (known after apply)
         + secondary_dfs_host               = (known after apply)
         + secondary_file_endpoint          = (known after apply)
         + secondary_file_host              = (known after apply)
         + secondary_location               = (known after apply)
         + secondary_queue_endpoint         = (known after apply)
         + secondary_queue_host             = (known after apply)
         + secondary_table_endpoint         = (known after apply)
         + secondary_table_host             = (known after apply)
         + secondary_web_endpoint           = (known after apply)
         + secondary_web_host               = (known after apply)
         + shared_access_key_enabled        = true
         + tags                             = {
             + "environment" = "Terraform SAP HANA deployment"
           }

         + blob_properties {
             + change_feed_enabled      = (known after apply)
             + default_service_version  = (known after apply)
             + last_access_time_enabled = (known after apply)
             + versioning_enabled       = (known after apply)

             + container_delete_retention_policy {
                 + days = (known after apply)
               }

             + cors_rule {
                 + allowed_headers    = (known after apply)
                 + allowed_methods    = (known after apply)
                 + allowed_origins    = (known after apply)
                 + exposed_headers    = (known after apply)
                 + max_age_in_seconds = (known after apply)
               }

             + delete_retention_policy {
                 + days = (known after apply)
               }
           }

         + identity {
             + identity_ids = (known after apply)
             + principal_id = (known after apply)
             + tenant_id    = (known after apply)
             + type         = (known after apply)
           }

         + network_rules {
             + bypass                     = (known after apply)
             + default_action             = (known after apply)
             + ip_rules                   = (known after apply)
             + virtual_network_subnet_ids = (known after apply)

             + private_link_access {
                 + endpoint_resource_id = (known after apply)
                 + endpoint_tenant_id   = (known after apply)
               }
           }

         + queue_properties {
             + cors_rule {
                 + allowed_headers    = (known after apply)
                 + allowed_methods    = (known after apply)
                 + allowed_origins    = (known after apply)
                 + exposed_headers    = (known after apply)
                 + max_age_in_seconds = (known after apply)
               }

             + hour_metrics {
                 + enabled               = (known after apply)
                 + include_apis          = (known after apply)
                 + retention_policy_days = (known after apply)
                 + version               = (known after apply)
               }

             + logging {
                 + delete                = (known after apply)
                 + read                  = (known after apply)
                 + retention_policy_days = (known after apply)
                 + version               = (known after apply)
                 + write                 = (known after apply)
               }

             + minute_metrics {
                 + enabled               = (known after apply)
                 + include_apis          = (known after apply)
                 + retention_policy_days = (known after apply)
                 + version               = (known after apply)
               }
           }

         + routing {
             + choice                      = (known after apply)
             + publish_internet_endpoints  = (known after apply)
             + publish_microsoft_endpoints = (known after apply)
        }

         + share_properties {
             + cors_rule {
                 + allowed_headers    = (known after apply)
                 + allowed_methods    = (known after apply)
                 + allowed_origins    = (known after apply)
                 + exposed_headers    = (known after apply)
                 + max_age_in_seconds = (known after apply)
               }

             + retention_policy {
                 + days = (known after apply)
               }

             + smb {
                 + authentication_types            = (known after apply)
                 + channel_encryption_type         = (known after apply)
                 + kerberos_ticket_encryption_type = (known after apply)
                 + versions                        = (known after apply)
               }
           }
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine.vm will be created
     + resource "azurerm_virtual_machine" "vm" {
         + availability_set_id              = (known after apply)
         + delete_data_disks_on_termination = false
         + delete_os_disk_on_termination    = true
         + id                               = (known after apply)
         + license_type                     = (known after apply)
         + location                         = "westus2"
         + name                             = "hdb0"
         + network_interface_ids            = (known after apply)
         + resource_group_name              = "hana-sn-RG"
         + tags                             = {
             + "database-hana-sn-RG" = ""
             + "hdb0"                = ""
           }
         + vm_size                          = "Standard_D2s_v3"

         + boot_diagnostics {
             + enabled     = true
             + storage_uri = (known after apply)
           }

         + identity {
             + identity_ids = (known after apply)
             + principal_id = (known after apply)
             + type         = (known after apply)
           }

         + os_profile {
             + admin_username = "labuser"
             + computer_name  = "hdb0"
             + custom_data    = (known after apply)
           }

         + os_profile_linux_config {
             + disable_password_authentication = true

             + ssh_keys {
                 + key_data = <<-EOT
                       ---- BEGIN SSH2 PUBLIC KEY ----
                       Comment: "rsa-key-20210911"
                       AAAAB3NzaC1yc2EAAAADAQABAAABAQCyi9UBbwfLv93GwhS4xzz2xmaOQBkhrKwK
                       Yu9YQ9/9pDOhMC0IdJ5DJe3XtkTovZA9TpYhm5MezUsNdnJCvRSVn2rGWf/hZTPy
                       Gw1e3rEhHjwWGO/5sXThmqaYs976+moGb03VGoOIgrE1vc4lpn4piOaaDetSVDZz
                       A2d8RMzDE3s3GpEp+0niRZ19kKeOA5bR0s7lJL4AyshMrmPPV3IoChzZLptEdKPU
                       NvtF9hwWiLEAtoo0SnsUsadis67li3c5rnolBhLP/+9pqSCwAyLZ5gGkodPcsJdD
                       kiL42OJTf4V9gh04UoJ3Jk18oo97itQIYSAsEKbCJRFMiUuU9Und
                       ---- END SSH2 PUBLIC KEY ----
                   EOT
                 + path     = "/home/labuser/.ssh/authorized_keys"
               }
           }

         + storage_data_disk {
             + caching                   = (known after apply)
             + create_option             = (known after apply)
             + disk_size_gb              = (known after apply)
             + lun                       = (known after apply)
             + managed_disk_id           = (known after apply)
             + managed_disk_type         = (known after apply)
             + name                      = (known after apply)
             + vhd_uri                   = (known after apply)
             + write_accelerator_enabled = (known after apply)
           }

         + storage_image_reference {
             + offer     = "sles-sap-12-sp5"
             + publisher = "SUSE"
             + sku       = "gen1"
             + version   = "latest"
           }

         + storage_os_disk {
             + caching                   = "ReadWrite"
             + create_option             = "FromImage"
             + disk_size_gb              = (known after apply)
             + managed_disk_id           = (known after apply)
             + managed_disk_type         = "Standard_LRS"
             + name                      = "hdb0-OsDisk"
             + os_type                   = (known after apply)
             + write_accelerator_enabled = false
           }
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine_data_disk_attachment.disk[0] will be created
     + resource "azurerm_virtual_machine_data_disk_attachment" "disk" {
         + caching                   = "ReadWrite"
         + create_option             = "Attach"
         + id                        = (known after apply)
         + lun                       = 0
         + managed_disk_id           = (known after apply)
         + virtual_machine_id        = (known after apply)
         + write_accelerator_enabled = false
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine_data_disk_attachment.disk[1] will be created
     + resource "azurerm_virtual_machine_data_disk_attachment" "disk" {
         + caching                   = "ReadWrite"
         + create_option             = "Attach"
         + id                        = (known after apply)
         + lun                       = 1
         + managed_disk_id           = (known after apply)
         + virtual_machine_id        = (known after apply)
         + write_accelerator_enabled = false
       }

     # module.create_hdb.module.vm_and_disk_creation.azurerm_virtual_machine_data_disk_attachment.disk[2] will be created
     + resource "azurerm_virtual_machine_data_disk_attachment" "disk" {
         + caching                   = "ReadWrite"
         + create_option             = "Attach"
         + id                        = (known after apply)
         + lun                       = 2
         + managed_disk_id           = (known after apply)
         + virtual_machine_id        = (known after apply)
         + write_accelerator_enabled = false
       }

     # module.create_hdb.module.vm_and_disk_creation.random_id.randomId will be created
     + resource "random_id" "randomId" {
         + b64_std     = (known after apply)
         + b64_url     = (known after apply)
         + byte_length = 8
         + dec         = (known after apply)
         + hex         = (known after apply)
         + id          = (known after apply)
         + keepers     = {
             + "resource_group" = "hana-sn-RG"
           }
       }

   Plan: 20 to add, 0 to change, 0 to destroy.

   Changes to Outputs:
     + hdb_ip      = (known after apply)
     + hdb_vm_user = "labuser"


   ─────────────────────────────────────────────────────────────────────────────

   Saved the plan to: tfplan_tf_with_ansible

   To perform exactly these actions, run the following command to apply:
       terraform apply "tfplan_full_setup"
   ```

> **Note**: The additional resource (comparing with the previous lab) is **mount-disks-and-configure-hana**.

1. From the Bash session, run the following command to deploy the 20 resources included in the plan generated by Terraform:

   ```
   terraform apply -auto-approve tfplan_tf_with_ansible
   ```   

1. From the Bash session, examine the output generated during the deployment and verify that it includes that entry `Apply complete! Resources: 20 added, 0 changed, 0 destroyed`.
1. In the output generated during the deployment, identify and record the value of the **hdb_ip** entry and note the name of the **hdb_vm_user** (which should be set to **labuser**).
1. From the Bash session, run the following command to connect to the Azure VM (replace the `<hdb_ip>` placeholder with the value you identified in the previous step):

   ```
   ssh labuser@<hdb_ip>
   ```

1. When prompted, confirm that you want to continue connecting.
1. Once connected, run the following command to display the local volume configuration:

   ```
   df -h
   ```

1. From the Bash session, examine the output of the command you ran in the previous step and verify that it resembles the following content:

   ```
   Filesystem                                 Size  Used Avail Use% Mounted on
   devtmpfs                                   3.9G  8.0K  3.9G   1% /dev
   tmpfs                                      5.9G     0  5.9G   0% /dev/shm
   tmpfs                                      3.9G   18M  3.9G   1% /run
   tmpfs                                      3.9G     0  3.9G   0% /sys/fs/cgroup
   /dev/sda4                                   29G  2.2G   27G   8% /
   /dev/sda3                                 1014M   99M  916M  10% /boot
   /dev/sda2                                  512M  1.1M  511M   1% /boot/efi
   /dev/sdb1                                   16G   45M   15G   1% /mnt
   /dev/mapper/vg_hana_shared-lv_hana_shared  512G   33M  512G   1% /hana/shared
   /dev/mapper/vg_hana_data_I20-lv_hana_data  512G   33M  512G   1% /hana/data/I20
   /dev/mapper/vg_hana_log_I20-lv_hana_logs   512G   33M  512G   1% /hana/log/I20
   tmpfs                                      797M     0  797M   0% /run/user/1000
   ```

1. From the Bash session, run the following command to delete the provisioned Azure resources

   ```
   terraform destroy -auto-approve
   ```
