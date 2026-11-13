# Subspace: Production Environment TF Module
![Oxenwagen: load balanced, vpc isolated production infrastructure](/doc/oxenwagen.jpg)

This terraform module is used as a default, standard, load balanced environment suitable for initial production rails deploys.  It has a lot of configuration but it also fairly opinionated.
# Load Balancer
The load balancer is tricky.  If you have access to the DNS zone on AWS/Route53, it can be provisioned automatically (if we write this feature):

    route53_zone_id = "Z0123456789ABCDEF0"
    lb_domain_name = "my.production.site"
    lb_alternate_names = ["www.production.site", "production.site"]

If not, e.g. if you have to do email or outside DNS validation, you can instead maunally create a cert on AWS and then specify the ARN:

    lb_certificate_arn "aws.arn.whateverexamplethign"

If you do not specify either `lb_domain_name` or `lb_certificate_arn` your load balancer *will not* be created with an HTTPS/TLS target group, it will be HTTP only.

# Redis

Most rails projects need a redis for things like sidekiq, actioncable, etc, so this tf script can create an elasticache redis instance/cluster for you.  Alternatively, you can configure a worker server to run redis, but using elasticache is is usually preferred.

    # Number of redis nodes in the cluster.
    redis_node_count = 1
    redis_node_type = "cache.t4g.micro"
    redis_engine_version = "6.x"
    redis_parameter_group_name = "default.redis6.x"

By default, this will *not* create a redis cluster.
