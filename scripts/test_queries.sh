#!/bin/bash
# test_queries.sh - Test RAG platform with sample queries
# Usage: ./test_queries.sh [API_URL] [API_KEY]

set -e

# Configuration
API_URL="${1:-http://localhost:8080}"
API_KEY="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Auto-detect API key if not provided
if [ -z "$API_KEY" ]; then
    if [ -f "${PROJECT_ROOT}/deploy/aws/api-key.txt" ]; then
        API_KEY=$(cat "${PROJECT_ROOT}/deploy/aws/api-key.txt")
    elif [ -f "${PROJECT_ROOT}/deploy/gcp/api-key.txt" ]; then
        API_KEY=$(cat "${PROJECT_ROOT}/deploy/gcp/api-key.txt")
    elif [ -f "${PROJECT_ROOT}/.env" ]; then
        API_KEY=$(grep API_KEY "${PROJECT_ROOT}/.env" | cut -d= -f2)
    else
        echo -e "${RED}Error: API key not provided${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}RAG Platform Query Testing${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo -e "API URL: ${API_URL}"
echo ""

# Test queries organized by use case
declare -A QUERIES

# Enterprise Knowledge Base
QUERIES["Enterprise KB - PTO Policy"]="What is the PTO policy for employees with 5 years of tenure?"
QUERIES["Enterprise KB - Password Requirements"]="What are the password requirements for TechCorp systems?"

# Customer Support
QUERIES["Support - Sync Failures"]="How do I fix sync failures in CloudSync?"
QUERIES["Support - Mobile Backup"]="Why are my photos not backing up on iOS?"

# Legal/Compliance
QUERIES["Legal - Data Retention"]="How long do we retain customer transaction records?"
QUERIES["Legal - Privacy Rights"]="What rights do users have under the privacy policy?"

# Education
QUERIES["Education - ML Metrics"]="What is the difference between precision and recall?"
QUERIES["Education - Python Lists"]="How do I create and modify a list in Python?"

# Technical (RAG Differentiator)
QUERIES["Technical - API Rate Limits"]="What are the API rate limits for enterprise tier?"
QUERIES["Technical - Error Code"]="What does error code TC-409-USR-010 mean?"
QUERIES["Technical - SDK Install"]="How do I install and initialize the TechCorp Python SDK?"
QUERIES["Technical - Pricing"]="What is the hourly cost for GPU compute instances?"

# Run queries
PASSED=0
FAILED=0

for category in "${!QUERIES[@]}"; do
    query="${QUERIES[$category]}"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Category:${NC} $category"
    echo -e "${YELLOW}Query:${NC} $query"
    echo ""

    # Execute query
    START_TIME=$(date +%s.%N)

    response=$(curl -s -X POST "${API_URL}/query" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY}" \
        -d "{\"query\": \"$query\"}" \
        --max-time 180 2>&1)

    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)

    # Parse response
    if echo "$response" | grep -q '"answer"'; then
        answer=$(echo "$response" | jq -r '.answer' 2>/dev/null | head -c 500)
        sources=$(echo "$response" | jq -r '.sources[]?' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

        echo -e "${GREEN}Answer:${NC}"
        echo "$answer"
        if [ ${#answer} -ge 500 ]; then
            echo "... [truncated]"
        fi
        echo ""

        if [ -n "$sources" ]; then
            echo -e "${BLUE}Sources:${NC} $sources"
        fi

        echo -e "${BLUE}Response Time:${NC} ${DURATION}s"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}Error:${NC} Failed to get response"
        echo "$response" | head -c 200
        FAILED=$((FAILED + 1))
    fi

    echo ""
done

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"
echo -e "Total:  $((PASSED + FAILED))"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All queries successful!${NC}"
else
    echo -e "${YELLOW}Some queries failed. Check the output above.${NC}"
fi
