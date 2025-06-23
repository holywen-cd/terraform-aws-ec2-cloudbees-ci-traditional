output "operation_center_url" {
  value = "https://${var.oc_subdomain}.${var.hosted_zone_name}"
}

output "client_controller_url" {
  value = "https://${var.cm_subdomain}.${var.hosted_zone_name}"
}

output "initial_password_path" {
  value = "/var/lib/jenkins/secrets/initialAdminPassword"
}

output "alb_dns_name" {
  value = aws_lb.cb_alb.dns_name
}

output "subnet_cidrs" {
  value = [for s in aws_subnet.public : s.cidr_block]
}

output "oc_server_public_ip" {
  value = aws_instance.oc_server.public_ip
}

output "cm_server_public_ip" {
  value = aws_instance.cm_server.public_ip
}