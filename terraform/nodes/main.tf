module "hostvds_compute" {
  source = "./modules/hostvds-compute"
  count  = local.hostvds_compute_enabled_effective ? 1 : 0

  providers = {
    openstack = openstack.hostvds
  }

  nodes = local.hostvds_compute_input_nodes
}

module "yandex_whitelist_entry" {
  source = "./modules/yandex-whitelist-entry"
  count  = length(var.yandex_whitelist_entry_nodes) > 0 ? 1 : 0

  providers = {
    yandex = yandex
  }

  nodes = var.yandex_whitelist_entry_nodes
}

module "hostvds_api_catalog" {
  source = "./modules/hostvds-api"

  enabled                = local.hostvds_api_enabled
  os_auth_url            = var.hostvds_os_auth_url
  os_username            = var.hostvds_os_username
  os_password            = var.hostvds_os_password
  os_project_name        = var.hostvds_os_project_name
  os_user_domain_name    = var.hostvds_os_user_domain_name
  os_user_domain_id      = var.hostvds_os_user_domain_id
  os_project_domain_name = var.hostvds_os_project_domain_name
  os_project_domain_id   = var.hostvds_os_project_domain_id
  os_region_name         = var.hostvds_os_region_name
  os_interface           = var.hostvds_os_interface
  nodes                  = local.hostvds_api_input_nodes
}

resource "local_file" "vpn_nodes_inventory" {
  filename        = local.resolved_inventory_output_path
  file_permission = "0600"
  content = yamlencode({
    vpn_nodes = local.vpn_nodes_list
  })

  lifecycle {
    precondition {
      condition     = length(local.enabled_vpn_nodes_list) > 0 || var.allow_empty_vpn_nodes
      error_message = "Enabled VPN node set is empty. Set allow_empty_vpn_nodes=true only for intentional full decommission."
    }

    precondition {
      condition     = !local.hostvds_credentials_required || trimspace(var.hostvds_os_auth_url) != ""
      error_message = "hostvds_os_auth_url is required when HostVDS API/compute mode has nodes enabled."
    }

    precondition {
      condition     = !local.hostvds_credentials_required || trimspace(var.hostvds_os_username) != ""
      error_message = "hostvds_os_username is required when HostVDS API/compute mode has nodes enabled."
    }

    precondition {
      condition     = !local.hostvds_credentials_required || trimspace(var.hostvds_os_project_name) != ""
      error_message = "hostvds_os_project_name is required when HostVDS API/compute mode has nodes enabled."
    }

    precondition {
      condition     = !local.hostvds_credentials_required || trimspace(var.hostvds_os_interface) != ""
      error_message = "hostvds_os_interface is required when HostVDS API/compute mode has nodes enabled."
    }

    precondition {
      condition     = !local.hostvds_credentials_required || trimspace(var.hostvds_os_user_domain_name) != "" || trimspace(var.hostvds_os_user_domain_id) != ""
      error_message = "Set hostvds_os_user_domain_name or hostvds_os_user_domain_id when HostVDS API/compute mode has nodes enabled."
    }

    precondition {
      condition     = !local.hostvds_credentials_required || trimspace(var.hostvds_os_project_domain_name) != "" || trimspace(var.hostvds_os_project_domain_id) != ""
      error_message = "Set hostvds_os_project_domain_name or hostvds_os_project_domain_id when HostVDS API/compute mode has nodes enabled."
    }

    precondition {
      condition     = !local.hostvds_credentials_required || trimspace(var.hostvds_os_password) != ""
      error_message = "hostvds_os_password is required when HostVDS API/compute mode has nodes enabled."
    }
  }
}
