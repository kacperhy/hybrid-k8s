variable "subscription_id" {
  description = "ID subskrypcji Azure for Students (az account show --query id -o tsv)"
  type        = string
}

variable "location" {
  description = "Region – musi być na liście 'Allowed resource deployment regions' Twojej subskrypcji studenckiej"
  type        = string
  default     = "polandcentral"
}

variable "prefix" {
  description = "Krótki prefiks nazw zasobów (małe litery i cyfry)"
  type        = string
  default     = "hybryda"
}

variable "node_vm_size" {
  description = "Rozmiar węzła AKS. B2ms (2 vCPU / 8 GB) mieści aplikację + Argo CD + Prometheus"
  type        = string
  default     = "Standard_B2ms"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "onprem_fqdn" {
  description = "Publiczna nazwa DNS klastra lokalnego (rekord DDNS), np. onprem.serwerfrajerow.top"
  type        = string
}

variable "aks_dns_label" {
  description = "Etykieta DNS publicznego IP Traefika w AKS -> <label>.<region>.cloudapp.azure.com (musi być unikalna w regionie)"
  type        = string
}

variable "storage_account_name" {
  description = "Globalnie unikalna nazwa konta Storage na backupy Velero (3-24 znaki, a-z0-9)"
  type        = string
}
