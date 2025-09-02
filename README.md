# AWS EC2 Infrastructure with Nginx and Python API

This Terraform configuration creates an EC2 instance in AWS with Nginx and a Python API. The setup is designed to demonstrate a SYN blackhole scenario.

## Features

- Creates a custom VPC with a public subnet
- Launches a t3.micro EC2 instance with an Elastic IP
- Installs and configures Nginx as a reverse proxy with HTTPS support
- Uses a self-signed SSL certificate with proper IP address configuration for secure communication
- Implements SSL termination at the Nginx level with optimized SSL settings
- Includes robust error handling and health checks for API availability
- Deploys a simple Python Flask API that returns "hello world kunal"
- Allows stopping the Python API without affecting Nginx (for SYN blackhole testing)
- Provides graceful error responses when the API is unavailable

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) (v1.2.0 or newer)
- AWS CLI configured with appropriate credentials
- An existing SSH key pair in AWS

## Usage

1. Clone this repository:
   ```
   git clone <repository-url>
   cd aws-infra-ec2
   ```

2. Initialize Terraform:
   ```
   terraform init
   ```

3. Use the provided `params.tfvars` file to set your variables:
   ```hcl
   # Copy the params.tfvars file to terraform.tfvars
   cp params.tfvars terraform.tfvars
   
   # Edit terraform.tfvars to set your specific values
   # At minimum, you must set your SSH key name:
   key_name = "your-actual-key-name"  # Name of your existing SSH key pair in AWS
   ```
   
   Alternatively, you can directly reference the params.tfvars file:
   ```
   terraform plan -var-file=params.tfvars
   terraform apply -var-file=params.tfvars
   ```

4. Review the plan:
   ```
   terraform plan
   ```

5. Apply the configuration:
   ```
   terraform apply
   ```

6. After the deployment completes, Terraform will output:
   - The Elastic IP address of the EC2 instance
   - SSH command to connect to the instance
   - HTTP and HTTPS URLs to access the API endpoint
   - Instructions for testing the SYN blackhole scenario
   
   Note: When accessing the HTTPS endpoint, your browser will show a security warning because the site uses a self-signed certificate. You can proceed by accepting the risk or adding an exception for this certificate.

## Testing the SYN Blackhole Scenario

1. Connect to the EC2 instance using the SSH command from the Terraform output.
2. Stop the Python API service:
   ```
   sudo systemctl stop kunal-api
   ```
3. From your local machine, run a Java client with connection and read timeouts set.
   The connection should hang for 3-4 minutes due to the SYN blackhole scenario.
4. To restore normal operation:
   ```
   sudo systemctl start kunal-api
   ```

## Java Client Example for Testing

Here's a simple Java client using Apache HttpClient 5 that you can use to test the SYN blackhole scenario:

```java
import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.config.RequestConfig;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.client5.http.ssl.NoopHostnameVerifier;
import org.apache.hc.client5.http.ssl.SSLConnectionSocketFactory;
import org.apache.hc.client5.http.ssl.TrustAllStrategy;
import org.apache.hc.core5.ssl.SSLContextBuilder;
import org.apache.hc.core5.util.Timeout;

import javax.net.ssl.SSLContext;
import java.io.IOException;
import java.security.KeyManagementException;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.util.concurrent.TimeUnit;

public class SynBlackholeTest {
    public static void main(String[] args) {
        try {
            // Replace with your EC2 instance's Elastic IP
            String apiUrl = "https://your-elastic-ip/api/kunal/helloworld";
            
            // Set connection timeout and read timeout
            RequestConfig requestConfig = RequestConfig.custom()
                    .setConnectTimeout(Timeout.of(10, TimeUnit.SECONDS))
                    .setResponseTimeout(Timeout.of(10, TimeUnit.SECONDS))
                    .build();
            
            // Create SSL context that trusts all certificates (for self-signed cert)
            SSLContext sslContext = new SSLContextBuilder()
                    .loadTrustMaterial(null, TrustAllStrategy.INSTANCE)
                    .build();
            
            // Create SSL connection factory with the custom SSL context
            SSLConnectionSocketFactory sslFactory = new SSLConnectionSocketFactory(
                    sslContext, NoopHostnameVerifier.INSTANCE);
            
            // Create connection manager with the SSL factory
            var connectionManager = PoolingHttpClientConnectionManagerBuilder.create()
                    .setSSLSocketFactory(sslFactory)
                    .build();
            
            // Create HTTP client with SSL support for self-signed certificates
            try (CloseableHttpClient httpClient = HttpClients.custom()
                    .setConnectionManager(connectionManager)
                    .setDefaultRequestConfig(requestConfig)
                    .build()) {
                
                HttpGet request = new HttpGet(apiUrl);
                System.out.println("Executing request: " + request);
                
                long startTime = System.currentTimeMillis();
                try {
                    // This will hang in a SYN blackhole scenario
                    httpClient.execute(request);
                    System.out.println("Request completed successfully");
                } catch (IOException e) {
                    long endTime = System.currentTimeMillis();
                    System.out.println("Exception: " + e.getMessage());
                    System.out.println("Time elapsed: " + (endTime - startTime) / 1000 + " seconds");
                }
            }
        } catch (IOException | NoSuchAlgorithmException | KeyStoreException | KeyManagementException e) {
            e.printStackTrace();
        }
    }
}
```

## Troubleshooting

### SSL Connection Issues

If you encounter SSL connection issues such as `SSL_ERROR_SYSCALL` when connecting to the HTTPS endpoint, the following improvements have been implemented to address these issues:

1. **Proper Certificate Configuration**
   - The self-signed certificate now uses the instance's public IP address in both the CN and SAN fields
   - This ensures the certificate is valid for external access via IP address

2. **Optimized SSL Settings**
   - More permissive SSL protocol configuration (TLSv1, TLSv1.1, TLSv1.2, TLSv1.3)
   - Optimized cipher settings for better compatibility
   - Buffer size settings to handle larger SSL handshakes
   - Appropriate timeouts for SSL handshakes
   - Session caching for improved performance

3. **Enhanced Error Handling**
   - Detailed error logging for SSL-related issues
   - Custom error pages for different error scenarios
   - Health checks to detect API availability
   - Graceful error responses when the API is unavailable

If you still encounter SSL issues:
- Check the Nginx error logs on the EC2 instance: `sudo cat /var/log/nginx/ssl_error.log`
- Ensure your client supports the SSL protocols and ciphers configured
- Try accessing the health check endpoint: `https://<your-elastic-ip>/health`

## Cleanup

To destroy the infrastructure when you're done:

```
terraform destroy
```

## Auto Shutdown/Startup System

This infrastructure includes an automated EC2 instance scheduling system that automatically stops instances at midnight and starts them at noon Sydney time, running for exactly one month to optimize costs.

### How the Workflow Works

The auto shutdown/startup system operates through the following components:

1. **EventBridge Rules**: Two cron-based schedules trigger Lambda functions
   - **Stop Schedule**: `cron(0 14 * * ? *)` - Runs at 14:00 UTC (midnight Sydney time)
   - **Start Schedule**: `cron(0 2 * * ? *)` - Runs at 02:00 UTC (noon Sydney time)

2. **Lambda Functions**: Python-based functions that manage EC2 instances
   - **Stop Function**: Stops running instances and logs the operation
   - **Start Function**: Starts stopped instances and logs the operation

3. **IAM Permissions**: Secure role-based access for Lambda functions to manage EC2 instances

4. **End Date Protection**: Built-in logic prevents scheduling beyond August 31, 2025

### Architecture Overview

```
EventBridge Rules (Cron)
    ↓
Lambda Functions (Python 3.9)
    ↓
EC2 API Calls (Start/Stop)
    ↓
CloudWatch Logs (Monitoring)
```

**Managed Instances:**
- Server B (API Server): Nginx + Python Flask API
- Server A (Java Client): Development environment with SDKMAN, Java 17, Gradle

### Schedule Details

| Action | Sydney Time | UTC Time | Cron Expression | Description |
|--------|-------------|----------|-----------------|-------------|
| STOP   | 12:00 AM    | 14:00    | `cron(0 14 * * ? *)` | Stop instances at midnight |
| START  | 12:00 PM    | 02:00    | `cron(0 2 * * ? *)`  | Start instances at noon |

**Important Notes:**
- Schedule runs daily from July 31, 2025 to August 31, 2025
- Timezone conversion: Sydney (AEST) = UTC + 10 hours
- Functions automatically disable after the end date

### Monitoring and Diagnostics

#### Quick Status Check

```bash
# View scheduling configuration
terraform output auto_shutdown_startup_summary

# Check Lambda function names
terraform output lambda_function_names

# View EventBridge schedules
terraform output eventbridge_schedules
```

#### Manual Testing

```bash
# Test stop function
aws lambda invoke --function-name kunal-api-demo-stop-ec2-instances --payload '{}' response.json --no-verify-ssl
cat response.json

# Test start function
aws lambda invoke --function-name kunal-api-demo-start-ec2-instances --payload '{}' response.json --no-verify-ssl
cat response.json
```

#### CloudWatch Monitoring

1. **Lambda Function Logs:**
   - Log Group: `/aws/lambda/kunal-api-demo-stop-ec2-instances`
   - Log Group: `/aws/lambda/kunal-api-demo-start-ec2-instances`

2. **EventBridge Rule Metrics:**
   - Go to Amazon EventBridge Console
   - Check rules: `kunal-api-demo-stop-ec2-schedule` and `kunal-api-demo-start-ec2-schedule`
   - View execution history and metrics

### Troubleshooting Guide

#### Issue: Instances Not Stopping/Starting

**Symptoms:**
- Instances remain in the same state after scheduled time
- No CloudWatch logs for Lambda execution

**Diagnosis Steps:**

1. **Check EventBridge Rules:**
   ```bash
   aws events list-rules --name-prefix kunal-api-demo --no-verify-ssl
   aws events list-targets-by-rule --rule kunal-api-demo-stop-ec2-schedule --no-verify-ssl
   ```

2. **Verify Lambda Function Status:**
   ```bash
   aws lambda get-function --function-name kunal-api-demo-stop-ec2-instances --no-verify-ssl
   aws lambda get-function --function-name kunal-api-demo-start-ec2-instances --no-verify-ssl
   ```

3. **Check IAM Permissions:**
   ```bash
   aws iam get-role --role-name kunal-api-demo-ec2-scheduler-lambda-role --no-verify-ssl
   aws iam list-attached-role-policies --role-name kunal-api-demo-ec2-scheduler-lambda-role --no-verify-ssl
   ```

**Common Solutions:**
- Ensure EventBridge rules are enabled
- Verify Lambda functions have proper IAM permissions
- Check if current date is past the end date (2025-08-31)

#### Issue: Lambda Function Errors

**Symptoms:**
- CloudWatch logs show errors
- Lambda function returns 4xx or 5xx status codes

**Diagnosis Steps:**

1. **Check CloudWatch Logs:**
   ```bash
   aws logs describe-log-groups --log-group-name-prefix /aws/lambda/kunal-api-demo --no-verify-ssl
   aws logs get-log-events --log-group-name /aws/lambda/kunal-api-demo-stop-ec2-instances --log-stream-name [LATEST_STREAM] --no-verify-ssl
   ```

2. **Verify Instance IDs:**
   ```bash
   # Check if instances exist
   aws ec2 describe-instances --instance-ids i-00367948d6a779b55 i-00bc3e80e1efa9e25 --no-verify-ssl
   ```

3. **Test Manual Execution:**
   ```bash
   aws lambda invoke --function-name kunal-api-demo-stop-ec2-instances --payload '{}' response.json --no-verify-ssl
   cat response.json
   ```

**Common Error Codes:**
- `400`: Invalid instance IDs or end date format
- `500`: AWS API errors or permission issues
- `200`: Successful execution (check response body for details)

#### Issue: Wrong Timezone Execution

**Symptoms:**
- Functions execute at incorrect Sydney time
- Instances stop/start at unexpected hours

**Diagnosis Steps:**

1. **Verify Cron Expressions:**
   - Stop: `cron(0 14 * * ? *)` should execute at 14:00 UTC = 00:00 Sydney
   - Start: `cron(0 2 * * ? *)` should execute at 02:00 UTC = 12:00 Sydney

2. **Check EventBridge Rule Configuration:**
   ```bash
   aws events describe-rule --name kunal-api-demo-stop-ec2-schedule --no-verify-ssl
   aws events describe-rule --name kunal-api-demo-start-ec2-schedule --no-verify-ssl
   ```

**Note:** EventBridge uses UTC time. Sydney AEST = UTC + 10 hours.

#### Issue: End Date Reached

**Symptoms:**
- Functions execute but no instances are stopped/started
- Logs show "Scheduling period ended" message

**Diagnosis:**
- Check if current date > 2025-08-31
- Review Lambda function logs for end date messages

**Solution:**
- Update the `END_DATE` environment variable in Lambda functions if you need to extend the schedule
- Redeploy with `terraform apply` after updating the end date in `main.tf`

### Emergency Controls

#### Disable Scheduling Temporarily

```bash
# Disable stop schedule
aws events disable-rule --name kunal-api-demo-stop-ec2-schedule --no-verify-ssl

# Disable start schedule
aws events disable-rule --name kunal-api-demo-start-ec2-schedule --no-verify-ssl
```

#### Re-enable Scheduling

```bash
# Enable stop schedule
aws events enable-rule --name kunal-api-demo-stop-ec2-schedule --no-verify-ssl

# Enable start schedule
aws events enable-rule --name kunal-api-demo-start-ec2-schedule --no-verify-ssl
```

#### Manual Instance Control

```bash
# Manually stop instances
aws ec2 stop-instances --instance-ids i-00367948d6a779b55 i-00bc3e80e1efa9e25 --no-verify-ssl

# Manually start instances
aws ec2 start-instances --instance-ids i-00367948d6a779b55 i-00bc3e80e1efa9e25 --no-verify-ssl

# Check instance status
aws ec2 describe-instances --instance-ids i-00367948d6a779b55 i-00bc3e80e1efa9e25 --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name}' --no-verify-ssl
```

### Cost Optimization

The auto shutdown/startup system provides significant cost savings:
- **12 hours offline daily** = ~50% cost reduction
- **Automatic scheduling** = No manual intervention required
- **Built-in end date** = Prevents runaway costs

**Estimated Savings:**
- t3.micro: ~$4.50/month → ~$2.25/month
- t3.nano: ~$2.25/month → ~$1.13/month

## Files

- `main.tf` - Main infrastructure definitions
- `variables.tf` - Variable definitions
- `outputs.tf` - Output definitions
- `providers.tf` - Provider configuration
- `params.tfvars` - Example variable values for deployment
- `stop_ec2_instances.py` - Lambda function to stop EC2 instances
- `start_ec2_instances.py` - Lambda function to start EC2 instances
- `stop_ec2_instances.zip` - Packaged Lambda function for deployment
- `start_ec2_instances.zip` - Packaged Lambda function for deployment

# Download certificate from IP
openssl s_client -connect IP:PORT </dev/null 2>/dev/null | openssl x509 -outform PEM > server.crt

# Then use it with curl
curl --cacert server.crt https://IP:PORT/your-endpoint


Use a Fake Domain Name + /etc/hosts mapping
•  CN: test-server.fake or catalog-service.test
•  Advantage: Most reliable, works with any client
•  Setup: Add to /etc/hosts on client machines:
  <current-server-ip> test-server.fake

•  Usage: Always connect to https://test-server.fake:port

I am thinking to use option 1, will it work for both curl and java clients ?

Yes, **Option 1 (fake domain + /etc/hosts)** will work perfectly for both curl and Java clients! This is actually one of the most reliable approaches for testing.

## How it works:

### **For curl:**
- curl resolves the hostname using the system's `/etc/hosts` file
- When you connect to `https://test-server.fake`, curl looks up the IP in `/etc/hosts`
- The SSL certificate CN matches the hostname, so handshake succeeds

### **For Java clients:**
- Java applications also use the system's hostname resolution (via `/etc/hosts`)
- Java's SSL implementation validates the certificate CN against the hostname used in the connection
- Since both match `test-server.fake`, validation passes

## Setup steps:

1. **Create certificate with fake domain:**
   openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.crt -days 365 -nodes \
   -subj "/CN=test-server.fake"
2. **Add to /etc/hosts on client machines:**
   # Replace with your actual server IP
   3.25.241.36 test-server.fake
3. **Test with curl:**
   curl -v --cacert server.crt https://test-server.fake/your-endpoint
4. **Java clients:** Just use the URL `https://test-server.fake` and import the certificate into truststore if needed.

## Advantages:
- ✅ Works with any client (curl, Java, browsers, etc.)
- ✅ No IP hardcoding in certificates
- ✅ Easy to update when server IP changes (just update /etc/hosts)
- ✅ No confusion with localhost/127.0.0.1

Would you like me to help you create the certificate and set this up?