output "control_plane_ip" {
  value = aws_instance.control_plane.public_ip
}

output "worker_ip" {
  value = aws_instance.worker_1.public_ip
}
