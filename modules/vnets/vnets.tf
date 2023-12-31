data "azurerm_client_config" "current" {}

resource "azurerm_virtual_network" "vnet" {
  name                = format("%s%s", "vnet-", var.project)
  location            = var.location
  resource_group_name = var.rg_name
  address_space       = [var.vnet_cidr_range]
  tags                = var.tags
}

resource "azurerm_network_security_group" "db_nsg" {
  name                = format("%s%s", "db-nsg-", var.project)
  location            = var.location
  resource_group_name = var.rg_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "aad" {
  name                        = "AllowAAD"
  priority                    = 200
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "AzureActiveDirectory"
  resource_group_name         = var.rg_name
  network_security_group_name = azurerm_network_security_group.db_nsg.name
}

resource "azurerm_network_security_rule" "azfrontdoor" {
  name                        = "AllowAzureFrontDoor"
  priority                    = 201
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "AzureFrontDoor.Frontend"
  resource_group_name         = var.rg_name
  network_security_group_name = azurerm_network_security_group.db_nsg.name
}

# data "http" "myip" {
#   url = "http://ipv4.icanhazip.com"
# }${chomp(data.http.myip.body)}/32

# resource "azurerm_network_security_rule" "az_allow_my_ip" {
#   name                        = "AllowMyIP"
#   priority                    = 150
#   direction                   = "Inbound"
#   access                      = "Allow"
#   protocol                    = "*"
#   source_port_range           = "443"
#   destination_port_range      = "*"
#   source_address_prefix       = "${chomp(data.http.myip.body)}/32"
#   destination_address_prefix  = "*"
#   resource_group_name         = var.rg_name
#   network_security_group_name = azurerm_network_security_group.db_nsg.name
# }

resource "azurerm_subnet" "db_public" {
  name                 = format("%s%s", "db-public-subnet-", var.project)
  resource_group_name  = var.rg_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr_range, 2, 0)]

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.db_public.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}

variable "private_subnet_endpoints" {
  default = []
}

resource "azurerm_subnet" "db_private" {
  name                 = format("%s%s", "db-private-subnet-", var.project)
  resource_group_name  = var.rg_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr_range, 2, 1)]

  private_endpoint_network_policies_enabled     = true
  private_link_service_network_policies_enabled = true

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }

  service_endpoints = var.private_subnet_endpoints
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.db_private.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}


resource "azurerm_subnet" "pl_subnet" {
  name                                      = format("%s%s", "db-pl-subnet-", var.project)
  resource_group_name                       = var.rg_name
  virtual_network_name                      = azurerm_virtual_network.vnet.name
  address_prefixes                          = [cidrsubnet(var.vnet_cidr_range, 2, 2)]
  private_endpoint_network_policies_enabled = true
}


### Virtual Machine
resource "azurerm_subnet" "vm_windows_server" {
  name                 = format("%s%s", "vm-windows-server-", var.project)
  resource_group_name  = var.rg_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr_range, 2, 3)]
}

resource "azurerm_public_ip" "vm_windows_server" {
  name                = format("%s%s", "vm-windows-server-public-ip-", var.project)
  location            = var.location
  resource_group_name = var.rg_name
  allocation_method   = "Dynamic"
}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

resource "azurerm_network_security_group" "vm_windows_server" {
  name                = format("%s%s", "vm-windows-server-nsg-", var.project)
  location            = var.location
  resource_group_name = var.rg_name

  security_rule {
    name                       = "RDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "${chomp(data.http.myip.body)}/32"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "web"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "vm_windows_server" {
  name                = format("%s%s", "vm-windows-server-nic-", var.project)
  location            = var.location
  resource_group_name = var.rg_name

  ip_configuration {
    name                          = "my_nic_configuration"
    subnet_id                     = azurerm_subnet.vm_windows_server.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_windows_server.id
  }
}

resource "azurerm_network_interface_security_group_association" "vm_windows_server" {
  network_interface_id      = azurerm_network_interface.vm_windows_server.id
  network_security_group_id = azurerm_network_security_group.vm_windows_server.id
}
