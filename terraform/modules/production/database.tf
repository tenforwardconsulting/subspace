resource "aws_db_instance" "production" {
  identifier               = "${var.project_name}-${var.project_environment}"
  allocated_storage        = var.database_allocated_storage
  max_allocated_storage    = var.database_max_allocated_storage
  engine                   = var.database_engine
  engine_version           = var.database_engine_version
  instance_class           = var.database_instance_class
  name                     = var.database_name
  username                 = var.database_username
  password                 = var.database_password
  db_subnet_group_name     = aws_db_subnet_group.production-subnet-group.name
  delete_automated_backups = false
  deletion_protection      = true
  iops                     = var.database_iops
  vpc_security_group_ids   = [aws_security_group.production-rds.id]
  storage_encrypted        = true
}
