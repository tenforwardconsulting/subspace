# Global (e.g. include -var-file=../global.vars)

variable aws_region { type = string }
variable project_name { type = string }
variable project_environment { type = string }
variable instance_ami { type = string }
variable subspace_public_key { type = string }
variable ssh_cidr_blocks { type = list }

# worker.tf
variable worker_instance_type { type = string }
variable worker_instance_count { type = number }
variable worker_volume_size {
  type = number
  default = 32 #GB
}

# web.tf
variable web_instance_type { type = string }
variable web_instance_count { type = number }
variable web_volume_size {
  type = number
  default = 16 #GB
}


# load_balancer.tf
variable lb_domain_name {
  type = string
  default = ""
}
variable lb_alternate_names {
  type = list(string)
  default = []
}
variable lb_health_check_path { type = string }

# database.tf
variable database_engine { type = string }
variable database_engine_version { type = string }
variable database_instance_class { type = string }
variable database_name { type = string }
variable database_username { type = string }
variable database_password { type = string }
variable database_allocated_storage { type = number }
variable database_max_allocated_storage { type = number }
variable database_iops { type = number }
