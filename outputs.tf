output "public_ip" {
  value = aws_eip.eip.public_ip #this should be the public ip of the jump host , the aws instance
}

output "url" {
  value = "https://${var.tfe_hostname}"
}

data "aws_instances" "bastion" {
  instance_tags = {
    "Name" = "${var.prefix}-tfe-asg"
  }
  instance_state_names = ["running"]
}

output "ssh_bastion" {
    value = "ssh ec2-user@${aws_eip.eip.public_ip}"
}

output "ssh_connect" {
  value = [
    for k in data.aws_instances.bastion.private_ips : "ssh -J ec2-user@${var.tfe_hostname} ec2-user@${k}"
  ]
}