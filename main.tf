


##########################
# DNS: Hosted Zone
##########################
data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}

data "aws_availability_zones" "available" {}

locals {
  license_key_content = file(var.license_key_path)
  license_cert_content = file(var.license_cert_path)
  oc_url = "https://${var.oc_subdomain}.${var.hosted_zone_name}"
  cm_url = "https://${var.cm_subdomain}.${var.hosted_zone_name}"
  oc_jenkins_yaml_content = templatefile("casc/cjoc/jenkins.yaml.tpl", {
    license_key_content = local.license_key_content
    license_cert_content = local.license_cert_content
    oc_login_user = var.oc_login_user
    oc_login_pwd  = var.oc_login_pwd
    oc_url = local.oc_url
  })

  public_subnet_count = 2
  public_subnet_cidrs = [for i in range(local.public_subnet_count) : cidrsubnet(var.vpc_cidr, 8, i)]
}

resource "random_id" "suffix" {
  byte_length = 3
}

##########################
# Network
##########################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "cb-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "cb-igw" }
}

resource "aws_subnet" "public" {
  count = local.public_subnet_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "cb-subnet--${data.aws_availability_zones.available.names[count.index]}" }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "pub_assoc" {
  count = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.rt.id
}

##########################
# Security Groups
##########################

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTPS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Allow 8888/8080 from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8888
    to_port         = 8888
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
      description = "Allow traffic between instances in the same security group"
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      cidr_blocks = [for s in aws_subnet.public : s.cidr_block]
  }

  ingress {
    description = "Allow SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "efs_sg" {
  name   = "efs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "NFS from EC2 Security Group"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#create EFS File System
resource "aws_efs_file_system" "efs" {
  # creation_token = "my-efs"
  throughput_mode = "bursting"
}

# create EFS Mount Target
resource "aws_efs_mount_target" "efs_mount_target" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.public[1].id
  security_groups = [aws_security_group.efs_sg.id]
}

##########################
# ACM Certificate + DNS Validation
##########################

resource "aws_acm_certificate" "cert" {
  domain_name               = "${var.oc_subdomain}.${var.hosted_zone_name}"
  subject_alternative_names = ["${var.cm_subdomain}.${var.hosted_zone_name}"]
  validation_method         = "DNS"
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  name    = each.value.name
  type    = each.value.type
  zone_id = data.aws_route53_zone.main.zone_id
  records = [each.value.record]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

##########################
# ALB + TG
##########################

resource "aws_lb" "cb_alb" {
  name               = "cloudbees-alb-${random_id.suffix.hex}"
  internal           = false
  load_balancer_type = "application"
  subnets            = [for subnet in aws_subnet.public : subnet.id]
  security_groups    = [aws_security_group.alb_sg.id]
}

###########################################
# Target Groups
###########################################

# Operation Center: port 8888
resource "aws_lb_target_group" "oc_tg" {
  name     = "cb-oc-tg-${random_id.suffix.hex}"
  port     = 8888
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path     = "/whoAmI/api/json?tree=authenticated"
    protocol = "HTTP"
    port     = "traffic-port"
    matcher  = "200-399"
  }

  tags = {
    Name = "CloudBees Operation Center TG"
  }
}

# Client Controller: port 8080
resource "aws_lb_target_group" "cm_tg" {
  name     = "cb-cm-tg-${random_id.suffix.hex}"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  stickiness {
    enabled = true
    type    = "lb_cookie"
    cookie_duration = 86400  # uom: s, default 1 day
  }

  health_check {
    path     = "/whoAmI/api/json?tree=authenticated"
    protocol = "HTTP"
    port     = "traffic-port"
    matcher  = "200-399"
  }

  tags = {
    Name = "CloudBees Client Controller TG"
  }
}

###########################################
# Target Group Attachments
###########################################
resource "aws_lb_target_group_attachment" "oc_attach" {
  target_group_arn = aws_lb_target_group.oc_tg.arn
  target_id        = aws_instance.oc_server.id
  port             = 8888
}

##########################
# AWS KEY PAIRS
##########################

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.key_pair_name}-${random_id.suffix.hex}"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.ec2_key.private_key_pem
  filename = "${path.module}/${aws_key_pair.generated_key.key_name}.pem"
  file_permission = "0400"
}



##########################
# Jenkins EC2 Instances
##########################

resource "aws_instance" "oc_server" {
  ami                    = var.ami_image
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public[0].id
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  associate_public_ip_address = true

  user_data = templatefile("cloud-init/oc.tpl", {
    license_key_content = local.license_key_content
    license_cert_content = local.license_cert_content
    oc_jenkins_yaml_content = local.oc_jenkins_yaml_content
  })

  tags = merge(var.tags, {
    Name = "cb-oc-server"
  }
  )
}

resource "aws_launch_template" "cm_template" {
  name_prefix            = "cm-server-"
  image_id               = var.ami_image
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.generated_key.key_name

  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  user_data = base64encode(templatefile("cloud-init/cm.tpl", {
    oc_url = local.oc_url
    cm_url = local.cm_url
    efs_dns = "${aws_efs_file_system.efs.id}.efs.${var.region}.amazonaws.com"
    oc_login_user = var.oc_login_user
    oc_login_pwd  = var.oc_login_pwd
  }))

  depends_on = [aws_efs_mount_target.efs_mount_target]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "cb-cm-server"
    }
  }
}

resource "aws_autoscaling_group" "cm_asg" {
  name                      = "cm-server-asg-${random_id.suffix.hex}"
  max_size                  = 2
  min_size                  = 2
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.public[1].id]  #  subnet ids
  launch_template {
    id      = aws_launch_template.cm_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.cm_tg.arn]

  health_check_type         = "EC2"
  health_check_grace_period = 60

  tag {
    key                 = "Name"
    value               = "cb-cm-server-${random_id.suffix.hex}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

###########################################
# ALB Listener (HTTPS)
###########################################
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.cb_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.cert.arn
  ssl_policy = "ELBSecurityPolicy-TLS-1-2-2017-01"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Invalid hostname"
      status_code  = "404"
    }
  }
}

###########################################
# Listener Rules (Host-based routing)
###########################################

# https://oc.example.com → port 8888
resource "aws_lb_listener_rule" "oc_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.oc_tg.arn
  }

  condition {
    host_header {
      values = ["${var.oc_subdomain}.${var.hosted_zone_name}"]
    }
  }
}

# https://mc.example.com → port 8080
resource "aws_lb_listener_rule" "cm_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 101

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cm_tg.arn
  }

  condition {
    host_header {
      values = ["${var.cm_subdomain}.${var.hosted_zone_name}"]
    }
  }
}

##########################
# DNS Records
##########################

resource "aws_route53_record" "oc_dns" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.oc_subdomain}.${var.hosted_zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.cb_alb.dns_name
    zone_id                = aws_lb.cb_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cm_dns" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.cm_subdomain}.${var.hosted_zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.cb_alb.dns_name
    zone_id                = aws_lb.cb_alb.zone_id
    evaluate_target_health = true
  }
}