resource "aws_route53_zone" "primary" {
  name = var.domain_name
  tags = {
    Name = "${var.project_name} Primary Domain"
  }
}

resource "aws_route53_record" "single" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "${var.instance_hostname}"
  type    = "A"
  ttl     = "300"
  records = [aws_eip.single.public_ip]
}

resource "aws_route53_record" "cname" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "${var.project_environment}"
  type    = "CNAME"
  ttl     = "300"
  records = ["${var.instance_hostname}.${var.domain_name}."]
}
