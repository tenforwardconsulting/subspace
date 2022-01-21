# Subspace / Workhorse

This terraform module creates a single server designed to host an entire application all in one place.  Often this is used for development/staging environments or very lightweight applications. It does not provision any storage other than local / EBS storage (e.g. no RDS, no S3, etc) but you can certainly add that.

It does create networking resources including a (public) VPC and an Elastic IP address for the server.


## Input Variables

See (variables.tf)[variables.tf] for details.

## Outputs

See (outputs.tf)[outputs.tf] for details.

## Route 53 DNS

This will *always* create a Route53 zone, but it is up to you to ensure that the zone is referenced at the registrar.  The nameservers are included in the outputs.  If you don't actually use it, it can still be useful for tracking the IPs internally.

Since multiple environments will usually share the same Route53 Zone, you often need to import any existing zone, which you can do as follow:

  terraform import module.workhorse.aws_route53_zone.primary Z01235183LTADNNF1ZD2D