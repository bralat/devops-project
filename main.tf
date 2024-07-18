terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region     = "eu-west-2"
  access_key = var.aws_credentials.access_key
  secret_key = var.aws_credentials.secret_key
}
