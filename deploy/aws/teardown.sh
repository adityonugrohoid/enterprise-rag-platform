#!/bin/bash
# Teardown AWS Infrastructure
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

# IAM resource names (must match 01-deploy-infrastructure.sh)
IAM_ROLE_NAME="${APP_NAME:-rag-platform}-ec2-role"
INSTANCE_PROFILE_NAME="${APP_NAME:-rag-platform}-ec2-profile"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=========================================${NC}"
echo -e "${RED}AWS Infrastructure Teardown${NC}"
echo -e "${RED}=========================================${NC}"
echo ""
echo -e "${RED}WARNING: This will permanently delete:${NC}"
echo "  - EC2 Instance: ${INSTANCE_ID}"
echo "  - Elastic IP: ${ELASTIC_IP}"
echo "  - VPC and all networking: ${VPC_ID}"
echo "  - IAM Role and Instance Profile (if exists)"
echo "  - All data on the server"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Teardown cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting teardown...${NC}"

# Terminate EC2 instance
echo -e "${YELLOW}Terminating EC2 instance...${NC}"
aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}" > /dev/null 2>&1 || true
aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}" 2>/dev/null || true
echo -e "${GREEN}✓ EC2 instance terminated${NC}"

# Release Elastic IP
echo -e "${YELLOW}Releasing Elastic IP...${NC}"
aws ec2 release-address --allocation-id "${ALLOCATION_ID}" --region "${AWS_REGION}" 2>/dev/null || true
echo -e "${GREEN}✓ Elastic IP released${NC}"

# Delete security group
echo -e "${YELLOW}Deleting Security Group...${NC}"
sleep 5  # Wait for instance to fully terminate
aws ec2 delete-security-group --group-id "${SG_ID}" --region "${AWS_REGION}" 2>/dev/null || true
echo -e "${GREEN}✓ Security Group deleted${NC}"

# Delete subnet
echo -e "${YELLOW}Deleting Subnet...${NC}"
aws ec2 delete-subnet --subnet-id "${SUBNET_ID}" --region "${AWS_REGION}" 2>/dev/null || true
echo -e "${GREEN}✓ Subnet deleted${NC}"

# Delete route table
echo -e "${YELLOW}Deleting Route Table...${NC}"
aws ec2 delete-route-table --route-table-id "${RTB_ID}" --region "${AWS_REGION}" 2>/dev/null || true
echo -e "${GREEN}✓ Route Table deleted${NC}"

# Detach and delete Internet Gateway
echo -e "${YELLOW}Deleting Internet Gateway...${NC}"
aws ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" --region "${AWS_REGION}" 2>/dev/null || true
aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}" --region "${AWS_REGION}" 2>/dev/null || true
echo -e "${GREEN}✓ Internet Gateway deleted${NC}"

# Delete VPC
echo -e "${YELLOW}Deleting VPC...${NC}"
aws ec2 delete-vpc --vpc-id "${VPC_ID}" --region "${AWS_REGION}" 2>/dev/null || true
echo -e "${GREEN}✓ VPC deleted${NC}"

# Clean up IAM resources (for Bedrock deployment)
echo -e "${YELLOW}Cleaning up IAM resources...${NC}"

# Remove role from instance profile
aws iam remove-role-from-instance-profile \
    --instance-profile-name "${INSTANCE_PROFILE_NAME}" \
    --role-name "${IAM_ROLE_NAME}" 2>/dev/null || true

# Delete instance profile
aws iam delete-instance-profile \
    --instance-profile-name "${INSTANCE_PROFILE_NAME}" 2>/dev/null || true

# Detach policies from role
aws iam delete-role-policy \
    --role-name "${IAM_ROLE_NAME}" \
    --policy-name "BedrockAccess" 2>/dev/null || true

# Delete IAM role
aws iam delete-role \
    --role-name "${IAM_ROLE_NAME}" 2>/dev/null || true

echo -e "${GREEN}✓ IAM resources cleaned up${NC}"

# Remove deployment info file
rm -f "${SCRIPT_DIR}/deployment-info.env"
rm -f "${SCRIPT_DIR}/api-key.txt"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Teardown Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "All AWS resources have been deleted."
