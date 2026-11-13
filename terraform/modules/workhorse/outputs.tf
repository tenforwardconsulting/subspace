output "instances" {
  value = {
    for key, instance in aws_instance.single : key => {
      id         = instance.id
      hostname   = var.instances[key].hostname
      private_ip = instance.private_ip
      public_ip  = key == var.active_instance ? aws_eip.single.public_ip : instance.public_ip
      active     = key == var.active_instance
    }
  }
}

output "active_instance" {
  value = var.active_instance
}

output "allow_instance_ssh" {
  value = var.allow_instance_ssh
}

output "inventory" {
  value = {
    hostnames    = [for key, instance in aws_instance.single : var.instances[key].hostname]
    ip_addresses = [for key, instance in aws_instance.single : key == var.active_instance ? aws_eip.single.public_ip : instance.public_ip]
    groups       = [for key, instance in aws_instance.single : "${var.project_environment} ${var.project_environment}_web ${var.project_environment}_worker"]
    users        = [for key, instance in aws_instance.single : var.instance_user]
  }
}
