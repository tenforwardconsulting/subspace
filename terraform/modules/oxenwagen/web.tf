resource "aws_instance" "web" {
  for_each               = var.web_instances
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.subspace.key_name
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [aws_security_group.production-webservers.id, aws_security_group.production-internal.id]
  monitoring             = true

  tags = {
    Name = each.value.hostname
  }

  root_block_device {
    volume_size = each.value.volume_size
    encrypted   = true
    kms_key_id  = aws_kms_key.subspace.arn
  }
}

# Associate an elastic IP with each web server
resource aws_eip "web" {
  for_each = var.web_instances
  instance = aws_instance.web[each.key].id

  tags = {
    Name = each.value.hostname
  }
}

resource "aws_eip_association" "eip_assoc" {
  for_each      = var.web_instances
  instance_id   = aws_instance.web[each.key].id
  allocation_id = aws_eip.web[each.key].id
}
