#!/bin/bash
# Deploy Application to GCP GPU Instance
# Run this after 01-deploy-infrastructure.sh

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

# GCP SSH command helper
gcp_ssh() {
    gcloud compute ssh ${SSH_USER}@${INSTANCE_NAME} \
        --zone=${GCP_ZONE} \
        --project=${GCP_PROJECT_ID} \
        --command="$1" \
        --quiet
}

gcp_scp() {
    gcloud compute scp "$1" ${SSH_USER}@${INSTANCE_NAME}:"$2" \
        --zone=${GCP_ZONE} \
        --project=${GCP_PROJECT_ID} \
        --quiet
}

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}GCP GPU Instance Deployment${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Instance: ${INSTANCE_NAME}"
echo -e "IP: ${STATIC_IP}"
echo -e "Machine: ${MACHINE_TYPE} (${GPU_TYPE})"
echo -e "LLM: Ollama with ${OLLAMA_MODEL}"
echo ""

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! gcp_ssh "echo 'SSH connection successful'"; then
    echo -e "${RED}Cannot connect to instance.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ SSH connection established${NC}"
echo ""

# Create setup script to run on server (with NVIDIA drivers)
cat > /tmp/setup-server.sh << 'SETUP_SCRIPT'
#!/bin/bash
set -e

echo "=== GCP GPU Server Setup Script ==="
echo ""

# Update system
echo "Updating system packages..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install NVIDIA drivers (GCP images may have them pre-installed)
echo "Installing NVIDIA drivers..."
if ! command -v nvidia-smi &> /dev/null; then
    sudo apt-get install -y linux-headers-$(uname -r)
    # Install NVIDIA driver
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

# Restart Docker to apply NVIDIA runtime
sudo systemctl restart docker

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

# Check GPU
echo ""
echo "GPU Status:"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv 2>/dev/null || echo "GPU not detected yet (may need reboot)"
SETUP_SCRIPT

# Copy and run setup script
echo -e "${YELLOW}Setting up server with GPU drivers (this may take 10-15 minutes)...${NC}"
gcp_scp /tmp/setup-server.sh /tmp/setup-server.sh
gcp_ssh "chmod +x /tmp/setup-server.sh && /tmp/setup-server.sh"
echo -e "${GREEN}✓ Server setup complete${NC}"
echo ""

# Check if reboot is needed for NVIDIA drivers
echo -e "${YELLOW}Checking GPU status...${NC}"
if ! gcp_ssh "nvidia-smi" &>/dev/null; then
    echo -e "${YELLOW}GPU drivers need activation. Rebooting instance...${NC}"
    gcloud compute instances reset ${INSTANCE_NAME} \
        --zone=${GCP_ZONE} \
        --project=${GCP_PROJECT_ID}
    echo "Waiting 60 seconds for instance to reboot..."
    sleep 60

    # Wait for SSH to be available again
    for i in {1..30}; do
        if gcp_ssh "echo 'ready'" &>/dev/null; then
            echo -e "${GREEN}✓ Instance rebooted and ready${NC}"
            break
        fi
        echo "Waiting for instance... ($i/30)"
        sleep 10
    done
fi

# Verify GPU is working
echo -e "${YELLOW}Verifying GPU...${NC}"
gcp_ssh "nvidia-smi"
echo -e "${GREEN}✓ GPU verified${NC}"
echo ""

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
    -czf /tmp/rag-platform.tar.gz .
echo -e "${GREEN}✓ Application packaged${NC}"

# Upload application
echo -e "${YELLOW}Uploading application to server...${NC}"
gcp_scp /tmp/rag-platform.tar.gz /tmp/rag-platform.tar.gz
gcp_ssh "cd /opt/rag-platform && tar -xzf /tmp/rag-platform.tar.gz && rm /tmp/rag-platform.tar.gz"
echo -e "${GREEN}✓ Application uploaded${NC}"
echo ""

# Generate production .env file
echo -e "${YELLOW}Generating production configuration...${NC}"
API_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
MINIO_PASSWORD=$(openssl rand -hex 16)
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1:8b}"

echo -e "LLM Provider: ${GREEN}Ollama (GPU)${NC}"
echo -e "Model: ${GREEN}${OLLAMA_MODEL}${NC}"

gcp_ssh "cat > /opt/rag-platform/.env << EOF
# Production Environment - GCP GPU Instance
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

# LLM Configuration - Ollama (GPU-accelerated)
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

# Start Docker services
echo -e "${YELLOW}Starting Docker services with GPU...${NC}"
gcp_ssh "cd /opt/rag-platform && sudo docker compose up -d"
echo -e "${GREEN}✓ Docker services started${NC}"

# Pull Ollama model
echo -e "${YELLOW}Pulling Ollama model ${OLLAMA_MODEL} (this may take 5-10 minutes)...${NC}"
gcp_ssh "sudo docker exec ollama ollama pull ${OLLAMA_MODEL}"
echo -e "${GREEN}✓ Ollama model pulled${NC}"

# Verify Ollama is using GPU
echo -e "${YELLOW}Verifying Ollama GPU access...${NC}"
gcp_ssh "sudo docker exec ollama ollama run ${OLLAMA_MODEL} 'Say GPU OK in 2 words' --verbose 2>&1 | head -20" || true
echo -e "${GREEN}✓ Ollama ready${NC}"

# Setup Python environment
echo -e "${YELLOW}Setting up Python environment...${NC}"
gcp_ssh "cd /opt/rag-platform && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt"
echo -e "${GREEN}✓ Python environment ready${NC}"

# Copy systemd service files from shared directory
echo -e "${YELLOW}Installing systemd services...${NC}"
for service in ${SHARED_DIR}/systemd/*.service; do
    gcp_scp "$service" /tmp/
done
gcp_ssh "sudo cp /tmp/*.service /etc/systemd/system/ && sudo systemctl daemon-reload"

# Enable and start services
gcp_ssh "sudo systemctl enable rag-ingestion rag-retrieval rag-query rag-api-gateway rag-ui"
gcp_ssh "sudo systemctl start rag-ingestion rag-retrieval rag-query rag-api-gateway rag-ui"
echo -e "${GREEN}✓ Systemd services installed and started${NC}"

# Wait for services to be ready
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 30

# Check service health
echo -e "${YELLOW}Checking service health...${NC}"
if gcp_ssh "curl -s http://localhost:8080/health" | grep -q "healthy"; then
    echo -e "${GREEN}✓ Services are healthy${NC}"
else
    echo -e "${YELLOW}⚠ Services may still be starting.${NC}"
fi

# Clean up
rm -f /tmp/rag-platform.tar.gz /tmp/setup-server.sh

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}GCP GPU Deployment Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Instance:      ${INSTANCE_NAME}"
echo -e "Static IP:     ${STATIC_IP}"
echo -e "Machine:       ${MACHINE_TYPE} (${GPU_TYPE})"
echo -e "API Endpoint:  http://${STATIC_IP}:8080"
echo -e "Web UI:        http://${STATIC_IP}:8501"
echo -e "API Key:       ${API_KEY}"
echo -e "LLM Model:     ${OLLAMA_MODEL}"
echo ""
echo -e "Test the API:"
echo -e "  ${YELLOW}curl -s http://${STATIC_IP}:8080/health${NC}"
echo ""
echo -e "SSH to instance:"
echo -e "  ${YELLOW}gcloud compute ssh ${SSH_USER}@${INSTANCE_NAME} --zone=${GCP_ZONE}${NC}"
echo ""
echo -e "Check GPU:"
echo -e "  ${YELLOW}gcloud compute ssh ${SSH_USER}@${INSTANCE_NAME} --zone=${GCP_ZONE} --command='nvidia-smi'${NC}"
echo ""
echo -e "${YELLOW}Next step: Run ./03-configure-production.sh to set up Nginx and SSL${NC}"
