resource "aws_instance" "single" {
  for_each      = var.instances
  ami           = each.value.ami
  instance_type = each.value.instance_type
  key_name      = aws_key_pair.subspace.key_name
  vpc_security_group_ids = [aws_security_group.single.id]

  tags = {
    Name        = "${var.project_name} ${var.project_environment} Server"
    Environment = var.project_environment
  }
  root_block_device {
    volume_size = each.value.volume_size
  }
}

resource aws_eip "single" {}

resource "aws_eip_association" "eip_assoc" {
  allocation_id = aws_eip.single.id
  instance_id   = aws_instance.single[var.active_instance].id
}
