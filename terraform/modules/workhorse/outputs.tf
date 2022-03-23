output "inventory" {
  value = {
    hostnames = ["${var.instance_hostname}"]
    ip_addresses = [aws_eip.single.public_ip]
    groups = ["${var.project_environment} ${var.project_environment}_web ${var.project_environment}_worker"]
    users = [var.instance_user]
  }
}
