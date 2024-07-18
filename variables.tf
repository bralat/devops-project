variable "rds_credentials" {
  type = object({
    username = string
    password = string
  })
  sensitive = true
}

variable "aws_credentials" {
  type = object({
    access_key = string
    secret_key = string
  })
  sensitive = true
}
