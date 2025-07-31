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

# Server A (Java Spring Boot client) outputs
output "server_a_instance_id" {
  description = "ID of Server A (Java Spring Boot client) EC2 instance"
  value       = aws_instance.server_a.id
}

output "server_a_public_ip" {
  description = "Public IP of Server A (Java Spring Boot client)"
  value       = aws_instance.server_a.public_ip
}

output "server_a_ssh_command" {
  description = "SSH command to connect to Server A (Java Spring Boot client)"
  value       = "ssh -i /path/to/${var.key_name}.pem ec2-user@${aws_instance.server_a.public_ip}"
}

output "server_a_setup_instructions" {
  description = "Instructions for using Server A"
  value       = <<-EOT
    Server A (Java Spring Boot Client) Setup Instructions:
    
    1. Connect to Server A:
       ssh -i /path/to/${var.key_name}.pem ec2-user@${aws_instance.server_a.public_ip}
    
    2. Test connectivity to Server B:
       ./test-server-b-connection.sh
    
    3. Clone your Spring Boot repository:
       git clone <your-github-repo-url>
       cd <your-repo-directory>
    
    4. Copy the .sdkmanrc file to your project directory:
       cp ~/.sdkmanrc <your-repo-directory>/
    
    5. Build and run your Spring Boot application:
       source ~/.sdkman/bin/sdkman-init.sh
       ./gradlew build
       ./gradlew bootRun
    
    Server A is configured with:
    - Git (for cloning repositories)
    - SDKMAN (Java and Gradle version management)
    - Java 17 (Amazon Corretto)
    - Gradle (latest version)
    
    Server B API endpoint: https://${aws_eip.instance_eip.public_ip}/api/kunal/helloworld
    
    Note: Server B uses a self-signed SSL certificate. Configure your Spring Boot 
    application accordingly or use curl with -k flag for testing.
  EOT
}

output "infrastructure_summary" {
  description = "Summary of the complete infrastructure"
  value       = <<-EOT
    Infrastructure Summary:
    
    Server B (API Server with Nginx):
    - Instance ID: ${aws_instance.api_server.id}
    - Elastic IP: ${aws_eip.instance_eip.public_ip}
    - SSH: ssh -i /path/to/${var.key_name}.pem ec2-user@${aws_eip.instance_eip.public_ip}
    - API Endpoint: https://${aws_eip.instance_eip.public_ip}/api/kunal/helloworld
    
    Server A (Java Spring Boot Client):
    - Instance ID: ${aws_instance.server_a.id}
    - Public IP: ${aws_instance.server_a.public_ip}
    - SSH: ssh -i /path/to/${var.key_name}.pem ec2-user@${aws_instance.server_a.public_ip}
    
    Both servers are in the same subnet (${aws_subnet.public.cidr_block}) and can communicate with each other.
    Both servers use the same SSH key pair: ${var.key_name}
  EOT
}

# ==============================================================================
# AUTO SHUTDOWN/STARTUP OUTPUTS
# ==============================================================================

output "auto_shutdown_startup_summary" {
  description = "Summary of the auto shutdown/startup configuration"
  value       = <<-EOT
    Auto Shutdown/Startup Configuration:
    
    📅 Schedule (Sydney Australia Timezone):
    - STOP instances: Every day at 12:00 AM (midnight) Sydney time
    - START instances: Every day at 12:00 PM (noon) Sydney time
    
    ⏰ Schedule Period: July 31, 2025 - August 31, 2025 (1 month)
    
    🖥️  Managed Instances:
    - Server B (API Server): ${aws_instance.api_server.id}
    - Server A (Java Client): ${aws_instance.server_a.id}
    
    🔧 AWS Resources Created:
    - Lambda Functions: ${aws_lambda_function.stop_ec2_instances.function_name}, ${aws_lambda_function.start_ec2_instances.function_name}
    - EventBridge Rules: ${aws_cloudwatch_event_rule.stop_ec2_schedule.name}, ${aws_cloudwatch_event_rule.start_ec2_schedule.name}
    - IAM Role: ${aws_iam_role.ec2_scheduler_lambda_role.name}
    
    ⚠️  Important Notes:
    - Scheduling automatically stops after August 31, 2025
    - Functions check the end date before executing any actions
    - All times are converted to UTC for EventBridge (AEST = UTC+10)
  EOT
}

output "lambda_function_names" {
  description = "Names of the Lambda functions for EC2 scheduling"
  value = {
    stop_function  = aws_lambda_function.stop_ec2_instances.function_name
    start_function = aws_lambda_function.start_ec2_instances.function_name
  }
}

output "eventbridge_schedules" {
  description = "EventBridge schedule expressions and details"
  value = {
    stop_schedule = {
      name        = aws_cloudwatch_event_rule.stop_ec2_schedule.name
      expression  = aws_cloudwatch_event_rule.stop_ec2_schedule.schedule_expression
      description = "Stop instances at 12:00 AM Sydney time (14:00 UTC)"
    }
    start_schedule = {
      name        = aws_cloudwatch_event_rule.start_ec2_schedule.name
      expression  = aws_cloudwatch_event_rule.start_ec2_schedule.schedule_expression
      description = "Start instances at 12:00 PM Sydney time (02:00 UTC)"
    }
  }
}

output "monitoring_instructions" {
  description = "Instructions for monitoring and managing the auto shutdown/startup system"
  value       = <<-EOT
    Monitoring and Management Instructions:
    
    🔍 Monitor Lambda Function Execution:
    1. Go to AWS Lambda Console
    2. Check functions: ${aws_lambda_function.stop_ec2_instances.function_name} and ${aws_lambda_function.start_ec2_instances.function_name}
    3. View CloudWatch Logs for execution details
    
    📊 Monitor EventBridge Rules:
    1. Go to Amazon EventBridge Console
    2. Check rules: ${aws_cloudwatch_event_rule.stop_ec2_schedule.name} and ${aws_cloudwatch_event_rule.start_ec2_schedule.name}
    3. View rule metrics and execution history
    
    🛠️  Manual Testing:
    # Test stop function
    aws lambda invoke --function-name ${aws_lambda_function.stop_ec2_instances.function_name} --payload '{}' response.json
    
    # Test start function  
    aws lambda invoke --function-name ${aws_lambda_function.start_ec2_instances.function_name} --payload '{}' response.json
    
    ⚙️  Disable Scheduling (if needed):
    # Disable stop schedule
    aws events disable-rule --name ${aws_cloudwatch_event_rule.stop_ec2_schedule.name}
    
    # Disable start schedule
    aws events disable-rule --name ${aws_cloudwatch_event_rule.start_ec2_schedule.name}
    
    # Re-enable schedules
    aws events enable-rule --name ${aws_cloudwatch_event_rule.stop_ec2_schedule.name}
    aws events enable-rule --name ${aws_cloudwatch_event_rule.start_ec2_schedule.name}
    
    📝 CloudWatch Logs:
    - Log Group: /aws/lambda/${aws_lambda_function.stop_ec2_instances.function_name}
    - Log Group: /aws/lambda/${aws_lambda_function.start_ec2_instances.function_name}
  EOT
}