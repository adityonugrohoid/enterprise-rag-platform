#!/bin/bash
# Verify GCP Deployment - Post-deployment testing script

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

# GCP SSH command helper
gcp_ssh() {
    gcloud compute ssh ${SSH_USER}@${INSTANCE_NAME} \
        --zone=${GCP_ZONE} \
        --project=${GCP_PROJECT_ID} \
        --command="$1" \
        --quiet 2>/dev/null
}

# Load API key
API_KEY=""
if [ -f "${SCRIPT_DIR}/api-key.txt" ]; then
    API_KEY=$(cat "${SCRIPT_DIR}/api-key.txt")
fi

BASE_URL="http://${STATIC_IP}"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}GCP Deployment Verification${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "Instance: ${INSTANCE_NAME}"
echo -e "IP:       ${STATIC_IP}"
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
if gcp_ssh "echo 'connected'"; then
    record_test "SSH Connectivity" "true"
else
    record_test "SSH Connectivity" "false" "Cannot connect to instance"
    echo -e "${RED}Cannot proceed without SSH access. Exiting.${NC}"
    exit 1
fi

# ============================================
# 2. GPU Test
# ============================================
echo -e "${YELLOW}[2/8] Checking GPU...${NC}"
if gcp_ssh "nvidia-smi" &>/dev/null; then
    GPU_NAME=$(gcp_ssh "nvidia-smi --query-gpu=name --format=csv,noheader")
    record_test "GPU (${GPU_NAME})" "true"
else
    record_test "GPU" "false" "nvidia-smi failed"
fi

# ============================================
# 3. Docker Containers Test
# ============================================
echo -e "${YELLOW}[3/8] Checking Docker containers...${NC}"
DOCKER_OUTPUT=$(gcp_ssh "sudo docker compose -f /opt/rag-platform/docker-compose.yaml ps --format '{{.Name}}:{{.Status}}'" 2>/dev/null)

EXPECTED_CONTAINERS=("chroma" "minio" "ollama" "redis")

for container in "${EXPECTED_CONTAINERS[@]}"; do
    if echo "$DOCKER_OUTPUT" | grep -q "${container}.*healthy"; then
        record_test "Docker: $container" "true"
    elif echo "$DOCKER_OUTPUT" | grep -q "${container}"; then
        record_test "Docker: $container" "false" "Running but not healthy"
    else
        record_test "Docker: $container" "false" "Container not found"
    fi
done

# ============================================
# 4. Systemd Services Test
# ============================================
echo -e "${YELLOW}[4/8] Checking systemd services...${NC}"
EXPECTED_SERVICES=("rag-api-gateway" "rag-ingestion" "rag-retrieval" "rag-query" "rag-ui")

for service in "${EXPECTED_SERVICES[@]}"; do
    STATUS=$(gcp_ssh "systemctl is-active $service" 2>/dev/null || echo "inactive")
    if [ "$STATUS" = "active" ]; then
        record_test "Service: $service" "true"
    else
        record_test "Service: $service" "false" "Status: $STATUS"
    fi
done

# ============================================
# 5. Health Endpoint Test
# ============================================
echo -e "${YELLOW}[5/8] Testing health endpoint...${NC}"
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "${BASE_URL}/health" 2>/dev/null)
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    if echo "$HEALTH_BODY" | grep -q '"status":"healthy"'; then
        record_test "Health Endpoint" "true"
    else
        record_test "Health Endpoint" "false" "Status is degraded"
    fi
else
    record_test "Health Endpoint" "false" "HTTP $HTTP_CODE"
fi

# ============================================
# 6. Document Upload Test
# ============================================
echo -e "${YELLOW}[6/8] Testing document upload...${NC}"
TEST_DOC="${PROJECT_ROOT}/data/documents/internal_doc_00_network_performance_standards.txt"
if [ -f "$TEST_DOC" ] && [ -n "$API_KEY" ]; then
    UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/documents/upload" \
        -H "X-API-Key: $API_KEY" \
        -F "file=@$TEST_DOC" 2>/dev/null)
    HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | tail -n1)

    if [ "$HTTP_CODE" = "200" ]; then
        record_test "Document Upload" "true"
    else
        record_test "Document Upload" "false" "HTTP $HTTP_CODE"
    fi
else
    record_test "Document Upload" "false" "Test document or API key not found"
fi

# ============================================
# 7. Query Test
# ============================================
echo -e "${YELLOW}[7/8] Testing RAG query...${NC}"
if [ -n "$API_KEY" ]; then
    QUERY_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/query" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d '{"query": "What is this document about?"}' \
        --max-time 60 2>/dev/null)
    HTTP_CODE=$(echo "$QUERY_RESPONSE" | tail -n1)

    if [ "$HTTP_CODE" = "200" ]; then
        record_test "RAG Query" "true"
    else
        record_test "RAG Query" "false" "HTTP $HTTP_CODE"
    fi
else
    record_test "RAG Query" "false" "API key not found"
fi

# ============================================
# 8. Web UI Test
# ============================================
echo -e "${YELLOW}[8/8] Testing Web UI...${NC}"
UI_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null "${BASE_URL}/ui" 2>/dev/null)
if [ "$UI_RESPONSE" = "200" ] || [ "$UI_RESPONSE" = "301" ] || [ "$UI_RESPONSE" = "302" ]; then
    record_test "Web UI" "true"
else
    record_test "Web UI" "false" "HTTP $UI_RESPONSE"
fi

# ============================================
# Summary
# ============================================
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
TOTAL=$((TESTS_PASSED + TESTS_FAILED))
echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC} / ${TOTAL}"
echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC} / ${TOTAL}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! Your GCP deployment is ready.${NC}"
    echo ""
    echo -e "Access your RAG platform:"
    echo -e "  Web UI:  ${YELLOW}http://${STATIC_IP}/ui${NC}"
    echo -e "  API:     ${YELLOW}http://${STATIC_IP}/health${NC}"
else
    echo -e "${YELLOW}Some tests failed. Check the services:${NC}"
    echo -e "  ${YELLOW}gcloud compute ssh ${SSH_USER}@${INSTANCE_NAME} --zone=${GCP_ZONE} --command='sudo systemctl status rag-*'${NC}"
fi
