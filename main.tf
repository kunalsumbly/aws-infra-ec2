# Get the latest Amazon Linux 2 AMI if not specified
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2.id
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "instance_sg" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH, HTTP, and HTTPS traffic"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # Outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# EC2 Instance
resource "aws_instance" "api_server" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    set -e  # Exit on any error

    # Log all output to a file for debugging
    exec > /var/log/user-data.log 2>&1

    echo "Starting user data script execution..."

    # Update system packages
    yum update -y

    # Install required packages
    yum install -y python3 python3-pip openssl

    # Install nginx
    amazon-linux-extras install nginx1 -y

    # Create directory for the API
    mkdir -p /opt/kunal-api

    # Create Python API script
    cat > /opt/kunal-api/app.py << 'PYEOF'
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route('/api/kunal/helloworld')
def hello_world():
    return "hello world kunal"

@app.route('/mcssapi-501/rp-webapp-9-common/billing/dashboard/billing-accounts', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH'])
def billing_accounts():
    # Accept all headers and request data
    headers = dict(request.headers)
    request_data = None
    
    # Try to get request data in various formats
    try:
        if request.is_json:
            request_data = request.get_json()
        elif request.form:
            request_data = dict(request.form)
        elif request.data:
            request_data = request.data.decode('utf-8')
    except:
        pass
    
    # Log the received data (optional)
    print(f"Received headers: {headers}")
    print(f"Received data: {request_data}")
    
    # Always return the same JSON response regardless of input
    return jsonify({
        "ImplRetrieveBillingAccountsOutput": {
            "transactionId": "049273e6-021c-4104-95ca-93188475a123",
            "migratingAccount": False,
            "billingAccountDetails": [],
            "contactType": None
        }
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=${var.api_port})
PYEOF

    # Install Flask
    pip3 install flask

    # Create systemd service for the API
    cat > /etc/systemd/system/kunal-api.service << 'SVCEOF'
[Unit]
Description=Kunal API Service
After=network.target

[Service]
User=root
WorkingDirectory=/opt/kunal-api
ExecStart=/usr/bin/python3 /opt/kunal-api/app.py
Restart=always

[Install]
WantedBy=multi-user.target
SVCEOF

    # Enable and start the API service
    systemctl enable kunal-api
    systemctl start kunal-api

    # Wait for API service to be ready
    sleep 5

    echo "Skipping SSL certificate generation - HTTP only configuration"

    # Create nginx configuration
    cat > /etc/nginx/conf.d/api-proxy.conf << 'NGINXEOF'
# API backend definition with health check
upstream api_backend {
    server localhost:${var.api_port} max_fails=3 fail_timeout=30s;
}

# HTTP server - handle all requests directly
server {
    listen 80;
    server_name _;

    # Error logging
    error_log /var/log/nginx/error.log warn;
    access_log /var/log/nginx/access.log;

    # Custom error pages
    error_page 500 502 503 504 /50x.html;

    # Static error page
    location = /50x.html {
        root /usr/share/nginx/html;
        internal;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "OK - HTTP";
        add_header Content-Type text/plain;
    }

    location /api/kunal/helloworld {
        # Use the upstream with health check
        proxy_pass http://api_backend/api/kunal/helloworld;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Proxy buffer settings
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;

        # Proxy timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Error handling
        proxy_intercept_errors on;
        proxy_next_upstream error timeout http_500 http_502 http_503 http_504;

        # For SYN blackhole testing - return a 503 error when the API is unavailable
        error_page 502 503 504 =503 /api_unavailable.html;
    }

    location /mcssapi-501/rp-webapp-9-common/billing/dashboard/billing-accounts {
        # Use the upstream with health check
        proxy_pass http://api_backend/mcssapi-501/rp-webapp-9-common/billing/dashboard/billing-accounts;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Proxy buffer settings
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;

        # Proxy timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Error handling
        proxy_intercept_errors on;
        proxy_next_upstream error timeout http_500 http_502 http_503 http_504;

        # For SYN blackhole testing - return a 503 error when the API is unavailable
        error_page 502 503 504 =503 /api_unavailable.html;
    }

    # Custom error page for API unavailability
    location = /api_unavailable.html {
        internal;
        return 503 '{"error": "API service unavailable", "message": "The API service is currently unavailable. Please try again later."}';
        add_header Content-Type application/json;
    }
}
NGINXEOF

    # Test nginx configuration before starting
    echo "Testing nginx configuration..."
    nginx -t

    if [[ $? -eq 0 ]]; then
        echo "Nginx configuration is valid"
        # Enable and start nginx
        systemctl enable nginx
        systemctl start nginx

        # Check if nginx started successfully
        if systemctl is-active --quiet nginx; then
            echo "Nginx started successfully"
        else
            echo "ERROR: Nginx failed to start"
            systemctl status nginx
            exit 1
        fi
    else
        echo "ERROR: Nginx configuration test failed"
        nginx -t
        exit 1
    fi

    echo "User data script completed successfully"

    # Final status check
    echo "=== Service Status ==="
    systemctl status kunal-api --no-pager
    systemctl status nginx --no-pager

    echo "=== SSL Certificate Info ==="
    openssl x509 -in /etc/nginx/ssl/nginx.crt -text -noout | head -20
  EOF

  tags = {
    Name = "${var.project_name}-ec2"
  }

  # Wait for instance to be available
  depends_on = [aws_internet_gateway.igw]
}


# Security Group for Server A (Java Spring Boot client)
resource "aws_security_group" "server_a_sg" {
  name        = "${var.project_name}-server-a-sg"
  description = "Allow SSH access and outbound traffic for Server A"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  # Allow outbound traffic to communicate with Server B and internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-server-a-sg"
  }
}

# EC2 Instance - Server A (Java Spring Boot client)
resource "aws_instance" "server_a" {
  ami                    = local.ami_id
  instance_type          = "t3.small"  # Upgraded from micro to small
  key_name               = var.key_name  # Same key as server B
  subnet_id              = aws_subnet.public.id  # Same subnet as server B
  vpc_security_group_ids = [aws_security_group.server_a_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    set -e  # Exit on any error

    # Log all output to a file for debugging
    exec > /var/log/user-data-server-a.log 2>&1

    echo "Starting Server A user data script execution..."

    # Update system packages
    yum update -y

    # Install git
    yum install -y git

    # Install curl and zip (required for sdkman)
    yum install -y curl zip unzip

    # Install Docker
    yum install -y docker
    
    # Enable and start Docker service
    systemctl enable docker
    systemctl start docker
    
    # Add ec2-user to docker group so they can run docker commands without sudo
    usermod -a -G docker ec2-user
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Create ec2-user home directory if it doesn't exist
    mkdir -p /home/ec2-user
    chown ec2-user:ec2-user /home/ec2-user

    # Install SDKMAN as ec2-user
    sudo -u ec2-user bash -c '
      # Download and install SDKMAN
      curl -s "https://get.sdkman.io" | bash
      
      # Source SDKMAN
      source "/home/ec2-user/.sdkman/bin/sdkman-init.sh"
      
      # Install Java 17 (Amazon Corretto)
      sdk install java 17.0.12-amzn
      
      # Install Gradle
      sdk install gradle
      
      # Set Java 17 as default
      sdk default java 17.0.12-amzn
      
      # Create .sdkmanrc file for the project
      cat > /home/ec2-user/.sdkmanrc << "SDKEOF"
# Enable auto-env through the sdkman_auto_env config
# Add these lines to your project root directory
java=17.0.12-amzn
gradle=current
SDKEOF
      
      # Verify installations
      echo "=== Java Version ==="
      java -version
      
      echo "=== Gradle Version ==="
      gradle --version
      
      echo "=== Git Version ==="
      git --version
      
      echo "=== SDKMAN Version ==="
      sdk version
    '

    # Verify Docker and Docker Compose installations
    echo "=== Docker Version ==="
    docker --version
    
    echo "=== Docker Compose Version ==="
    docker-compose --version
    
    echo "=== Docker Service Status ==="
    systemctl status docker --no-pager

    # Set proper ownership for ec2-user home directory
    chown -R ec2-user:ec2-user /home/ec2-user

    # Create a simple test script to verify Server B connectivity
    cat > /home/ec2-user/test-server-b-connection.sh << 'TESTEOF'
#!/bin/bash
echo "Testing connection to Server B..."
SERVER_B_IP="${aws_instance.api_server.public_ip}"

echo "Testing HTTP connection (should redirect to HTTPS):"
curl -v -L "http://$SERVER_B_IP/api/kunal/helloworld" || echo "HTTP test completed"

echo ""
echo "Testing HTTPS connection (with self-signed certificate):"
curl -v -k "https://$SERVER_B_IP/api/kunal/helloworld" || echo "HTTPS test completed"

echo ""
echo "Server B IP: $SERVER_B_IP"
echo "You can now clone your Spring Boot repository and configure it to call the API at:"
echo "https://$SERVER_B_IP/api/kunal/helloworld"
TESTEOF

    chmod +x /home/ec2-user/test-server-b-connection.sh
    chown ec2-user:ec2-user /home/ec2-user/test-server-b-connection.sh

    # Create a welcome message for the user
    cat > /home/ec2-user/README-SERVER-A.md << 'READMEEOF'
# Server A - Java Spring Boot Client

This server is configured with:
- Git (for cloning repositories)
- SDKMAN (Java and Gradle version management)
- Java 17 (Amazon Corretto)
- Gradle (latest version)
- Docker (container runtime)
- Docker Compose v2.21.0 (container orchestration)

## Getting Started

1. **Test connection to Server B:**
   ```bash
   ./test-server-b-connection.sh
   ```

2. **Clone your Spring Boot repository:**
   ```bash
   git clone <your-github-repo-url>
   cd <your-repo-directory>
   ```

3. **Use SDKMAN to manage Java/Gradle versions:**
   ```bash
   # Check current versions
   sdk current
   
   # List available Java versions
   sdk list java
   
   # Install a different version if needed
   sdk install java <version>
   ```

4. **Build and run your Spring Boot application:**
   ```bash
   # If using Gradle wrapper
   ./gradlew build
   ./gradlew bootRun
   
   # Or using system Gradle
   gradle build
   gradle bootRun
   ```

5. **Use Docker and Docker Compose:**
   ```bash
   # Check Docker installation
   docker --version
   docker-compose --version
   
   # Test Docker with hello-world
   docker run hello-world
   
   # Build and run a containerized Spring Boot app (example)
   # Create a Dockerfile in your project directory first
   docker build -t my-spring-app .
   docker run -p 8080:8080 my-spring-app
   
   # Use Docker Compose for multi-container applications
   # Create a docker-compose.yml file first
   docker-compose up -d
   docker-compose down
   
   # View running containers
   docker ps
   
   # View Docker logs
   docker logs <container-id>
   ```

## Server B API Endpoint
- HTTP: http://SERVER_B_IP/api/kunal/helloworld (redirects to HTTPS)
- HTTPS: https://SERVER_B_IP/api/kunal/helloworld

Note: Server B uses a self-signed SSL certificate, so you may need to configure your Spring Boot application to accept it or use the `-k` flag with curl for testing.

## SDKMAN Configuration
A `.sdkmanrc` file has been created in your home directory with the default Java and Gradle versions. You can copy this to your project directory for consistent environment setup.
READMEEOF

    chown ec2-user:ec2-user /home/ec2-user/README-SERVER-A.md

    echo "Server A user data script completed successfully"

    # Final status check
    echo "=== Final Setup Summary ==="
    echo "Git installed: $(which git)"
    echo "Docker installed: $(which docker)"
    echo "Docker Compose installed: $(which docker-compose)"
    echo "Docker service status: $(systemctl is-active docker)"
    echo "SDKMAN installed: $(ls -la /home/ec2-user/.sdkman/bin/sdkman-init.sh)"
    echo "Java version: $(sudo -u ec2-user bash -c 'source /home/ec2-user/.sdkman/bin/sdkman-init.sh && java -version')"
    echo "Gradle version: $(sudo -u ec2-user bash -c 'source /home/ec2-user/.sdkman/bin/sdkman-init.sh && gradle --version | head -3')"
  EOF

  tags = {
    Name = "${var.project_name}-server-a"
  }

  # Wait for instance to be available
  depends_on = [aws_internet_gateway.igw]
}

# ==============================================================================
# AUTO SHUTDOWN/STARTUP FUNCTIONALITY FOR EC2 INSTANCES
# ==============================================================================

# IAM Role for Lambda functions to manage EC2 instances
resource "aws_iam_role" "ec2_scheduler_lambda_role" {
  name = "${var.project_name}-ec2-scheduler-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-scheduler-lambda-role"
  }
}

# IAM Policy for Lambda to manage EC2 instances
resource "aws_iam_policy" "ec2_scheduler_policy" {
  name        = "${var.project_name}-ec2-scheduler-policy"
  description = "Policy for Lambda to start/stop EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-scheduler-policy"
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "ec2_scheduler_policy_attachment" {
  role       = aws_iam_role.ec2_scheduler_lambda_role.name
  policy_arn = aws_iam_policy.ec2_scheduler_policy.arn
}

# Lambda function to stop EC2 instances
resource "aws_lambda_function" "stop_ec2_instances" {
  filename         = "stop_ec2_instances.zip"
  function_name    = "${var.project_name}-stop-ec2-instances"
  role            = aws_iam_role.ec2_scheduler_lambda_role.arn
  handler         = "stop_ec2_instances.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      INSTANCE_IDS = "${aws_instance.api_server.id},${aws_instance.server_a.id}"
      END_DATE     = "2025-08-31"  # 1 month from July 31, 2025
    }
  }

  tags = {
    Name = "${var.project_name}-stop-ec2-instances"
  }

  depends_on = [aws_iam_role_policy_attachment.ec2_scheduler_policy_attachment]
}

# Lambda function to start EC2 instances
resource "aws_lambda_function" "start_ec2_instances" {
  filename         = "start_ec2_instances.zip"
  function_name    = "${var.project_name}-start-ec2-instances"
  role            = aws_iam_role.ec2_scheduler_lambda_role.arn
  handler         = "start_ec2_instances.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      INSTANCE_IDS = "${aws_instance.api_server.id},${aws_instance.server_a.id}"
      END_DATE     = "2025-08-31"  # 1 month from July 31, 2025
    }
  }

  tags = {
    Name = "${var.project_name}-start-ec2-instances"
  }

  depends_on = [aws_iam_role_policy_attachment.ec2_scheduler_policy_attachment]
}

# EventBridge rule to stop instances at midnight Sydney time (14:00 UTC)
resource "aws_cloudwatch_event_rule" "stop_ec2_schedule" {
  name                = "${var.project_name}-stop-ec2-schedule"
  description         = "Stop EC2 instances at midnight Sydney time"
  schedule_expression = "cron(0 14 * * ? *)"  # 14:00 UTC = 00:00 AEST (Sydney)

  tags = {
    Name = "${var.project_name}-stop-ec2-schedule"
  }
}

# EventBridge rule to start instances at noon Sydney time (02:00 UTC)
resource "aws_cloudwatch_event_rule" "start_ec2_schedule" {
  name                = "${var.project_name}-start-ec2-schedule"
  description         = "Start EC2 instances at noon Sydney time"
  schedule_expression = "cron(0 2 * * ? *)"   # 02:00 UTC = 12:00 AEST (Sydney)

  tags = {
    Name = "${var.project_name}-start-ec2-schedule"
  }
}

# EventBridge target for stop schedule
resource "aws_cloudwatch_event_target" "stop_ec2_target" {
  rule      = aws_cloudwatch_event_rule.stop_ec2_schedule.name
  target_id = "StopEC2InstancesTarget"
  arn       = aws_lambda_function.stop_ec2_instances.arn
}

# EventBridge target for start schedule
resource "aws_cloudwatch_event_target" "start_ec2_target" {
  rule      = aws_cloudwatch_event_rule.start_ec2_schedule.name
  target_id = "StartEC2InstancesTarget"
  arn       = aws_lambda_function.start_ec2_instances.arn
}

# Lambda permission for EventBridge to invoke stop function
resource "aws_lambda_permission" "allow_eventbridge_stop" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_ec2_instances.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_ec2_schedule.arn
}

# Lambda permission for EventBridge to invoke start function
resource "aws_lambda_permission" "allow_eventbridge_start" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_ec2_instances.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_ec2_schedule.arn
}