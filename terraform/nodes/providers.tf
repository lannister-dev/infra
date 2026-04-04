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

    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }

    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.191"
    }
  }
}

provider "openstack" {
  alias = "hostvds"

  auth_url    = trimspace(var.hostvds_os_auth_url) != "" ? var.hostvds_os_auth_url : null
  user_name   = trimspace(var.hostvds_os_username) != "" ? var.hostvds_os_username : null
  password    = trimspace(var.hostvds_os_password) != "" ? var.hostvds_os_password : null
  tenant_name = trimspace(var.hostvds_os_project_name) != "" ? var.hostvds_os_project_name : null

  user_domain_id   = trimspace(var.hostvds_os_user_domain_id) != "" ? var.hostvds_os_user_domain_id : null
  user_domain_name = trimspace(var.hostvds_os_user_domain_id) == "" && trimspace(var.hostvds_os_user_domain_name) != "" ? var.hostvds_os_user_domain_name : null

  project_domain_id   = trimspace(var.hostvds_os_project_domain_id) != "" ? var.hostvds_os_project_domain_id : null
  project_domain_name = trimspace(var.hostvds_os_project_domain_id) == "" && trimspace(var.hostvds_os_project_domain_name) != "" ? var.hostvds_os_project_domain_name : null

  region        = trimspace(var.hostvds_os_region_name) != "" ? var.hostvds_os_region_name : null
  endpoint_type = trimspace(var.hostvds_os_interface) != "" ? var.hostvds_os_interface : null
}

provider "yandex" {
  token                    = trimspace(var.yandex_token) != "" ? var.yandex_token : null
  service_account_key_file = trimspace(var.yandex_service_account_key_file) != "" ? var.yandex_service_account_key_file : null
  cloud_id                 = trimspace(var.yandex_cloud_id) != "" ? var.yandex_cloud_id : null
  folder_id                = trimspace(var.yandex_folder_id) != "" ? var.yandex_folder_id : null
  zone                     = trimspace(var.yandex_zone) != "" ? var.yandex_zone : null
}
