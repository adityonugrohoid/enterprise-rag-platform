#!/bin/bash
# Deploy AWS Infrastructure for Enterprise RAG Platform
# Prerequisites: AWS CLI configured with appropriate credentials

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Track created resources for cleanup on failure
CREATED_RESOURCES=()

# Cleanup function for rollback on failure
cleanup_on_failure() {
    if [ ${#CREATED_RESOURCES[@]} -eq 0 ]; then
        return
    fi

    echo ""
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}Deployment failed. Cleaning up resources...${NC}"
    echo -e "${RED}=========================================${NC}"

    # Cleanup in reverse order
    for resource in $(printf '%s\n' "${CREATED_RESOURCES[@]}" | tac); do
        IFS=':' read -r type id <<< "$resource"
        echo -e "${YELLOW}Deleting ${type}: ${id}${NC}"
        case $type in
            "instance")
                aws ec2 terminate-instances --instance-ids "$id" --region "${AWS_REGION}" 2>/dev/null || true
                aws ec2 wait instance-terminated --instance-ids "$id" --region "${AWS_REGION}" 2>/dev/null || true
                ;;
            "eip")
                aws ec2 release-address --allocation-id "$id" --region "${AWS_REGION}" 2>/dev/null || true
                ;;
            "sg")
                sleep 5  # Wait for dependencies
                aws ec2 delete-security-group --group-id "$id" --region "${AWS_REGION}" 2>/dev/null || true
                ;;
            "subnet")
                aws ec2 delete-subnet --subnet-id "$id" --region "${AWS_REGION}" 2>/dev/null || true
                ;;
            "rtb")
                aws ec2 delete-route-table --route-table-id "$id" --region "${AWS_REGION}" 2>/dev/null || true
                ;;
            "igw")
                aws ec2 detach-internet-gateway --internet-gateway-id "$id" --vpc-id "${VPC_ID}" --region "${AWS_REGION}" 2>/dev/null || true
                aws ec2 delete-internet-gateway --internet-gateway-id "$id" --region "${AWS_REGION}" 2>/dev/null || true
                ;;
            "vpc")
                aws ec2 delete-vpc --vpc-id "$id" --region "${AWS_REGION}" 2>/dev/null || true
                ;;
        esac
    done
    echo -e "${GREEN}Cleanup complete${NC}"
}

# Set trap to cleanup on error
trap cleanup_on_failure ERR

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}AWS Infrastructure Deployment${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Install it: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi

echo -e "${GREEN}AWS CLI configured. Account:${NC}"
aws sts get-caller-identity --query 'Account' --output text
echo ""

# Check if key pair exists
echo -e "${YELLOW}Checking EC2 Key Pair...${NC}"
if ! aws ec2 describe-key-pairs --key-names "${KEY_PAIR_NAME}" --region "${AWS_REGION}" &> /dev/null; then
    echo -e "${RED}Error: Key pair '${KEY_PAIR_NAME}' not found in ${AWS_REGION}${NC}"
    echo ""
    echo "Create a key pair in AWS Console:"
    echo "  1. Go to EC2 > Key Pairs"
    echo "  2. Create key pair named: ${KEY_PAIR_NAME}"
    echo "  3. Download and save the .pem file"
    echo "  4. Run: chmod 400 ${KEY_PAIR_NAME}.pem"
    exit 1
fi
echo -e "${GREEN}✓ Key pair found${NC}"

# Set SSH CIDR
if [ -z "$MY_IP" ]; then
    SSH_CIDR="0.0.0.0/0"
    echo -e "${YELLOW}Warning: SSH open to all IPs. Set MY_IP in config.env for better security${NC}"
else
    SSH_CIDR="${MY_IP}"
fi

# Check for spot pricing (informational)
echo ""
echo -e "${YELLOW}Checking Spot Instance pricing...${NC}"
SPOT_PRICE=$(aws ec2 describe-spot-price-history \
    --instance-types "${INSTANCE_TYPE}" \
    --product-descriptions "Linux/UNIX" \
    --region "${AWS_REGION}" \
    --query 'SpotPriceHistory[0].SpotPrice' \
    --output text 2>/dev/null || echo "N/A")
echo -e "${GREEN}Current spot price for ${INSTANCE_TYPE}: \$${SPOT_PRICE}/hour${NC}"

# Create VPC
echo ""
echo -e "${YELLOW}Creating VPC...${NC}"
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "${VPC_CIDR}" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${APP_NAME}-vpc},{Key=Project,Value=${PROJECT}}]" \
    --region "${AWS_REGION}" \
    --query 'Vpc.VpcId' \
    --output text)
CREATED_RESOURCES+=("vpc:${VPC_ID}")
echo -e "${GREEN}✓ VPC created: ${VPC_ID}${NC}"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames --region "${AWS_REGION}"

# Create Internet Gateway
echo -e "${YELLOW}Creating Internet Gateway...${NC}"
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${APP_NAME}-igw},{Key=Project,Value=${PROJECT}}]" \
    --region "${AWS_REGION}" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)
CREATED_RESOURCES+=("igw:${IGW_ID}")
aws ec2 attach-internet-gateway --vpc-id "${VPC_ID}" --internet-gateway-id "${IGW_ID}" --region "${AWS_REGION}"
echo -e "${GREEN}✓ Internet Gateway created: ${IGW_ID}${NC}"

# Create Subnet
echo -e "${YELLOW}Creating Subnet...${NC}"
SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "${VPC_ID}" \
    --cidr-block "${SUBNET_CIDR}" \
    --availability-zone "${AWS_REGION}a" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-subnet},{Key=Project,Value=${PROJECT}}]" \
    --region "${AWS_REGION}" \
    --query 'Subnet.SubnetId' \
    --output text)
CREATED_RESOURCES+=("subnet:${SUBNET_ID}")
echo -e "${GREEN}✓ Subnet created: ${SUBNET_ID}${NC}"

# Enable auto-assign public IP
aws ec2 modify-subnet-attribute --subnet-id "${SUBNET_ID}" --map-public-ip-on-launch --region "${AWS_REGION}"

# Create Route Table
echo -e "${YELLOW}Creating Route Table...${NC}"
RTB_ID=$(aws ec2 create-route-table \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${APP_NAME}-rtb},{Key=Project,Value=${PROJECT}}]" \
    --region "${AWS_REGION}" \
    --query 'RouteTable.RouteTableId' \
    --output text)
CREATED_RESOURCES+=("rtb:${RTB_ID}")
aws ec2 create-route --route-table-id "${RTB_ID}" --destination-cidr-block "0.0.0.0/0" --gateway-id "${IGW_ID}" --region "${AWS_REGION}" > /dev/null
aws ec2 associate-route-table --subnet-id "${SUBNET_ID}" --route-table-id "${RTB_ID}" --region "${AWS_REGION}" > /dev/null
echo -e "${GREEN}✓ Route Table created: ${RTB_ID}${NC}"

# Create Security Group
echo -e "${YELLOW}Creating Security Group...${NC}"
SG_ID=$(aws ec2 create-security-group \
    --group-name "${APP_NAME}-sg-$(date +%s)" \
    --description "Security group for RAG Platform" \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${APP_NAME}-sg},{Key=Project,Value=${PROJECT}}]" \
    --region "${AWS_REGION}" \
    --query 'GroupId' \
    --output text)
CREATED_RESOURCES+=("sg:${SG_ID}")

# Add inbound rules
aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol tcp --port 22 --cidr "${SSH_CIDR}" --region "${AWS_REGION}" > /dev/null
aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol tcp --port 80 --cidr "0.0.0.0/0" --region "${AWS_REGION}" > /dev/null
aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol tcp --port 443 --cidr "0.0.0.0/0" --region "${AWS_REGION}" > /dev/null
echo -e "${GREEN}✓ Security Group created: ${SG_ID}${NC}"

# Create IAM Role for EC2 (with Bedrock permissions if needed)
echo -e "${YELLOW}Creating IAM Role for EC2...${NC}"
IAM_ROLE_NAME="${APP_NAME}-ec2-role"
INSTANCE_PROFILE_NAME="${APP_NAME}-instance-profile"

# Check if role already exists
if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
    echo -e "${YELLOW}IAM Role already exists, skipping creation${NC}"
else
    # Create IAM role trust policy
    cat > /tmp/trust-policy.json << 'TRUSTPOLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUSTPOLICY

    # Create IAM role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "IAM role for RAG Platform EC2 instances" \
        --tags Key=Project,Value="${PROJECT}" Key=Environment,Value="${ENVIRONMENT}" \
        > /dev/null

    # Create Bedrock access policy
    cat > /tmp/bedrock-policy.json << 'BEDROCKPOLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockInvoke",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:*::foundation-model/*"
    },
    {
      "Sid": "BedrockList",
      "Effect": "Allow",
      "Action": [
        "bedrock:ListFoundationModels",
        "bedrock:GetFoundationModel"
      ],
      "Resource": "*"
    }
  ]
}
BEDROCKPOLICY

    # Attach Bedrock policy to role
    aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name "${APP_NAME}-bedrock-policy" \
        --policy-document file:///tmp/bedrock-policy.json

    # Clean up temp files
    rm -f /tmp/trust-policy.json /tmp/bedrock-policy.json
fi

# Create instance profile if it doesn't exist
if ! aws iam get-instance-profile --instance-profile-name "${INSTANCE_PROFILE_NAME}" &> /dev/null; then
    aws iam create-instance-profile --instance-profile-name "${INSTANCE_PROFILE_NAME}" > /dev/null
    aws iam add-role-to-instance-profile \
        --instance-profile-name "${INSTANCE_PROFILE_NAME}" \
        --role-name "${IAM_ROLE_NAME}"
    # Wait for instance profile to propagate
    sleep 10
fi
echo -e "${GREEN}✓ IAM Role created: ${IAM_ROLE_NAME}${NC}"

# Create EC2 Spot Instance
echo -e "${YELLOW}Creating EC2 Spot Instance (${INSTANCE_TYPE})...${NC}"
echo -e "${YELLOW}Using Spot Instance for cost savings (~70% cheaper)${NC}"

# Try Spot Instance first
INSTANCE_ID=""
SPOT_SUCCESS=false

# Request Spot Instance
SPOT_RESULT=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type "${INSTANCE_TYPE}" \
    --key-name "${KEY_PAIR_NAME}" \
    --subnet-id "${SUBNET_ID}" \
    --security-group-ids "${SG_ID}" \
    --iam-instance-profile Name="${INSTANCE_PROFILE_NAME}" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${EBS_SIZE},\"VolumeType\":\"gp3\",\"Encrypted\":true,\"DeleteOnTermination\":true}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${APP_NAME}-server},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" "ResourceType=spot-instances-request,Tags=[{Key=Name,Value=${APP_NAME}-spot},{Key=Project,Value=${PROJECT}}]" \
    --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"persistent","InstanceInterruptionBehavior":"stop"}}' \
    --region "${AWS_REGION}" \
    2>&1) || true

if echo "$SPOT_RESULT" | grep -q "InstanceId"; then
    INSTANCE_ID=$(echo "$SPOT_RESULT" | grep -o '"InstanceId": "[^"]*"' | head -1 | cut -d'"' -f4)
    SPOT_SUCCESS=true
    echo -e "${GREEN}✓ Spot Instance requested successfully${NC}"
else
    echo -e "${YELLOW}Spot Instance request failed. Trying On-Demand...${NC}"
    echo -e "${YELLOW}Error was: $(echo "$SPOT_RESULT" | grep -i "error" | head -1)${NC}"

    # Fallback to On-Demand
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "${AMI_ID}" \
        --instance-type "${INSTANCE_TYPE}" \
        --key-name "${KEY_PAIR_NAME}" \
        --subnet-id "${SUBNET_ID}" \
        --security-group-ids "${SG_ID}" \
        --iam-instance-profile Name="${INSTANCE_PROFILE_NAME}" \
        --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${EBS_SIZE},\"VolumeType\":\"gp3\",\"Encrypted\":true,\"DeleteOnTermination\":true}}]" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${APP_NAME}-server},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRONMENT}}]" \
        --region "${AWS_REGION}" \
        --query 'Instances[0].InstanceId' \
        --output text)
fi

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
    echo -e "${RED}Failed to create EC2 instance${NC}"
    exit 1
fi

CREATED_RESOURCES+=("instance:${INSTANCE_ID}")
if [ "$SPOT_SUCCESS" = true ]; then
    echo -e "${GREEN}✓ EC2 Spot Instance created: ${INSTANCE_ID}${NC}"
else
    echo -e "${GREEN}✓ EC2 On-Demand Instance created: ${INSTANCE_ID}${NC}"
fi

# Wait for instance to be running
echo -e "${YELLOW}Waiting for instance to be running...${NC}"
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}"
echo -e "${GREEN}✓ Instance is running${NC}"

# Allocate and associate Elastic IP
echo -e "${YELLOW}Allocating Elastic IP...${NC}"
ALLOCATION_ID=$(aws ec2 allocate-address \
    --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${APP_NAME}-eip},{Key=Project,Value=${PROJECT}}]" \
    --region "${AWS_REGION}" \
    --query 'AllocationId' \
    --output text)
CREATED_RESOURCES+=("eip:${ALLOCATION_ID}")
ELASTIC_IP=$(aws ec2 describe-addresses --allocation-ids "${ALLOCATION_ID}" --region "${AWS_REGION}" --query 'Addresses[0].PublicIp' --output text)
aws ec2 associate-address --instance-id "${INSTANCE_ID}" --allocation-id "${ALLOCATION_ID}" --region "${AWS_REGION}" > /dev/null
echo -e "${GREEN}✓ Elastic IP allocated: ${ELASTIC_IP}${NC}"

# Clear the trap since we succeeded
trap - ERR

# Save deployment info
cat > "${SCRIPT_DIR}/deployment-info.env" << EOF
# Deployment Info - Generated $(date)
# DO NOT COMMIT THIS FILE

VPC_ID=${VPC_ID}
IGW_ID=${IGW_ID}
SUBNET_ID=${SUBNET_ID}
RTB_ID=${RTB_ID}
SG_ID=${SG_ID}
INSTANCE_ID=${INSTANCE_ID}
ALLOCATION_ID=${ALLOCATION_ID}
ELASTIC_IP=${ELASTIC_IP}
AWS_REGION=${AWS_REGION}
KEY_PAIR_NAME=${KEY_PAIR_NAME}
SPOT_INSTANCE=${SPOT_SUCCESS}
EOF

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Infrastructure Deployment Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Instance ID:   ${INSTANCE_ID}"
echo -e "Instance Type: ${INSTANCE_TYPE}"
if [ "$SPOT_SUCCESS" = true ]; then
    echo -e "Pricing:       ${GREEN}Spot Instance (saves ~70%)${NC}"
else
    echo -e "Pricing:       On-Demand"
fi
echo -e "Public IP:     ${ELASTIC_IP}"
echo -e "SSH Command:   ${YELLOW}ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem ubuntu@${ELASTIC_IP}${NC}"
echo ""
echo -e "${YELLOW}Wait 2-3 minutes for the instance to fully initialize, then run:${NC}"
echo -e "  ${GREEN}./02-deploy-application.sh${NC}"
echo ""
echo -e "Deployment info saved to: ${SCRIPT_DIR}/deployment-info.env"
