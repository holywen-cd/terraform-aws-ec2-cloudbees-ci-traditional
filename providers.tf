terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.67.0"
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
}