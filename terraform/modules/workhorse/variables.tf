# Global (e.g. include -var-file=../global.vars)

variable aws_region { type = string }
variable project_name { type = string }
variable project_environment { type = string }
variable zone_id { type = string }
variable subdomain { type = string }
variable subspace_public_key { type = string }

# single_ec2.tf
variable instance_user { type = string }

variable ssh_cidr_blocks {
  default = ["0.0.0.0/0"]
}

variable instances {
  # key = host slot.  Slots are permanent terraform state addresses; never renumber them.
  type = map(object({
    hostname      = string
    ami           = string
    instance_type = string
    volume_size   = number
  }))
}

variable active_instance {
  description = "Which instances key owns the Elastic IP, and therefore the DNS record"
  type        = string
}

variable allow_instance_ssh {
  description = "Temporarily allow ssh between instances in this group.  Used by subspace upgrade for the db copy; should be false at rest."
  type        = bool
  default     = false
}
