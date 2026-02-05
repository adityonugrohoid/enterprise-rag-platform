#!/bin/bash
# Deploy Application to AWS EC2 Instance
# Run this after 01-deploy-infrastructure.sh
# Supports both CPU and GPU instances

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

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

# Detect if GPU instance
IS_GPU_INSTANCE=false
if [[ "$INSTANCE_TYPE" == g4dn* ]] || [[ "$INSTANCE_TYPE" == g5* ]] || [[ "$INSTANCE_TYPE" == p3* ]] || [[ "$INSTANCE_TYPE" == p4* ]]; then
    IS_GPU_INSTANCE=true
fi

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
echo -e "${GREEN}AWS EC2 Deployment${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Target: ubuntu@${ELASTIC_IP}"
echo -e "Instance: ${INSTANCE_TYPE}"
if [ "$IS_GPU_INSTANCE" = true ]; then
    echo -e "Mode: ${GREEN}GPU-accelerated${NC}"
else
    echo -e "Mode: ${YELLOW}CPU-only${NC}"
fi
echo -e "LLM: Ollama with ${OLLAMA_MODEL}"
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

# Create setup script based on instance type
if [ "$IS_GPU_INSTANCE" = true ]; then
    # GPU setup script with NVIDIA drivers
    cat > /tmp/setup-server.sh << 'SETUP_SCRIPT'
#!/bin/bash
set -e

echo "=== AWS GPU Server Setup Script ==="
echo ""

# Update system
echo "Updating system packages..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install NVIDIA drivers
echo "Installing NVIDIA drivers..."
if ! command -v nvidia-smi &> /dev/null; then
    sudo apt-get install -y linux-headers-$(uname -r)
    sudo apt-get install -y nvidia-driver-535 nvidia-utils-535
    echo "NVIDIA drivers installed."
fi

# Install NVIDIA Container Toolkit
echo "Installing NVIDIA Container Toolkit..."
if ! dpkg -l | grep -q nvidia-container-toolkit; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
fi

# Install Docker
echo "Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker ubuntu
    rm get-docker.sh
fi

sudo systemctl restart docker

# Install Docker Compose
echo "Installing Docker Compose..."
sudo apt-get install -y docker-compose-plugin

# Install Python and tools
echo "Installing Python..."
sudo apt-get install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx jq

# Create app directory
sudo mkdir -p /opt/rag-platform
sudo chown ubuntu:ubuntu /opt/rag-platform

echo ""
echo "=== Server setup complete ==="
echo "GPU Status:"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv 2>/dev/null || echo "GPU not detected (may need reboot)"
SETUP_SCRIPT

else
    # CPU-only setup script (no NVIDIA)
    cat > /tmp/setup-server.sh << 'SETUP_SCRIPT'
#!/bin/bash
set -e

echo "=== AWS CPU Server Setup Script ==="
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

sudo systemctl restart docker

# Install Docker Compose
echo "Installing Docker Compose..."
sudo apt-get install -y docker-compose-plugin

# Install Python and tools
echo "Installing Python..."
sudo apt-get install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx jq

# Create app directory
sudo mkdir -p /opt/rag-platform
sudo chown ubuntu:ubuntu /opt/rag-platform

echo ""
echo "=== Server setup complete (CPU mode) ==="
SETUP_SCRIPT
fi

# Copy and run setup script
if [ "$IS_GPU_INSTANCE" = true ]; then
    echo -e "${YELLOW}Setting up server with GPU drivers (this may take 10-15 minutes)...${NC}"
else
    echo -e "${YELLOW}Setting up server (this may take 5-10 minutes)...${NC}"
fi
${SCP_CMD} /tmp/setup-server.sh ubuntu@${ELASTIC_IP}:/tmp/
${SSH_CMD} ubuntu@${ELASTIC_IP} "chmod +x /tmp/setup-server.sh && /tmp/setup-server.sh"
echo -e "${GREEN}✓ Server setup complete${NC}"
echo ""

# GPU: Check if reboot is needed for NVIDIA drivers
if [ "$IS_GPU_INSTANCE" = true ]; then
    echo -e "${YELLOW}Checking GPU status...${NC}"
    if ! ${SSH_CMD} ubuntu@${ELASTIC_IP} "nvidia-smi" &>/dev/null; then
        echo -e "${YELLOW}GPU drivers installed but not active. Rebooting instance...${NC}"
        ${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo reboot" || true
        echo "Waiting 60 seconds for instance to reboot..."
        sleep 60

        for i in {1..30}; do
            if ${SSH_CMD} ubuntu@${ELASTIC_IP} "echo 'ready'" &>/dev/null; then
                echo -e "${GREEN}✓ Instance rebooted and ready${NC}"
                break
            fi
            echo "Waiting for instance... ($i/30)"
            sleep 10
        done
    fi

    echo -e "${YELLOW}Verifying GPU...${NC}"
    ${SSH_CMD} ubuntu@${ELASTIC_IP} "nvidia-smi"
    echo -e "${GREEN}✓ GPU verified${NC}"
    echo ""
fi

# Create tarball of project
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
    --exclude='deploy/gcp/deployment-info.env' \
    --exclude='deploy/aws/*.pem' \
    --exclude='deploy/gcp/*.pem' \
    --exclude='deploy/aws/*.txt' \
    --exclude='deploy/gcp/*.txt' \
    --exclude='deploy/aws/*.log' \
    --exclude='deploy/gcp/*.log' \
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
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2:3b}"

if [ "$IS_GPU_INSTANCE" = true ]; then
    echo -e "LLM Provider: ${GREEN}Ollama (GPU)${NC}"
else
    echo -e "LLM Provider: ${YELLOW}Ollama (CPU)${NC}"
fi
echo -e "Model: ${GREEN}${OLLAMA_MODEL}${NC}"

${SSH_CMD} ubuntu@${ELASTIC_IP} "cat > /opt/rag-platform/.env << EOF
# Production Environment - AWS EC2
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

# LLM Configuration - Ollama
LLM_PROVIDER=ollama
LLM_MODEL=${OLLAMA_MODEL}
OLLAMA_HOST=http://localhost:11434

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379

# Streamlit UI Configuration
API_GATEWAY_URL=http://localhost:8080
EOF"
echo -e "${GREEN}✓ Production configuration generated${NC}"

# Save API key locally
echo ""
echo -e "${YELLOW}Important! Save this API key:${NC}"
echo -e "${GREEN}API_KEY=${API_KEY}${NC}"
echo ""
echo "API key also saved to: ${SCRIPT_DIR}/api-key.txt"
echo "${API_KEY}" > "${SCRIPT_DIR}/api-key.txt"

# Configure Docker Compose for CPU/GPU
echo -e "${YELLOW}Configuring Docker Compose...${NC}"
if [ "$IS_GPU_INSTANCE" = false ]; then
    # Remove GPU configuration from docker-compose for CPU deployment
    ${SSH_CMD} ubuntu@${ELASTIC_IP} "cd /opt/rag-platform && sed -i '/deploy:/,/capabilities: \[gpu\]/d' docker-compose.yaml"
    echo -e "${GREEN}✓ Docker Compose configured for CPU${NC}"
else
    echo -e "${GREEN}✓ Docker Compose configured for GPU${NC}"
fi

# Start Docker services
echo -e "${YELLOW}Starting Docker services...${NC}"
${SSH_CMD} ubuntu@${ELASTIC_IP} "cd /opt/rag-platform && sudo docker compose up -d"
echo -e "${GREEN}✓ Docker services started${NC}"

# Pull Ollama model
echo -e "${YELLOW}Pulling Ollama model ${OLLAMA_MODEL}...${NC}"
echo -e "(Model size: ~2GB for llama3.2:3b, ~1.3GB for llama3.2:1b)"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo docker exec ollama ollama pull ${OLLAMA_MODEL}"
echo -e "${GREEN}✓ Ollama model pulled${NC}"

# Quick test
echo -e "${YELLOW}Testing Ollama...${NC}"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo docker exec ollama ollama run ${OLLAMA_MODEL} 'Say OK' --verbose 2>&1 | head -10" || true
echo -e "${GREEN}✓ Ollama ready${NC}"

# Setup Python environment
echo -e "${YELLOW}Setting up Python environment...${NC}"
${SSH_CMD} ubuntu@${ELASTIC_IP} "cd /opt/rag-platform && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt"
echo -e "${GREEN}✓ Python environment ready${NC}"

# Copy systemd service files
echo -e "${YELLOW}Installing systemd services...${NC}"
${SCP_CMD} -r "${SHARED_DIR}/systemd/"* ubuntu@${ELASTIC_IP}:/tmp/
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo cp /tmp/*.service /etc/systemd/system/ && sudo systemctl daemon-reload"

# Enable and start services
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo systemctl enable rag-ingestion rag-retrieval rag-query rag-api-gateway rag-ui"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo systemctl start rag-ingestion rag-retrieval rag-query rag-api-gateway rag-ui"
echo -e "${GREEN}✓ Systemd services installed and started${NC}"

# Wait for services
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 30

# Check health
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
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Server IP:     ${ELASTIC_IP}"
echo -e "Instance:      ${INSTANCE_TYPE}"
if [ "$IS_GPU_INSTANCE" = true ]; then
    echo -e "Mode:          GPU-accelerated"
else
    echo -e "Mode:          CPU-only (inference may be slower)"
fi
echo -e "API Endpoint:  http://${ELASTIC_IP}:8080"
echo -e "Web UI:        http://${ELASTIC_IP}:8501"
echo -e "API Key:       ${API_KEY}"
echo -e "LLM Model:     ${OLLAMA_MODEL}"
echo ""
echo -e "Test the API:"
echo -e "  ${YELLOW}curl -s http://${ELASTIC_IP}:8080/health${NC}"
echo ""
echo -e "SSH to server:"
echo -e "  ${YELLOW}ssh -i ${SSH_KEY} ubuntu@${ELASTIC_IP}${NC}"
echo ""
if [ "$IS_GPU_INSTANCE" = true ]; then
    echo -e "Check GPU:"
    echo -e "  ${YELLOW}ssh -i ${SSH_KEY} ubuntu@${ELASTIC_IP} nvidia-smi${NC}"
    echo ""
fi
echo -e "${YELLOW}Next step: Run ./03-configure-production.sh to set up Nginx${NC}"
