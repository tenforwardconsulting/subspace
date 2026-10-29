# resource "aws_route53_zone" "primary" {
#   name = var.domain_name
#   tags = {
#     Name = "${var.project_name} Primary Domain"
#   }
# }

resource "aws_route53_record" "single" {
  count = length(var.zone_id) > 0 ? 1 : 0
  zone_id = var.zone_id
  name    = "${var.subdomain}"
  type    = "A"
  ttl     = "300"
  records = [aws_eip.single.public_ip]
}

# resource "aws_route53_record" "cname" {
#   zone_id = aws_route53_zone.primary.zone_id
#   name    = "${var.project_environment}"
#   type    = "CNAME"
#   ttl     = "300"
#   records = ["${var.project_name}."]
# }
