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

## Files

- `main.tf` - Main infrastructure definitions
- `variables.tf` - Variable definitions
- `outputs.tf` - Output definitions
- `providers.tf` - Provider configuration
- `params.tfvars` - Example variable values for deployment