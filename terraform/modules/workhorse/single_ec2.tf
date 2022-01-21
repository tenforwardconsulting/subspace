resource "aws_instance" "single" {
  ami           = var.instance_ami
  instance_type = var.instance_type
  key_name      = aws_key_pair.subspace.key_name
  vpc_security_group_ids = [aws_security_group.single.id]

  tags = {
    Name = "${var.project_environment} Server"
    Environment = var.project_environment
  }
}

# Associate an elastic IP with each single server
resource aws_eip "single" {
  instance = aws_instance.single.id
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.single.id
  allocation_id = aws_eip.single.id
}
