resource "aws_instance" "worker" {
  for_each               = var.worker_instances
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.subspace.key_name
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [aws_security_group.production-webservers.id, aws_security_group.production-internal.id]
  monitoring             = true

  root_block_device {
    volume_size = each.value.volume_size
    encrypted   = true
    kms_key_id  = aws_kms_key.subspace.arn
  }

  tags = {
    Name = each.value.hostname
  }
}

# Associate an elastic IP with each worker server
resource aws_eip "worker" {
  for_each = var.worker_instances
  instance = aws_instance.worker[each.key].id

  tags = {
    Name = each.value.hostname
  }
}

resource "aws_eip_association" "worker_eip_assoc" {
  for_each      = var.worker_instances
  instance_id   = aws_instance.worker[each.key].id
  allocation_id = aws_eip.worker[each.key].id
}
