output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "aks_ingress_ip" {
  description = "Wewnętrzny adres Traefika w AKS – backend 'azure' w HAProxy na Pi"
  value       = var.ingress_ip
}

output "vnet_cidr" {
  description = "Tę sieć trzeba dodać do AllowedIPs peera bramki na Pi i do trasy na Pi"
  value       = var.vnet_cidr
}

output "gw_public_ip" {
  description = "Publiczny adres bramki (SSH: ssh azureuser@<ten adres>)"
  value       = azurerm_public_ip.gw.ip_address
}

output "velero_storage_account" {
  value = azurerm_storage_account.velero.name
}

output "velero_storage_key" {
  value     = azurerm_storage_account.velero.primary_access_key
  sensitive = true
}

output "subscription_id" {
  value = var.subscription_id
}
