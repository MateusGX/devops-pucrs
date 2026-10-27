terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.regiao_aws

  default_tags {
    tags = {
      Projeto       = var.projeto
      Ambiente      = var.ambiente
      GerenciadoPor = "terraform"
    }
  }
}
