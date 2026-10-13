output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "aks_ingress_fqdn" {
  description = "Nazwa, pod którą Traefik w AKS będzie widoczny z internetu"
  value       = local.aks_ingress_fqdn
}

output "traffic_manager_fqdn" {
  description = "Ustaw CNAME app.<Twoja domena> -> ta wartość"
  value       = azurerm_traffic_manager_profile.tm.fqdn
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
