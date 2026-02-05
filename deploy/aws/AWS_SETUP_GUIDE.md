# AWS Setup Guide

This guide covers the prerequisites you need to complete in your AWS account before running the deployment scripts.

> **Last Updated:** February 2026
>
> **Sources:** [AWS IAM Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/), [AWS EC2 Key Pairs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html), [AWS CLI Installation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), [Ubuntu on AWS](https://documentation.ubuntu.com/aws/aws-how-to/instances/find-ubuntu-images/)

---

## Prerequisites Checklist

- [ ] AWS Account with billing enabled
- [ ] IAM User with programmatic access (Access Key ID + Secret Access Key)
- [ ] AWS CLI installed and configured
- [ ] EC2 Key Pair created and downloaded
- [ ] Configuration file updated (`config.env`)

---

## Step 1: Create an AWS Account (Skip if you have one)

1. Go to [https://aws.amazon.com/](https://aws.amazon.com/)
2. Click **Create an AWS Account**
3. Follow the signup process (requires email, credit card, phone verification)
4. Choose the **Basic Support - Free** plan

---

## Step 2: Create IAM User with Access Keys

AWS recommends using [IAM Identity Center](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html) for human users, but for simplicity in this deployment, we'll create a traditional IAM user with access keys.

### 2.1 Sign in to AWS Console

1. Go to [https://console.aws.amazon.com/](https://console.aws.amazon.com/)
2. Sign in with your root account email and password

### 2.2 Navigate to IAM

1. In the search bar at the top, type **IAM**
2. Click on **IAM** (Identity and Access Management)

### 2.3 Create a New User

1. In the left sidebar, click **Users**
2. Click the **Create user** button (top right)

### 2.4 Set User Details

1. **User name:** `rag-platform-deployer`
2. Leave **Provide user access to the AWS Management Console** unchecked (we only need programmatic access)
3. Click **Next**

### 2.5 Set Permissions

1. Select **Attach policies directly**
2. In the search box, type `AdministratorAccess`
3. Check the box next to **AdministratorAccess**
4. Click **Next**

### 2.6 Review and Create

1. Review the settings
2. Click **Create user**

### 2.7 Create Access Key

After the user is created:

1. Click on the user name **rag-platform-deployer** to open user details
2. Click on the **Security credentials** tab
3. Scroll down to **Access keys** section
4. Click **Create access key**

### 2.8 Select Use Case

1. Select **Command Line Interface (CLI)**
2. Check the confirmation box at the bottom ("I understand the above recommendation...")
3. Click **Next**

### 2.9 Set Description Tag (Optional)

1. Description tag value: `RAG Platform Deployment`
2. Click **Create access key**

### 2.10 Save Your Credentials

**IMPORTANT: This is your only chance to save the Secret Access Key!**

1. You'll see:
   - **Access key ID:** something like `AKIAIOSFODNN7EXAMPLE`
   - **Secret access key:** something like `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`

2. Click **Download .csv file** to save both keys
3. Store this file securely (you'll need these in Step 4)
4. Click **Done**

---

## Step 3: Install AWS CLI

The AWS CLI (Command Line Interface) lets you manage AWS from your terminal.

### For Linux / WSL (Windows Subsystem for Linux)

```bash
# Download the installer
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Unzip (install unzip if needed: sudo apt install unzip)
unzip awscliv2.zip

# Install
sudo ./aws/install

# Verify installation
aws --version
# Should show: aws-cli/2.x.x Python/3.x.x Linux/...

# Clean up
rm -rf awscliv2.zip aws/
```

### For macOS

```bash
# Download the installer
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"

# Install
sudo installer -pkg AWSCLIV2.pkg -target /

# Verify
aws --version

# Clean up
rm AWSCLIV2.pkg
```

### For Windows

1. Download the installer: [https://awscli.amazonaws.com/AWSCLIV2.msi](https://awscli.amazonaws.com/AWSCLIV2.msi)
2. Run the downloaded MSI installer
3. Follow the installation wizard
4. Open a new Command Prompt or PowerShell and verify:
   ```cmd
   aws --version
   ```

### Alternative: Install via Snap (Linux)

```bash
sudo snap install aws-cli --classic
aws --version
```

---

## Step 4: Configure AWS CLI

Now connect your AWS CLI to your AWS account using the access keys from Step 2.

```bash
aws configure
```

You'll be prompted for four pieces of information:

| Prompt | What to Enter |
|--------|---------------|
| AWS Access Key ID | Paste your Access Key ID from Step 2.10 |
| AWS Secret Access Key | Paste your Secret Access Key from Step 2.10 |
| Default region name | `us-east-1` (or your preferred region, see note below) |
| Default output format | `json` |

**Example session:**
```
$ aws configure
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: json
```

### Region Selection

Choose a region close to your users for better latency:

| Region Code | Location |
|-------------|----------|
| `us-east-1` | N. Virginia (cheapest, most services) |
| `us-west-2` | Oregon |
| `eu-west-1` | Ireland |
| `ap-southeast-1` | Singapore |
| `ap-northeast-1` | Tokyo |

### Verify Configuration

```bash
aws sts get-caller-identity
```

**Expected output:**
```json
{
    "UserId": "AIDAEXAMPLEEXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/rag-platform-deployer"
}
```

If you see your account information, the CLI is configured correctly!

---

## Step 5: Create EC2 Key Pair

A key pair lets you securely SSH into your EC2 instance.

### 5.1 Navigate to EC2

1. In AWS Console, search for **EC2** in the top search bar
2. Click on **EC2**

### 5.2 Go to Key Pairs

1. In the left sidebar, scroll down to **Network & Security**
2. Click **Key Pairs**

### 5.3 Create Key Pair

1. Click **Create key pair** (orange button, top right)

### 5.4 Configure Key Pair

Fill in the form:

| Field | Value |
|-------|-------|
| **Name** | `rag-platform-key` |
| **Key pair type** | RSA |
| **Private key file format** | `.pem` (for Linux/macOS) or `.ppk` (for PuTTY on Windows) |

### 5.5 Create and Download

1. Click **Create key pair**
2. Your browser will automatically download the `.pem` file
3. **Save this file!** You cannot download it again.

### 5.6 Secure the Key File

**On Linux/macOS/WSL:**

```bash
# Move to SSH directory
mkdir -p ~/.ssh
mv ~/Downloads/rag-platform-key.pem ~/.ssh/

# Set correct permissions (REQUIRED - SSH will refuse to use the key otherwise)
chmod 400 ~/.ssh/rag-platform-key.pem

# Verify
ls -la ~/.ssh/rag-platform-key.pem
# Should show: -r-------- ... rag-platform-key.pem
```

**On Windows (if using WSL):**

```bash
# Copy from Windows Downloads to WSL
cp /mnt/c/Users/YOUR_USERNAME/Downloads/rag-platform-key.pem ~/.ssh/
chmod 400 ~/.ssh/rag-platform-key.pem
```

---

## Step 6: Get the Ubuntu AMI ID

We'll use Ubuntu 24.04 LTS, which is supported until April 2029.

### Option A: Using SSM Parameter (Recommended)

This automatically gets the latest official Ubuntu AMI:

```bash
# Get Ubuntu 24.04 LTS AMI ID for your region
aws ssm get-parameter \
    --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query 'Parameter.Value' \
    --output text \
    --region us-east-1
```

**Example output:**
```
ami-0abcdef1234567890
```

Copy this AMI ID for the next step.

### Option B: Using EC2 describe-images

```bash
aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text \
    --region us-east-1
```

### Option C: Manual Lookup (AWS Console)

1. Go to EC2 → **AMIs** (left sidebar under Images)
2. Change filter from "Owned by me" to **Public images**
3. Search for: `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server`
4. Sort by **Creation date** (newest first)
5. Copy the **AMI ID** of the first result

---

## Step 7: Update Configuration File

Edit the deployment configuration with your values:

```bash
# From project root
nano deploy/aws/config.env
```

### Required Changes

```bash
# AWS Region (same as you used in aws configure)
AWS_REGION="us-east-1"

# AMI ID from Step 6
AMI_ID="ami-0abcdef1234567890"  # Replace with your actual AMI ID

# Key pair name (must match exactly what you created in Step 5)
KEY_PAIR_NAME="rag-platform-key"
```

### Recommended Security Setting

```bash
# Get your current public IP
curl -s ifconfig.me

# Add to config.env with /32 suffix (restricts SSH to only your IP)
MY_IP="203.0.113.50/32"  # Replace with YOUR IP from above
```

### Optional Settings

```bash
# Instance type (default is fine for most cases)
INSTANCE_TYPE="t3.xlarge"     # 4 vCPU, 16GB RAM (~$55/month)
# INSTANCE_TYPE="t3.large"    # 2 vCPU, 8GB RAM (~$30/month) - budget option

# Domain name (only if you have one)
DOMAIN_NAME=""                # e.g., "rag.yourdomain.com"
```

### Save and Exit

- In nano: Press `Ctrl+X`, then `Y`, then `Enter`

---

## Step 8: Run Deployment

You're now ready to deploy!

```bash
cd deploy/aws

# Step 1: Create AWS infrastructure (~3-5 minutes)
./01-deploy-infrastructure.sh

# Wait 2-3 minutes for the instance to fully initialize

# Step 2: Deploy application (~15-20 minutes)
./02-deploy-application.sh

# Step 3: Configure production (Nginx, SSL) (~5 minutes)
./03-configure-production.sh
```

---

## Step 9: Post-Deployment Testing

After deployment completes, run these tests to verify everything is working:

### 9.1 Health Check

```bash
# Replace YOUR_SERVER_IP with your actual Elastic IP
curl http://YOUR_SERVER_IP/health
```

**Expected response:**
```json
{"status":"healthy","services":{"ingestion":"healthy","query":"healthy"},"service":"api_gateway"}
```

If you see `"status":"degraded"`, check the service status on the server.

### 9.2 Document Upload Test

```bash
# Get your API key from deploy/aws/api-key.txt
API_KEY=$(cat deploy/aws/api-key.txt)

# Create a test document
echo "This is a test document about artificial intelligence and machine learning." > test_doc.txt

# Upload the document
curl -X POST http://YOUR_SERVER_IP/documents/upload \
  -H "X-API-Key: $API_KEY" \
  -F "file=@test_doc.txt"
```

**Expected response:**
```json
{"document_id":"...","filename":"test_doc.txt","chunks_created":1,"message":"Document ingested successfully"}
```

### 9.3 Query Test

```bash
API_KEY=$(cat deploy/aws/api-key.txt)

curl -X POST http://YOUR_SERVER_IP/query \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"query": "What is this document about?"}'
```

**Expected response:**
```json
{"answer":"...","sources":["test_doc.txt"],"chunks_used":1}
```

### 9.4 Web UI Test

Open your browser and navigate to:
```
http://YOUR_SERVER_IP/ui
```

You should see the Streamlit-based Enterprise RAG Platform UI.

### 9.5 Verify Auto-Restart on Reboot

To test that services restart automatically after a server reboot:

```bash
# SSH into the server
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_SERVER_IP

# Reboot the server
sudo reboot
```

Wait 2-3 minutes, then test:

```bash
# Check Docker containers are running
curl http://YOUR_SERVER_IP/health
```

All services should be healthy without manual intervention.

---

## Troubleshooting

### "Invalid API key" Error

If you get `{"detail":"Invalid API key"}` when making API requests:

1. **Verify you're using the correct API key:**
   ```bash
   cat deploy/aws/api-key.txt
   ```

2. **Check the API key on the server matches:**
   ```bash
   ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_SERVER_IP
   grep API_KEY /opt/rag-platform/.env
   ```

3. **Ensure services are loading the .env file:**
   ```bash
   sudo systemctl restart rag-api-gateway
   sudo journalctl -u rag-api-gateway -n 20
   ```

### Docker Containers Not Running After Reboot

If `docker compose ps` shows no containers after server reboot:

```bash
# SSH into the server
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_SERVER_IP

# Start Docker containers
cd /opt/rag-platform
sudo docker compose up -d

# Verify containers are healthy
sudo docker compose ps

# Restart systemd services
sudo systemctl restart rag-ingestion rag-retrieval rag-query rag-api-gateway rag-ui
```

### Services Show "Degraded" Status

If health check returns `"status":"degraded"`:

```bash
# Check which service is unhealthy
curl http://YOUR_SERVER_IP/health

# SSH and check service logs
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_SERVER_IP
sudo journalctl -u rag-ingestion -n 50
sudo journalctl -u rag-retrieval -n 50
```

Common causes:
- Docker containers not running (ChromaDB, Redis, Ollama, MinIO)
- Services started before Docker containers were healthy

### "Unable to locate credentials"

```bash
# Check if credentials are configured
aws configure list

# Reconfigure if needed
aws configure
```

### "Key pair does not exist"

```bash
# List your key pairs
aws ec2 describe-key-pairs --region us-east-1

# Make sure the name in config.env matches exactly
```

### "Invalid AMI ID"

AMI IDs are region-specific. Make sure you:
1. Got the AMI ID for the correct region
2. Used the exact AMI ID (starts with `ami-`)

```bash
# Get fresh AMI ID for your region
aws ssm get-parameter \
    --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query 'Parameter.Value' \
    --output text \
    --region YOUR_REGION
```

### "Permission denied" when running scripts

```bash
chmod +x deploy/aws/*.sh
```

### SSH "Connection refused" or timeout

- Wait 2-3 minutes after instance creation
- Check that your IP matches `MY_IP` in config.env
- Verify security group allows SSH from your IP:
  ```bash
  source deploy/aws/deployment-info.env
  aws ec2 describe-security-groups --group-ids $SG_ID --region $AWS_REGION
  ```

### "Permission denied (publickey)" when SSH

```bash
# Check key file permissions
ls -la ~/.ssh/rag-platform-key.pem
# Must show: -r-------- (400)

# Fix if needed
chmod 400 ~/.ssh/rag-platform-key.pem
```

---

## Cost Estimation

| Resource | Specification | Monthly Cost (USD) |
|----------|---------------|-------------------|
| EC2 Instance | t3.xlarge (4 vCPU, 16GB RAM) | ~$55 |
| EBS Storage | 100GB gp3 | ~$8 |
| Elastic IP | Static public IP | ~$3.65 |
| Data Transfer | ~100GB outbound | ~$9 |
| **Total** | | **~$75/month** |

### Save Money

| Option | Savings | How |
|--------|---------|-----|
| Spot Instance | ~70% | Add `--instance-market-options '{"MarketType":"spot"}'` to launch (may be interrupted) |
| Reserved Instance | ~40% | Commit to 1-year term in EC2 Console |
| Smaller Instance | ~45% | Use `t3.large` instead (slower but works) |

---

## Cleanup (Stop All Charges)

To delete all AWS resources created by this deployment:

```bash
cd deploy/aws
./teardown.sh
```

This permanently deletes:
- EC2 instance and all data
- Elastic IP
- VPC and networking components

**Warning:** This cannot be undone. Back up any important data first.

---

## Quick Reference

### SSH into your server

```bash
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_ELASTIC_IP
```

### Check service status (on server)

```bash
# Check all RAG services
sudo systemctl status rag-*

# Check Docker containers
sudo docker compose -f /opt/rag-platform/docker-compose.yaml ps
```

### View logs (on server)

```bash
# API Gateway logs
sudo journalctl -u rag-api-gateway -f

# Ingestion service logs
sudo journalctl -u rag-ingestion -f

# Streamlit UI logs
sudo journalctl -u rag-ui -f

# All RAG services
sudo journalctl -u 'rag-*' -f
```

### Restart services (on server)

```bash
# Restart all services (after ensuring Docker containers are running)
sudo docker compose -f /opt/rag-platform/docker-compose.yaml up -d
sudo systemctl restart rag-ingestion rag-retrieval rag-query rag-api-gateway rag-ui
```

### Access Points

| Service | URL |
|---------|-----|
| API Health | `http://YOUR_IP/health` |
| Web UI | `http://YOUR_IP/ui` |
| Document Upload | `POST http://YOUR_IP/documents/upload` |
| Query | `POST http://YOUR_IP/query` |

---

## Additional Resources

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS CLI Command Reference](https://docs.aws.amazon.com/cli/latest/reference/)
- [EC2 Key Pairs Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html)
- [Ubuntu on AWS Documentation](https://documentation.ubuntu.com/aws/aws-how-to/instances/find-ubuntu-images/)
