# GCP Setup Guide

Complete guide for deploying the Enterprise RAG Platform on Google Cloud Platform with GPU-accelerated inference.

> **Last Updated:** February 2026
>
> **Architecture:** GCP Compute Engine GPU Instance + Ollama (Self-hosted Llama 3.1)

---

## Prerequisites Checklist

- [ ] GCP Account with billing enabled
- [ ] gcloud CLI installed and configured
- [ ] GPU quota approved (if needed)
- [ ] Configuration file updated (`config.env`)

---

## Step 1: Create a GCP Account (Skip if you have one)

1. Go to [https://cloud.google.com/](https://cloud.google.com/)
2. Click **Get started for free**
3. Sign in with your Google account
4. Follow the signup process (requires credit card)
5. You'll receive $300 in free credits for 90 days

---

## Step 2: Create or Select a GCP Project

### 2.1 Go to GCP Console

1. Go to [https://console.cloud.google.com/](https://console.cloud.google.com/)
2. Sign in with your Google account

### 2.2 Create a New Project

1. Click the project dropdown at the top (next to "Google Cloud")
2. Click **New Project**
3. Fill in:
   - **Project name:** `rag-platform`
   - **Project ID:** (auto-generated, or customize)
   - **Billing account:** Select your billing account
4. Click **Create**

### 2.3 Note Your Project ID

Your project ID will be something like `rag-platform-123456`. You'll need this later.

```bash
# Example
GCP_PROJECT_ID="rag-platform-123456"
```

---

## Step 3: Install gcloud CLI

### For Linux / WSL

```bash
# Add Google Cloud SDK repository
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

# Import Google Cloud public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

# Update and install
sudo apt-get update
sudo apt-get install -y google-cloud-cli

# Verify
gcloud --version
```

### Alternative: Install via Script

```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud --version
```

### For macOS

```bash
# Using Homebrew
brew install google-cloud-sdk

# Verify
gcloud --version
```

### For Windows

1. Download installer: [https://cloud.google.com/sdk/docs/install](https://cloud.google.com/sdk/docs/install)
2. Run the installer
3. Open a new terminal and verify: `gcloud --version`

---

## Step 4: Configure gcloud CLI

### 4.1 Initialize gcloud

```bash
gcloud init
```

Follow the prompts:
1. **Log in:** Press `Y` to log in with your Google account
2. **Select project:** Choose your project (e.g., `rag-platform-123456`)
3. **Configure region:** Choose `asia-southeast1` (Singapore) or your preferred region

### 4.2 Verify Configuration

```bash
# Check current configuration
gcloud config list

# Expected output shows project and account
```

### 4.3 Set Default Zone

```bash
gcloud config set compute/zone asia-southeast1-b
gcloud config set compute/region asia-southeast1
```

---

## Step 5: Enable Required APIs

```bash
# Enable Compute Engine API
gcloud services enable compute.googleapis.com

# Verify
gcloud services list --enabled | grep compute
```

---

## Step 6: Check GPU Quota

GPU instances require quota approval. Check your current quota:

```bash
gcloud compute regions describe asia-southeast1 \
    --format="table(quotas.metric,quotas.limit,quotas.usage)" \
    | grep -i gpu
```

### Request GPU Quota (if needed)

1. Go to GCP Console → **IAM & Admin** → **Quotas**
2. Filter by: `Metric: GPUs (all regions)` or `NVIDIA L4 GPUs`
3. Select the quota for your region
4. Click **Edit Quotas**
5. Request at least **1 GPU**
6. Provide a reason: "GPU-accelerated ML inference for RAG platform"
7. Submit and wait for approval (usually 24-48 hours)

### Alternative: Use gcloud Command

```bash
# Check current GPU quota
gcloud compute project-info describe --project=YOUR_PROJECT_ID \
    --format="table(quotas.metric,quotas.limit,quotas.usage)" \
    | grep -i gpu
```

---

## Step 7: Update Configuration File

Edit the deployment configuration:

```bash
nano deploy/gcp/config.env
```

### Required Changes

```bash
# GCP Project ID (from Step 2)
GCP_PROJECT_ID="rag-platform-123456"

# GCP Zone (Singapore)
GCP_ZONE="asia-southeast1-b"
GCP_REGION="asia-southeast1"
```

### GPU Instance Selection

```bash
# GPU machine types:
#   g2-standard-4  - NVIDIA L4 (24GB), 4 vCPU, 16GB RAM (~$0.70/hr)
#   g2-standard-8  - NVIDIA L4 (24GB), 8 vCPU, 32GB RAM (~$1.00/hr)
#   n1-standard-4 + T4 - NVIDIA T4 (16GB), 4 vCPU, 15GB RAM (~$0.55/hr)
MACHINE_TYPE="g2-standard-4"
GPU_TYPE="nvidia-l4"
```

### LLM Model Selection

```bash
# Recommended models for NVIDIA L4 (24GB VRAM):
#   llama3.1:8b     - Best quality/speed balance (recommended)
#   llama3.1:70b-q4 - Highest quality (fits in 24GB)
#   mistral:7b      - Fast, good quality
#   qwen2.5:14b     - Good for multilingual
OLLAMA_MODEL="llama3.1:8b"
```

### Save and Exit

Press `Ctrl+X`, then `Y`, then `Enter`

---

## Step 8: Run Deployment

```bash
cd deploy/gcp

# Step 1: Create GCP infrastructure (~3-5 minutes)
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

## Step 9: Post-Deployment Testing

### 9.1 Health Check

```bash
# Get your static IP from deployment output
curl http://YOUR_STATIC_IP/health
```

Expected response:
```json
{"status":"healthy","services":{"ingestion":"healthy","query":"healthy"}}
```

### 9.2 Check GPU Status

```bash
gcloud compute ssh ubuntu@rag-platform --zone=asia-southeast1-b --command='nvidia-smi'
```

Expected output shows NVIDIA L4 with driver version.

### 9.3 Document Upload Test

```bash
API_KEY=$(cat deploy/gcp/api-key.txt)

curl -X POST http://YOUR_STATIC_IP/documents/upload \
  -H "X-API-Key: $API_KEY" \
  -F "file=@data/documents/internal_doc_00_network_performance_standards.txt"
```

### 9.4 Query Test

```bash
API_KEY=$(cat deploy/gcp/api-key.txt)

curl -X POST http://YOUR_STATIC_IP/query \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"query": "What are the 5G performance targets?"}'
```

Response time should be **2-5 seconds** with GPU acceleration.

### 9.5 Web UI

Open your browser: `http://YOUR_STATIC_IP/ui`

---

## Troubleshooting

### GPU Not Detected

```bash
# SSH to instance
gcloud compute ssh ubuntu@rag-platform --zone=asia-southeast1-b

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

### "Quota exceeded" Error

GPU quota needs to be increased:

1. Go to GCP Console → **IAM & Admin** → **Quotas**
2. Search for "NVIDIA L4" or "GPUs (all regions)"
3. Request quota increase

### "ZONE_RESOURCE_POOL_EXHAUSTED" Error

GPU instances have limited availability. Try:

1. Different zone in the same region:
   ```bash
   # Try different zones
   gcloud compute zones list --filter="region:asia-southeast1"
   ```
2. Different region entirely
3. Wait and retry later

### Services Show "Degraded"

```bash
# SSH and check logs
gcloud compute ssh ubuntu@rag-platform --zone=asia-southeast1-b
sudo journalctl -u rag-query -n 50

# Restart services
sudo systemctl restart rag-api-gateway rag-query
```

### Slow Model Downloads

The first deployment downloads the Llama model (~4.7GB). If it times out:

```bash
# SSH to instance and manually pull
gcloud compute ssh ubuntu@rag-platform --zone=asia-southeast1-b
sudo docker exec ollama ollama pull llama3.1:8b
```

---

## Cost Estimation

| Resource | Specification | Monthly Cost (USD) |
|----------|---------------|-------------------|
| Compute Engine | g2-standard-4 (GPU) | ~$500 |
| Boot Disk | 100GB SSD | ~$17 |
| Static IP | Regional IP | ~$3 |
| Data Transfer | ~100GB outbound | ~$12 |
| **Total** | | **~$530/month** |

### Cost Optimization

| Strategy | Savings | Notes |
|----------|---------|-------|
| Stop when not in use | 70%+ | `gcloud compute instances stop rag-platform` |
| Use n1 + T4 instead of g2 | 20% | T4 is sufficient for 8B models |
| Committed use (1yr) | 37% | Purchase in Compute Engine settings |
| Preemptible (testing only) | 60-91% | May be terminated anytime |

### Start/Stop Commands

```bash
# Stop instance (stops billing for compute, keeps disk)
gcloud compute instances stop rag-platform --zone=asia-southeast1-b

# Start instance
gcloud compute instances start rag-platform --zone=asia-southeast1-b
```

---

## Cleanup (Stop All Charges)

```bash
cd deploy/gcp
./teardown.sh
```

This permanently deletes:
- VM instance and all data
- Static IP
- Firewall rules
- VPC network (if empty)

**Warning:** Back up any important data first!

---

## Quick Reference

### SSH Access

```bash
gcloud compute ssh ubuntu@rag-platform --zone=asia-southeast1-b
```

### Check GPU

```bash
gcloud compute ssh ubuntu@rag-platform --zone=asia-southeast1-b --command='nvidia-smi'
```

### Check Services

```bash
# SSH first, then:
sudo systemctl status rag-*
sudo docker compose ps
```

### View Logs

```bash
# SSH first, then:
sudo journalctl -u rag-query -f
sudo docker logs ollama -f
```

### Restart Services

```bash
# SSH first, then:
sudo docker compose restart
sudo systemctl restart rag-api-gateway rag-query rag-ingestion rag-retrieval rag-ui
```

### Instance Management

```bash
# List instances
gcloud compute instances list

# Stop instance
gcloud compute instances stop rag-platform --zone=asia-southeast1-b

# Start instance
gcloud compute instances start rag-platform --zone=asia-southeast1-b

# Delete instance
gcloud compute instances delete rag-platform --zone=asia-southeast1-b
```

### Access Points

| Service | URL |
|---------|-----|
| Health Check | `http://YOUR_IP/health` |
| Web UI | `http://YOUR_IP/ui` |
| Document Upload | `POST http://YOUR_IP/documents/upload` |
| Query | `POST http://YOUR_IP/query` |

---

## GCP vs AWS Comparison

| Aspect | AWS | GCP |
|--------|-----|-----|
| GPU Instance | g4dn.xlarge (T4) | g2-standard-4 (L4) |
| GPU VRAM | 16GB | 24GB |
| Monthly Cost | ~$400 | ~$530 |
| CLI Tool | `aws` | `gcloud` |
| SSH | Key file (.pem) | gcloud ssh |

---

## Additional Resources

- [GCP Compute Engine GPU](https://cloud.google.com/compute/docs/gpus)
- [NVIDIA L4 GPU Documentation](https://cloud.google.com/compute/docs/gpus/l4-gpus)
- [gcloud CLI Reference](https://cloud.google.com/sdk/gcloud/reference)
- [Ollama Documentation](https://ollama.ai/docs)
