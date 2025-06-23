variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  default = "10.0.1.0/24"
}

variable "availability_zone" {
  default = "us-east-1a"
}

variable "hosted_zone_name" {
  default = "training.swen.aws.ps.beescloud.com"
}

variable "oc_subdomain" {
  default = "oc"
}

variable "cm_subdomain" {
  default = "cm"
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name"
  default     = "your-keypair-name"
}

variable "license_file_path" {
  description = "Content of the CloudBees CD license file."
  default = "secrets/license.xml"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources."
  default     = {}
  type        = map(string)
}
