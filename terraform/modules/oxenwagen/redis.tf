resource "aws_elasticache_cluster" "redis" {
  count                = var.redis_node_count > 0 ? 1 : 0
  cluster_id           = "${var.project_environment}"
  engine               = "redis"
  apply_immediately    = var.redis_apply_immediately
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet[0].name
  node_type            = var.redis_node_type
  num_cache_nodes      = var.redis_node_count
  engine_version       = var.redis_engine_version
  parameter_group_name = var.redis_parameter_group_name

  port                 = 6379
  security_group_ids   = [aws_security_group.production-redis[0].id]
}

resource "aws_elasticache_subnet_group" "redis_subnet" {
  count      = var.redis_node_count > 0 ? 1 : 0
  name       = "${var.project_environment}-cache-subnet"
  subnet_ids = data.aws_subnets.subnets.ids
}

resource "aws_security_group" "production-redis" {
  count       = var.redis_node_count > 0 ? 1 : 0
  name        = "${var.project_environment}-redis"
  description = "${var.project_environment}-redis"
  vpc_id      = aws_vpc.production-internal.id

  ingress {
    description      = "Redis traffic from webservers and workers"
    from_port        = 6379
    to_port          = 6379
    protocol         = "tcp"
    security_groups  = [aws_security_group.production-webservers.id, aws_security_group.production-workers.id]
  }
}
