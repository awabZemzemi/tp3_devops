variable "db_name" {
  description = "Nom de la base de données PostgreSQL."
  type        = string
  default     = "devops_db_v2"
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

  validation {
    condition     = length(var.db_password) >= 12
    error_message = "Utiliser un mot de passe d'au moins 12 caractères."
  }
}

variable "db_port_external" {
  description = "Port PostgreSQL sur l'hôte local."
  type        = number
  default     = 5432

  validation {
    condition     = var.db_port_external >= 1 && var.db_port_external <= 65535 && floor(var.db_port_external) == var.db_port_external
    error_message = "Le port doit être un entier compris entre 1 et 65535."
  }
}

variable "app_port_external" {
  description = "Port HTTP sur l'hôte local, associé au port 80 du conteneur."
  type        = number
  default     = 8080

  validation {
    condition     = var.app_port_external >= 1 && var.app_port_external <= 65535 && floor(var.app_port_external) == var.app_port_external
    error_message = "Le port doit être un entier compris entre 1 et 65535."
  }
}
