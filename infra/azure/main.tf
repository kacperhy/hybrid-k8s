# Wariant "tylko przez VPN":
#  - AKS nie ma publicznego Ingressu; Traefik dostaje WEWNĘTRZNY load balancer w VNet,
#  - do VNet wchodzimy tunelem WireGuard: Raspberry Pi <-> mała VM-bramka (gateway.tf),
#  - API AKS (kubectl) jest publiczne, ale tylko dla adresów z api_allowed_cidrs,
#  - przełączanie ruchu między klastrami robi HAProxy na Pi (vpn/pi/), nie Azure.

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags = {
    project = "hybrid-k8s"
  }
}

# ---------------------------------------------------------------- AKS
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.prefix
  sku_tier            = "Free" # control plane bez opłat

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    node_count                  = var.node_count
    os_disk_size_gb             = 64
    vnet_subnet_id              = azurerm_subnet.aks.id
    temporary_name_for_rotation = "tmprot"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
  }

  # kubectl tylko z naszych publicznych adresów (IP wychodzące klastra AKS dodaje sam)
  api_server_access_profile {
    authorized_ip_ranges = concat(var.api_allowed_cidrs, ["${azurerm_public_ip.gw.ip_address}/32"])
  }

  tags = azurerm_resource_group.rg.tags

  # route table musi być przypięta do podsieci, zanim AKS utworzy węzły
  depends_on = [azurerm_subnet_route_table_association.aks]
}

# AKS tworzy wewnętrzny load balancer (Traefik) w NASZEJ podsieci – potrzebuje uprawnień do VNet
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_resource_group.rg.id # VNet + route table
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

# ------------------------------------------- Storage na backupy Velero
resource "azurerm_storage_account" "velero" {
  name                            = var.storage_account_name
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = azurerm_resource_group.rg.tags
}

resource "azurerm_storage_container" "velero" {
  name                  = "velero"
  storage_account_id    = azurerm_storage_account.velero.id
  container_access_type = "private"
}
