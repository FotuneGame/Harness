path "kv/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/*" {
  capabilities = ["list", "read", "delete"]
}
