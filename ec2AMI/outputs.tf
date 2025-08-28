output "env"               { value = var.env }
output "ami_version"       { value = var.ami_version }
output "snapshot_ami_id"   { value = aws_ami_from_instance.snapshot.id }
output "snapshot_ami_name" { value = aws_ami_from_instance.snapshot.name }

output "source_instance_id"   { value = aws_instance.source.id }
output "source_public_ip"     { value = aws_instance.source.public_ip }
output "clone_instance_id"    { value = aws_instance.clone.id }
output "clone_public_ip"      { value = aws_instance.clone.public_ip }
