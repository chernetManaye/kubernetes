provider "aws" {
  region = var.aws_region
}

resource "aws_instance" "control_plane" {
  ami           = data.aws_ami.ubuntu_ami
  instance_type = "t3.medium"
  key_name      = data.aws_key_pair.key_pair.key_name

  user_data = file("../scripts/master.sh")

  tags = {
    Name = "k8s-control-plane"
  }
}

resource "aws_instance" "worker_1" {
  ami           = data.aws_ami.ubuntu_ami
  instance_type = "t3.medium"
  key_name      = data.aws_key_pair.key_pair.key_name

  user_data = file("../scripts/worker.sh")

  tags = {
    Name = "k8s-worker-1"
  }
}
