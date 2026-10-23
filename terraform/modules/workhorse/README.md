# Subspace / Workhorse

This terraform module creates a single server designed to host an entire application all in one place.  Often this is used for development/dev environments or very lightweight applications. It does not provision any storage other than local / EBS storage (e.g. no RDS, no S3, etc) but you can certainly add that.

It does create networking resources including a (public) VPC and an Elastic IP address for the server.

# Example Usage

    provider "aws" {
      region                   = "us-east-1"
      profile                  = "subspace-my-project"
    }

    module workhorse {
      source = "github.com/tenforwardconsulting/terraform-subspace-workhorse"
      project_name = "my-project"
      project_environment = "dev"
      aws_region = "us-east-1"
      subspace_public_key = file("../../subspace.pem.pub")
      subdomain = "myproject"
      zone_id = "" # AWS zone id if you want to autocreate DNS

      instance_user = "ubuntu"
      ssh_cidr_blocks = ["0.0.0.0/0"]

      instances = {
        "1" = {
          hostname      = "dev-app1"
          ami           = "ami-039af3bfc52681cd5"
          instance_type = "t3.medium"
          volume_size   = 16
        }
      }
      active_instance = "1"
    }

## Input Variables

See [variables.tf] for details.

## Instance slots

`instances` is keyed by *slot*, and a slot is a permanent terraform state address:
`module.workhorse.aws_instance.single["1"]`.  Slots are never renamed or renumbered,
which is what lets `subspace upgrade` stand a second server up beside the first one,
cut over to it, and destroy the original without terraform ever proposing to replace
the instance that is serving traffic.

`active_instance` names the slot that owns the Elastic IP.  Because the EIP itself is
never replaced, moving it is the entire cutover: the Route53 record and the letsencrypt
certificate both keep pointing at the same address.

## Upgrading from v1.x

v2.0.0 replaces `instance_ami`, `instance_type`, `instance_volume_size` and
`instance_hostname` with the `instances` map, so the migration is a config rewrite plus
one `terraform state mv`:

    instances = {
      "1" = {
        hostname      = "dev-app1"    # whatever instance_hostname was
        ami           = "ami-..."     # whatever instance_ami was
        instance_type = "t3.medium"
        volume_size   = 16
      }
    }
    active_instance = "1"

    terraform state mv 'module.workhorse.aws_instance.single' 'module.workhorse.aws_instance.single["1"]'

`terraform plan` must then report no changes.  A plan that proposes *replacing* the
instance means the migration is wrong; do not apply it.

`aws_eip.single` also drops its inline `instance` attribute, which duplicated (and
could fight with) `aws_eip_association.eip_assoc`.  The association resource is now the
only thing that binds the EIP to an instance.

## Outputs

See [outputs.tf] for details.

## Route 53 DNS

This will *always* create a Route53 zone, but it is up to you to ensure that the zone is referenced at the registrar.  The nameservers are included in the outputs.  If you don't actually use it, it can still be useful for tracking the IPs internally.

Since multiple environments will usually share the same Route53 Zone, you often need to import any existing zone, which you can do as follow:

  terraform import module.workhorse.aws_route53_zone.primary Z01235183LTADNNF1ZD2D
