# Enterprise RAG Platform - Cloud Deployment

Deploy the Enterprise RAG Platform to **AWS** or **GCP** with GPU-accelerated inference using open-source models.

## Architecture

Both deployments use the same architecture:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cloud GPU Instance                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────┐   │
│  │   Nginx     │────▶│ API Gateway │────▶│  Query Service  │   │
│  │  (Port 80)  │     │ (Port 8080) │     │   (Port 8003)   │   │
│  └─────────────┘     └─────────────┘     └────────┬────────┘   │
│                                                    │            │
│  ┌─────────────┐     ┌─────────────┐     ┌────────▼────────┐   │
│  │ Streamlit   │     │  Ingestion  │     │     Ollama      │   │
│  │    UI       │     │   Service   │     │   (GPU LLM)     │   │
│  │ (Port 8501) │     │ (Port 8001) │     │  (Port 11434)   │   │
│  └─────────────┘     └──────┬──────┘     └─────────────────┘   │
│                             │                                   │
│  ┌──────────────────────────┴───────────────────────────────┐  │
│  │                    Docker Containers                      │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────┐  │  │
│  │  │ChromaDB │  │  MinIO  │  │  Redis  │  │   Ollama    │  │  │
│  │  │ :8000   │  │  :9000  │  │  :6379  │  │   :11434    │  │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Deployment Options

| Option | Cloud | GPU | LLM | Use Case |
|--------|-------|-----|-----|----------|
| **AWS** | Amazon Web Services | NVIDIA T4/A10G | Ollama (Llama 3.1) | Production |
| **GCP** | Google Cloud Platform | NVIDIA L4/T4 | Ollama (Llama 3.1) | Production |

## Folder Structure

```
deploy/
├── README.md              # This file
├── shared/                # Shared configurations (used by both AWS and GCP)
│   ├── systemd/           # Systemd service files
│   │   ├── rag-api-gateway.service
│   │   ├── rag-ingestion.service
│   │   ├── rag-retrieval.service
│   │   ├── rag-query.service
│   │   └── rag-ui.service
│   └── nginx/             # Nginx configuration
│       └── rag-platform.conf
│
├── aws/                   # AWS GPU deployment
│   ├── config.env         # AWS configuration
│   ├── 01-deploy-infrastructure.sh
│   ├── 02-deploy-application.sh
│   ├── 03-configure-production.sh
│   ├── 04-verify-deployment.sh
│   └── teardown.sh
│
└── gcp/                   # GCP GPU deployment
    ├── config.env         # GCP configuration
    ├── 01-deploy-infrastructure.sh
    ├── 02-deploy-application.sh
    ├── 03-configure-production.sh
    ├── 04-verify-deployment.sh
    └── teardown.sh
```

## Quick Start

### AWS Deployment

```bash
cd deploy/aws

# 1. Edit configuration
nano config.env
# Set: KEY_PAIR_NAME, INSTANCE_TYPE, OLLAMA_MODEL

# 2. Deploy
./01-deploy-infrastructure.sh
./02-deploy-application.sh
./03-configure-production.sh
./04-verify-deployment.sh

# Access
# Web UI: http://<ELASTIC_IP>/ui
# API: http://<ELASTIC_IP>/health
```

### GCP Deployment

```bash
cd deploy/gcp

# 1. Edit configuration
nano config.env
# Set: GCP_PROJECT_ID, MACHINE_TYPE, OLLAMA_MODEL

# 2. Deploy
./01-deploy-infrastructure.sh
./02-deploy-application.sh
./03-configure-production.sh
./04-verify-deployment.sh

# Access
# Web UI: http://<STATIC_IP>/ui
# API: http://<STATIC_IP>/health
```

## GPU Instance Comparison

| Cloud | Instance Type | GPU | VRAM | vCPU | RAM | Cost/hr |
|-------|---------------|-----|------|------|-----|---------|
| **AWS** | g4dn.xlarge | NVIDIA T4 | 16GB | 4 | 16GB | ~$0.53 |
| **AWS** | g5.xlarge | NVIDIA A10G | 24GB | 4 | 16GB | ~$1.01 |
| **GCP** | g2-standard-4 | NVIDIA L4 | 24GB | 4 | 16GB | ~$0.70 |
| **GCP** | n1-standard-4 + T4 | NVIDIA T4 | 16GB | 4 | 15GB | ~$0.55 |

## Recommended Ollama Models

| Model | Size | VRAM Needed | Quality | Speed |
|-------|------|-------------|---------|-------|
| `llama3.1:8b` | 8B | ~6GB | Good | Fast |
| `llama3.1:70b-q4` | 70B (4-bit) | ~40GB | Excellent | Moderate |
| `mistral:7b` | 7B | ~5GB | Good | Fast |
| `qwen2.5:7b` | 7B | ~5GB | Good | Fast |

## Teardown

### AWS
```bash
cd deploy/aws
./teardown.sh
```

### GCP
```bash
cd deploy/gcp
./teardown.sh
```

## Troubleshooting

### Check GPU Status
```bash
# AWS
ssh -i ~/.ssh/rag-platform-key.pem ubuntu@<IP> nvidia-smi

# GCP
gcloud compute ssh ubuntu@rag-platform --zone=asia-southeast1-b --command='nvidia-smi'
```

### Check Services
```bash
# On the server
sudo systemctl status rag-*
sudo docker compose ps
sudo journalctl -u rag-query -f
```

### Check Ollama
```bash
# On the server
sudo docker exec ollama ollama list
sudo docker exec ollama ollama run llama3.1:8b "Hello"
```

## Cost Optimization

1. **Stop instance when not in use**
   - AWS: `aws ec2 stop-instances --instance-ids <ID>`
   - GCP: `gcloud compute instances stop rag-platform`

2. **Use smaller models for development**
   - `llama3.2:3b` uses only ~3GB VRAM

3. **Use preemptible/spot instances for testing**
   - Not recommended for production (can be terminated)
