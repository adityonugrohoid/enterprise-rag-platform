#!/bin/bash
# Configure Production: Nginx + SSL
# Run this after 02-deploy-application.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Find SSH key
SSH_KEY=""
for path in "${KEY_PAIR_NAME}.pem" "${HOME}/.ssh/${KEY_PAIR_NAME}.pem" "${HOME}/${KEY_PAIR_NAME}.pem"; do
    if [ -f "$path" ]; then
        SSH_KEY="$path"
        break
    fi
done

if [ -z "$SSH_KEY" ]; then
    echo -e "${RED}Error: SSH key not found${NC}"
    exit 1
fi

SSH_CMD="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no"
SCP_CMD="scp -i ${SSH_KEY} -o StrictHostKeyChecking=no"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Production Configuration${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# Copy Nginx configuration
echo -e "${YELLOW}Configuring Nginx...${NC}"
${SCP_CMD} "${SCRIPT_DIR}/../nginx/rag-platform.conf" ubuntu@${ELASTIC_IP}:/tmp/

# Update Nginx config with actual IP/domain
if [ -n "$DOMAIN_NAME" ]; then
    SERVER_NAME="${DOMAIN_NAME}"
else
    SERVER_NAME="${ELASTIC_IP}"
fi

${SSH_CMD} ubuntu@${ELASTIC_IP} "sed -i 's/SERVER_NAME_PLACEHOLDER/${SERVER_NAME}/g' /tmp/rag-platform.conf"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo cp /tmp/rag-platform.conf /etc/nginx/sites-available/rag-platform"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo ln -sf /etc/nginx/sites-available/rag-platform /etc/nginx/sites-enabled/"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo rm -f /etc/nginx/sites-enabled/default"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo nginx -t && sudo systemctl reload nginx"
echo -e "${GREEN}✓ Nginx configured${NC}"

# SSL Configuration
if [ -n "$DOMAIN_NAME" ]; then
    echo ""
    echo -e "${YELLOW}Setting up SSL with Let's Encrypt...${NC}"
    echo -e "Domain: ${DOMAIN_NAME}"
    echo ""
    read -p "Enter email for SSL certificate notifications: " SSL_EMAIL

    if [ -n "$SSL_EMAIL" ]; then
        ${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo certbot --nginx -d ${DOMAIN_NAME} --non-interactive --agree-tos -m ${SSL_EMAIL}"
        echo -e "${GREEN}✓ SSL certificate installed${NC}"
    else
        echo -e "${YELLOW}Skipping SSL setup (no email provided)${NC}"
    fi
else
    echo ""
    echo -e "${YELLOW}No domain configured. Skipping SSL setup.${NC}"
    echo "To add SSL later:"
    echo "  1. Point your domain to: ${ELASTIC_IP}"
    echo "  2. Update DOMAIN_NAME in config.env"
    echo "  3. Run: sudo certbot --nginx -d yourdomain.com"
fi

# Configure firewall
echo ""
echo -e "${YELLOW}Configuring firewall...${NC}"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo ufw allow 'Nginx Full' && sudo ufw allow OpenSSH && sudo ufw --force enable"
echo -e "${GREEN}✓ Firewall configured${NC}"

# Create health check cron job
echo -e "${YELLOW}Setting up health monitoring...${NC}"
${SSH_CMD} ubuntu@${ELASTIC_IP} "cat > /tmp/health-check.sh << 'EOF'
#!/bin/bash
if ! curl -sf http://localhost:8080/health > /dev/null; then
    echo \"\$(date): Health check failed, restarting services\" >> /var/log/rag-health.log
    systemctl restart rag-api-gateway rag-ingestion rag-retrieval rag-query rag-ui
fi
EOF"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo cp /tmp/health-check.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/health-check.sh"
${SSH_CMD} ubuntu@${ELASTIC_IP} "(sudo crontab -l 2>/dev/null; echo '*/5 * * * * /usr/local/bin/health-check.sh') | sudo crontab -"
echo -e "${GREEN}✓ Health monitoring configured${NC}"

# Final status check
echo ""
echo -e "${YELLOW}Final status check...${NC}"
echo ""
echo "Docker containers:"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo docker compose -f /opt/rag-platform/docker-compose.yaml ps"
echo ""
echo "Systemd services:"
${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo systemctl status rag-api-gateway --no-pager -l | head -5"
echo ""

# Test endpoints
echo "Testing endpoints..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${ELASTIC_IP}/health" || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ HTTP endpoint working${NC}"
else
    echo -e "${YELLOW}⚠ HTTP endpoint returned: ${HTTP_CODE}${NC}"
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Production Configuration Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
if [ -n "$DOMAIN_NAME" ]; then
    echo -e "API Endpoint:  https://${DOMAIN_NAME}"
    echo -e "Web UI:        https://${DOMAIN_NAME}/ui"
else
    echo -e "API Endpoint:  http://${ELASTIC_IP}"
    echo -e "Web UI:        http://${ELASTIC_IP}/ui"
fi
echo ""
echo -e "Test the API:"
if [ -n "$DOMAIN_NAME" ]; then
    echo -e "  ${YELLOW}curl https://${DOMAIN_NAME}/health${NC}"
else
    echo -e "  ${YELLOW}curl http://${ELASTIC_IP}/health${NC}"
fi
echo ""
echo -e "Upload a document:"
API_KEY=$(cat "${SCRIPT_DIR}/api-key.txt" 2>/dev/null || echo "YOUR_API_KEY")
if [ -n "$DOMAIN_NAME" ]; then
    echo -e "  ${YELLOW}curl -X POST https://${DOMAIN_NAME}/documents/upload -H 'X-API-Key: ${API_KEY}' -F 'file=@document.txt'${NC}"
else
    echo -e "  ${YELLOW}curl -X POST http://${ELASTIC_IP}/documents/upload -H 'X-API-Key: ${API_KEY}' -F 'file=@document.txt'${NC}"
fi
echo ""
echo -e "SSH to server:"
echo -e "  ${YELLOW}ssh -i ${SSH_KEY} ubuntu@${ELASTIC_IP}${NC}"
