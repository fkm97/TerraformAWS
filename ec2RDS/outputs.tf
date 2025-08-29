output "web_url"       { value = "http://${aws_instance.web.public_ip}/" }
output "ec2_public_ip" { value = aws_instance.web.public_ip }
output "rds_endpoint"  { value = aws_db_instance.postgres.address }
output "vpc_id"        { value = aws_vpc.vpc.id }
