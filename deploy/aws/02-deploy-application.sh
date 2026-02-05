#!/bin/bash
# Deploy Application to EC2 Instance
# Run this after 01-deploy-infrastructure.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load deployment info
if [ ! -f "${SCRIPT_DIR}/deployment-info.env" ]; then
    echo "Error: deployment-info.env not found. Run 01-deploy-infrastructure.sh first."
    exit 1
fi
source "${SCRIPT_DIR}/deployment-info.env"
source "${SCRIPT_DIR}/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Find SSH key
SSH_KEY=""
for path in "${KEY_PAIR_NAME}.pem" "${HOME}/.ssh/${KEY_PAIR_NAME}.pem" "${HOME}/${KEY_PAIR_NAME}.pem"; do
    if [ -f "$path" ]; then
        SSH_KEY="$path"
        break
    fi
done

if [ -z "$SSH_KEY" ]; then
    echo -e "${RED}Error: SSH key '${KEY_PAIR_NAME}.pem' not found${NC}"
    echo "Please place the key file in one of these locations:"
    echo "  - ${KEY_PAIR_NAME}.pem (current directory)"
    echo "  - ${HOME}/.ssh/${KEY_PAIR_NAME}.pem"
    echo "  - ${HOME}/${KEY_PAIR_NAME}.pem"
    exit 1
fi

SSH_CMD="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
SCP_CMD="scp -i ${SSH_KEY} -o StrictHostKeyChecking=no"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Application Deployment${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Target: ubuntu@${ELASTIC_IP}"
echo ""

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! ${SSH_CMD} ubuntu@${ELASTIC_IP} "echo 'SSH connection successful'" 2>/dev/null; then
    echo -e "${RED}Cannot connect to instance. It may still be initializing.${NC}"
    echo "Wait a few minutes and try again."
    exit 1
fi
echo -e "${GREEN}✓ SSH connection established${NC}"
echo ""

# Create setup script to run on server
cat > /tmp/setup-server.sh << 'SETUP_SCRIPT'
#!/bin/bash
set -e

echo "=== Server Setup Script ==="
echo ""

# Update system
echo "Updating system packages..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install Docker
echo "Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker ubuntu
    rm get-docker.sh
fi

# Install Docker Compose
echo "Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    sudo apt-get install -y docker-compose-plugin
fi

# Install Python and dependencies
echo "Installing Python..."
sudo apt-get install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx jq

# Create app directory
echo "Creating application directory..."
sudo mkdir -p /opt/rag-platform
sudo chown ubuntu:ubuntu /opt/rag-platform

echo ""
echo "=== Server setup complete ==="
SETUP_SCRIPT

# Copy and run setup script
echo -e "${YELLOW}Setting up server (this may take 5-10 minutes)...${NC}"
${SCP_CMD} /tmp/setup-server.sh ubuntu@${ELASTIC_IP}:/tmp/
${SSH_CMD} ubuntu@${ELASTIC_IP} "chmod +x /tmp/setup-server.sh && /tmp/setup-server.sh"
echo -e "${GREEN}✓ Server setup complete${NC}"
echo ""

# Create tarball of project (excluding unnecessary files)
echo -e "${YELLOW}Packaging application...${NC}"
cd "${PROJECT_ROOT}"
tar --exclude='.venv' \
    --exclude='.git' \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='logs/*.log' \
    --exclude='data/chroma/*' \
    --exclude='data/minio/*' \
    --exclude='data/redis/*' \
    --exclude='./models/*' \
    --exclude='deploy/aws/deployment-info.env' \
    --exclude='deploy/aws/*.pem' \
    --exclude='deploy/aws/*.txt' \
    --exclude='deploy/aws/*.log' \
    -czf /tmp/rag-platform.tar.gz .
echo -e "${GREEN}✓ Application packaged${NC}"

# Upload application
echo -e "${YELLOW}Uploading application to server...${NC}"
${SCP_CMD} /tmp/rag-platform.tar.gz ubuntu@${ELASTIC_IP}:/tmp/
${SSH_CMD} ubuntu@${ELASTIC_IP} "cd /opt/rag-platform && tar -xzf /tmp/rag-platform.tar.gz && rm /tmp/rag-platform.tar.gz"
echo -e "${GREEN}✓ Application uploaded${NC}"
echo ""

# Generate production .env file
echo -e "${YELLOW}Generating production configuration...${NC}"
API_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
MINIO_PASSWORD=$(openssl rand -hex 16)

# Determine LLM provider from config
LLM_PROVIDER="${LLM_PROVIDER:-ollama}"
echo -e "LLM Provider: ${GREEN}${LLM_PROVIDER}${NC}"

if [ "$LLM_PROVIDER" = "bedrock" ]; then
    # Bedrock configuration
    BEDROCK_MODEL="${BEDROCK_MODEL:-meta.llama3-1-8b-instruct-v1:0}"
    echo -e "Bedrock Model: ${GREEN}${BEDROCK_MODEL}${NC}"

    ${SSH_CMD} ubuntu@${ELASTIC_IP} "cat > /opt/rag-platform/.env << EOF
# Production Environment
ENVIRONMENT=production

# API Configuration
API_KEY=${API_KEY}
JWT_SECRET_KEY=${JWT_SECRET}

# MinIO Configuration
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${MINIO_PASSWORD}
MINIO_ENDPOINT=localhost:9000

# ChromaDB Configuration
CHROMA_HOST=http://localhost:8000

# LLM Configuration - Amazon Bedrock
LLM_PROVIDER=bedrock
BEDROCK_MODEL=${BEDROCK_MODEL}
AWS_REGION=${AWS_REGION}

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379

# Streamlit UI Configuration
API_GATEWAY_URL=http://localhost:8080
EOF"
else
    # Ollama configuration
    OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2:1b}"

    ${SSH_CMD} ubuntu@${ELASTIC_IP} "cat > /opt/rag-platform/.env << EOF
# Production Environment
ENVIRONMENT=production

# API Configuration
API_KEY=${API_KEY}
JWT_SECRET_KEY=${JWT_SECRET}

# MinIO Configuration
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${MINIO_PASSWORD}
MINIO_ENDPOINT=localhost:9000

# ChromaDB Configuration
CHROMA_HOST=http://localhost:8000

# LLM Configuration - Ollama (self-hosted)
LLM_PROVIDER=ollama
LLM_MODEL=${OLLAMA_MODEL}
OLLAMA_HOST=http://localhost:11434

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379

# Streamlit UI Configuration
API_GATEWAY_URL=http://localhost:8080
EOF"
fi
echo -e "${GREEN}✓ Production configuration generated${NC}"

# Save API key locally
echo ""
echo -e "${YELLOW}Important! Save this API key:${NC}"
echo -e "${GREEN}API_KEY=${API_KEY}${NC}"
echo ""
echo "API key also saved to: ${SCRIPT_DIR}/api-key.txt"
echo "${API_KEY}" > "${SCRIPT_DIR}/api-key.txt"

# Configure Docker Compose based on LLM provider
echo -e "${YELLOW}Configuring Docker Compose...${NC}"
if [ "$LLM_PROVIDER" = "bedrock" ]; then
    # Remove Ollama service from docker-compose for Bedrock deployment
    ${SSH_CMD} ubuntu@${ELASTIC_IP} "cd /opt/rag-platform && sed -i '/# Ollama/,/retries: 3/d' docker-compose.yaml"
    echo -e "${GREEN}✓ Docker Compose configured for Bedrock (Ollama removed)${NC}"
else
    # Remove GPU config for CPU-only Ollama deployment
    ${SSH_CMD} ubuntu@${ELASTIC_IP} "cd /opt/rag-platform && sed -i '/deploy:/,/capabilities: \[gpu\]/d' docker-compose.yaml"
    echo -e "${GREEN}✓ Docker Compose configured for CPU${NC}"
fi

# Start Docker services
echo -e "${YELLOW}Starting Docker services...${NC}"
${SSH_CMD} ubuntu@${ELASTIC_IP} "cd /opt/rag-platform && sudo docker compose up -d"
echo -e "${GREEN}✓ Docker services started${NC}"

# Pull Ollama model (only for Ollama provider)
if [ "$LLM_PROVIDER" = "ollama" ]; then
    echo -e "${YELLOW}Pulling Ollama model (this may take 5-10 minutes)...${NC}"
    ${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo docker exec ollama ollama pull ${OLLAMA_MODEL}"
    echo -e "${GREEN}✓ Ollama model pulled${NC}"
else
    echo -e "${GREEN}✓ Skipping Ollama model pull (using Bedrock)${NC}"
fi

# Setup Python environment
echo -e "${YELLOW}Setting up Python environment...${NC}"
${SSH_CMD} ubuntu@${ELASTIC_IP} "cd /opt/rag-platform && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt"
echo -e "${GREEN}✓ Python environment ready${NC}"

# Copy systemd service files
echo -e "${YELLOW}Installing systemd services...${NC}"
${SCP_CMD} -r "${SCRIPT_DIR}/../systemd/"* ubuntu@${ELASTIC_IP}:/tmp/
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo cp /tmp/*.service /etc/systemd/system/ && sudo systemctl daemon-reload"

# Enable and start services
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo systemctl enable rag-ingestion rag-retrieval rag-query rag-api-gateway rag-ui"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo systemctl start rag-ingestion rag-retrieval rag-query rag-api-gateway rag-ui"
echo -e "${GREEN}✓ Systemd services installed and started${NC}"

# Wait for services to be ready
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 30

# Check service health
echo -e "${YELLOW}Checking service health...${NC}"
if ${SSH_CMD} ubuntu@${ELASTIC_IP} "curl -s http://localhost:8080/health" | grep -q "healthy"; then
    echo -e "${GREEN}✓ Services are healthy${NC}"
else
    echo -e "${YELLOW}⚠ Services may still be starting. Check with: ssh -i ${SSH_KEY} ubuntu@${ELASTIC_IP} 'sudo systemctl status rag-*'${NC}"
fi

# Clean up
rm -f /tmp/rag-platform.tar.gz /tmp/setup-server.sh

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Application Deployment Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Server IP:     ${ELASTIC_IP}"
echo -e "API Endpoint:  http://${ELASTIC_IP}:8080"
echo -e "Web UI:        http://${ELASTIC_IP}:8501 (direct) or /ui after Nginx setup"
echo -e "API Key:       ${API_KEY}"
echo ""
echo -e "Test the API:"
echo -e "  ${YELLOW}curl -s http://${ELASTIC_IP}:8080/health${NC}"
echo ""
echo -e "SSH to server:"
echo -e "  ${YELLOW}ssh -i ${SSH_KEY} ubuntu@${ELASTIC_IP}${NC}"
echo ""
echo -e "${YELLOW}Next step: Run ./03-configure-production.sh to set up Nginx and SSL${NC}"
