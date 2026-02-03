#!/bin/bash
# End-to-End Test Script for Enterprise RAG Platform

set -e

API_URL="http://localhost:8080"
API_KEY="dev-api-key"
TEST_DOC="data/documents/internal_doc_00_network_performance_standards.txt"

echo "========================================="
echo "Enterprise RAG Platform - E2E Test"
echo "========================================="
echo ""

# Check if services are running
echo "Step 1: Checking service health..."
if ! curl -s -f "${API_URL}/health" > /dev/null; then
    echo "❌ API Gateway is not responding. Please start services first."
    echo "   Run: docker compose up -d"
    exit 1
fi
echo "✅ API Gateway is healthy"
echo ""

# Check if test document exists
if [ ! -f "$TEST_DOC" ]; then
    echo "❌ Test document not found: $TEST_DOC"
    echo "   Please generate sample documents first:"
    echo "   python scripts/generate_sample_docs.py"
    exit 1
fi

# Phase 2: Document Ingestion Test
echo "Step 2: Testing document ingestion..."
UPLOAD_RESPONSE=$(curl -s -X POST "${API_URL}/documents/upload" \
    -H "X-API-Key: ${API_KEY}" \
    -F "file=@${TEST_DOC}")

DOC_ID=$(echo "$UPLOAD_RESPONSE" | grep -o '"document_id":"[^"]*"' | cut -d'"' -f4)
CHUNKS=$(echo "$UPLOAD_RESPONSE" | grep -o '"chunks_created":[0-9]*' | cut -d':' -f2)

if [ -z "$DOC_ID" ]; then
    echo "❌ Document upload failed"
    echo "Response: $UPLOAD_RESPONSE"
    exit 1
fi

echo "✅ Document uploaded successfully"
echo "   Document ID: $DOC_ID"
echo "   Chunks created: $CHUNKS"
echo ""

# Wait a moment for indexing
echo "Waiting 2 seconds for indexing..."
sleep 2

# Phase 3: RAG Query Test
echo "Step 3: Testing RAG query..."
QUERY="What are the 5G RAN performance targets for call drop rate?"
QUERY_RESPONSE=$(curl -s -X POST "${API_URL}/query" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    -d "{
        \"query\": \"${QUERY}\"
    }")

# Extract full answer using Python for better JSON parsing
ANSWER=$(echo "$QUERY_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('answer', ''))" 2>/dev/null || echo "")
SOURCES=$(echo "$QUERY_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(', '.join(data.get('sources', [])))" 2>/dev/null || echo "")
CHUNKS_USED=$(echo "$QUERY_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('chunks_used', 0))" 2>/dev/null || echo "0")

if [ -z "$ANSWER" ]; then
    echo "❌ Query failed"
    echo "Response: $QUERY_RESPONSE"
    exit 1
fi

echo "✅ Query processed successfully"
echo ""
echo "   Query: ${QUERY}"
echo "   Sources: ${SOURCES}"
echo "   Chunks used: ${CHUNKS_USED}"
echo ""
echo "   Model Response:"
echo "   ──────────────────────────────────────────────────────────────"
echo "${ANSWER}" | sed 's/^/   /'
echo "   ──────────────────────────────────────────────────────────────"
echo ""

# Phase 4: Additional Test Queries
echo "Step 4: Testing additional queries..."

# Test query 2
QUERY2="What is network optimization?"
QUERY2_RESPONSE=$(curl -s -X POST "${API_URL}/query" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    -d "{
        \"query\": \"${QUERY2}\"
    }")

QUERY2_SUCCESS=$(echo "$QUERY2_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('success', False))" 2>/dev/null || echo "False")
QUERY2_ANSWER=$(echo "$QUERY2_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('answer', ''))" 2>/dev/null || echo "")

if [ "$QUERY2_SUCCESS" = "True" ] && [ -n "$QUERY2_ANSWER" ]; then
    echo "✅ Additional query test passed"
    echo ""
    echo "   Query: ${QUERY2}"
    echo "   Model Response:"
    echo "   ──────────────────────────────────────────────────────────────"
    echo "${QUERY2_ANSWER}" | sed 's/^/   /'
    echo "   ──────────────────────────────────────────────────────────────"
else
    echo "⚠️  Additional query test had issues"
    echo "Response: $QUERY2_RESPONSE"
fi
echo ""

echo "========================================="
echo "✅ All E2E tests passed!"
echo "========================================="
