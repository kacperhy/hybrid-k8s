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
    temporary_name_for_rotation = "tmprot"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
  }

  tags = azurerm_resource_group.rg.tags
}

# ------------------------------------------------- Traffic Manager (DNS failover)
# Routing "Priority": cały ruch idzie do onprem, a gdy sonda /healthz
# na onprem zawiedzie – do AKS. TTL 10 s + sonda co 10 s => przełączenie
# w ok. 30–60 s (zależnie od cache DNS klienta).
locals {
  aks_ingress_fqdn = "${var.aks_dns_label}.${var.location}.cloudapp.azure.com"
}

resource "azurerm_traffic_manager_profile" "tm" {
  name                   = "tm-${var.prefix}"
  resource_group_name    = azurerm_resource_group.rg.name
  traffic_routing_method = "Priority"

  dns_config {
    relative_name = "tm-${var.prefix}"
    ttl           = 10
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/healthz"
    interval_in_seconds          = 10
    timeout_in_seconds           = 5
    tolerated_number_of_failures = 1
    expected_status_code_ranges  = ["200-299"]
  }

  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_traffic_manager_external_endpoint" "onprem" {
  name       = "onprem"
  profile_id = azurerm_traffic_manager_profile.tm.id
  target     = var.onprem_fqdn
  priority   = 1
  weight     = 1
}

resource "azurerm_traffic_manager_external_endpoint" "azure" {
  name       = "azure"
  profile_id = azurerm_traffic_manager_profile.tm.id
  target     = local.aks_ingress_fqdn
  priority   = 2
  weight     = 1
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
