terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  backend "s3" {}

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    twc = {
      source  = "tf.timeweb.cloud/timeweb-cloud/timeweb-cloud"
      version = "~> 1.0"
    }
  }
}

provider "twc" {
  token = trimspace(var.timeweb_api_token) != "" ? var.timeweb_api_token : null
}
