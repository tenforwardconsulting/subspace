resource "aws_route53_record" "web" {
  for_each = length(var.route53_zone_id) > 0 ? var.web_instances : {}
  zone_id  = var.route53_zone_id
  name     = each.value.hostname
  type     = "A"
  ttl      = 300
  records  = [aws_eip.web[each.key].public_ip]
}

resource "aws_route53_record" "worker" {
  for_each = length(var.route53_zone_id) > 0 ? var.worker_instances : {}
  zone_id  = var.route53_zone_id
  name     = each.value.hostname
  type     = "A"
  ttl      = 300
  records  = [aws_eip.worker[each.key].public_ip]
}

resource "aws_route53_record" "lb" {
  count   = length(var.route53_zone_id) > 0 ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.lb_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.production.dns_name
    zone_id                = aws_lb.production.zone_id
    evaluate_target_health = true
  }
}

