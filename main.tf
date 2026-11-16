terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.0"
    }
  }

  # Local par défaut ; le pipeline fournit un chemin persistant sur le runner.
  backend "local" {}
}

provider "docker" {}

resource "docker_image" "postgres_image" {
  name         = "postgres:latest"
  keep_locally = true
}

resource "docker_container" "db_container" {
  name           = "tp-db-postgres"
  image          = docker_image.postgres_image.image_id
  remove_volumes = true
  wait           = true
  wait_timeout   = 120

  ports {
    internal = 5432
    external = var.db_port_external
    ip       = "127.0.0.1"
  }

  env = [
    "POSTGRES_USER=${var.db_user}",
    "POSTGRES_PASSWORD=${var.db_password}",
    "POSTGRES_DB=${var.db_name}",
  ]

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
    interval     = "2s"
    timeout      = "3s"
    retries      = 30
    start_period = "5s"
  }
}

resource "docker_image" "app_image" {
  name = "tp-web-app:latest"

  build {
    context            = abspath(path.module)
    dockerfile         = "Dockerfile_app"
    use_legacy_builder = true
  }

  triggers = {
    dockerfile = filesha256("${path.module}/Dockerfile_app")
    nginx      = filesha256("${path.module}/nginx.conf")
  }
}

resource "docker_container" "app_container" {
  name  = "tp-app-web"
  image = docker_image.app_image.image_id

  # wait=true sur PostgreSQL rend cette dépendance sensible à sa disponibilité.
  depends_on = [docker_container.db_container]

  ports {
    internal = 80
    external = var.app_port_external
    ip       = "127.0.0.1"
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/"]
    interval = "2s"
    timeout  = "3s"
    retries  = 15
  }

  wait         = true
  wait_timeout = 60
}
