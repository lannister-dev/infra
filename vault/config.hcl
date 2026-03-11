# TODO
ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

storage "raft" {
  path = "/vault/data"
  node_id = "node1"
  retry_join = [
        {
            leader_api_addr = "http://vault:8200"
        }
    ]
}

api_addr = "https://vault.lannister-dev.ru"
cluster_addr = "https://vault:8201"

disable_mlock = true
