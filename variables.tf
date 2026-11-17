variable "db_name" {
  description = "Nom de la base de données PostgreSQL."
  type        = string
  default     = "devops_db_v3"
}

variable "db_user" {
  description = "Utilisateur PostgreSQL créé au premier démarrage."
  type        = string
  default     = "devops_user"
}

variable "db_password" {
  description = "Mot de passe de démonstration locale ; utiliser TF_VAR_db_password pour le remplacer."
  type        = string
  sensitive   = true
  default     = "TP_local_demo_change_me_2026!"
}

variable "db_port_external" {
  description = "Port PostgreSQL sur l'hôte local."
  type        = number
  default     = 5432
}

variable "app_port_external" {
  description = "Port HTTP sur l'hôte local, associé au port 80 du conteneur."
  type        = number
  default     = 8080
}
