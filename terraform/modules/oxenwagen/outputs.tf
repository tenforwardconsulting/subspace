output web_instance_ips {
  value = [for key, eip in aws_eip.web : eip.public_ip]
}
output worker_instance_ips {
  value = [for key, eip in aws_eip.worker : eip.public_ip]
}
output certification_dns_options {
  value = aws_acm_certificate.production[*].domain_validation_options
}

output database_endpoint {
  value = aws_db_instance.production.endpoint
}

output inventory {
  value = {
    hostnames    = concat([for key, instance in aws_instance.web : var.web_instances[key].hostname], [for key, instance in aws_instance.worker : var.worker_instances[key].hostname])
    ip_addresses = concat([for key, instance in aws_instance.web : aws_eip.web[key].public_ip], [for key, instance in aws_instance.worker : aws_eip.worker[key].public_ip])
    groups       = concat([for key, instance in aws_instance.web : "${var.project_environment} ${var.project_environment}_web"], [for key, instance in aws_instance.worker : "${var.project_environment} ${var.project_environment}_worker"])
    users        = concat([for key, instance in aws_instance.web : "ubuntu"], [for key, instance in aws_instance.worker : "ubuntu"])
  }
}

output "web_instances" {
  value = {
    for key, instance in aws_instance.web : key => {
      id         = instance.id
      hostname   = var.web_instances[key].hostname
      private_ip = instance.private_ip
      public_ip  = aws_eip.web[key].public_ip
      subnet_id  = instance.subnet_id
      in_lb      = contains(var.lb_instances, key)
    }
  }
}

output "worker_instances" {
  value = {
    for key, instance in aws_instance.worker : key => {
      id         = instance.id
      hostname   = var.worker_instances[key].hostname
      private_ip = instance.private_ip
      public_ip  = aws_eip.worker[key].public_ip
      subnet_id  = instance.subnet_id
    }
  }
}

output "lb_instances" {
  value = var.lb_instances
}

output "lb_target_group_arn" {
  value = aws_lb_target_group.production[0].arn
}

data "aws_caller_identity" "current" {}

output switch_role_url {
  value = "https://signin.aws.amazon.com/switchrole?roleName=DelegatedAccess&account=${data.aws_caller_identity.current.account_id}&displayName=${var.project_name}"
}

output lb_http_arn {
  value = aws_lb_listener.http.arn
}

output tls_http_arn {
  value = aws_lb_listener.tls[0].arn
}

output "redis_nodes" {
  value = aws_elasticache_cluster.redis[*].cache_nodes
}
