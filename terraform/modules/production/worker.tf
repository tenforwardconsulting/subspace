

variable worker_instance_type {
    type = string
    default = "t3.medium"
}

variable worker_instance_count {
    type = number
    default = 1
}

resource "aws_instance" "worker" {
  count         = var.worker_instance_count
  ami           = var.instance_ami
  instance_type = var.worker_instance_type
  key_name      = aws_key_pair.subspace.key_name
  availability_zone = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available)]
  vpc_security_group_ids = [aws_security_group.ssh.id]
  monitoring    = true

  tags = {
    Name = "${var.project_environment} worker ${count.index+1}"
    Environment = var.project_environment
  }
}

# Associate an elastic IP with each worker server
resource aws_eip "worker" {
  count   = var.worker_instance_count
  instance = aws_instance.worker[count.index].id
}

resource "aws_eip_association" "worker_eip_assoc" {
  count = var.worker_instance_count
  instance_id   = aws_instance.worker[count.index].id
  allocation_id = aws_eip.worker[count.index].id
}