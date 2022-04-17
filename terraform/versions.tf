terraform {
  backend "local" {
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.20.0, < 4.0.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "2.1.0"
    }

  }
  required_version = ">= 0.14"
}
