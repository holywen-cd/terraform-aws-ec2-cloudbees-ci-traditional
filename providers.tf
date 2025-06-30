terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.67.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

#   cloud {
#     organization = "holywen"
#     workspaces {
#       name = "telstra-training-aws"
#     }
#   }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      cb-owner           = var.tags.cb-owner
      cb-user            = var.tags.cb-user
      cb-environment     = var.tags.cb-environment
    }
  }
}