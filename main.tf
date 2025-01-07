terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    mysql = {
      source  = "petoju/mysql"
      version = "~> 3.0.0"
    }
  }
  
}


provider "aws" {
  region = "us-east-2"
}