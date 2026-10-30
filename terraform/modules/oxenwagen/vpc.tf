resource "aws_vpc" "production-internal" {
  cidr_block = "172.31.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.production-internal.id
}

resource "aws_subnet" "production-internal-a" {
  vpc_id            = aws_vpc.production-internal.id
  cidr_block        = "172.31.0.0/20"
  availability_zone = "${var.aws_region}a"
}

resource "aws_subnet" "production-internal-b" {
  vpc_id            = aws_vpc.production-internal.id
  cidr_block        = "172.31.16.0/20"
  availability_zone = "${var.aws_region}b"
}

resource "aws_subnet" "production-internal-c" {
  vpc_id            = aws_vpc.production-internal.id
  cidr_block        = "172.31.32.0/20"
  availability_zone = "${var.aws_region}c"
}

resource "aws_db_subnet_group" "production-subnet-group" {
  name       = "${var.project_environment}-${var.project_name}"
  subnet_ids = [aws_subnet.production-internal-a.id, aws_subnet.production-internal-b.id, aws_subnet.production-internal-c.id]

  tags = {
    Name = "${var.project_environment}-${var.project_name}"
  }
}

resource "aws_route_table" "production" {
  vpc_id = aws_vpc.production-internal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.production-internal.id
  route_table_id = aws_route_table.production.id
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [aws_vpc.production-internal.id]
  }
}

resource "aws_security_group" "production-webservers" {
  name        = "${var.project_environment}-webservers"
  description = "${var.project_environment}-webservers"
  vpc_id      = aws_vpc.production-internal.id

  ingress {
    description      = "HTTP from lb"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups = [aws_security_group.production-load-balancer.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "production-workers" {
  name        = "${var.project_environment}-workers"
  description = "${var.project_environment}-workers"
  vpc_id      = aws_vpc.production-internal.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "production-internal" {
  name        = "${var.project_environment}-internal"
  description = "${var.project_environment}-internal"
  vpc_id      = aws_vpc.production-internal.id

  ingress {
    description      = "All traffic from webservers and workers"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    security_groups  = [aws_security_group.production-webservers.id, aws_security_group.production-workers.id]
  }

  ingress {
    description      = "SSH Access"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.ssh_cidr_blocks
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "production-rds" {
  name        = "${var.project_environment}-rds"
  description = "${var.project_environment}-rds"
  vpc_id      = aws_vpc.production-internal.id

  ingress {
    description      = "PSQL traffic from webservers and workers"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    security_groups  = [aws_security_group.production-webservers.id, aws_security_group.production-workers.id]
  }
}
