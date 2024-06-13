# DNS
data "aws_route53_zone" "zone" {
  name = var.tfe_domain
}


# Create DNS for the Load Balancer
resource "aws_route53_record" "lb" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "${var.tfe_subdomain}.${data.aws_route53_zone.zone.name}"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_lb.tfe_lb.dns_name] #point it to the lb dns name
}

# Create DNS for the Bastion server
resource "aws_route53_record" "bastion" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "${var.tfe_subdomain}.${data.aws_route53_zone.zone.name}-bastion"
  type    = "A"
  ttl     = "300"
  records = [aws_eip.eip.public_ip]
}


# Create Certificates
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}

resource "acme_registration" "reg" {
  account_key_pem = tls_private_key.private_key.private_key_pem
  email_address   = var.email
}

resource "acme_certificate" "certificate" {
  account_key_pem = acme_registration.reg.account_key_pem
  #common_name                  = "fdo-docker.${data.aws_route53_zone.zone.name}"
  #subject_alternative_names    = ["fdo-docker.${data.aws_route53_zone.zone.name}"]
  common_name                  = "${var.tfe_subdomain}.${data.aws_route53_zone.zone.name}"
  subject_alternative_names    = ["${var.tfe_subdomain}.${data.aws_route53_zone.zone.name}"]
  disable_complete_propagation = true

  dns_challenge {
    provider = "route53"
    config = {
      AWS_HOSTED_ZONE_ID = data.aws_route53_zone.zone.zone_id,
      AWS_REGION         = var.aws_region
    }
  }
}

# Add my certificates to a S3 Bucket
resource "aws_s3_bucket" "s3bucket" {
  bucket = var.bucket

  tags = {
    Name        = "${var.prefix} FDO Bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_object" "object" {
  for_each = toset(["certificate_pem", "issuer_pem", "private_key_pem"])
  bucket   = aws_s3_bucket.s3bucket.bucket
  key      = "ssl-certs/${each.key}"
  content  = lookup(acme_certificate.certificate, "${each.key}")
}

resource "aws_s3_object" "object_full_chain" {
  bucket  = aws_s3_bucket.s3bucket.bucket
  key     = "ssl-certs/full_chain"
  content = "${acme_certificate.certificate.certificate_pem}${acme_certificate.certificate.issuer_pem}"
}

# Create network
resource "aws_vpc" "vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "${var.prefix}-vpc"
  }
}

resource "aws_subnet" "publicsub" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "${var.prefix}-public-subnet"
  }
}

resource "aws_subnet" "privatesub" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.prefix}-private-subnet"
  }
}



resource "aws_internet_gateway" "internetgw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.prefix}-internet-gateway"
  }
}

resource "aws_route_table" "route" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internetgw.id
  }

  tags = {
    Name = "${var.prefix}-route"
  }
}

resource "aws_route_table_association" "route_association" {
  subnet_id      = aws_subnet.publicsub.id
  route_table_id = aws_route_table.route.id
}

resource "aws_security_group" "securitygp" {

  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "https-access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh-access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "db-access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "redis-access"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "vault-access"
    from_port   = 8201
    to_port     = 8201
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "egress-rule"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    type = "${var.prefix}-security-group"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nateip.id
  subnet_id     = aws_subnet.publicsub.id

  tags = {
    Name = "${var.prefix}-nat-gateway"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.internetgw]
}

resource "aws_route_table" "routenat" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.prefix}-routenat"
  }
}

resource "aws_route_table_association" "routenat_association" {
  subnet_id      = aws_subnet.privatesub.id
  route_table_id = aws_route_table.routenat.id
}


# Create network to attach to the Bastion server
resource "aws_network_interface" "nic" {
  subnet_id       = aws_subnet.publicsub.id
  security_groups = [aws_security_group.securitygp.id]
}


resource "aws_eip" "eip" {
  domain                    = "vpc"
  associate_with_private_ip = aws_network_interface.nic.private_ip
  instance                  = aws_instance.bastion.id

  tags = {
    Name = "${var.prefix}-eip"
  }
}

resource "aws_eip" "nateip" {
  domain                    = "vpc"
  associate_with_private_ip = aws_network_interface.nic.private_ip

  tags = {
    Name = "${var.prefix}-eip-nat"
  }
}

# Create Bastion Server/Jump host
resource "aws_instance" "bastion" {
  ami                  = "ami-0bd23a7080ec75f4d" # eu-west-3 redhat machine 
  instance_type        = "m5.xlarge"
  iam_instance_profile = aws_iam_instance_profile.profile.name

  credit_specification {
    cpu_credits = "unlimited"
  }

  key_name = var.key_pair

  root_block_device {
    volume_size = 50
  }

  network_interface {
    network_interface_id = aws_network_interface.nic.id
    device_index         = 0
  }

  tags = {
    Name = "${var.prefix}-tfe-bastion"
  }

}



# Create roles and policies to attach to the instance
resource "aws_iam_role" "role" {
  name = "${var.prefix}-role-podman"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.prefix}-profile-podman"
  role = aws_iam_role.role.name
}

resource "aws_iam_role_policy" "policy" {
  name = "${var.prefix}-policy-podman"
  role = aws_iam_role.role.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : "s3:ListBucket",
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ],
        "Resource" : [
          "arn:aws:s3:::*/*"
        ]
      }
    ]
  })
}

resource "aws_key_pair" "key-pair" {
  key_name   = var.key_pair
  public_key = file("~/.ssh/id_rsa.pub")
}


# Create External Services: AWS S3 Bucket
resource "aws_s3_bucket" "s3bucket_data" {
  bucket        = var.storage_bucket
  force_destroy = true

  tags = {
    Name        = "${var.prefix} FDO Storage"
    Environment = "Dev"
  }
}

# Create External Services: Postgres 14.x DB
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.prefix}-db-subnetgroup"
  subnet_ids = [aws_subnet.publicsub.id, aws_subnet.privatesub.id]

  tags = {
    Name = "${var.prefix}-db-subnet-group "
  }
}

resource "aws_db_instance" "tfe_db" {
  allocated_storage      = 400
  identifier             = var.db_identifier
  db_name                = var.db_name
  engine                 = "postgres"
  engine_version         = "14.9"
  instance_class         = "db.m5.xlarge"
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = "default.postgres14"
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.securitygp.id]
}

# Create Redis instance
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "${var.prefix}-redis-subnetgroup"
  subnet_ids = [aws_subnet.publicsub.id, aws_subnet.privatesub.id]
}

resource "aws_elasticache_cluster" "tfe_redis" {
  cluster_id           = "${var.prefix}-tfe-redis"
  engine               = "redis"
  node_type            = "cache.t3.small"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = 6379
  security_group_ids   = [aws_security_group.securitygp.id]
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
}

# Create the Application Load Balancer
resource "aws_lb" "tfe_lb" {
  name               = "${var.prefix}-tfe-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.securitygp.id]
  subnets            = [aws_subnet.publicsub.id, aws_subnet.privatesub.id]

  enable_deletion_protection = false

  tags = {
    Environment = "${var.prefix}-load-balancer"
  }
}

resource "aws_lb_target_group" "tfe_lbtarget" {
  name     = "${var.prefix}-lb-targetgroup"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.vpc.id
}

resource "aws_lb_listener" "tfe_front_end" {
  load_balancer_arn = aws_lb.tfe_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.lbcert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tfe_lbtarget.arn
  }
}

resource "aws_acm_certificate" "lbcert" {
  private_key       = acme_certificate.certificate.private_key_pem #- (Required) Certificate's PEM-formatted private key
  certificate_body  = acme_certificate.certificate.certificate_pem #- (Required) Certificate's PEM-formatted public key
  certificate_chain = acme_certificate.certificate.issuer_pem      #- (Optional) Certificate's PEM-formatted chain

  tags = {
    Environment = "${var.prefix}-acm-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}


# Create the Launch Template for the ASG
resource "aws_launch_template" "tfe_launchtemp" {
  name_prefix   = "${var.prefix}-launch-template"
  image_id      = "ami-0bd23a7080ec75f4d" # eu-west-3 redhat machine
  instance_type = "m5.xlarge"
  key_name      = var.key_pair

  iam_instance_profile {
    name = aws_iam_instance_profile.profile.name
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      delete_on_termination = true
      volume_size           = 50
    }
  }

  network_interfaces {
    security_groups = [aws_security_group.securitygp.id]
    subnet_id       = aws_subnet.privatesub.id
  }

  user_data = base64encode(templatefile("${path.module}/fdo_ent.yaml", {
    tfe_version      = var.tfe_version,
    tfe_hostname     = var.tfe_hostname,
    enc_password     = var.enc_password,
    email            = var.email,
    username         = var.username,
    password         = var.password,
    bucket           = var.bucket,
    license_value    = var.license_value
    db_username      = var.db_username,
    db_password      = var.db_password,
    db_host          = aws_db_instance.tfe_db.endpoint,
    db_name          = var.db_name,
    storage_bucket   = var.storage_bucket,
    aws_region       = var.aws_region,
    redis_address    = lookup(aws_elasticache_cluster.tfe_redis.cache_nodes[0], "address", "Redis address not found"),
    redis_port       = aws_elasticache_cluster.tfe_redis.port

  }))

  tags = {
    Name = "${var.prefix}-tfe-podman"
  }

}

# Create ASG Group with a Launch Template. The ASG will create the EC2 instances
resource "aws_autoscaling_group" "tfe_asg" {
  #availability_zones     = ["${var.aws_region}"]
  desired_capacity       = 2
  max_size               = 2
  min_size               = 1
  vpc_zone_identifier    = [aws_subnet.privatesub.id]
  target_group_arns      = [aws_lb_target_group.tfe_lbtarget.arn]
  force_delete           = true
  force_delete_warm_pool = true

  launch_template {
    id      = aws_launch_template.tfe_launchtemp.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.prefix}-tfe-asg"
    propagate_at_launch = true
  }

  depends_on = [aws_nat_gateway.nat]
}

