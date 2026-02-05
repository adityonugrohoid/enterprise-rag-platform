# Amazon Bedrock Integration Guide

Complete guide for deploying the Enterprise RAG Platform with Amazon Bedrock as the LLM provider.

> **Last Updated:** February 2026
>
> **Prerequisites:** AWS Account with billing enabled, AWS CLI configured

---

## Table of Contents

1. [Overview](#1-overview)
2. [Cost Comparison](#2-cost-comparison)
3. [Prerequisites](#3-prerequisites)
4. [Enable Bedrock Model Access](#4-enable-bedrock-model-access)
5. [Deployment Steps](#5-deployment-steps)
6. [Configuration Options](#6-configuration-options)
7. [Testing](#7-testing)
8. [Troubleshooting](#8-troubleshooting)
9. [Cost Optimization](#9-cost-optimization)

---

## 1. Overview

### Why Amazon Bedrock?

| Feature | Ollama (CPU) | Ollama (GPU) | Amazon Bedrock |
|---------|--------------|--------------|----------------|
| Response Time | 60-120s | 5-15s | 2-5s |
| Infrastructure | Self-managed | Self-managed | Fully managed |
| Hourly Cost | ~$0.05 | ~$0.16-0.40 | Pay per token |
| Scaling | Manual | Manual | Automatic |
| Maintenance | Required | Required | None |

### Architecture with Bedrock

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────┐   │
│  │   Nginx     │────▶│ API Gateway │────▶│  Query Service  │   │
│  │  (Port 80)  │     │ (Port 8080) │     │   (Port 8003)   │   │
│  └─────────────┘     └─────────────┘     └────────┬────────┘   │
│                                                    │            │
│                                          ┌────────▼────────┐   │
│                                          │ Amazon Bedrock  │   │
│                                          │  (Llama 3.1 8B) │   │
│                                          └─────────────────┘   │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────┐   │
│  │ Streamlit   │     │  Ingestion  │     │    Retrieval    │   │
│  │    UI       │     │   Service   │     │    Service      │   │
│  │ (Port 8501) │     │ (Port 8001) │     │   (Port 8002)   │   │
│  └─────────────┘     └──────┬──────┘     └────────┬────────┘   │
│                             │                      │            │
│  ┌──────────────────────────┴──────────────────────┴─────────┐ │
│  │                    Docker Containers                       │ │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐      │ │
│  │  │ ChromaDB│  │  MinIO  │  │  Redis  │  │ (Ollama │      │ │
│  │  │  :8000  │  │  :9000  │  │  :6379  │  │ removed)│      │ │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘      │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Key Difference:** Ollama container is no longer needed. LLM inference is handled by Amazon Bedrock API.

---

## 2. Cost Comparison

### Per-Query Cost (Bedrock)

| Model | Input Cost | Output Cost | ~2K tokens query |
|-------|------------|-------------|------------------|
| **Llama 3.1 8B** | $0.22/1M | $0.22/1M | ~$0.0004 |
| Llama 3.1 70B | $0.99/1M | $0.99/1M | ~$0.002 |
| Titan Text Lite | $0.15/1M | $0.20/1M | ~$0.0003 |
| Mistral 7B | $0.15/1M | $0.20/1M | ~$0.0003 |
| Claude 3 Haiku | $0.25/1M | $1.25/1M | ~$0.001 |

### Monthly Cost Estimate

| Usage | Queries/Day | Bedrock Cost | EC2 Cost | Total |
|-------|-------------|--------------|----------|-------|
| Light | 50 | ~$0.60/mo | ~$37/mo | ~$38/mo |
| Medium | 200 | ~$2.40/mo | ~$37/mo | ~$40/mo |
| Heavy | 1000 | ~$12/mo | ~$37/mo | ~$49/mo |

**Note:** EC2 cost assumes t3.medium spot instance (~$0.05/hr). No GPU needed with Bedrock.

---

## 3. Prerequisites

### 3.1 AWS Account Requirements

- [ ] AWS Account with billing enabled
- [ ] IAM user with AdministratorAccess (or specific permissions below)
- [ ] AWS CLI installed and configured

### 3.2 Required IAM Permissions

Your IAM user needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2Permissions",
      "Effect": "Allow",
      "Action": [
        "ec2:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMPermissions",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:PassRole",
        "iam:GetRole",
        "iam:GetInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Sid": "BedrockPermissions",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:ListFoundationModels",
        "bedrock:GetFoundationModel"
      ],
      "Resource": "*"
    }
  ]
}
```

#### Set Up Permissions via CLI

**Option A: Create a managed policy and attach it**

```bash
# Create the policy JSON file
cat > /tmp/rag-deployment-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2Permissions",
      "Effect": "Allow",
      "Action": ["ec2:*"],
      "Resource": "*"
    },
    {
      "Sid": "IAMPermissions",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:PassRole",
        "iam:GetRole",
        "iam:GetInstanceProfile",
        "iam:DeleteRole",
        "iam:DeleteRolePolicy",
        "iam:DeleteInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Sid": "BedrockPermissions",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:ListFoundationModels",
        "bedrock:GetFoundationModel"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Create the managed policy
aws iam create-policy \
    --policy-name RAGPlatformDeployment \
    --policy-document file:///tmp/rag-deployment-policy.json

# Get your AWS account ID and attach policy to your user
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
YOUR_USERNAME=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)

aws iam attach-user-policy \
    --user-name $YOUR_USERNAME \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/RAGPlatformDeployment
```

**Option B: Inline policy (single command)**

```bash
# Get your username
YOUR_USERNAME=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)

# Attach inline policy directly to user
aws iam put-user-policy \
    --user-name $YOUR_USERNAME \
    --policy-name RAGPlatformDeployment \
    --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "EC2Permissions", "Effect": "Allow", "Action": ["ec2:*"], "Resource": "*"},
    {"Sid": "IAMPermissions", "Effect": "Allow", "Action": ["iam:CreateRole","iam:PutRolePolicy","iam:AttachRolePolicy","iam:CreateInstanceProfile","iam:AddRoleToInstanceProfile","iam:PassRole","iam:GetRole","iam:GetInstanceProfile","iam:DeleteRole","iam:DeleteRolePolicy","iam:DeleteInstanceProfile","iam:RemoveRoleFromInstanceProfile"], "Resource": "*"},
    {"Sid": "BedrockPermissions", "Effect": "Allow", "Action": ["bedrock:InvokeModel","bedrock:InvokeModelWithResponseStream","bedrock:ListFoundationModels","bedrock:GetFoundationModel"], "Resource": "*"}
  ]
}'
```

**Verify permissions were attached:**

```bash
# For managed policy
aws iam list-attached-user-policies --user-name $YOUR_USERNAME

# For inline policy
aws iam list-user-policies --user-name $YOUR_USERNAME
```

### 3.3 Verify AWS CLI Configuration

```bash
# Check AWS CLI is configured
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAEXAMPLE",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-user"
# }
```

---

## 4. Enable Bedrock Model Access

**Important:** You must enable model access before using Bedrock.

### 4.1 Via AWS Console (Recommended)

1. Go to [Amazon Bedrock Console](https://console.aws.amazon.com/bedrock/)

2. Select your region (e.g., `us-east-1`)

3. In the left sidebar, click **Model access**

4. Click **Manage model access** (orange button)

5. Enable these models (check the boxes):

   | Provider | Model | Recommended |
   |----------|-------|-------------|
   | Meta | Llama 3.1 8B Instruct | ✅ Primary |
   | Meta | Llama 3.1 70B Instruct | Optional (higher quality) |
   | Amazon | Titan Text Lite | ✅ Backup (cheapest) |
   | Amazon | Titan Text Express | Optional |
   | Mistral AI | Mistral 7B Instruct | Optional |

6. Click **Save changes**

7. Wait for status to show **Access granted** (usually instant for Llama/Titan)

### 4.2 Via AWS CLI

```bash
# List available models
aws bedrock list-foundation-models --region us-east-1 \
  --query 'modelSummaries[?contains(modelId, `llama`) || contains(modelId, `titan`)].{ID:modelId,Name:modelName}' \
  --output table

# Note: Model access must be enabled via Console for most models
```

### 4.3 Verify Model Access

```bash
# Test Bedrock access with a simple call
aws bedrock-runtime invoke-model \
  --model-id meta.llama3-1-8b-instruct-v1:0 \
  --region us-east-1 \
  --body '{"prompt": "Hello", "max_gen_len": 10}' \
  --content-type application/json \
  --accept application/json \
  /tmp/response.json

cat /tmp/response.json
```

If you get an error about model access, go back to Step 4.1.

---

## 5. Deployment Steps

### 5.1 Update Configuration

Edit `deploy/aws/config.env`:

```bash
# Required: Set your AWS region (must match Bedrock model region)
AWS_REGION="us-east-1"

# Required: Set LLM provider to Bedrock
LLM_PROVIDER="bedrock"

# Required: Choose your Bedrock model
# Options:
#   - meta.llama3-1-8b-instruct-v1:0 (recommended, balanced)
#   - meta.llama3-1-70b-instruct-v1:0 (higher quality, more expensive)
#   - amazon.titan-text-lite-v1 (cheapest)
#   - amazon.titan-text-express-v1 (good quality)
#   - mistral.mistral-7b-instruct-v0:2 (fast)
BEDROCK_MODEL="meta.llama3-1-8b-instruct-v1:0"

# Optional: Instance type (can use smaller instance without Ollama)
INSTANCE_TYPE="t3.medium"

# Optional: Use spot instance for cost savings
USE_SPOT_INSTANCE="true"
```

### 5.2 Run Deployment

```bash
cd deploy/aws

# Step 1: Teardown existing infrastructure (if any)
./teardown.sh

# Step 2: Deploy infrastructure with Bedrock IAM role
./01-deploy-infrastructure.sh

# Wait 2-3 minutes for instance initialization

# Step 3: Deploy application
./02-deploy-application.sh

# Step 4: Configure production (Nginx, firewall)
./03-configure-production.sh

# Step 5: Verify deployment
./04-verify-deployment.sh
```

### 5.3 What the Scripts Do

**01-deploy-infrastructure.sh:**
- Creates VPC, subnet, security group
- Creates IAM role with Bedrock permissions
- Launches EC2 instance with IAM role attached
- Allocates Elastic IP

**02-deploy-application.sh:**
- Installs Docker, Python, Nginx
- Uploads application code
- Creates `.env` with Bedrock configuration
- Starts Docker containers (ChromaDB, MinIO, Redis - no Ollama)
- Installs and starts systemd services

**03-configure-production.sh:**
- Configures Nginx reverse proxy
- Sets up firewall rules
- Configures health monitoring

---

## 6. Configuration Options

### 6.1 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LLM_PROVIDER` | LLM provider | `bedrock` |
| `BEDROCK_MODEL` | Bedrock model ID | `meta.llama3-1-8b-instruct-v1:0` |
| `AWS_REGION` | AWS region for Bedrock | `us-east-1` |

### 6.2 Available Bedrock Models

#### Meta Llama Models

| Model ID | Parameters | Best For |
|----------|------------|----------|
| `meta.llama3-1-8b-instruct-v1:0` | 8B | General RAG, fast responses |
| `meta.llama3-1-70b-instruct-v1:0` | 70B | Complex reasoning |
| `meta.llama3-2-1b-instruct-v1:0` | 1B | Simple tasks, lowest cost |
| `meta.llama3-2-3b-instruct-v1:0` | 3B | Balanced small model |

#### Amazon Titan Models

| Model ID | Best For |
|----------|----------|
| `amazon.titan-text-lite-v1` | Cost-sensitive, simple tasks |
| `amazon.titan-text-express-v1` | General purpose |

#### Mistral Models

| Model ID | Parameters | Best For |
|----------|------------|----------|
| `mistral.mistral-7b-instruct-v0:2` | 7B | Fast, efficient |
| `mistral.mixtral-8x7b-instruct-v0:1` | 8x7B | Higher quality |

### 6.3 Switching Models

To change models after deployment:

```bash
# SSH to server
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_SERVER_IP

# Update .env
sudo sed -i 's/BEDROCK_MODEL=.*/BEDROCK_MODEL=meta.llama3-1-70b-instruct-v1:0/' /opt/rag-platform/.env

# Restart services
sudo systemctl restart rag-query rag-api-gateway
```

---

## 7. Testing

### 7.1 Health Check

```bash
curl http://YOUR_SERVER_IP/health
```

Expected response:
```json
{"status":"healthy","services":{"ingestion":"healthy","query":"healthy"},"service":"api_gateway"}
```

### 7.2 Document Upload

```bash
API_KEY=$(cat deploy/aws/api-key.txt)

curl -X POST http://YOUR_SERVER_IP/documents/upload \
  -H "X-API-Key: $API_KEY" \
  -F "file=@data/documents/internal_doc_00_network_performance_standards.txt"
```

Expected response:
```json
{"document_id":"...","filename":"internal_doc_00...","chunks_created":15,"message":"Document ingested successfully"}
```

### 7.3 RAG Query

```bash
API_KEY=$(cat deploy/aws/api-key.txt)

curl -X POST http://YOUR_SERVER_IP/query \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"query": "What are the 5G RAN performance targets?"}'
```

Expected response (2-5 seconds):
```json
{
  "success": true,
  "answer": "Based on the document, the 5G RAN performance targets include...",
  "sources": ["internal_doc_00_network_performance_standards.txt"],
  "chunks_used": 3
}
```

### 7.4 Web UI

Open in browser: `http://YOUR_SERVER_IP/ui`

1. Select documents in sidebar
2. Click "Ingest Selected Documents"
3. Choose a question from the dropdown
4. Compare Direct LLM vs RAG responses

---

## 8. Troubleshooting

### 8.1 "AccessDeniedException" from Bedrock

**Cause:** Model access not enabled or IAM permissions missing.

**Solution:**
1. Verify model access in Bedrock Console (Section 4.1)
2. Check EC2 instance has IAM role with Bedrock permissions:
   ```bash
   # On server
   curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
   ```

### 8.2 "ResourceNotFoundException" from Bedrock

**Cause:** Model ID incorrect or not available in your region.

**Solution:**
1. Verify model ID in `config.env`
2. Check model is available in your region:
   ```bash
   aws bedrock list-foundation-models --region us-east-1 \
     --query 'modelSummaries[].modelId' --output text | grep llama
   ```

### 8.3 Query Returns Empty or Error

**Check query service logs:**
```bash
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_SERVER_IP
sudo journalctl -u rag-query -n 50 --no-pager
```

**Common issues:**
- ChromaDB not running → `sudo docker compose up -d`
- Service not loading .env → `sudo systemctl restart rag-query`

### 8.4 Slow First Response

**Cause:** Bedrock may have cold start latency on first request.

**Solution:** This is normal. Subsequent requests will be faster (2-5 seconds).

---

## 9. Cost Optimization

### 9.1 Choose the Right Model

| Use Case | Recommended Model | Cost/1M tokens |
|----------|-------------------|----------------|
| Simple Q&A | Titan Text Lite | $0.15 |
| General RAG | Llama 3.1 8B | $0.22 |
| Complex Analysis | Llama 3.1 70B | $0.99 |

### 9.2 Reduce Token Usage

The deployment is already optimized:
- `top_k=3` chunks (reduced from 5)
- `max_tokens=2000` context (reduced from 4000)

To further reduce costs:
```bash
# On server, edit query service
sudo nano /opt/rag-platform/services/query/main.py

# Change top_k from 3 to 2
# Change max_tokens from 2000 to 1500
```

### 9.3 Use Spot Instances

Already enabled by default. Saves ~70% on EC2 costs.

### 9.4 Monitor Usage

```bash
# Check Bedrock usage in AWS Console
# Go to: CloudWatch → Metrics → Bedrock → Invocations
```

---

## Quick Reference

### Endpoints

| Endpoint | URL |
|----------|-----|
| Health Check | `http://YOUR_IP/health` |
| Web UI | `http://YOUR_IP/ui` |
| Document Upload | `POST http://YOUR_IP/documents/upload` |
| Query | `POST http://YOUR_IP/query` |

### SSH Access

```bash
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@YOUR_SERVER_IP
```

### Service Management

```bash
# Check all services
sudo systemctl status rag-*

# Restart all services
sudo systemctl restart rag-api-gateway rag-ingestion rag-retrieval rag-query rag-ui

# View logs
sudo journalctl -u rag-query -f
```

### Docker Containers

```bash
# Check containers
sudo docker compose -f /opt/rag-platform/docker-compose.yaml ps

# Restart containers
sudo docker compose -f /opt/rag-platform/docker-compose.yaml restart
```

---

## Appendix: Bedrock Regions

Bedrock is available in these regions (as of Feb 2026):

| Region | Llama 3.1 | Titan | Claude |
|--------|-----------|-------|--------|
| us-east-1 (N. Virginia) | ✅ | ✅ | ✅ |
| us-west-2 (Oregon) | ✅ | ✅ | ✅ |
| eu-west-1 (Ireland) | ✅ | ✅ | ✅ |
| ap-southeast-1 (Singapore) | ✅ | ✅ | ✅ |
| ap-northeast-1 (Tokyo) | ✅ | ✅ | ✅ |

Choose a region close to your users for lower latency.

---

**Document Version:** 1.0
**Maintainer:** Enterprise RAG Platform Team
