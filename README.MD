# Terraform Module for Creating Cloudbees CI Operation Center and Client Controller in AWS EC2
# Overview
This Terraform module is designed to deploy Cloudbees CI Operation Center and Client Controller on AWS EC2 instances. It provides a flexible and customizable setup for running Cloudbees CI in a cloud environment.
# Features
- Deploys Cloudbees CI Operation Center and Client Controller on AWS EC2 instances.
- Automatically configures security groups.
- Automatically install wildcard license file `license.xml`.
- Automatically configures VPC and subnet configurations.
- Automatically configure ALB for Operation Center and Client Controller.

# Requirements
- AWS account with necessary permissions to create EC2 instances, security groups, and VPCs.
- Predefined hosted zone in Route53 for DNS configuration.
- Predefined EC2 key pair for SSH access to the instances.
- Terraform installed on your local machine or CI/CD environment.
- Cloudbees CI license file (`license.xml`) placed in the `secrets` directory.
- Terraform version 0.12 or higher.
- AWS provider version 3.0 or higher.

# Usage
- Copy .auto.tfvars.example to .auto.tfvars and fill in the required variables.
- Create hosted zone in Route53 for DNS configuration. and update the .auto.tfvars file
- Create EC2 key pair for SSH access to the instances and update the .auto.tfvars file.
- Copy wildcard license file `license.xml` to the `secrets` directory.
- Run `terraform init` to initialize the module.
- Run `terraform plan` to see the execution plan.
- Run `terraform apply` to create the resources defined in the module.
- Run `terraform destroy` to remove the resources created by the module.
