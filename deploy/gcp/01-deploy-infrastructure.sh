#!/bin/bash
# Deploy GCP Infrastructure
# Creates: VPC, Firewall Rules, Static IP, GPU VM Instance

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "${SCRIPT_DIR}/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validate configuration
if [ -z "$GCP_PROJECT_ID" ]; then
    echo -e "${RED}Error: GCP_PROJECT_ID is not set in config.env${NC}"
    exit 1
fi

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}GCP Infrastructure Deployment${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Project:  ${GCP_PROJECT_ID}"
echo -e "Zone:     ${GCP_ZONE}"
echo -e "Machine:  ${MACHINE_TYPE} with ${GPU_TYPE}"
echo ""

# Set project
echo -e "${YELLOW}Setting GCP project...${NC}"
gcloud config set project ${GCP_PROJECT_ID}
echo -e "${GREEN}✓ Project set${NC}"

# Enable required APIs
echo -e "${YELLOW}Enabling required APIs...${NC}"
gcloud services enable compute.googleapis.com
echo -e "${GREEN}✓ APIs enabled${NC}"

# Create VPC network (if not exists)
echo -e "${YELLOW}Creating VPC network...${NC}"
if ! gcloud compute networks describe rag-network --project=${GCP_PROJECT_ID} &>/dev/null; then
    gcloud compute networks create rag-network \
        --project=${GCP_PROJECT_ID} \
        --subnet-mode=auto
    echo -e "${GREEN}✓ VPC network created${NC}"
else
    echo -e "${GREEN}✓ VPC network already exists${NC}"
fi

# Create firewall rules
echo -e "${YELLOW}Creating firewall rules...${NC}"

# SSH access
if ! gcloud compute firewall-rules describe rag-allow-ssh --project=${GCP_PROJECT_ID} &>/dev/null; then
    gcloud compute firewall-rules create rag-allow-ssh \
        --project=${GCP_PROJECT_ID} \
        --network=rag-network \
        --allow=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=${NETWORK_TAG}
fi

# HTTP/HTTPS access
if ! gcloud compute firewall-rules describe rag-allow-http --project=${GCP_PROJECT_ID} &>/dev/null; then
    gcloud compute firewall-rules create rag-allow-http \
        --project=${GCP_PROJECT_ID} \
        --network=rag-network \
        --allow=tcp:80,tcp:443,tcp:8080,tcp:8501 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=${NETWORK_TAG}
fi
echo -e "${GREEN}✓ Firewall rules created${NC}"

# Reserve static IP
echo -e "${YELLOW}Reserving static IP...${NC}"
if ! gcloud compute addresses describe rag-platform-ip --region=${GCP_REGION} --project=${GCP_PROJECT_ID} &>/dev/null; then
    gcloud compute addresses create rag-platform-ip \
        --project=${GCP_PROJECT_ID} \
        --region=${GCP_REGION}
fi
STATIC_IP=$(gcloud compute addresses describe rag-platform-ip \
    --region=${GCP_REGION} \
    --project=${GCP_PROJECT_ID} \
    --format='get(address)')
echo -e "${GREEN}✓ Static IP reserved: ${STATIC_IP}${NC}"

# Create GPU VM instance
echo -e "${YELLOW}Creating GPU VM instance (this may take 2-3 minutes)...${NC}"

# Check if instance exists
if gcloud compute instances describe ${INSTANCE_NAME} --zone=${GCP_ZONE} --project=${GCP_PROJECT_ID} &>/dev/null; then
    echo -e "${YELLOW}Instance already exists. Deleting...${NC}"
    gcloud compute instances delete ${INSTANCE_NAME} \
        --zone=${GCP_ZONE} \
        --project=${GCP_PROJECT_ID} \
        --quiet
fi

# Create instance with GPU
gcloud compute instances create ${INSTANCE_NAME} \
    --project=${GCP_PROJECT_ID} \
    --zone=${GCP_ZONE} \
    --machine-type=${MACHINE_TYPE} \
    --accelerator=type=${GPU_TYPE},count=${GPU_COUNT} \
    --maintenance-policy=TERMINATE \
    --boot-disk-size=${BOOT_DISK_SIZE}GB \
    --boot-disk-type=pd-ssd \
    --image-family=${IMAGE_FAMILY} \
    --image-project=${IMAGE_PROJECT} \
    --network=rag-network \
    --address=${STATIC_IP} \
    --tags=${NETWORK_TAG} \
    --metadata=enable-oslogin=FALSE \
    --labels=environment=${ENVIRONMENT},project=${PROJECT}

echo -e "${GREEN}✓ GPU VM instance created${NC}"

# Wait for instance to be ready
echo -e "${YELLOW}Waiting for instance to be ready...${NC}"
sleep 30

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
for i in {1..10}; do
    if gcloud compute ssh ${SSH_USER}@${INSTANCE_NAME} \
        --zone=${GCP_ZONE} \
        --project=${GCP_PROJECT_ID} \
        --command="echo 'SSH ready'" \
        --quiet 2>/dev/null; then
        echo -e "${GREEN}✓ SSH connection successful${NC}"
        break
    fi
    echo "Waiting for SSH... ($i/10)"
    sleep 15
done

# Save deployment info
cat > "${SCRIPT_DIR}/deployment-info.env" << EOF
# GCP Deployment Info - Generated $(date)
GCP_PROJECT_ID="${GCP_PROJECT_ID}"
GCP_ZONE="${GCP_ZONE}"
GCP_REGION="${GCP_REGION}"
INSTANCE_NAME="${INSTANCE_NAME}"
STATIC_IP="${STATIC_IP}"
MACHINE_TYPE="${MACHINE_TYPE}"
GPU_TYPE="${GPU_TYPE}"
SSH_USER="${SSH_USER}"
EOF

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}GCP Infrastructure Ready!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Instance:   ${INSTANCE_NAME}"
echo -e "Zone:       ${GCP_ZONE}"
echo -e "Machine:    ${MACHINE_TYPE}"
echo -e "GPU:        ${GPU_TYPE}"
echo -e "Static IP:  ${STATIC_IP}"
echo ""
echo -e "SSH to instance:"
echo -e "  ${YELLOW}gcloud compute ssh ${SSH_USER}@${INSTANCE_NAME} --zone=${GCP_ZONE}${NC}"
echo ""
echo -e "${YELLOW}Next step: Run ./02-deploy-application.sh${NC}"
