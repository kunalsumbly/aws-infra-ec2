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
from flask import Flask

app = Flask(__name__)

@app.route('/api/kunal/helloworld')
def hello_world():
    return "hello world kunal"

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

    # Create directory structure for SSL certificates
    mkdir -p /etc/pki/nginx/private

    echo "Generating SSL certificates..."

    # Generate the private key
    openssl genrsa -out /etc/pki/nginx/private/server.key 2048

    # Generate the self-signed certificate
    openssl req -new -x509 -key /etc/pki/nginx/private/server.key -out /etc/pki/nginx/server.crt -days 365 -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

    # Set proper permissions
    chmod 600 /etc/pki/nginx/private/server.key
    chmod 644 /etc/pki/nginx/server.crt

    # Verify files exist and have content
    if [[ -f /etc/pki/nginx/server.crt ]] && [[ -s /etc/pki/nginx/server.crt ]]; then
        echo "SSL certificate created successfully"
        ls -la /etc/pki/nginx/
        ls -la /etc/pki/nginx/private/
    else
        echo "ERROR: SSL certificate file is missing or empty!"
        exit 1
    fi

    # Create nginx configuration
    cat > /etc/nginx/nginx.conf << 'NGINXEOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # HTTP Server Block (Port 80)
    server {
        listen       80;
        listen       [::]:80;
        server_name  _;
        
        location / {
            proxy_pass http://127.0.0.1:${var.api_port};
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
    }

    # HTTPS Server Block (Port 443)
    server {
        listen       443 ssl;
        listen       [::]:443 ssl;
        http2        on;
        server_name  _;

        ssl_certificate "/etc/pki/nginx/server.crt";
        ssl_certificate_key "/etc/pki/nginx/private/server.key";
        ssl_session_cache shared:SSL:1m;
        ssl_session_timeout  10m;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        location / {
            proxy_pass http://127.0.0.1:${var.api_port};
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
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

# Elastic IP
resource "aws_eip" "instance_eip" {
  domain = "vpc"
  tags = {
    Name = "${var.project_name}-eip"
  }
}

# EIP Association
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.api_server.id
  allocation_id = aws_eip.instance_eip.id
}