# AWS Setup Guide

Complete guide for deploying the Enterprise RAG Platform on AWS with GPU-accelerated inference.

> **Last Updated:** February 2026
>
> **Architecture:** AWS EC2 GPU Instance + Ollama (Self-hosted Llama 3.1)

---

## Prerequisites Checklist

- [ ] AWS Account with billing enabled
- [ ] IAM User with programmatic access (Access Key ID + Secret Access Key)
- [ ] AWS CLI installed and configured
- [ ] EC2 Key Pair created and downloaded
- [ ] GPU quota approved (if needed)
- [ ] Configuration file updated (`config.env`)

---

## Step 1: Create an AWS Account (Skip if you have one)

1. Go to [https://aws.amazon.com/](https://aws.amazon.com/)
2. Click **Create an AWS Account**
3. Follow the signup process (requires email, credit card, phone verification)
4. Choose the **Basic Support - Free** plan

---

## Step 2: Create IAM User with Access Keys

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
2. Leave **Provide user access to the AWS Management Console** unchecked
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
2. Check the confirmation box at the bottom
3. Click **Next**

### 2.9 Save Your Credentials

**IMPORTANT: This is your only chance to save the Secret Access Key!**

1. You'll see:
   - **Access key ID:** something like `AKIAIOSFODNN7EXAMPLE`
   - **Secret access key:** something like `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`

2. Click **Download .csv file** to save both keys
3. Store this file securely
4. Click **Done**

---

## Step 3: Install AWS CLI

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
3. Open Command Prompt and verify: `aws --version`

---

## Step 4: Configure AWS CLI

```bash
aws configure
```

| Prompt | What to Enter |
|--------|---------------|
| AWS Access Key ID | Your Access Key ID from Step 2 |
| AWS Secret Access Key | Your Secret Access Key from Step 2 |
| Default region name | `ap-southeast-1` (or your preferred region) |
| Default output format | `json` |

### Verify Configuration

```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDAEXAMPLEEXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/rag-platform-deployer"
}
```

---

## Step 5: Check GPU Instance Quota

GPU instances require quota approval. Check if you have quota:

```bash
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-DB2E81BA \
    --region ap-southeast-1 \
    --query 'Quota.Value'
```

If the value is `0`, you need to request a quota increase:

### Request GPU Quota (if needed)

1. Go to AWS Console → **Service Quotas** → **EC2**
2. Search for "Running On-Demand G and VT instances"
3. Click **Request quota increase**
4. Request at least **4 vCPUs** (for g4dn.xlarge)
5. Wait for approval (usually 24-48 hours)

---

## Step 6: Create EC2 Key Pair

### 6.1 Navigate to EC2

1. In AWS Console, search for **EC2**
2. Click on **EC2**

### 6.2 Go to Key Pairs

1. In the left sidebar, scroll to **Network & Security**
2. Click **Key Pairs**

### 6.3 Create Key Pair

1. Click **Create key pair**
2. Fill in:

| Field | Value |
|-------|-------|
| **Name** | `rag-platform-key` |
| **Key pair type** | RSA |
| **Private key file format** | `.pem` |

3. Click **Create key pair**
4. The `.pem` file will download automatically

### 6.4 Secure the Key File

```bash
# Move to SSH directory
mkdir -p ~/.ssh
mv ~/Downloads/rag-platform-key.pem ~/.ssh/

# Set correct permissions (REQUIRED)
chmod 400 ~/.ssh/rag-platform-key.pem

# Verify
ls -la ~/.ssh/rag-platform-key.pem
```

---

## Step 7: Get Ubuntu AMI ID

Get the latest Ubuntu 24.04 LTS AMI for your region:

```bash
aws ssm get-parameter \
    --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query 'Parameter.Value' \
    --output text \
    --region ap-southeast-1
```

Copy the AMI ID (e.g., `ami-08d59269edddde222`).

---

## Step 8: Update Configuration File

Edit the deployment configuration:

```bash
nano deploy/aws/config.env
```

### Required Changes

```bash
# AWS Region
AWS_REGION="ap-southeast-1"

# AMI ID from Step 7
AMI_ID="ami-08d59269edddde222"

# Key pair name (must match exactly)
KEY_PAIR_NAME="rag-platform-key"
```

### GPU Instance Selection

```bash
# GPU instances for Ollama inference:
#   g4dn.xlarge  - NVIDIA T4 (16GB), 4 vCPU, 16GB RAM (~$0.53/hr)
#   g4dn.2xlarge - NVIDIA T4 (16GB), 8 vCPU, 32GB RAM (~$0.75/hr)
#   g5.xlarge    - NVIDIA A10G (24GB), 4 vCPU, 16GB RAM (~$1.01/hr)
INSTANCE_TYPE="g4dn.xlarge"
```

### LLM Model Selection

```bash
# Recommended models for NVIDIA T4 (16GB VRAM):
#   llama3.1:8b  - Best quality/speed balance (recommended)
#   mistral:7b   - Fast, good quality
#   qwen2.5:7b   - Good for multilingual
OLLAMA_MODEL="llama3.1:8b"
```

### Security Setting (Recommended)

```bash
# Get your current public IP
curl -s ifconfig.me

# Restrict SSH to your IP only
MY_IP="YOUR_IP/32"
```

### Save and Exit

Press `Ctrl+X`, then `Y`, then `Enter`

---

## Step 9: Run Deployment

```bash
cd deploy/aws

# Step 1: Create AWS infrastructure (~3-5 minutes)
./01-deploy-infrastructure.sh

# Wait 2-3 minutes for instance initialization

# Step 2: Deploy application with GPU (~15-20 minutes)
# This includes NVIDIA driver installation and model download
./02-deploy-application.sh

# Step 3: Configure Nginx (~2 minutes)
./03-configure-production.sh

# Step 4: Verify deployment
./04-verify-deployment.sh
```

---

## Step 10: Post-Deployment Testing

### 10.1 Health Check

```bash
# Get your Elastic IP from deployment output
curl http://YOUR_ELASTIC_IP/health
```

Expected response:
```json
{"status":"healthy","services":{"ingestion":"healthy","query":"healthy"}}
```

### 10.2 Check GPU Status

```bash
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_ELASTIC_IP nvidia-smi
```

Expected output shows NVIDIA T4 with driver version.

### 10.3 Document Upload Test

```bash
API_KEY=$(cat deploy/aws/api-key.txt)

curl -X POST http://YOUR_ELASTIC_IP/documents/upload \
  -H "X-API-Key: $API_KEY" \
  -F "file=@data/documents/internal_doc_00_network_performance_standards.txt"
```

### 10.4 Query Test

```bash
API_KEY=$(cat deploy/aws/api-key.txt)

curl -X POST http://YOUR_ELASTIC_IP/query \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"query": "What are the 5G performance targets?"}'
```

Response time should be **2-5 seconds** with GPU acceleration.

### 10.5 Web UI

Open your browser: `http://YOUR_ELASTIC_IP/ui`

---

## Troubleshooting

### GPU Not Detected

```bash
# SSH to server
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_ELASTIC_IP

# Check NVIDIA driver
nvidia-smi

# If not found, install drivers
sudo apt-get update
sudo apt-get install -y nvidia-driver-535
sudo reboot
```

### Ollama Not Using GPU

```bash
# Check Ollama GPU access
sudo docker exec ollama nvidia-smi

# If no GPU, restart with GPU support
cd /opt/rag-platform
sudo docker compose down
sudo docker compose up -d
```

### "InsufficientInstanceCapacity" Error

GPU instances have limited availability. Try:
1. Different availability zone (change region)
2. Different GPU instance type (g5.xlarge instead of g4dn.xlarge)
3. Wait and retry later

### "VcpuLimitExceeded" Error

You need to request GPU quota increase (Step 5).

### Services Show "Degraded"

```bash
# SSH and check logs
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_ELASTIC_IP
sudo journalctl -u rag-query -n 50

# Restart services
sudo systemctl restart rag-api-gateway rag-query
```

### Slow Model Downloads

The first deployment downloads the Llama model (~4.7GB). If it times out:

```bash
# SSH to server and manually pull
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_ELASTIC_IP
sudo docker exec ollama ollama pull llama3.1:8b
```

---

## Cost Estimation

| Resource | Specification | Monthly Cost (USD) |
|----------|---------------|-------------------|
| EC2 Instance | g4dn.xlarge (GPU) | ~$380 |
| EBS Storage | 100GB gp3 SSD | ~$8 |
| Elastic IP | Static public IP | ~$3.65 |
| Data Transfer | ~100GB outbound | ~$9 |
| **Total** | | **~$400/month** |

### Cost Optimization

| Strategy | Savings | Notes |
|----------|---------|-------|
| Stop when not in use | 70%+ | `aws ec2 stop-instances --instance-ids <ID>` |
| Use g4dn.xlarge (not g5) | 50% | T4 GPU is sufficient for 8B models |
| Reserved Instance (1yr) | 40% | Commit in EC2 Console |

---

## Cleanup (Stop All Charges)

```bash
cd deploy/aws
./teardown.sh
```

This permanently deletes all resources. Back up data first!

---

## Quick Reference

### SSH Access

```bash
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_ELASTIC_IP
```

### Check GPU

```bash
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_ELASTIC_IP nvidia-smi
```

### Check Services

```bash
# On server
sudo systemctl status rag-*
sudo docker compose ps
```

### View Logs

```bash
# On server
sudo journalctl -u rag-query -f
sudo docker logs ollama -f
```

### Restart Services

```bash
# On server
sudo docker compose restart
sudo systemctl restart rag-api-gateway rag-query rag-ingestion rag-retrieval rag-ui
```

### Access Points

| Service | URL |
|---------|-----|
| Health Check | `http://YOUR_IP/health` |
| Web UI | `http://YOUR_IP/ui` |
| Document Upload | `POST http://YOUR_IP/documents/upload` |
| Query | `POST http://YOUR_IP/query` |

---

## Additional Resources

- [AWS EC2 GPU Instances](https://aws.amazon.com/ec2/instance-types/g4/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/overview.html)
- [Ollama Documentation](https://ollama.ai/docs)
