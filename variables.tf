variable "aws_credentials" {
  type = object({
    access_key = string
    secret_key = string
  })
  sensitive = true
}

variable "account_id" {
  type = string
  sensitive = false
}
