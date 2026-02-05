# Cloud Migration Plan: Enterprise RAG Platform

## Overview

This document outlines the minimum practical cloud migration strategy for the Enterprise RAG Platform, moving from local development to AWS cloud deployment while maintaining open-source models and minimizing costs.

**Migration Strategy:** Single VM Deployment (Lowest Cost)
**Cloud Provider:** AWS (current), GCP (future upgrade path)
**Compute Plan:** CPU-only (GPU upgrade when budget allows)

---

## Current Architecture (Local)

```
┌─────────────────────────────────────────────────────┐
│                   Local Machine                      │
├─────────────────────────────────────────────────────┤
│  Docker Compose                                      │
│  ├── Ollama (LLM) ──────── llama3.2:3b             │
│  ├── ChromaDB (Vector DB)                           │
│  ├── MinIO (Object Storage)                         │
│  └── Redis (Cache)                                  │
│                                                      │
│  Python Services (background processes)              │
│  ├── API Gateway :8080                              │
│  ├── Ingestion :8001                                │
│  ├── Retrieval :8002                                │
│  └── Query :8003                                    │
└─────────────────────────────────────────────────────┘
```

---

## Target Architecture (AWS Single VM)

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              EC2 Instance (t3.xlarge)                    │    │
│  │              4 vCPU, 16GB RAM, 100GB EBS                │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │                                                          │    │
│  │  ┌─── Docker Compose ────────────────────────┐          │    │
│  │  │  Ollama + ChromaDB + MinIO + Redis        │          │    │
│  │  └───────────────────────────────────────────┘          │    │
│  │                                                          │    │
│  │  ┌─── Systemd Services ──────────────────────┐          │    │
│  │  │  API Gateway, Ingestion, Retrieval, Query │          │    │
│  │  └───────────────────────────────────────────┘          │    │
│  │                                                          │    │
│  │  ┌─── Nginx ─────────────────────────────────┐          │    │
│  │  │  Reverse Proxy + SSL Termination          │          │    │
│  │  └───────────────────────────────────────────┘          │    │
│  │                                                          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Security Group: Allow 22 (SSH), 80, 443 only           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Elastic IP (Static Public IP)                          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
                    ┌─────────────────┐
                    │  Your Domain    │
                    │  (Optional)     │
                    └─────────────────┘
```

---

## Cost Estimation (AWS)

### Recommended: t3.xlarge (CPU-only)

| Resource | Specification | Monthly Cost |
|----------|---------------|--------------|
| EC2 Instance | t3.xlarge (4 vCPU, 16GB RAM) | ~$55 |
| EBS Storage | 100GB gp3 | ~$8 |
| Elastic IP | Static IP | ~$3.65 |
| Data Transfer | 100GB outbound | ~$9 |
| **Total** | | **~$75/month** |

### Budget Options

| Option | Instance | Cost | Trade-off |
|--------|----------|------|-----------|
| Spot Instance | t3.xlarge spot | ~$17/month | May be interrupted |
| Smaller Instance | t3.large (2 vCPU, 8GB) | ~$30/month | Slower performance |
| Reserved (1yr) | t3.xlarge reserved | ~$35/month | Upfront commitment |

### Future GPU Upgrade

| Instance | GPU | Monthly Cost | LLM Response Time |
|----------|-----|--------------|-------------------|
| g4dn.xlarge | T4 (16GB) | ~$180 | 2-5 seconds |
| g5.xlarge | A10G (24GB) | ~$350 | 1-3 seconds |

---

## Implementation Phases

### Phase 1: AWS Account Setup (Prerequisites)

**You need to do this manually in AWS Console:**

1. Create/verify AWS account
2. Create IAM user with programmatic access
3. Generate Access Key ID and Secret Access Key
4. Install AWS CLI locally and configure credentials
5. Create EC2 Key Pair for SSH access
6. (Optional) Register a domain or use existing one

### Phase 2: Infrastructure Deployment (Day 1)

Run the deployment script to create:
- VPC and networking
- Security groups
- EC2 instance
- Elastic IP

```bash
cd deploy/aws
./01-deploy-infrastructure.sh
```

### Phase 3: Application Deployment (Day 1)

SSH into the instance and deploy the application:

```bash
./02-deploy-application.sh
```

### Phase 4: Production Hardening (Day 2)

1. Configure Nginx reverse proxy
2. Set up SSL with Let's Encrypt
3. Configure systemd services
4. Set up basic monitoring

```bash
./03-configure-production.sh
```

### Phase 5: Monitoring & Backup (Day 3)

1. Enable CloudWatch monitoring
2. Set up automated EBS snapshots
3. Configure CloudWatch alarms

---

## What Changes in Code

### Minimal Changes Required

| File | Change |
|------|--------|
| `.env` | Update hostnames, strong secrets |
| `docker-compose.yaml` | Remove GPU section (CPU deployment) |
| New: `deploy/aws/*` | Deployment scripts |
| New: `deploy/nginx/` | Nginx configuration |
| New: `deploy/systemd/` | Service management files |

### No Changes Required

- Python application code
- Service architecture
- API endpoints
- Business logic

---

## Security Considerations

### Network Security
- Security group allows only ports 22 (SSH), 80 (HTTP), 443 (HTTPS)
- SSH access restricted to your IP (recommended)
- All services bind to localhost except Nginx

### Application Security
- Strong API keys (generated during deployment)
- HTTPS enforced via Nginx
- No default credentials

### Data Security
- EBS encryption enabled
- Regular automated backups
- MinIO data persisted on EBS

---

## Deployment Files Structure

```
deploy/
├── aws/
│   ├── 01-deploy-infrastructure.sh   # Create AWS resources
│   ├── 02-deploy-application.sh      # Deploy app to EC2
│   ├── 03-configure-production.sh    # SSL, systemd setup
│   ├── teardown.sh                   # Remove all resources
│   └── config.env                    # Deployment configuration
├── nginx/
│   └── rag-platform.conf             # Nginx configuration
├── systemd/
│   ├── rag-api-gateway.service
│   ├── rag-ingestion.service
│   ├── rag-retrieval.service
│   ├── rag-query.service
│   └── rag-docker.service
└── scripts/
    └── setup-server.sh               # Server initialization script
```

---

## Rollback Plan

If issues occur, you can:

1. **Quick rollback:** Restore from EBS snapshot
2. **Full rollback:** Run `teardown.sh` to remove all AWS resources
3. **Local fallback:** Continue using local development setup

---

## Future Upgrade Path (GCP)

When ready for full cloud-native deployment:

| Current (AWS VM) | Future (GCP Cloud-Native) |
|------------------|---------------------------|
| Ollama on EC2 | Vertex AI (Gemini/Claude API) |
| ChromaDB on EC2 | Vertex AI Vector Search |
| MinIO on EC2 | Google Cloud Storage |
| Single EC2 | Cloud Run (auto-scaling) |
| Manual SSL | Cloud Load Balancer |
| CloudWatch | Cloud Monitoring + Logging |

**Estimated future GCP cost:** $100-500/month depending on usage (pay-per-request)

---

## Support & Troubleshooting

### Common Issues

1. **SSH connection refused:** Check security group allows your IP
2. **Services not starting:** Check CloudWatch logs or `journalctl -u rag-*`
3. **Out of memory:** Consider upgrading to larger instance
4. **Slow LLM responses:** Expected on CPU (~10-30s), upgrade to GPU instance

### Useful Commands

```bash
# Check service status
sudo systemctl status rag-*

# View logs
sudo journalctl -u rag-api-gateway -f

# Restart all services
sudo systemctl restart rag-*

# Check Docker containers
docker compose ps

# Check disk usage
df -h
```

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-04 | 1.0 | Initial cloud migration plan |
