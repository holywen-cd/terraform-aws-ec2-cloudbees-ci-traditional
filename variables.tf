variable "region" {
  default = "us-east-1"
}

variable "ami_image" {
  default = "ami-0b8c2bd77c5e270cf"
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

variable "oc_login_user" {
    description = "Username for the CloudBees CI Operation Center admin user."
    default     = "admin"
    type        = string
}

variable "oc_login_pwd" {
  description = "Password for the CloudBees CI Operation Center admin user."
  default     = "admin"
  type        = string
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name"
  default     = "your-keypair-name"
}

variable "license_key_path" {
  description = "Path of the CloudBees CI license key file."
  default = "secrets/license.key"
  type        = string
}

variable "license_cert_path" {
  description = "Path of the CloudBees CI license cert file."
  default = "secrets/license.cert"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources."
  default     = {}
  type        = map(string)
}
