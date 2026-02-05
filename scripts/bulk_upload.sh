#!/bin/bash
# bulk_upload.sh - Upload all documents in a directory to RAG platform
# Usage: ./bulk_upload.sh [API_URL] [API_KEY] [DOC_DIR]

set -e

# Configuration
API_URL="${1:-http://localhost:8080}"
API_KEY="${2:-}"
DOC_DIR="${3:-data/documents}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Auto-detect API key if not provided
if [ -z "$API_KEY" ]; then
    if [ -f "${PROJECT_ROOT}/deploy/aws/api-key.txt" ]; then
        API_KEY=$(cat "${PROJECT_ROOT}/deploy/aws/api-key.txt")
        echo -e "${YELLOW}Using API key from deploy/aws/api-key.txt${NC}"
    elif [ -f "${PROJECT_ROOT}/deploy/gcp/api-key.txt" ]; then
        API_KEY=$(cat "${PROJECT_ROOT}/deploy/gcp/api-key.txt")
        echo -e "${YELLOW}Using API key from deploy/gcp/api-key.txt${NC}"
    elif [ -f "${PROJECT_ROOT}/.env" ]; then
        API_KEY=$(grep API_KEY "${PROJECT_ROOT}/.env" | cut -d= -f2)
        echo -e "${YELLOW}Using API key from .env${NC}"
    else
        echo -e "${RED}Error: API key not provided and not found in standard locations${NC}"
        echo "Usage: $0 <API_URL> <API_KEY> [DOC_DIR]"
        exit 1
    fi
fi

# Resolve document directory
if [[ ! "$DOC_DIR" = /* ]]; then
    DOC_DIR="${PROJECT_ROOT}/${DOC_DIR}"
fi

if [ ! -d "$DOC_DIR" ]; then
    echo -e "${RED}Error: Document directory not found: ${DOC_DIR}${NC}"
    exit 1
fi

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}Bulk Document Upload${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo -e "API URL:   ${API_URL}"
echo -e "Directory: ${DOC_DIR}"
echo ""

# Test API connectivity
echo -e "${YELLOW}Testing API connectivity...${NC}"
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/health" 2>/dev/null || echo "000")
if [ "$HEALTH" != "200" ]; then
    echo -e "${RED}Error: Cannot connect to API (HTTP ${HEALTH})${NC}"
    echo "Check that the server is running and accessible."
    exit 1
fi
echo -e "${GREEN}✓ API is accessible${NC}"
echo ""

# Count files
FILE_COUNT=$(find "$DOC_DIR" -maxdepth 1 -name "*.txt" -type f | wc -l)
if [ "$FILE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No .txt files found in ${DOC_DIR}${NC}"
    exit 0
fi
echo -e "Found ${GREEN}${FILE_COUNT}${NC} documents to upload"
echo ""

# Counters
SUCCESS=0
FAILED=0
TOTAL_CHUNKS=0
FAILED_FILES=()

# Process each document
for doc in "${DOC_DIR}"/*.txt; do
    if [ -f "$doc" ]; then
        filename=$(basename "$doc")
        filesize=$(du -h "$doc" | cut -f1)

        printf "%-50s %8s ... " "$filename" "($filesize)"

        response=$(curl -s -X POST "${API_URL}/documents/upload" \
            -H "X-API-Key: ${API_KEY}" \
            -F "file=@${doc}" \
            --max-time 120 2>&1)

        if echo "$response" | grep -q '"success":true'; then
            chunks=$(echo "$response" | grep -o '"chunks_created":[0-9]*' | cut -d: -f2)
            echo -e "${GREEN}OK${NC} (${chunks} chunks)"
            SUCCESS=$((SUCCESS + 1))
            TOTAL_CHUNKS=$((TOTAL_CHUNKS + chunks))
        else
            echo -e "${RED}FAILED${NC}"
            FAILED=$((FAILED + 1))
            FAILED_FILES+=("$filename")

            # Show error details
            error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
            if [ -n "$error_msg" ]; then
                echo -e "  ${RED}→ ${error_msg}${NC}"
            fi
        fi
    fi
done

echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}Upload Summary${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo -e "Successful: ${GREEN}${SUCCESS}${NC}"
echo -e "Failed:     ${RED}${FAILED}${NC}"
echo -e "Total Chunks Created: ${GREEN}${TOTAL_CHUNKS}${NC}"

if [ ${#FAILED_FILES[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Failed files:${NC}"
    for f in "${FAILED_FILES[@]}"; do
        echo "  - $f"
    done
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All documents uploaded successfully!${NC}"
    exit 0
else
    echo -e "${YELLOW}Some documents failed to upload. Check errors above.${NC}"
    exit 1
fi
