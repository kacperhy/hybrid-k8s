# Mała VM z WireGuard: łączy VNet z siecią VPN na Raspberry Pi (site-to-site).
# Bramka sama nawiązuje połączenie do Pi (PersistentKeepalive), więc nie potrzebuje
# żadnych otwartych portów przychodzących poza SSH z naszych adresów.

resource "azurerm_public_ip" "gw" {
  name                = "pip-${var.prefix}-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.rg.tags
}

resource "azurerm_network_security_group" "gw" {
  name                = "nsg-${var.prefix}-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = azurerm_resource_group.rg.tags

  security_rule {
    name                       = "ssh-from-admins"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.api_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-aks-to-vpn"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.50.1.0/24"  # podsiec AKS
    destination_address_prefix = "10.10.20.0/24" # siec VPN za bramka
  }

  security_rule {
    name                       = "deny-internet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "gw" {
  name                  = "nic-${var.prefix}-gw"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  ip_forwarding_enabled = true # bramka przekazuje pakiety między VNet a VPN
  tags                  = azurerm_resource_group.rg.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.gw.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.gw_private_ip
    public_ip_address_id          = azurerm_public_ip.gw.id
  }
}

resource "azurerm_network_interface_security_group_association" "gw" {
  network_interface_id      = azurerm_network_interface.gw.id
  network_security_group_id = azurerm_network_security_group.gw.id
}

resource "azurerm_linux_virtual_machine" "gw" {
  name                  = "vm-${var.prefix}-gw"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.gw_vm_size
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.gw.id]
  tags                  = azurerm_resource_group.rg.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.gw_admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/gateway-cloud-init.yaml.tftpl", {
    wg_address       = var.wg_address
    wg_private_key   = var.wg_private_key
    wg_preshared_key = var.wg_preshared_key
    pi_public_key    = var.pi_public_key
    pi_endpoint      = var.pi_endpoint
    vpn_cidr         = var.vpn_cidr
  }))
}
