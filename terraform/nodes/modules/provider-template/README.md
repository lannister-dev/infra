# Provider Module Template

Use this template contract when adding real provider-specific modules (AWS, Hetzner, etc.).

Expected module behavior:

1. Create/replace VPS instances via provider API.
2. Output normalized node map consumable by `terraform/nodes`.

Suggested output shape:

```hcl
output "vpn_nodes" {
  value = {
    "vpn-amsterdam-01" = {
      public_ip = "203.0.113.10"
      channel   = "prod"
      ssh_user  = "root"
      ssh_port  = 22
      enabled   = true
      provider  = "example-api"
      region    = "eu-nl"
    }
  }
}
```

Then wire that output into `terraform/nodes` variable `vpn_nodes`.
