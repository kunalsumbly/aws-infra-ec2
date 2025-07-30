output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.api_server.id
}

output "elastic_ip" {
  description = "Elastic IP assigned to the EC2 instance"
  value       = aws_eip.instance_eip.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = "ssh -i /path/to/${var.key_name}.pem ec2-user@${aws_eip.instance_eip.public_ip}"
}

output "api_url_http" {
  description = "HTTP URL to access the API endpoint (redirects to HTTPS)"
  value       = "http://${aws_eip.instance_eip.public_ip}/api/kunal/helloworld"
}

output "api_url_https" {
  description = "HTTPS URL to access the API endpoint with SSL"
  value       = "https://${aws_eip.instance_eip.public_ip}/api/kunal/helloworld"
}

output "syn_blackhole_test_instructions" {
  description = "Instructions to test the SYN blackhole scenario"
  value       = <<-EOT
    To test the SYN blackhole scenario:
    
    1. Connect to the EC2 instance:
       ssh -i /path/to/${var.key_name}.pem ec2-user@${aws_eip.instance_eip.public_ip}
    
    2. Stop the Python API service:
       sudo systemctl stop kunal-api
    
    3. From your local machine, run a Java client with connection and read timeouts set.
       Use the provided Java example that supports HTTPS with self-signed certificates.
       The connection should hang for 3-4 minutes due to the SYN blackhole scenario.
    
    4. To restore normal operation:
       sudo systemctl start kunal-api
    
    Note: When testing with HTTPS, the SSL handshake will complete successfully because
    Nginx is still running, but the connection to the API will hang in the SYN blackhole
    scenario when the Python API service is stopped.
  EOT
}