variable "rds_credentials" {
  type = object({
    username = string
    password = string
  })
  sensitive = true
}
