resource "aws_instance" "web" {
  count                  = var.web_instance_count
  ami                    = var.instance_ami
  instance_type          = var.web_instance_type
  key_name               = aws_key_pair.subspace.key_name
  subnet_id              = data.aws_subnets.subnets.ids[count.index % length(data.aws_subnets.subnets)]
  vpc_security_group_ids = [aws_security_group.production-webservers.id, aws_security_group.production-internal.id]
  monitoring             = true

  tags = {
    Name = "${var.project_environment}-web${count.index+1}"
  }

  root_block_device {
    volume_size = var.web_volume_size
    encrypted = true
    kms_key_id = aws_kms_key.subspace.arn
  }
}

# Associate an elastic IP with each web server
resource aws_eip "web" {
  count   = var.web_instance_count
  instance = aws_instance.web[count.index].id

  tags = {
    Name = "${var.project_environment}-web${count.index+1}"
  }
}

resource "aws_eip_association" "eip_assoc" {
  count = var.web_instance_count
  instance_id   = aws_instance.web[count.index].id
  allocation_id = aws_eip.web[count.index].id
}
