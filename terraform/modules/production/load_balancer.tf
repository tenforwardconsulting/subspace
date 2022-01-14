

resource "aws_security_group" "lb_sg" {
  name        = "load_balancer"
  description = "Allow inbound web traffic"
  vpc_id      = aws_default_vpc.default.id

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
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.project_environment}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = data.aws_subnets.default.ids
  idle_timeout       = 300

  enable_deletion_protection = true

#   access_logs {
#     bucket  = aws_s3_bucket.lb_logs.bucket
#     prefix  = "test-lb"
#     enabled = true
#   }

  tags = {
    Environment = "${var.project_environment}"
  }
}

resource "aws_acm_certificate" "web" {
  domain_name       = "app.looper.golf"
  subject_alternative_names = ["prod.looper.golf"]
  validation_method = "DNS"

  tags = {
    Environment = "${var.project_environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_listener" "tls" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.web.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_target_group" "http" {
  name     = "${var.project_name}-http"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_default_vpc.default.id
  health_check {
    enabled             = true
    matcher             = "200"
    port                = "80"
    protocol            = "HTTP"
    path                = "/auth/sign_in"
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "web" {
  count            = var.web_instance_count
  target_group_arn = aws_lb_target_group.http.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}