# AWS Region to deploy resources
aws_region = "ap-southeast-2"

# CIDR block for the VPC
vpc_cidr = "10.0.0.0/16"

# CIDR block for the public subnet
public_subnet_cidr = "10.0.1.0/24"

# EC2 instance type
instance_type = "t3.micro"

# Name of the existing SSH key pair to use for the EC2 instance
# This is required - replace with your actual key name
key_name = "aws-elasticache-key"

# AMI ID for the EC2 instance (Amazon Linux 2)
# Leave empty to use the latest Amazon Linux 2 AMI automatically
ami_id = ""

# Name of the project for tagging resources
project_name = "kunal-api-demo"

# Port on which the Python API will run
api_port = 5000