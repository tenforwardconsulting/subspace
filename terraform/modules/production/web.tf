resource "aws_instance" "web" {
  count                  = var.web_instance_count
  ami                    = var.instance_ami
  instance_type          = var.web_instance_type
  key_name               = aws_key_pair.subspace.key_name
  subnet_id              = data.aws_subnets.subnets.ids[count.index % length(data.aws_subnets.subnets)]
  vpc_security_group_ids = [aws_security_group.production-webservers.id, aws_security_group.production-internal.id]
  monitoring             = true

  disable_api_termination = true

  tags = {
    Name = "web${count.index+1}"
    Environment = var.project_environment
    Project = var.project_name
  }
}

# Associate an elastic IP with each web server
resource aws_eip "web" {
  count   = var.web_instance_count
  instance = aws_instance.web[count.index].id

  tags = {
    Name = "web${count.index+1}"
    Environment = var.project_environment
    Project = var.project_name
  }
}

resource "aws_eip_association" "eip_assoc" {
  count = var.web_instance_count
  instance_id   = aws_instance.web[count.index].id
  allocation_id = aws_eip.web[count.index].id
}
