# Master Implementation Guide
## Enterprise RAG Platform - Complete Setup & Execution

This guide consolidates SETUP_INSTALLATION.md, IMPLEMENTATION_SUMMARY.md, RUNNING_THE_SYSTEM.md, and TEST_STATUS.md into a single actionable document for Claude Code CLI.

---

## 🎯 Current Status

### ✅ Completed
- Project structure created
- Docker Compose configuration ready
- Sample documents generated
- All shared utilities implemented
- All 4 microservices implemented (API Gateway, Ingestion, Retrieval, Query)
- E2E test scripts created
- Python dependencies defined

### ⚠️ Pending
- Services need to be started and tested
- Skills need to be uploaded to Claude Code
- End-to-end validation required

---

## 📋 Quick Start Checklist

### Phase 1: Environment Setup (5 minutes)

```bash
# 1. Navigate to project
cd /home/adityonugrohoid/projects/enterprise-rag-platform

# 2. Verify directory structure
ls -la

# 3. Check Python environment
python3 --version  # Should be 3.11+
which python3

# 4. Install dependencies (if not already done)
pip install -r requirements.txt

# 5. Verify .env file exists
cat .env
```

### Phase 2: Docker Services (10 minutes)

```bash
# 1. Start infrastructure services
docker compose up -d

# 2. Wait for services to be healthy (~60 seconds)
sleep 60
docker compose ps

# 3. Pull LLM model (~2GB, takes 5-10 minutes)
docker compose exec ollama ollama pull llama3.2:3b

# 4. Verify all services
curl http://localhost:8000/api/v1/heartbeat  # ChromaDB
curl http://localhost:11434/api/tags          # Ollama
curl http://localhost:9000/minio/health/live # MinIO
```

### Phase 3: Generate Sample Documents (2 minutes)

```bash
# Generate telecom sample documents
python scripts/generate_sample_docs.py

# Verify documents created
ls -lh data/documents/
# Should show 3 .txt files
```

### Phase 4: Start Backend Services (Manual)

**Option A: Using separate terminals**

```bash
# Terminal 1: API Gateway (Port 8080)
cd /home/adityonugrohoid/projects/enterprise-rag-platform
python services/api_gateway/main.py

# Terminal 2: Ingestion Service (Port 8001)
python services/ingestion/main.py

# Terminal 3: Retrieval Service (Port 8002)
python services/retrieval/main.py

# Terminal 4: Query Service (Port 8003)
python services/query/main.py
```

**Option B: Using tmux (recommended for CLI)**

```bash
# Install tmux if not available
sudo apt install tmux  # Ubuntu/Debian

# Start tmux session
tmux new -s rag-platform

# Split into 4 panes
# Ctrl+B then " (split horizontal)
# Ctrl+B then % (split vertical)
# Navigate with Ctrl+B then arrow keys

# In each pane, run one service
# Pane 1: python services/api_gateway/main.py
# Pane 2: python services/ingestion/main.py
# Pane 3: python services/retrieval/main.py
# Pane 4: python services/query/main.py

# Detach from tmux: Ctrl+B then D
# Reattach: tmux attach -t rag-platform
```

**Option C: Using screen**

```bash
# Start services in background with screen
screen -dmS api-gateway bash -c "cd /home/adityonugrohoid/projects/enterprise-rag-platform && python services/api_gateway/main.py"
screen -dmS ingestion bash -c "cd /home/adityonugrohoid/projects/enterprise-rag-platform && python services/ingestion/main.py"
screen -dmS retrieval bash -c "cd /home/adityonugrohoid/projects/enterprise-rag-platform && python services/retrieval/main.py"
screen -dmS query bash -c "cd /home/adityonugrohoid/projects/enterprise-rag-platform && python services/query/main.py"

# List running screens
screen -ls

# Attach to a screen
screen -r api-gateway
# Detach: Ctrl+A then D
```

### Phase 5: Health Checks (2 minutes)

```bash
# Run the diagnostics script to check all services
bash scripts/debug_services.sh
```

### Phase 6: Test Document Ingestion (3 minutes)

```bash
# Test document upload
curl -X POST http://localhost:8080/documents/upload \
  -H "X-API-Key: dev-api-key" \
  -F "file=@data/documents/internal_doc_00_network_performance_standards.txt" \
  | jq .

# Expected output:
# {
#   "success": true,
#   "data": {
#     "document_id": "uuid-here",
#     "filename": "internal_doc_00_network_performance_standards.txt",
#     "chunks_created": 25,
#     "classification": "internal",
#     "pii_detected": false
#   }
# }
```

### Phase 7: Test RAG Query (3 minutes)

```bash
# Test query
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -H "X-API-Key: dev-api-key" \
  -d '{
    "query": "What are the 5G RAN performance targets for call drop rate?"
  }' | jq .

# Expected output:
# {
#   "success": true,
#   "data": {
#     "answer": "According to the network performance standards...",
#     "sources": ["internal_doc_00_network_performance_standards.txt"],
#     "chunks_used": 3,
#     "model_used": "llama3.2:3b"
#   }
# }
```

### Phase 8: End-to-End Test (5 minutes)

```bash
# Run comprehensive E2E test
python scripts/test_rag_flow.py

# Should output:
# ✅ All E2E tests passed!
```

---

## 🔧 Troubleshooting Guide

### Issue: Services won't start

**Symptom:** Python service crashes on startup

**Solutions:**
```bash
# 1. Check if port is already in use
lsof -i :8080  # Check each port: 8080, 8001, 8002, 8003

# 2. Kill existing process if needed
kill -9 <PID>

# 3. Check Python dependencies
pip list | grep fastapi
pip list | grep chromadb

# 4. Reinstall dependencies
pip install -r requirements.txt --force-reinstall

# 5. Check environment variables
cat .env
export $(cat .env | xargs)  # Load env vars

# 6. Check logs
tail -f logs/api_gateway.log
```

### Issue: Docker services unhealthy

**Symptom:** `docker compose ps` shows services as unhealthy

**Solutions:**
```bash
# 1. Check Docker daemon
docker info

# 2. Check service logs
docker compose logs chromadb
docker compose logs ollama

# 3. Restart specific service
docker compose restart chromadb

# 4. Restart all services
docker compose down
docker compose up -d

# 5. Check disk space
df -h

# 6. Prune Docker (WARNING: removes unused data)
docker system prune -a
```

### Issue: Ollama model not loading

**Symptom:** LLM requests fail with "model not found"

**Solutions:**
```bash
# 1. List available models
docker compose exec ollama ollama list

# 2. Pull model again
docker compose exec ollama ollama pull llama3.2:3b

# 3. Check model size
docker compose exec ollama ls -lh /root/.ollama/models/

# 4. Test model directly
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.2:3b",
    "messages": [{"role": "user", "content": "Test"}]
  }'
```

### Issue: ChromaDB connection refused

**Symptom:** Services can't connect to ChromaDB

**Solutions:**
```bash
# 1. Check if ChromaDB is running
docker compose ps chroma

# 2. Check ChromaDB logs
docker compose logs chroma -f

# 3. Test ChromaDB directly
curl http://localhost:8000/api/v1/heartbeat

# 4. Check ChromaDB data directory permissions
ls -la data/chroma/

# 5. Reset ChromaDB (WARNING: deletes all data)
docker compose down
rm -rf data/chroma/*
docker compose up -d chroma
```

### Issue: No documents in ChromaDB

**Symptom:** Query returns no results despite uploading documents

**Solutions:**
```bash
# 1. Check if documents were uploaded
curl http://localhost:8080/health | jq .

# 2. Check ChromaDB collection
# Connect to Python shell
python3 << 'EOF'
from shared.clients.chroma_client import ChromaClient
client = ChromaClient()
print(f"Total documents: {client.count()}")
EOF

# 3. Re-upload documents
curl -X POST http://localhost:8080/documents/upload \
  -H "X-API-Key: dev-api-key" \
  -F "file=@data/documents/internal_doc_00_network_performance_standards.txt"

# 4. Check ingestion service logs
# (if running in terminal, check that terminal)
```

---

## 📝 How to Use This Guide in Claude Code CLI

### Starting Claude Code CLI

```bash
# 1. Navigate to project directory
cd /home/adityonugrohoid/projects/enterprise-rag-platform

# 2. Start Claude Code
claude-code chat

# Or if using the web/desktop interface:
# Just open claude.ai or Claude desktop app in this project folder
```

### Commands to Give Claude Code

Once in Claude Code CLI or interface, use these natural language commands:

#### **1. Initial Setup Review**
```
"Review the MASTER_IMPLEMENTATION_GUIDE.md file and tell me what needs to be done"
```

#### **2. Check Current Status**
```
"Check if all required files exist in the project structure"
"Verify the docker-compose.yaml configuration"
"Check if the .env file has all required variables"
```

#### **3. Start Services**
```
"Help me start all Docker services using docker compose"
"Create a script to start all backend services in the background"
"Show me how to use tmux to run all 4 Python services"
```

#### **4. Run Health Checks**
```
"Run the health check script and show me the results"
"Check if all services are responding correctly"
```

#### **5. Test the System**
```
"Help me upload a test document and verify it was ingested"
"Test a RAG query and show me the response"
"Run the end-to-end test script"
```

#### **6. Troubleshooting**
```
"The API Gateway isn't starting, help me debug"
"ChromaDB is showing as unhealthy, what should I check?"
"I'm getting connection errors, help me troubleshoot"
```

#### **7. Using Skills**
```
"Using the RAG Development Standards skill, review my implementation"
"Using the RAG Debugging skill, help me troubleshoot slow queries"
"Using the Production Deployment skill, add JWT authentication"
"Using the Multi-Provider LLM skill, help me switch from Ollama to OpenAI"
```

---

## 🎓 Skills Integration

Your uploaded Claude Skills are automatically available. Reference them naturally:

### RAG Development Standards
```
"Using RAG Development Standards skill, review my data models"
"Show me the PII detection pattern from the RAG Development Standards skill"
"Apply the API response format standard from RAG Development Standards"
```

### RAG Debugging & Testing
```
"Using RAG Debugging skill, help me profile slow queries"
"Show me the debugging checklist from RAG Debugging skill"
"Help me implement the integration tests from RAG Debugging skill"
```

### Multi-Provider LLM
```
"Using Multi-Provider LLM skill, show me how to add OpenAI support"
"Help me implement the UniversalLLMClient from the Multi-Provider LLM skill"
"Switch my LLM provider from Ollama to Anthropic Claude"
```

### Production Deployment
```
"Using Production Deployment skill, add JWT authentication"
"Implement Redis caching using the Production Deployment skill"
"Set up structured logging using the Production Deployment skill"
```

### Local to GCP Migration
```
"Using GCP Migration skill, help me deploy to Cloud Run"
"Show me the migration checklist from GCP Migration skill"
"Help me migrate from ChromaDB to Vertex AI Vector Search"
```

---

## 🚀 Implementation Sequence

For best results, follow this sequence when working with Claude Code:

### Stage 1: Validation (10 minutes)
1. "Check if all files from IMPLEMENTATION_SUMMARY.md exist"
2. "Verify docker-compose.yaml has all required services"
3. "Review the .env file configuration"

### Stage 2: Infrastructure (15 minutes)
1. "Help me start Docker services"
2. "Pull the Ollama model"
3. "Generate sample documents"
4. "Run health checks"

### Stage 3: Backend Services (10 minutes)
1. "Create a script to start all 4 backend services"
2. "Start the services using tmux/screen"
3. "Verify all services are healthy"

### Stage 4: Testing (15 minutes)
1. "Test document upload"
2. "Test RAG query"
3. "Run end-to-end tests"
4. "Review and fix any errors"

### Stage 5: Enhancement (optional)
1. "Add JWT authentication using Production Deployment skill"
2. "Add Redis caching"
3. "Implement cost tracking"
4. "Add monitoring metrics"

---

## 📊 Success Criteria

✅ **All checks must pass:**

1. **Docker Services**
   - [ ] ChromaDB responding on port 8000
   - [ ] Ollama responding on port 11434
   - [ ] MinIO responding on port 9000
   - [ ] Redis responding on port 6379 (optional)

2. **Backend Services**
   - [ ] API Gateway healthy on port 8080
   - [ ] Ingestion service healthy on port 8001
   - [ ] Retrieval service healthy on port 8002
   - [ ] Query service healthy on port 8003

3. **Functionality**
   - [ ] Document upload successful
   - [ ] Vector embeddings created
   - [ ] RAG query returns relevant answer
   - [ ] E2E test passes

4. **Performance**
   - [ ] Document ingestion < 10 seconds
   - [ ] Query response < 10 seconds
   - [ ] No errors in service logs

---

## 📖 Reference

### Port Mapping
- 8080: API Gateway
- 8001: Ingestion Service
- 8002: Retrieval Service
- 8003: Query Service
- 8000: ChromaDB
- 11434: Ollama
- 9000: MinIO API
- 9001: MinIO Console
- 6379: Redis

### Key Files
- `docker-compose.yaml`: Infrastructure services
- `.env`: Environment configuration
- `requirements.txt`: Python dependencies
- `scripts/start_services.sh`: Start all backend services
- `scripts/stop_services.sh`: Stop all backend services
- `scripts/debug_services.sh`: Service diagnostics
- `scripts/test_rag_flow.py`: E2E test script
- `scripts/start_ui.sh`: Start Streamlit UI

### Important Directories
- `services/`: All microservices
- `shared/`: Shared utilities and clients
- `data/`: Data storage (documents, ChromaDB, MinIO)
- `scripts/`: Utility scripts
- `logs/`: Service logs

---

**Document Version:** 3.0 (Master Consolidated)  
**Status:** ✅ Ready for Execution  
**Last Updated:** 2026-02-03  
**Created by:** Claude (Anthropic)
