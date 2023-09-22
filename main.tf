################################
# Input Variables & Locals (calculated vars)
################################


variable "vm_username" {
  description = "VM administrator username (Check VM Username Requirements!)"
  type        = string
  sensitive   = true
}

variable "vm_password" {
  description = "VM administrator password (Check VM Password Requirements!)"
  type        = string
  sensitive   = true
}


variable "IPAddress" {
  type = string
  description = "Enter your home public IP address. If you do not know it you can go to https://whatismyipaddress.com/. For example: 1.2.3.4"
  validation {
    condition = can(regex("\\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\b", var.IPAddress))
	error_message = "Could not parse IP address. Please ensure the IP is a valid IPv4 IP address."
  }
}


variable "OnpremIPRange" {
  type = string
  description = "Enter your onprem/home network address space (Ex: 10.0.0.0/16). If you do not know it you can find it by running ipconfig"
  validation {
    condition = can(regex("\\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\/(?:3[0-2]|[1-2]?[0-9])\\b", var.OnpremIPRange))
  error_message = "Could not parse IP address. Please ensure the IP is a valid IPv4 IP address with a subnet between /8 and /32."
  }
}


################################
# Resource Group
################################





resource "azurerm_resource_group" "rg" {
  location = "southcentralus"
  name     = "linux-nva-lab"
}

################################
# Low Analytics Workspace
################################



resource "azurerm_log_analytics_workspace" "log_analytics_sc" {
  name                = "LAW-nva-southcentralus"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 5
}


################################
# Storage Account, to store flow logs
################################


#Generate random text for a unique storage account name
resource "random_id" "random_id" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

#Create storage account for boot diagnostics
resource "azurerm_storage_account" "my_storage_account" {
  name                     = "diag${random_id.random_id.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}


################################
# Network Watcher and flog logs - Checkout https://learn.microsoft.com/en-us/azure/developer/terraform/create-network-watcher-nsg-flow-logs
################################


resource "azurerm_network_watcher" "net-watcher-sc" {
  name                = "NetworkWatcher_southcentralus"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}


resource "azurerm_network_watcher_flow_log" "nsg_network_logs" {
  name = "MyNSGFlowLogs"
  network_watcher_name = azurerm_network_watcher.net-watcher-sc.name
  resource_group_name  = azurerm_network_watcher.net-watcher-sc.resource_group_name

  network_security_group_id = azurerm_network_security_group.my_terraform_nsg.id
  storage_account_id        = azurerm_storage_account.my_storage_account.id
  enabled                   = true

  retention_policy {
    enabled = true
    days    = 90
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.log_analytics_sc.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.log_analytics_sc.location
    workspace_resource_id = azurerm_log_analytics_workspace.log_analytics_sc.id
    interval_in_minutes   = 10
  }
}


resource "azurerm_network_watcher_flow_log" "Mgmt_nsg_network_logs" {
  name = "MgmtNSGFlowLogs"
  network_watcher_name = azurerm_network_watcher.net-watcher-sc.name
  resource_group_name  = azurerm_network_watcher.net-watcher-sc.resource_group_name

  network_security_group_id = azurerm_network_security_group.management_nsg.id
  storage_account_id        = azurerm_storage_account.my_storage_account.id
  enabled                   = true

  retention_policy {
    enabled = true
    days    = 90
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.log_analytics_sc.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.log_analytics_sc.location
    workspace_resource_id = azurerm_log_analytics_workspace.log_analytics_sc.id
    interval_in_minutes   = 10
  }
}


################################
# Virtual Networks & Subnets
################################

# Create virtual network

# Hub VNET

resource "azurerm_virtual_network" "Hub_vnet" {
  name                = "HubVnet"
  address_space       = ["10.98.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "nva_untrust_subnet" {
  name                 = "NVAUntrustSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.Hub_vnet.name
  address_prefixes     = ["10.98.0.0/24"]
}


resource "azurerm_subnet" "nva_trust_subnet" {
  name                 = "NVATrustSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.Hub_vnet.name
  address_prefixes     = ["10.98.1.0/24"]
}


resource "azurerm_subnet" "nva_management_subnet" {
  name                 = "NVAMgmtSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.Hub_vnet.name
  address_prefixes     = ["10.98.2.0/24"]
}

# Spoke VNET

resource "azurerm_virtual_network" "spoke_vnet" {
  name                = "spokeVnet1"
  address_space       = ["10.97.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "Spoke_subnet" {
  name                 = "ServersSubnet1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.spoke_vnet.name
  address_prefixes     = ["10.97.1.0/24"]
}


resource "azurerm_subnet" "Spoke_subnet2" {
  name                 = "ServersSubnet2"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.spoke_vnet.name
  address_prefixes     = ["10.97.2.0/24"]
}




################################
# Public IPs
################################



# Create public IPs
resource "azurerm_public_ip" "Windows_public_ip" {
  name                = "WindowsPublicIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}



resource "azurerm_public_ip" "nva_untrust_pip" {
  name                = "NVAUntrustPIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku = "Standard"
  availability_zone   = "No-Zone"
}


resource "azurerm_public_ip" "nva_mgmt_pip" {
  name                = "NVAMgmtPIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku = "Standard"
  availability_zone   = "No-Zone"
}

################################
# Network security groups (NSGs)
################################


# Create Network Security Group and rule
resource "azurerm_network_security_group" "my_terraform_nsg" {
  name                = "myNSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

# Inbound rules

  # security_rule { # to allow Traffic and connections from your public IP/on-prem to Untrust NIC
  #   name                       = "Allow_all_home"
  #   priority                   = 150
  #   direction                  = "Inbound"
  #   access                     = "Allow"
  #   protocol                   = "*"
  #   source_port_range          = "*"
  #   destination_port_range     = "*"
  #   source_address_prefix      = var.IPAddress
  #   destination_address_prefix = "*"
  # }

  security_rule {
    name                       = "Allow_all_spoke_outbound"
    priority                   = 160
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.97.0.0/16"
    destination_address_prefix = "*"
  }


  security_rule {
    name                       = "Allow_all_on-prem_inbound"
    priority                   = 170
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "${var.OnpremIPRange}"
    destination_address_prefix = "*"
  }


  security_rule {
    name                       = "Allow_VNET_In"
    priority                   = 180
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow_AZ_LB_In"
    priority                   = 190
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }


  security_rule {
    name                       = "Allow_VPN_BGP_In"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges     = ["179", "500", "4500"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }


  security_rule {
    name                       = "Deny_all_Inbound"
    priority                   = 4095
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

# Outbound Rules

  security_rule {
    name                       = "Allow_all_on-prem_outbound"
    priority                   = 180
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "${var.OnpremIPRange}"
    destination_address_prefix = "*"
  }




}


# Management NIC NSG

resource "azurerm_network_security_group" "management_nsg" {
  name                = "MgmtNSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name



  security_rule { # to allow connections from your public IP/on-prem to management NIC
    name                       = "Allow_all_home"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.IPAddress
    destination_address_prefix = "*"
  }


}


################################
# User Defined Routes / Route Tables (UDRs)
################################



resource "azurerm_route_table" "spoke1-udr" {
  name                = "spoke1-udr"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  disable_bgp_route_propagation = false
  route {
    name           = "Route-to-nva"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.98.1.4"
  }

  route {
    name           = "Route-to-Spoke1"
    address_prefix = "10.97.0.0/16"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.98.1.4"
  }

  route {
    name           = "Route-to-Home"
    address_prefix = "${var.IPAddress}/32"
    next_hop_type  = "Internet"
  }

}

################################
# Network Interface Cards (NICs)
################################



# Create network interface

# NVA NIC Untrust

resource "azurerm_network_interface" "nva_untrust_nic" {
  name                = "UntrustNIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  enable_ip_forwarding = true


  ip_configuration {
    name                          = "Untrust_nic_configuration"
    subnet_id                     = azurerm_subnet.nva_untrust_subnet.id
    private_ip_address_allocation = "static"
    #private_ip_address_allocation = "Dynamic"
    private_ip_address            = "${cidrhost("10.98.0.0/24", 4)}"
    public_ip_address_id          = azurerm_public_ip.nva_untrust_pip.id
    
  }
}


# NVA NIC Trust

resource "azurerm_network_interface" "nva_trust_nic" {
  name                = "TrustNIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "Trust_nic_configuration"
    subnet_id                     = azurerm_subnet.nva_trust_subnet.id
    private_ip_address_allocation = "static"
    #private_ip_address_allocation = "Dynamic"
    private_ip_address            = "${cidrhost("10.98.1.0/24", 4)}"
    #public_ip_address_id          = azurerm_public_ip.nva_untrust_pip.id
    
  }
}


# NVA Management NIC

resource "azurerm_network_interface" "nva_mgmt_nic" {
  name                = "MgmtNIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  enable_ip_forwarding = false


  ip_configuration {
    name                          = "Mgmt_nic_configuration"
    subnet_id                     = azurerm_subnet.nva_management_subnet.id
    private_ip_address_allocation = "static"
    #private_ip_address_allocation = "Dynamic"
    private_ip_address            = "${cidrhost("10.98.2.0/24", 4)}"
    public_ip_address_id          = azurerm_public_ip.nva_mgmt_pip.id
    
  }
}



# Spoke Linux NIC


resource "azurerm_network_interface" "linux_nic" {
  name                = "LinuxNIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  

  ip_configuration {
    name                          = "Linux_nic_configuration"
    subnet_id                     = azurerm_subnet.Spoke_subnet2.id
    #private_ip_address_allocation = "static"
    private_ip_address_allocation = "Dynamic"
    #private_ip_address            = "${cidrhost("10.254.1.0/24", 4)}"
    #public_ip_address_id          = azurerm_public_ip.my_terraform_public_ip.id
    
  }
}

# Windows NIC


resource "azurerm_network_interface" "windows_nic" {
  name                = "WindowsNIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "Windows_nic_configuration"
    subnet_id                     = azurerm_subnet.Spoke_subnet.id
    private_ip_address_allocation = "Dynamic"
    #public_ip_address_id          = azurerm_public_ip.my_terraform_public_ip.id
    public_ip_address_id          = azurerm_public_ip.Windows_public_ip.id
  }
}





################################
# NIC Associations with NSG
################################


# Connect the security group to the network interface

# Hub NIC Association


resource "azurerm_network_interface_security_group_association" "nva_nic1_association" {
  network_interface_id      = azurerm_network_interface.nva_untrust_nic.id
  network_security_group_id = azurerm_network_security_group.my_terraform_nsg.id
  depends_on            = [azurerm_linux_virtual_machine.nva_vm]
}

resource "azurerm_network_interface_security_group_association" "nva_nic2_association" {
  network_interface_id      = azurerm_network_interface.nva_trust_nic.id
  network_security_group_id = azurerm_network_security_group.my_terraform_nsg.id
  depends_on            = [azurerm_linux_virtual_machine.nva_vm]
}


resource "azurerm_network_interface_security_group_association" "nva_nic3_association" {
  network_interface_id      = azurerm_network_interface.nva_mgmt_nic.id
  network_security_group_id = azurerm_network_security_group.management_nsg.id
  depends_on            = [azurerm_linux_virtual_machine.nva_vm]
}

# Spoke NIC Association


resource "azurerm_network_interface_security_group_association" "linux_association" {
  network_interface_id      = azurerm_network_interface.linux_nic.id
  network_security_group_id = azurerm_network_security_group.management_nsg.id
  depends_on            = [azurerm_linux_virtual_machine.linux_vm]
}


resource "azurerm_network_interface_security_group_association" "windows_association" {
  network_interface_id      = azurerm_network_interface.windows_nic.id
  network_security_group_id = azurerm_network_security_group.management_nsg.id
  depends_on            = [azurerm_windows_virtual_machine.windows_vm]
}


################################
# Subnet Associations with NSG
################################


# Connect the security group to the hub and spoke subnets

# Hub subnet Association


resource "azurerm_subnet_network_security_group_association" "priv_nva_association" {
  subnet_id      = azurerm_subnet.nva_trust_subnet.id
  network_security_group_id = azurerm_network_security_group.my_terraform_nsg.id
 
}

resource "azurerm_subnet_network_security_group_association" "nva_association" {
  subnet_id      = azurerm_subnet.nva_untrust_subnet.id
  network_security_group_id = azurerm_network_security_group.my_terraform_nsg.id
 
}

resource "azurerm_subnet_network_security_group_association" "mgmt_nva_association" {
  subnet_id      = azurerm_subnet.nva_management_subnet.id
  network_security_group_id = azurerm_network_security_group.management_nsg.id
 
}

# # Spoke NIC Association


resource "azurerm_subnet_network_security_group_association" "spoke2_association" {
  subnet_id      = azurerm_subnet.Spoke_subnet.id
  network_security_group_id = azurerm_network_security_group.management_nsg.id

}

resource "azurerm_subnet_network_security_group_association" "spoke_association" {
  subnet_id      = azurerm_subnet.Spoke_subnet2.id
  network_security_group_id = azurerm_network_security_group.management_nsg.id
 
}





################################
# Subnet Associations with UDR
################################


resource "azurerm_subnet_route_table_association" "udr-spoke-association" {
  subnet_id      = azurerm_subnet.Spoke_subnet.id
  route_table_id = azurerm_route_table.spoke1-udr.id
}

resource "azurerm_subnet_route_table_association" "udr-spoke2-association" {
  subnet_id      = azurerm_subnet.Spoke_subnet2.id
  route_table_id = azurerm_route_table.spoke1-udr.id
}



################################
# Virtual Machines (VMs)
################################


# Create virtual machine

# NVA VM

resource "azurerm_linux_virtual_machine" "nva_vm" {
  name                  = "NVAVM"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nva_untrust_nic.id, azurerm_network_interface.nva_trust_nic.id, azurerm_network_interface.nva_mgmt_nic.id]
  size                  = "Standard_B2s"
  custom_data = filebase64("setup.sh")

  os_disk {
    name                 = "NVAOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

    computer_name                   = "NVA-vm"
    admin_username                  = var.vm_username
    admin_password                  = var.vm_password
    disable_password_authentication = false



}


# Linux VM

resource "azurerm_linux_virtual_machine" "linux_vm" {
  name                  = "LinuxVM"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.linux_nic.id]
  size                  = "Standard_B1s"

  os_disk {
    name                 = "LinuxOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

    computer_name                   = "Linuxvm"
    admin_username                  = var.vm_username
    admin_password                  = var.vm_password
    disable_password_authentication = false



}


# Windows VM


resource "azurerm_windows_virtual_machine" "windows_vm" {
  name                  = "WindowsVM"
  admin_username        = var.vm_username
  admin_password        = var.vm_password  
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.windows_nic.id]
  size                  = "Standard_B2s"

  os_disk {
    name                 = "windowsOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }


}




################################
# VNET Peerings
################################




# Peering spoke to Hub

resource "azurerm_virtual_network_peering" "vnetpeeringsspoketoHub" {
    name                      = "spoke-to-Hub" 
    resource_group_name       = azurerm_resource_group.rg.name
    virtual_network_name      = azurerm_virtual_network.spoke_vnet.name
    remote_virtual_network_id = azurerm_virtual_network.Hub_vnet.id
    allow_virtual_network_access = true
    allow_forwarded_traffic      = true
    #use_remote_gateways = true
   
}

# Peering Hub to spoke
resource "azurerm_virtual_network_peering" "vnetpeering2Hubtospoke" {
    name                      = "Hub-to-spoke" 
    resource_group_name       = azurerm_resource_group.rg.name
    virtual_network_name      = azurerm_virtual_network.Hub_vnet.name
    remote_virtual_network_id = azurerm_virtual_network.spoke_vnet.id
    allow_virtual_network_access = true
    allow_forwarded_traffic      = true
    #allow_gateway_transit = true
    
}