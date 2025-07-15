output "operation_center_url" {
  value = "https://${var.oc_subdomain}.${var.hosted_zone_name}"
}

output "client_controller_url" {
  value = "https://${var.cm_subdomain}.${var.hosted_zone_name}"
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

output "agent1_public_ip" {
  value = aws_instance.agent1.public_ip
}

output "agent1_private_ip" {
  value = aws_instance.agent1.private_ip
}

output "asg_public_ips" {
  value = data.aws_instances.asg_instances.public_ips
}

output "cm_server_asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.cm_asg.name
}

output "efs_id" {
  value = aws_efs_file_system.efs.id
}

