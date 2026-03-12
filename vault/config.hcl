# TODO
ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "raft" {
  # Single-node Raft should bootstrap itself from local storage.
  path    = "/vault/data"
  node_id = "node1"
}

api_addr = "https://vault.lannister-dev.ru"
cluster_addr = "https://vault:8201"

disable_mlock = true
