locals {
  yandex_whitelist_address_import_ids = {
    for name, node in var.yandex_whitelist_entry_nodes : name => node.address_id
  }

  yandex_whitelist_security_group_import_ids = {
    for name, node in var.yandex_whitelist_entry_nodes : name => node.security_group_id
  }

  yandex_whitelist_instance_import_ids = {
    for name, node in var.yandex_whitelist_entry_nodes : name => node.instance_id
  }
}

import {
  for_each = local.yandex_whitelist_address_import_ids
  to       = module.yandex_whitelist_entry[0].yandex_vpc_address.whitelist_entry[each.key]
  id       = each.value
}

import {
  for_each = local.yandex_whitelist_security_group_import_ids
  to       = module.yandex_whitelist_entry[0].yandex_vpc_security_group.whitelist_entry[each.key]
  id       = each.value
}

import {
  for_each = local.yandex_whitelist_instance_import_ids
  to       = module.yandex_whitelist_entry[0].yandex_compute_instance.whitelist_entry[each.key]
  id       = each.value
}
