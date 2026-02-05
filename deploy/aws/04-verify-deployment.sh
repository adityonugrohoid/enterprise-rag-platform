#!/bin/bash
# Verify Deployment - Post-deployment testing script
# Run this after 03-configure-production.sh to verify everything is working

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load deployment info
if [ ! -f "${SCRIPT_DIR}/deployment-info.env" ]; then
    echo "Error: deployment-info.env not found. Run deployment scripts first."
    exit 1
fi
source "${SCRIPT_DIR}/deployment-info.env"
source "${SCRIPT_DIR}/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

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
    exit 1
fi

SSH_CMD="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Load API key
API_KEY=""
if [ -f "${SCRIPT_DIR}/api-key.txt" ]; then
    API_KEY=$(cat "${SCRIPT_DIR}/api-key.txt")
fi

# Determine endpoint URL
if [ -n "$DOMAIN_NAME" ]; then
    BASE_URL="https://${DOMAIN_NAME}"
else
    BASE_URL="http://${ELASTIC_IP}"
fi

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Deployment Verification${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "Server:   ${ELASTIC_IP}"
echo -e "Endpoint: ${BASE_URL}"
echo ""

# Function to record test result
record_test() {
    local name=$1
    local passed=$2
    local message=$3

    if [ "$passed" = "true" ]; then
        echo -e "${GREEN}✓ PASS${NC} - $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC} - $name: $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ============================================
# 1. SSH Connectivity Test
# ============================================
echo -e "${YELLOW}[1/8] Testing SSH connectivity...${NC}"
if ${SSH_CMD} ubuntu@${ELASTIC_IP} "echo 'connected'" &>/dev/null; then
    record_test "SSH Connectivity" "true"
else
    record_test "SSH Connectivity" "false" "Cannot connect to server"
    echo -e "${RED}Cannot proceed without SSH access. Exiting.${NC}"
    exit 1
fi

# ============================================
# 2. Docker Containers Test
# ============================================
echo -e "${YELLOW}[2/8] Checking Docker containers...${NC}"
DOCKER_OUTPUT=$(${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo docker compose -f /opt/rag-platform/docker-compose.yaml ps --format '{{.Name}}:{{.Status}}'" 2>/dev/null)

# Expected containers for GPU + Ollama deployment
EXPECTED_CONTAINERS=("chroma" "minio" "ollama" "redis")
ALL_HEALTHY=true

for container in "${EXPECTED_CONTAINERS[@]}"; do
    if echo "$DOCKER_OUTPUT" | grep -q "${container}.*healthy"; then
        record_test "Docker: $container" "true"
    elif echo "$DOCKER_OUTPUT" | grep -q "${container}"; then
        record_test "Docker: $container" "false" "Running but not healthy"
        ALL_HEALTHY=false
    else
        record_test "Docker: $container" "false" "Container not found"
        ALL_HEALTHY=false
    fi
done

# ============================================
# 3. Systemd Services Test
# ============================================
echo -e "${YELLOW}[3/8] Checking systemd services...${NC}"
EXPECTED_SERVICES=("rag-api-gateway" "rag-ingestion" "rag-retrieval" "rag-query" "rag-ui")

for service in "${EXPECTED_SERVICES[@]}"; do
    STATUS=$(${SSH_CMD} ubuntu@${ELASTIC_IP} "systemctl is-active $service" 2>/dev/null || echo "inactive")
    if [ "$STATUS" = "active" ]; then
        record_test "Service: $service" "true"
    else
        record_test "Service: $service" "false" "Status: $STATUS"
    fi
done

# ============================================
# 4. Health Endpoint Test
# ============================================
echo -e "${YELLOW}[4/8] Testing health endpoint...${NC}"
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "${BASE_URL}/health" 2>/dev/null)
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    if echo "$HEALTH_BODY" | grep -q '"status":"healthy"'; then
        record_test "Health Endpoint" "true"
    else
        record_test "Health Endpoint" "false" "Status is degraded: $HEALTH_BODY"
    fi
else
    record_test "Health Endpoint" "false" "HTTP $HTTP_CODE"
fi

# ============================================
# 5. Document Upload Test
# ============================================
echo -e "${YELLOW}[5/8] Testing document upload...${NC}"

if [ -z "$API_KEY" ]; then
    record_test "Document Upload" "false" "API key not found in api-key.txt"
else
    # Create a test document
    TEST_DOC="/tmp/verify-test-doc-$$.txt"
    echo "This is a test document for deployment verification. It contains information about testing and verification procedures." > "$TEST_DOC"

    UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/documents/upload" \
        -H "X-API-Key: ${API_KEY}" \
        -F "file=@${TEST_DOC}" 2>/dev/null)
    HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | tail -n1)
    UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')

    rm -f "$TEST_DOC"

    if [ "$HTTP_CODE" = "200" ]; then
        if echo "$UPLOAD_BODY" | grep -q '"document_id"'; then
            CHUNKS=$(echo "$UPLOAD_BODY" | grep -o '"chunks_created":[0-9]*' | cut -d: -f2)
            record_test "Document Upload" "true"
            echo -e "         Chunks created: ${CHUNKS:-unknown}"
        else
            record_test "Document Upload" "false" "Unexpected response: $UPLOAD_BODY"
        fi
    elif [ "$HTTP_CODE" = "401" ]; then
        record_test "Document Upload" "false" "Invalid API key"
    else
        record_test "Document Upload" "false" "HTTP $HTTP_CODE - $UPLOAD_BODY"
    fi
fi

# ============================================
# 6. Query Endpoint Test
# ============================================
echo -e "${YELLOW}[6/8] Testing query endpoint...${NC}"

if [ -z "$API_KEY" ]; then
    record_test "Query Endpoint" "false" "API key not found"
else
    QUERY_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/query" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY}" \
        -d '{"query": "What is this about?"}' 2>/dev/null)
    HTTP_CODE=$(echo "$QUERY_RESPONSE" | tail -n1)
    QUERY_BODY=$(echo "$QUERY_RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        if echo "$QUERY_BODY" | grep -q '"answer"'; then
            record_test "Query Endpoint" "true"
        else
            record_test "Query Endpoint" "false" "Unexpected response format"
        fi
    elif [ "$HTTP_CODE" = "401" ]; then
        record_test "Query Endpoint" "false" "Invalid API key"
    else
        record_test "Query Endpoint" "false" "HTTP $HTTP_CODE"
    fi
fi

# ============================================
# 7. Web UI Test
# ============================================
echo -e "${YELLOW}[7/8] Testing Web UI...${NC}"
# Follow redirects (-L) and increase timeout for Streamlit
UI_RESPONSE=$(curl -s -L -w "\n%{http_code}" --max-time 10 "${BASE_URL}/ui" 2>/dev/null)
HTTP_CODE=$(echo "$UI_RESPONSE" | tail -n1)

# Accept 200, 301, 302 as valid (Nginx redirects to Streamlit)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    record_test "Web UI" "true"
else
    # Try direct port as fallback with longer timeout
    DIRECT_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${ELASTIC_IP}:8501" 2>/dev/null)
    if [ "$DIRECT_CODE" = "200" ] || [ "$DIRECT_CODE" = "301" ] || [ "$DIRECT_CODE" = "302" ]; then
        record_test "Web UI" "true"
        echo -e "         (Accessible via direct port 8501)"
    else
        record_test "Web UI" "false" "HTTP $HTTP_CODE (Nginx), HTTP $DIRECT_CODE (direct)"
    fi
fi

# ============================================
# 8. Auto-Restart Configuration Test
# ============================================
echo -e "${YELLOW}[8/8] Checking auto-restart configuration...${NC}"

# Check Docker restart policy
RESTART_POLICY=$(${SSH_CMD} ubuntu@${ELASTIC_IP} "sudo docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' chroma 2>/dev/null" || echo "none")
if [ "$RESTART_POLICY" = "always" ]; then
    record_test "Docker Restart Policy" "true"
else
    record_test "Docker Restart Policy" "false" "Policy is '$RESTART_POLICY', should be 'always'"
fi

# Check systemd services are enabled
SERVICES_ENABLED=true
for service in "${EXPECTED_SERVICES[@]}"; do
    ENABLED=$(${SSH_CMD} ubuntu@${ELASTIC_IP} "systemctl is-enabled $service 2>/dev/null" || echo "disabled")
    if [ "$ENABLED" != "enabled" ]; then
        SERVICES_ENABLED=false
        break
    fi
done

if [ "$SERVICES_ENABLED" = "true" ]; then
    record_test "Systemd Services Enabled" "true"
else
    record_test "Systemd Services Enabled" "false" "Some services not enabled for auto-start"
fi

# ============================================
# Summary
# ============================================
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All $TOTAL_TESTS tests passed!${NC}"
    echo ""
    echo -e "${GREEN}Deployment is fully operational.${NC}"
else
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    if [ "$TESTS_FAILED" -gt 3 ]; then
        echo -e "${RED}Multiple failures detected. Consider redeploying.${NC}"
    else
        echo -e "${YELLOW}Some tests failed. Check the issues above.${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Access Points:${NC}"
echo -e "  API Health:  ${BASE_URL}/health"
echo -e "  Web UI:      ${BASE_URL}/ui"
echo -e "  SSH:         ssh -i ${SSH_KEY} ubuntu@${ELASTIC_IP}"
echo ""

if [ -n "$API_KEY" ]; then
    echo -e "${BLUE}API Key:${NC} ${API_KEY}"
    echo ""
fi

echo -e "${BLUE}Quick Commands:${NC}"
echo -e "  Upload doc:  curl -X POST ${BASE_URL}/documents/upload -H 'X-API-Key: \$API_KEY' -F 'file=@doc.txt'"
echo -e "  Query:       curl -X POST ${BASE_URL}/query -H 'Content-Type: application/json' -H 'X-API-Key: \$API_KEY' -d '{\"query\": \"your question\"}'"
echo ""

# Exit with appropriate code
if [ "$TESTS_FAILED" -eq 0 ]; then
    exit 0
else
    exit 1
fi
