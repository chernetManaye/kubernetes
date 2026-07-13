output "control_plane_ssh_command" {
  value = "ssh -i ~/.ssh/${data.aws_key_pair.key_pair.key_name}.pem ubuntu@${aws_instance.control_plane.public_ip}"
}

# control_plane_ssh_command = "ssh -i ~/.ssh/dev-key-pair.pem ubuntu@54.123.45.67"

# output "worker_ssh_commands" {
#   value = {
#     for idx, worker in aws_instance.worker_node :
#     "worker-${idx + 1}" => "ssh -i ~/.ssh/${data.aws_key_pair.key_pair.key_name}.pem ubuntu@${worker.public_ip}"
#   }
# }

# worker_ssh_commands = {
#   worker-1 = "ssh -i ~/.ssh/dev-key-pair.pem ubuntu@3.85.10.20"
#   worker-2 = "ssh -i ~/.ssh/dev-key-pair.pem ubuntu@44.201.15.31"
#   worker-3 = "ssh -i ~/.ssh/dev-key-pair.pem ubuntu@18.233.99.12"
# }
