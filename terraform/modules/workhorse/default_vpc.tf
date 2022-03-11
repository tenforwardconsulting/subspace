# Production was already set up here in the default VPC and I don't want to move it
# So look up the subnets instead

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_security_group" "single" {
  name        = "${var.project_environment} workhorse server"
  description = "Allow inbound web and ssh traffic"
  vpc_id      = aws_default_vpc.default.id
  lifecycle {
    create_before_destroy = true
  }

  ingress {
    description      = "TLS from world"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTP from world"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH from 10fw Office"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["172.220.8.253/32"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
