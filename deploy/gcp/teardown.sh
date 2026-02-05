#!/bin/bash
# Teardown GCP Infrastructure
# This will DELETE all resources created by 01-deploy-infrastructure.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load deployment info
if [ ! -f "${SCRIPT_DIR}/deployment-info.env" ]; then
    echo "Error: deployment-info.env not found. Nothing to teardown."
    exit 1
fi
source "${SCRIPT_DIR}/deployment-info.env"
source "${SCRIPT_DIR}/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=========================================${NC}"
echo -e "${RED}GCP Infrastructure Teardown${NC}"
echo -e "${RED}=========================================${NC}"
echo ""
echo -e "${RED}WARNING: This will permanently delete:${NC}"
echo "  - VM Instance: ${INSTANCE_NAME}"
echo "  - Static IP: ${STATIC_IP}"
echo "  - Firewall rules"
echo "  - VPC Network (if no other resources)"
echo "  - All data on the instance"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Teardown cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting teardown...${NC}"

# Delete VM instance
echo -e "${YELLOW}Deleting VM instance...${NC}"
gcloud compute instances delete ${INSTANCE_NAME} \
    --zone=${GCP_ZONE} \
    --project=${GCP_PROJECT_ID} \
    --quiet 2>/dev/null || true
echo -e "${GREEN}✓ VM instance deleted${NC}"

# Release static IP
echo -e "${YELLOW}Releasing static IP...${NC}"
gcloud compute addresses delete rag-platform-ip \
    --region=${GCP_REGION} \
    --project=${GCP_PROJECT_ID} \
    --quiet 2>/dev/null || true
echo -e "${GREEN}✓ Static IP released${NC}"

# Delete firewall rules
echo -e "${YELLOW}Deleting firewall rules...${NC}"
gcloud compute firewall-rules delete rag-allow-ssh \
    --project=${GCP_PROJECT_ID} \
    --quiet 2>/dev/null || true
gcloud compute firewall-rules delete rag-allow-http \
    --project=${GCP_PROJECT_ID} \
    --quiet 2>/dev/null || true
echo -e "${GREEN}✓ Firewall rules deleted${NC}"

# Delete VPC network (only if empty)
echo -e "${YELLOW}Deleting VPC network...${NC}"
gcloud compute networks delete rag-network \
    --project=${GCP_PROJECT_ID} \
    --quiet 2>/dev/null || echo "VPC network may have other resources, skipping deletion"
echo -e "${GREEN}✓ VPC network cleanup attempted${NC}"

# Remove local files
rm -f "${SCRIPT_DIR}/deployment-info.env"
rm -f "${SCRIPT_DIR}/api-key.txt"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Teardown Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "All GCP resources have been deleted."
