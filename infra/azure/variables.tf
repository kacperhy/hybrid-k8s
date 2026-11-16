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

# ------------------------------------------------------------------ AKS
variable "node_vm_size" {
  description = "Rozmiar węzła AKS. B2ms (2 vCPU / 8 GB) mieści aplikację + Argo CD + Prometheus"
  type        = string
  default     = "Standard_B2ms"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "api_allowed_cidrs" {
  description = "Publiczne adresy, z których wolno łączyć się z API AKS (kubectl), np. [\"79.191.165.165/32\"]. Ten sam zakres może logować się przez SSH do bramki."
  type        = list(string)
}

# --------------------------------------------------------------- Sieć
variable "vnet_cidr" {
  type    = string
  default = "10.50.0.0/16"
}

variable "aks_subnet_cidr" {
  type    = string
  default = "10.50.1.0/24"
}

variable "gw_subnet_cidr" {
  type    = string
  default = "10.50.2.0/24"
}

variable "gw_private_ip" {
  description = "Stały prywatny adres bramki WireGuard w VNet (cel trasy do sieci VPN)"
  type        = string
  default     = "10.50.2.4"
}

variable "ingress_ip" {
  description = "Wewnętrzny adres Traefika w AKS (Azure internal load balancer) – musi leżeć w aks_subnet_cidr"
  type        = string
  default     = "10.50.1.250"
}

variable "vpn_cidr" {
  description = "Sieć WireGuard na Raspberry Pi"
  type        = string
  default     = "10.10.20.0/24"
}

# ---------------------------------------------- Bramka WireGuard (site-to-site)
variable "gw_vm_size" {
  type    = string
  default = "Standard_B1s"
}

variable "gw_admin_ssh_public_key" {
  description = "Klucz publiczny SSH (cała linijka ssh-ed25519 AAAA...) do logowania na bramkę jako azureuser"
  type        = string
}

variable "wg_address" {
  description = "Adres bramki w sieci VPN (wolny adres z 10.10.20.0/24, np. 10.10.20.10)"
  type        = string
}

variable "wg_private_key" {
  description = "Klucz prywatny WireGuard bramki (PrivateKey z pliku .conf wygenerowanego na Pi)"
  type        = string
  sensitive   = true
}

variable "wg_preshared_key" {
  description = "PresharedKey z pliku .conf (zostaw puste, jeśli Twój skrypt go nie generuje)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pi_public_key" {
  description = "Klucz publiczny WireGuard Raspberry Pi (PublicKey w sekcji [Peer] pliku .conf)"
  type        = string
}

variable "pi_endpoint" {
  description = "Publiczny adres i port WireGuard na Pi, np. vpn.example.com:51820"
  type        = string
}

# ------------------------------------------------------------- Velero
variable "storage_account_name" {
  description = "Globalnie unikalna nazwa konta Storage na backupy Velero (3-24 znaki, a-z0-9)"
  type        = string
}
