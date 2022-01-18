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

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [aws_vpc.production-internal.id]
  }
}

resource "aws_security_group" "production-webservers" {
  name        = "production-webservers"
  description = "webservers"
  vpc_id      = aws_vpc.production-internal.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group_rule" "webservers_webservers_traffic" {
  security_group_id        = "${aws_security_group.production-webservers.id}"
  description              = "All traffic from webservers"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.production-webservers.id
  type                     = "ingress"
}

resource "aws_security_group_rule" "webservers_workers_traffic" {
  security_group_id        = "${aws_security_group.production-webservers.id}"
  description              = "All traffic from workers"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.production-workers.id
  type                     = "ingress"
}

resource "aws_security_group_rule" "webservers_world_http" {
  security_group_id = "${aws_security_group.production-webservers.id}"
  description       = "HTTP from world"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  type              = "ingress"
}

resource "aws_security_group_rule" "webservers_tenforward_ssh" {
  security_group_id = "${aws_security_group.production-webservers.id}"
  description       = "SSH from 10fw Office"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks  = ["172.220.8.253/32"]
  type              = "ingress"
}

resource "aws_security_group" "production-workers" {
  name        = "production-workers"
  description = "workers"
  vpc_id      = aws_vpc.production-internal.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group_rule" "workers_webservers_traffic" {
  security_group_id        = "${aws_security_group.production-workers.id}"
  description              = "All traffic from webservers"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.production-webservers.id
  type                     = "ingress"
}

resource "aws_security_group_rule" "workers_workers_traffic" {
  security_group_id        = "${aws_security_group.production-workers.id}"
  description              = "All traffic from workers"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.production-workers.id
  type                     = "ingress"
}

resource "aws_security_group_rule" "workers_tenforward_ssh" {
  security_group_id = "${aws_security_group.production-workers.id}"
  description       = "SSH from 10fw Office"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["172.220.8.253/32"]
  type              = "ingress"
}

resource "aws_security_group" "production-rds" {
  name        = "production-rds"
  description = "rds"
  vpc_id      = aws_vpc.production-internal.id

  ingress {
    description      = "PSQL traffic from webservers and workers"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    security_groups  = [aws_security_group.production-webservers.id, aws_security_group.production-workers.id]
  }
}
