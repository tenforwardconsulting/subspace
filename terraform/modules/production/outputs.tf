output web_instance_ips {
  value = aws_eip.web[*].public_ip
}
output worker_instance_ips {
  value = aws_eip.worker[*].public_ip
}
output certification_dns_options {
  value = aws_acm_certificate.web.domain_validation_options
}