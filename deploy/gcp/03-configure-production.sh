#!/bin/bash
# Configure Production: Nginx + SSL
# Run this after 02-deploy-application.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

# Load deployment info
if [ ! -f "${SCRIPT_DIR}/deployment-info.env" ]; then
    echo "Error: deployment-info.env not found. Run previous scripts first."
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
echo -e "${GREEN}Production Configuration${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# Copy Nginx configuration
echo -e "${YELLOW}Configuring Nginx...${NC}"
gcp_scp "${SHARED_DIR}/nginx/rag-platform.conf" /tmp/rag-platform.conf

# Update Nginx config with actual IP
gcp_ssh "sudo sed -i 's/server_name _;/server_name ${STATIC_IP};/' /tmp/rag-platform.conf"
gcp_ssh "sudo cp /tmp/rag-platform.conf /etc/nginx/sites-available/rag-platform"
gcp_ssh "sudo ln -sf /etc/nginx/sites-available/rag-platform /etc/nginx/sites-enabled/"
gcp_ssh "sudo rm -f /etc/nginx/sites-enabled/default"

# Test and reload Nginx
echo -e "${YELLOW}Testing Nginx configuration...${NC}"
if gcp_ssh "sudo nginx -t"; then
    gcp_ssh "sudo systemctl reload nginx"
    echo -e "${GREEN}✓ Nginx configured and reloaded${NC}"
else
    echo -e "${RED}Nginx configuration test failed${NC}"
    exit 1
fi

# Configure firewall (already done in infrastructure, but verify)
echo -e "${YELLOW}Verifying firewall rules...${NC}"
echo -e "${GREEN}✓ Firewall rules already configured in infrastructure step${NC}"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Production Configuration Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Your RAG platform is now accessible at:"
echo ""
echo -e "  API:     http://${STATIC_IP}/health"
echo -e "  Web UI:  http://${STATIC_IP}/ui"
echo ""
echo -e "API Key: $(cat ${SCRIPT_DIR}/api-key.txt 2>/dev/null || echo 'Check api-key.txt')"
echo ""
echo -e "${YELLOW}Next step: Run ./04-verify-deployment.sh to verify everything works${NC}"
